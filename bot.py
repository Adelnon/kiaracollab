"""Discord bot exposing a single `/task` slash command.

The command hands the user's request to Claude, which drives Discord actions
(create channels/roles, ban/kick/timeout users, send messages, …) via tool
calls declared in ``tools.py``.

Run:
    python bot.py
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import sys
import textwrap
import time
from typing import Any, Dict, List, Optional, Set

import discord
from anthropic import AsyncAnthropic
from anthropic import APIError
from discord import app_commands
from dotenv import load_dotenv

from tools import TOOL_SCHEMAS, ToolContext, run_tool
from web.status import BotStatus


log = logging.getLogger("kiara.task-bot")


SYSTEM_PROMPT = textwrap.dedent(
    """
    You are an operations agent embedded in a Discord bot. The user talks to you
    through a single `/task <request>` slash command and expects you to actually
    carry the request out using the provided tools.

    Ground rules:
    - Prefer discovery before action. If the user names a person, look them up
      with `find_member` before moderating. If they say "all servers", start with
      `list_guilds`.
    - Never invent snowflake IDs. If you don't have one, discover it with a tool.
    - Ask for the fewest, most-relevant tool calls that accomplish the goal.
      Chain tools when needed (e.g. category → channels; role → assign).
    - Discord bots cannot create a whole new Discord server, but they can build
      out a rich server layout (categories, channels, roles, permissions) inside
      a guild where they have Administrator. When the user says "make me a
      Discord server", interpret it as bootstrapping the invoking guild.
    - When you are done, call `finish` with a short human-readable summary. That
      summary is what the user sees. Do not call `finish` before the actions are
      actually completed.
    - If a tool errors, read the error and adjust. Report unrecoverable failures
      in the final summary — don't silently give up.
    """
).strip()


# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------


def _load_id_set(name: str) -> Set[int]:
    raw = os.getenv(name, "").strip()
    if not raw:
        return set()
    out: Set[int] = set()
    for chunk in raw.split(","):
        chunk = chunk.strip()
        if chunk:
            out.add(int(chunk))
    return out


def _build_intents() -> discord.Intents:
    intents = discord.Intents.default()
    intents.members = True  # privileged — enable in the developer portal
    intents.message_content = True  # privileged
    return intents


def _env_bool(name: str, default: bool = False) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def _format_uptime(seconds: float) -> str:
    total = int(seconds)
    days, total = divmod(total, 86400)
    hours, total = divmod(total, 3600)
    minutes, _ = divmod(total, 60)
    return f"{days}d {hours}h {minutes}m"


# ---------------------------------------------------------------------------
# Claude agent loop
# ---------------------------------------------------------------------------


def _content_to_jsonable(content_blocks) -> List[Dict[str, Any]]:
    """Convert an Anthropic response's content blocks into the shape the API
    expects when we echo them back as the assistant's turn."""
    out: List[Dict[str, Any]] = []
    for block in content_blocks:
        kind = getattr(block, "type", None)
        if kind == "text":
            out.append({"type": "text", "text": block.text})
        elif kind == "tool_use":
            out.append(
                {
                    "type": "tool_use",
                    "id": block.id,
                    "name": block.name,
                    "input": block.input,
                }
            )
    return out


