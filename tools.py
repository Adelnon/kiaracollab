"""Discord tool implementations exposed to the Claude agent.

Each entry in ``TOOL_SCHEMAS`` follows Anthropic's tool-use format
(https://docs.claude.com/en/docs/build-with-claude/tool-use). Each name maps
to a coroutine in ``TOOL_HANDLERS`` that receives the tool ``input`` dict and
a ``ToolContext`` and returns any JSON-serialisable value.
"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
from typing import Any, Awaitable, Callable, Dict, List, Optional

import discord


@dataclass
class ToolContext:
    """Runtime context passed to every tool call."""

    bot: discord.Client
    invoking_guild: Optional[discord.Guild]
    invoking_user: discord.abc.User
    allow_cross_guild: bool = True
    log: List[str] = field(default_factory=list)

    def note(self, line: str) -> None:
        self.log.append(line)


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------


def _guild_snapshot(guild: discord.Guild) -> Dict[str, Any]:
    return {
        "id": str(guild.id),
        "name": guild.name,
        "member_count": guild.member_count,
        "owner_id": str(guild.owner_id) if guild.owner_id else None,
    }


def _channel_snapshot(channel: discord.abc.GuildChannel) -> Dict[str, Any]:
    return {
        "id": str(channel.id),
        "name": channel.name,
        "type": channel.type.name,
        "category": channel.category.name if channel.category else None,
        "position": getattr(channel, "position", None),
    }


def _role_snapshot(role: discord.Role) -> Dict[str, Any]:
    return {
        "id": str(role.id),
        "name": role.name,
        "color": f"#{role.color.value:06x}",
        "position": role.position,
        "mentionable": role.mentionable,
        "hoist": role.hoist,
        "managed": role.managed,
    }


def _member_snapshot(member: discord.Member) -> Dict[str, Any]:
    return {
        "id": str(member.id),
        "name": member.name,
        "display_name": member.display_name,
        "bot": member.bot,
        "joined_at": member.joined_at.isoformat() if member.joined_at else None,
        "roles": [r.name for r in member.roles if r.name != "@everyone"],
    }


def _resolve_guild(ctx: ToolContext, guild_id: Optional[str]) -> discord.Guild:
    if not guild_id:
        if ctx.invoking_guild is None:
            raise ValueError("No invoking guild — supply guild_id.")
        return ctx.invoking_guild
    guild = ctx.bot.get_guild(int(guild_id))
    if guild is None:
        raise ValueError(f"Bot is not in guild {guild_id}.")
    if not ctx.allow_cross_guild and guild.id != (ctx.invoking_guild and ctx.invoking_guild.id):
        raise PermissionError("Cross-guild actions are disabled for this run.")
    return guild


def _parse_permissions(names: Optional[List[str]]) -> discord.Permissions:
    perms = discord.Permissions.none()
    if not names:
        return perms
    for raw in names:
        key = raw.strip().lower().replace("-", "_").replace(" ", "_")
        if key == "administrator":
            return discord.Permissions.all()
        if not hasattr(perms, key):
            raise ValueError(f"Unknown permission: {raw!r}")
        setattr(perms, key, True)
    return perms


def _parse_color(color: Optional[str]) -> discord.Color:
    if not color:
        return discord.Color.default()
    value = color.strip().lstrip("#")
    try:
        return discord.Color(int(value, 16))
    except ValueError as exc:
        raise ValueError(f"Invalid hex color {color!r}") from exc


# ---------------------------------------------------------------------------
# Tool schemas advertised to Claude
# ---------------------------------------------------------------------------

TOOL_SCHEMAS: List[Dict[str, Any]] = [
    {
        "name": "list_guilds",
        "description": "List every Discord server (guild) this bot is a member of. Use this first when the user talks about acting on 'all servers' or asks which servers the bot is in.",
        "input_schema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "get_guild_info",
        "description": "Get channels, roles, and member count for one guild. Omit guild_id to use the guild the /task command was invoked in.",
        "input_schema": {
            "type": "object",
            "properties": {"guild_id": {"type": "string", "description": "Snowflake ID of the guild. Optional; defaults to the invoking guild."}},
            "additionalProperties": False,
        },
    },
    {
        "name": "find_member",
        "description": "Look up a member in a guild by user mention/id/username/display-name. Returns matching member(s). Use this to translate names or mentions into user IDs before moderation actions.",
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "A raw <@id> mention, a user ID, a username, or a display name."},
                "guild_id": {"type": "string", "description": "Optional guild ID; defaults to invoking guild."},
                "limit": {"type": "integer", "default": 5, "minimum": 1, "maximum": 25},
            },
            "required": ["query"],
            "additionalProperties": False,
        },
    },
    {
        "name": "create_channel",
        "description": "Create a text, voice, category, or forum channel in a guild.",
        "input_schema": {
            "type": "object",
            "properties": {
                "name": {"type": "string"},
                "kind": {"type": "string", "enum": ["text", "voice", "category", "forum", "announcement", "stage"]},
                "guild_id": {"type": "string"},
                "category_id": {"type": "string", "description": "Parent category ID for text/voice/forum channels."},
                "topic": {"type": "string", "description": "Text channel topic (text/forum only)."},
                "nsfw": {"type": "boolean"},
                "position": {"type": "integer"},
            },
            "required": ["name", "kind"],
            "additionalProperties": False,
        },
    },
    {
        "name": "delete_channel",
        "description": "Delete a channel by ID.",
        "input_schema": {
            "type": "object",
            "properties": {
                "channel_id": {"type": "string"},
                "reason": {"type": "string"},
            },
            "required": ["channel_id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "rename_channel",
        "description": "Rename a channel.",
        "input_schema": {
            "type": "object",
            "properties": {
                "channel_id": {"type": "string"},
                "new_name": {"type": "string"},
            },
            "required": ["channel_id", "new_name"],
            "additionalProperties": False,
        },
    },
    {
        "name": "set_channel_topic",
        "description": "Set the topic (description) on a text or forum channel.",
        "input_schema": {
            "type": "object",
            "properties": {
                "channel_id": {"type": "string"},
                "topic": {"type": "string"},
            },
            "required": ["channel_id", "topic"],
            "additionalProperties": False,
        },
    },
    {
        "name": "create_role",
        "description": "Create a role in a guild.",
        "input_schema": {
            "type": "object",
            "properties": {
                "name": {"type": "string"},
                "guild_id": {"type": "string"},
                "color": {"type": "string", "description": "Hex color like '#5865F2' or 'ff0000'."},
                "permissions": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": "Permission flag names from discord.Permissions (e.g. 'manage_channels', 'kick_members', 'administrator').",
                },
                "hoist": {"type": "boolean", "description": "Display members with this role separately in the sidebar."},
                "mentionable": {"type": "boolean"},
            },
            "required": ["name"],
            "additionalProperties": False,
        },
    },
    {
        "name": "delete_role",
        "description": "Delete a role by ID.",
        "input_schema": {
            "type": "object",
            "properties": {
                "role_id": {"type": "string"},
                "guild_id": {"type": "string"},
                "reason": {"type": "string"},
            },
            "required": ["role_id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "assign_role",
        "description": "Give a role to a member.",
        "input_schema": {
            "type": "object",
            "properties": {
                "user_id": {"type": "string"},
                "role_id": {"type": "string"},
                "guild_id": {"type": "string"},
                "reason": {"type": "string"},
            },
            "required": ["user_id", "role_id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "remove_role",
        "description": "Remove a role from a member.",
        "input_schema": {
            "type": "object",
            "properties": {
                "user_id": {"type": "string"},
                "role_id": {"type": "string"},
                "guild_id": {"type": "string"},
                "reason": {"type": "string"},
            },
            "required": ["user_id", "role_id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "ban_member",
        "description": "Ban a user from a guild. Set scope='all_guilds' to ban them from every guild the bot has ban permission in.",
        "input_schema": {
            "type": "object",
            "properties": {
                "user_id": {"type": "string"},
                "guild_id": {"type": "string", "description": "Ignored when scope='all_guilds'."},
                "scope": {"type": "string", "enum": ["one_guild", "all_guilds"], "default": "one_guild"},
                "reason": {"type": "string"},
                "delete_message_days": {"type": "integer", "minimum": 0, "maximum": 7, "default": 0},
            },
            "required": ["user_id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "unban_member",
        "description": "Lift a ban from a user in a guild.",
        "input_schema": {
            "type": "object",
            "properties": {
                "user_id": {"type": "string"},
                "guild_id": {"type": "string"},
                "reason": {"type": "string"},
            },
            "required": ["user_id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "kick_member",
        "description": "Kick a user from a guild.",
        "input_schema": {
            "type": "object",
            "properties": {
                "user_id": {"type": "string"},
                "guild_id": {"type": "string"},
                "reason": {"type": "string"},
            },
            "required": ["user_id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "timeout_member",
        "description": "Time out a user (mute) for N minutes.",
        "input_schema": {
            "type": "object",
            "properties": {
                "user_id": {"type": "string"},
                "minutes": {"type": "integer", "minimum": 1, "maximum": 40320},
                "guild_id": {"type": "string"},
                "reason": {"type": "string"},
            },
            "required": ["user_id", "minutes"],
            "additionalProperties": False,
        },
    },
    {
        "name": "send_message",
        "description": "Send a text message to a channel.",
        "input_schema": {
            "type": "object",
            "properties": {
                "channel_id": {"type": "string"},
                "content": {"type": "string"},
            },
            "required": ["channel_id", "content"],
            "additionalProperties": False,
        },
    },
    {
        "name": "bulk_delete",
        "description": "Bulk-delete the most recent messages in a channel (up to 100). Messages older than 14 days are skipped by Discord.",
        "input_schema": {
            "type": "object",
            "properties": {
                "channel_id": {"type": "string"},
                "count": {"type": "integer", "minimum": 1, "maximum": 100},
            },
            "required": ["channel_id", "count"],
            "additionalProperties": False,
        },
    },
    {
        "name": "finish",
        "description": "Call this when the task is complete. `summary` is shown to the user as the final reply.",
        "input_schema": {
            "type": "object",
            "properties": {"summary": {"type": "string"}},
            "required": ["summary"],
            "additionalProperties": False,
        },
    },
]


# ---------------------------------------------------------------------------
# Handlers
# ---------------------------------------------------------------------------


async def _list_guilds(_: Dict[str, Any], ctx: ToolContext) -> Any:
    return [_guild_snapshot(g) for g in ctx.bot.guilds]


async def _get_guild_info(inp: Dict[str, Any], ctx: ToolContext) -> Any:
    guild = _resolve_guild(ctx, inp.get("guild_id"))
    return {
        **_guild_snapshot(guild),
        "channels": [_channel_snapshot(c) for c in guild.channels],
        "roles": [_role_snapshot(r) for r in guild.roles],
    }


async def _find_member(inp: Dict[str, Any], ctx: ToolContext) -> Any:
    guild = _resolve_guild(ctx, inp.get("guild_id"))
    query = inp["query"].strip()
    limit = int(inp.get("limit", 5))

    # <@id> or <@!id>
    if query.startswith("<@") and query.endswith(">"):
        query = query[2:-1].lstrip("!&")

    matches: List[discord.Member] = []
    if query.isdigit():
        member = guild.get_member(int(query))
        if member is None:
            try:
                member = await guild.fetch_member(int(query))
            except discord.NotFound:
                member = None
        if member:
            matches.append(member)

    if not matches:
        q = query.lower()
        for member in guild.members:
            if q in member.name.lower() or q in member.display_name.lower():
                matches.append(member)
                if len(matches) >= limit:
                    break

    return [_member_snapshot(m) for m in matches[:limit]]


async def _create_channel(inp: Dict[str, Any], ctx: ToolContext) -> Any:
    guild = _resolve_guild(ctx, inp.get("guild_id"))
    kind = inp["kind"]
    kwargs: Dict[str, Any] = {"name": inp["name"]}
    if inp.get("category_id"):
        category = guild.get_channel(int(inp["category_id"]))
        if not isinstance(category, discord.CategoryChannel):
            raise ValueError("category_id does not point to a category channel")
        kwargs["category"] = category
    if "position" in inp:
        kwargs["position"] = inp["position"]
    if inp.get("nsfw") is not None and kind in ("text", "forum", "announcement"):
        kwargs["nsfw"] = inp["nsfw"]

    if kind == "text":
        if inp.get("topic"):
            kwargs["topic"] = inp["topic"]
        channel = await guild.create_text_channel(**kwargs)
    elif kind == "voice":
        channel = await guild.create_voice_channel(**kwargs)
    elif kind == "category":
        cat_kwargs: Dict[str, Any] = {"name": inp["name"]}
        if "position" in inp:
            cat_kwargs["position"] = inp["position"]
        channel = await guild.create_category(**cat_kwargs)
    elif kind == "forum":
        if inp.get("topic"):
            kwargs["topic"] = inp["topic"]
        channel = await guild.create_forum(**kwargs)
    elif kind == "announcement":
        # discord.py's create_text_channel doesn't expose the announcement flag
        # directly; create a text channel and flip its type afterwards.
        if inp.get("topic"):
            kwargs["topic"] = inp["topic"]
        channel = await guild.create_text_channel(**kwargs)
        try:
            await channel.edit(type=discord.ChannelType.news)
        except (discord.HTTPException, AttributeError):
            pass  # community feature not enabled or unsupported — keep as text
    elif kind == "stage":
        channel = await guild.create_stage_channel(**kwargs)
    else:
        raise ValueError(f"Unsupported channel kind {kind!r}")

    ctx.note(f"created {kind} channel #{channel.name} ({channel.id}) in {guild.name}")
    return _channel_snapshot(channel)


async def _delete_channel(inp: Dict[str, Any], ctx: ToolContext) -> Any:
    channel = ctx.bot.get_channel(int(inp["channel_id"]))
    if channel is None:
        raise ValueError(f"No channel {inp['channel_id']} visible to the bot")
    await channel.delete(reason=inp.get("reason"))
    ctx.note(f"deleted channel {channel.name} ({channel.id})")
    return {"deleted": str(channel.id), "name": channel.name}


async def _rename_channel(inp: Dict[str, Any], ctx: ToolContext) -> Any:
    channel = ctx.bot.get_channel(int(inp["channel_id"]))
    if channel is None:
        raise ValueError(f"No channel {inp['channel_id']} visible to the bot")
    old = channel.name
    await channel.edit(name=inp["new_name"])
    ctx.note(f"renamed channel {old} -> {inp['new_name']}")
    return _channel_snapshot(channel)


async def _set_channel_topic(inp: Dict[str, Any], ctx: ToolContext) -> Any:
    channel = ctx.bot.get_channel(int(inp["channel_id"]))
    if channel is None:
        raise ValueError(f"No channel {inp['channel_id']} visible to the bot")
    await channel.edit(topic=inp["topic"])
    return _channel_snapshot(channel)


async def _create_role(inp: Dict[str, Any], ctx: ToolContext) -> Any:
    guild = _resolve_guild(ctx, inp.get("guild_id"))
    role = await guild.create_role(
        name=inp["name"],
        color=_parse_color(inp.get("color")),
        permissions=_parse_permissions(inp.get("permissions")),
        hoist=bool(inp.get("hoist", False)),
        mentionable=bool(inp.get("mentionable", False)),
    )
    ctx.note(f"created role @{role.name} ({role.id}) in {guild.name}")
    return _role_snapshot(role)


async def _delete_role(inp: Dict[str, Any], ctx: ToolContext) -> Any:
    guild = _resolve_guild(ctx, inp.get("guild_id"))
    role = guild.get_role(int(inp["role_id"]))
    if role is None:
        raise ValueError(f"No role {inp['role_id']} in guild {guild.name}")
    await role.delete(reason=inp.get("reason"))
    ctx.note(f"deleted role @{role.name}")
    return {"deleted": str(role.id), "name": role.name}


async def _assign_role(inp: Dict[str, Any], ctx: ToolContext) -> Any:
    guild = _resolve_guild(ctx, inp.get("guild_id"))
    member = guild.get_member(int(inp["user_id"]))
    if member is None:
        member = await guild.fetch_member(int(inp["user_id"]))
    role = guild.get_role(int(inp["role_id"]))
    if role is None:
        raise ValueError(f"No role {inp['role_id']} in guild {guild.name}")
    await member.add_roles(role, reason=inp.get("reason"))
    return {"member": _member_snapshot(member), "role": _role_snapshot(role)}


async def _remove_role(inp: Dict[str, Any], ctx: ToolContext) -> Any:
    guild = _resolve_guild(ctx, inp.get("guild_id"))
    member = guild.get_member(int(inp["user_id"]))
    if member is None:
        member = await guild.fetch_member(int(inp["user_id"]))
    role = guild.get_role(int(inp["role_id"]))
    if role is None:
        raise ValueError(f"No role {inp['role_id']} in guild {guild.name}")
    await member.remove_roles(role, reason=inp.get("reason"))
    return {"member": _member_snapshot(member), "role": _role_snapshot(role)}


async def _ban_member(inp: Dict[str, Any], ctx: ToolContext) -> Any:
    user_id = int(inp["user_id"])
    reason = inp.get("reason")
    delete_days = int(inp.get("delete_message_days", 0))
    scope = inp.get("scope", "one_guild")

    if scope == "all_guilds":
        if not ctx.allow_cross_guild:
            raise PermissionError("Cross-guild actions are disabled for this run.")
        results: List[Dict[str, Any]] = []
        user = await ctx.bot.fetch_user(user_id)
        for guild in ctx.bot.guilds:
            me = guild.me
            if me is None or not me.guild_permissions.ban_members:
                results.append({"guild": guild.name, "status": "skipped", "reason": "bot lacks Ban Members"})
                continue
            try:
                await guild.ban(user, reason=reason, delete_message_days=delete_days)
                results.append({"guild": guild.name, "guild_id": str(guild.id), "status": "banned"})
                ctx.note(f"banned {user} from {guild.name}")
            except discord.Forbidden:
                results.append({"guild": guild.name, "status": "forbidden"})
            except discord.HTTPException as exc:
                results.append({"guild": guild.name, "status": "error", "error": str(exc)})
        return {"user_id": str(user_id), "scope": "all_guilds", "results": results}

    guild = _resolve_guild(ctx, inp.get("guild_id"))
    user = await ctx.bot.fetch_user(user_id)
    await guild.ban(user, reason=reason, delete_message_days=delete_days)
    ctx.note(f"banned {user} from {guild.name}")
    return {"user_id": str(user_id), "guild_id": str(guild.id), "status": "banned"}


async def _unban_member(inp: Dict[str, Any], ctx: ToolContext) -> Any:
    guild = _resolve_guild(ctx, inp.get("guild_id"))
    user = await ctx.bot.fetch_user(int(inp["user_id"]))
    await guild.unban(user, reason=inp.get("reason"))
    return {"user_id": str(user.id), "guild_id": str(guild.id), "status": "unbanned"}


async def _kick_member(inp: Dict[str, Any], ctx: ToolContext) -> Any:
    guild = _resolve_guild(ctx, inp.get("guild_id"))
    member = guild.get_member(int(inp["user_id"]))
    if member is None:
        member = await guild.fetch_member(int(inp["user_id"]))
    await member.kick(reason=inp.get("reason"))
    return {"user_id": str(member.id), "guild_id": str(guild.id), "status": "kicked"}


async def _timeout_member(inp: Dict[str, Any], ctx: ToolContext) -> Any:
    from datetime import timedelta

    guild = _resolve_guild(ctx, inp.get("guild_id"))
    member = guild.get_member(int(inp["user_id"]))
    if member is None:
        member = await guild.fetch_member(int(inp["user_id"]))
    minutes = int(inp["minutes"])
    await member.timeout(timedelta(minutes=minutes), reason=inp.get("reason"))
    return {"user_id": str(member.id), "guild_id": str(guild.id), "timeout_minutes": minutes}


async def _send_message(inp: Dict[str, Any], ctx: ToolContext) -> Any:
    channel = ctx.bot.get_channel(int(inp["channel_id"]))
    if channel is None:
        raise ValueError(f"No channel {inp['channel_id']} visible to the bot")
    if not hasattr(channel, "send"):
        raise ValueError("Channel is not messageable")
    message = await channel.send(inp["content"])
    return {"message_id": str(message.id), "channel_id": str(channel.id)}


async def _bulk_delete(inp: Dict[str, Any], ctx: ToolContext) -> Any:
    channel = ctx.bot.get_channel(int(inp["channel_id"]))
    if not isinstance(channel, discord.TextChannel):
        raise ValueError("bulk_delete only works on text channels")
    count = int(inp["count"])
    deleted = await channel.purge(limit=count)
    return {"channel_id": str(channel.id), "deleted": len(deleted)}


async def _finish(inp: Dict[str, Any], ctx: ToolContext) -> Any:
    return {"summary": inp["summary"]}


ToolHandler = Callable[[Dict[str, Any], ToolContext], Awaitable[Any]]

TOOL_HANDLERS: Dict[str, ToolHandler] = {
    "list_guilds": _list_guilds,
    "get_guild_info": _get_guild_info,
    "find_member": _find_member,
    "create_channel": _create_channel,
    "delete_channel": _delete_channel,
    "rename_channel": _rename_channel,
    "set_channel_topic": _set_channel_topic,
    "create_role": _create_role,
    "delete_role": _delete_role,
    "assign_role": _assign_role,
    "remove_role": _remove_role,
    "ban_member": _ban_member,
    "unban_member": _unban_member,
    "kick_member": _kick_member,
    "timeout_member": _timeout_member,
    "send_message": _send_message,
    "bulk_delete": _bulk_delete,
    "finish": _finish,
}


async def run_tool(name: str, payload: Dict[str, Any], ctx: ToolContext, timeout: float = 30.0) -> Any:
    handler = TOOL_HANDLERS.get(name)
    if handler is None:
        raise ValueError(f"Unknown tool: {name}")
    return await asyncio.wait_for(handler(payload, ctx), timeout=timeout)