async def run_agent(
    anthropic: AsyncAnthropic,
    model: str,
    user_request: str,
    ctx: ToolContext,
    max_turns: int,
    progress: Optional[Any] = None,
) -> Dict[str, Any]:
    """Drive the tool-use loop until the model calls `finish` or hits max_turns.

    Returns ``{"summary": str, "actions": [str], "turns": int}``.
    """

    messages: List[Dict[str, Any]] = [
        {"role": "user", "content": user_request},
    ]
    final_summary: Optional[str] = None

    for turn in range(1, max_turns + 1):
        try:
            response = await anthropic.messages.create(
                model=model,
                max_tokens=4096,
                system=SYSTEM_PROMPT,
                tools=TOOL_SCHEMAS,
                messages=messages,
            )
        except APIError as exc:
            log.exception("Anthropic API error on turn %d", turn)
            return {
                "summary": f"Claude API error: {exc}",
                "actions": ctx.log,
                "turns": turn,
            }

        assistant_blocks = _content_to_jsonable(response.content)
        messages.append({"role": "assistant", "content": assistant_blocks})

        tool_uses = [b for b in response.content if getattr(b, "type", None) == "tool_use"]
        text_chunks = [b.text for b in response.content if getattr(b, "type", None) == "text"]

        if progress and text_chunks:
            joined = "\n".join(t for t in text_chunks if t.strip())
            if joined:
                await progress(joined[:1900])

        if not tool_uses:
            final_summary = ("\n".join(text_chunks)).strip() or "(no reply)"
            break

        tool_results: List[Dict[str, Any]] = []
        for use in tool_uses:
            if use.name == "finish":
                final_summary = str(use.input.get("summary", "")).strip() or "Done."
                tool_results.append(
                    {"type": "tool_result", "tool_use_id": use.id, "content": "acknowledged"}
                )
                continue

            if progress:
                await progress(f"→ {use.name}({json.dumps(use.input)[:400]})")

            try:
                result = await run_tool(use.name, dict(use.input), ctx)
                tool_results.append(
                    {
                        "type": "tool_result",
                        "tool_use_id": use.id,
                        "content": json.dumps(result, default=str),
                    }
                )
            except Exception as exc:  # noqa: BLE001 — surface every failure back to the model
                log.exception("Tool %s failed", use.name)
                tool_results.append(
                    {
                        "type": "tool_result",
                        "tool_use_id": use.id,
                        "content": f"ERROR: {type(exc).__name__}: {exc}",
                        "is_error": True,
                    }
                )

        messages.append({"role": "user", "content": tool_results})

        if final_summary is not None:
            break

    if final_summary is None:
        final_summary = f"Reached the {max_turns}-turn cap without finishing."

    return {"summary": final_summary, "actions": ctx.log, "turns": turn}


# ---------------------------------------------------------------------------
# Discord client
# ---------------------------------------------------------------------------


class TaskBot(discord.Client):
    def __init__(self, *, model: str, anthropic: AsyncAnthropic, max_turns: int,
                 allowed_users: Set[int], allowed_guilds: Set[int],
                 web_enabled: bool = False, web_host: str = "127.0.0.1",
                 web_port: int = 8080) -> None:
        super().__init__(intents=_build_intents())
        self.tree = app_commands.CommandTree(self)
        self.model = model
        self.anthropic = anthropic
        self.max_turns = max_turns
        self.allowed_users = allowed_users
        self.allowed_guilds = allowed_guilds
        self.start_time = time.monotonic()
        self.web_enabled = web_enabled
        self.web_host = web_host
        self.web_port = web_port
        self.web_status = BotStatus()
        self._web_started = False

    async def setup_hook(self) -> None:
        # Global sync. This can take up to an hour to propagate the first time;
        # during dev, copy commands to a test guild via `guild=discord.Object(id=...)`.
        await self.tree.sync()
        log.info("slash commands synced")

    def _refresh_web_status(self) -> None:
        """Push a fresh snapshot of the bot's state to the web front-end."""
        if not self.web_enabled or self.user is None:
            return
        guilds = [
            {"id": str(g.id), "name": g.name, "member_count": g.member_count or 0}
            for g in self.guilds
        ]
        member_total = sum(g["member_count"] for g in guilds)
        self.web_status.set_online(
            username=str(self.user),
            guilds=guilds,
            member_count=member_total,
        )

    async def on_ready(self) -> None:
        log.info("logged in as %s (%s), in %d guilds", self.user, self.user and self.user.id, len(self.guilds))
        if self.web_enabled:
            self._refresh_web_status()
            if not self._web_started:
                # Imported lazily so the bot still starts if Flask isn't installed
                # and the web front-end is disabled.
                from web.server import start_web_server

                start_web_server(self.web_status, self.web_host, self.web_port)
                self._web_started = True

    async def on_guild_join(self, guild: discord.Guild) -> None:
        self._refresh_web_status()

    async def on_guild_remove(self, guild: discord.Guild) -> None:
        self._refresh_web_status()


def _user_is_allowed(bot: TaskBot, interaction: discord.Interaction) -> bool:
    if bot.allowed_users and interaction.user.id in bot.allowed_users:
        return True
    if not bot.allowed_users:
        perms = getattr(interaction.user, "guild_permissions", None)
        if perms is not None and perms.administrator:
            return True
    return False


def _guild_is_allowed(bot: TaskBot, interaction: discord.Interaction) -> bool:
    if not bot.allowed_guilds:
        return True
    return interaction.guild is not None and interaction.guild.id in bot.allowed_guilds


def register_commands(bot: TaskBot) -> None:
    @bot.tree.command(
        name="task",
        description="Describe something you want done, and the bot's AI will figure out how to do it.",
    )
    @app_commands.describe(request="What should the bot do?")
    async def task_cmd(interaction: discord.Interaction, request: str) -> None:
        if not _guild_is_allowed(bot, interaction):
            await interaction.response.send_message(
                "This bot isn't allowed to run tasks in this server.", ephemeral=True
            )
            return
        if not _user_is_allowed(bot, interaction):
            await interaction.response.send_message(
                "You don't have permission to use `/task` here.", ephemeral=True
            )
            return

        await interaction.response.defer(thinking=True)

        progress_lock = asyncio.Lock()

        async def send_progress(line: str) -> None:
            async with progress_lock:
                try:
                    await interaction.followup.send(f"`{line}`", ephemeral=True)
                except discord.HTTPException:
                    log.debug("progress send failed", exc_info=True)

        ctx = ToolContext(
            bot=bot,
            invoking_guild=interaction.guild,
            invoking_user=interaction.user,
            allow_cross_guild=True,
        )

        try:
            result = await run_agent(
                bot.anthropic,
                bot.model,
                request,
                ctx,
                max_turns=bot.max_turns,
                progress=send_progress,
            )
        except Exception as exc:  # noqa: BLE001
            log.exception("agent crashed")
            await interaction.followup.send(
                f"The agent hit an internal error: `{type(exc).__name__}: {exc}`",
                ephemeral=True,
            )
            return

        actions = result.get("actions") or []
        summary = result.get("summary") or "Done."
        body = summary
        if actions:
            action_lines = "\n".join(f"• {a}" for a in actions[:15])
            body = f"{summary}\n\n**Actions taken:**\n{action_lines}"
            if len(actions) > 15:
                body += f"\n_(and {len(actions) - 15} more)_"

        if len(body) > 1900:
            body = body[:1900] + "…"
        await interaction.followup.send(body)

    @bot.tree.command(
        name="uptime",
        description="Show how long the bot has been running.",
    )
    async def uptime_cmd(interaction: discord.Interaction) -> None:
        await interaction.response.send_message(_format_uptime(time.monotonic() - bot.start_time))


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main() -> int:
    load_dotenv()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")

    discord_token = os.getenv("DISCORD_TOKEN")
    anthropic_key = os.getenv("ANTHROPIC_API_KEY")
    if not discord_token or not anthropic_key:
        print("DISCORD_TOKEN and ANTHROPIC_API_KEY are required (see .env.example).", file=sys.stderr)
        return 2

    model = os.getenv("CLAUDE_MODEL", "claude-sonnet-5").strip() or "claude-sonnet-5"
    try:
        max_turns = int(os.getenv("MAX_AGENT_TURNS", "12"))
    except ValueError:
        max_turns = 12

    web_enabled = _env_bool("WEB_ENABLED", False)
    web_host = os.getenv("WEB_HOST", "127.0.0.1").strip() or "127.0.0.1"
    try:
        web_port = int(os.getenv("WEB_PORT", "8080"))
    except ValueError:
        web_port = 8080

    bot = TaskBot(
        model=model,
        anthropic=AsyncAnthropic(api_key=anthropic_key),
        max_turns=max_turns,
        allowed_users=_load_id_set("TASK_ALLOWED_USER_IDS"),
        allowed_guilds=_load_id_set("TASK_ALLOWED_GUILD_IDS"),
        web_enabled=web_enabled,
        web_host=web_host,
        web_port=web_port,
    )
    register_commands(bot)
    bot.run(discord_token, log_handler=None)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
