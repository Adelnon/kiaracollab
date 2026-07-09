# kiaracollab

A Discord bot whose entire interface is a single slash command: **`/task`**.

Type what you want done and Claude figures out how to do it using Discord's
API — creating channels and roles, banning or timing out users, sending
messages, or building out an entire server layout in one shot.

Examples:

```
/task set this server up like a general community — welcome, rules,
      announcements, general chat, voice lounge, and a mod-only channel
/task ban <@842…> from every server this bot is in
/task give @newbie the Member role and send them a hi in #welcome
/task rename #general to #lobby and set its topic to "hang out here"
```

## How the /task command works

1. You send `/task <request>`.
2. The bot hands your request to Claude, which is given a set of Discord
   tools (list guilds, look up members, create/delete channels and roles,
   ban/kick/timeout, send messages, and so on).
3. Claude picks a sequence of tools, the bot runs them, and Claude keeps
   going until it calls `finish` with a plain-English summary — which is
   what you see back in Discord.

The tool set, the schemas Claude sees, and the safety caps live in
[`tools.py`](tools.py). The Claude loop lives in [`bot.py`](bot.py).

## Setup

1. **Install** (Python 3.10+):

   ```sh
   python3 -m venv .venv
   source .venv/bin/activate
   pip install -r requirements.txt
   ```

2. **Create the Discord application** at
   <https://discord.com/developers/applications>:
   - Under *Bot* → *Reset Token*, copy the token.
   - Enable the **Server Members Intent** and **Message Content Intent**
     (both are privileged intents).
   - Under *OAuth2 → URL Generator*, tick `bot` and `applications.commands`
     scopes and give it at least these bot permissions: *Manage Channels*,
     *Manage Roles*, *Kick Members*, *Ban Members*, *Moderate Members*,
     *Send Messages*, *Manage Messages*. Invite the bot to your server with
     the generated URL.

3. **Get an Anthropic API key** at
   <https://console.anthropic.com/settings/keys>.

4. **Configure**:

   ```sh
   cp .env.example .env
   # edit .env — at minimum set DISCORD_TOKEN and ANTHROPIC_API_KEY
   ```

   Optional settings in `.env`:

   | Variable | Meaning |
   | --- | --- |
   | `CLAUDE_MODEL` | Model id — defaults to `claude-sonnet-5`. |
   | `TASK_ALLOWED_USER_IDS` | Comma-separated user IDs allowed to run `/task`. Empty = anyone with the guild *Administrator* permission. |
   | `TASK_ALLOWED_GUILD_IDS` | Restrict `/task` to specific guild IDs. Empty = all guilds. |
   | `MAX_AGENT_TURNS` | Safety cap on how many tool-use turns Claude gets per invocation. Default `12`. |

5. **Run**:

   ```sh
   python bot.py
   ```

   Slash commands are synced globally on startup; the first sync can take
   up to an hour to appear in a guild. Subsequent runs are instant.

## Safety notes

- `/task` is gated: only users in `TASK_ALLOWED_USER_IDS` (or, if that's
  empty, guild Administrators) can run it.
- The bot only ever does what its Discord permissions allow — a ban with
  no *Ban Members* permission returns `forbidden`, not a crash.
- `ban_member` supports `scope=all_guilds` for the "kick this user out of
  every server we share" case. Every ban still requires the bot to hold
  *Ban Members* in that specific guild; guilds where it doesn't are
  reported as `skipped`.
- Discord bots **cannot** create a whole new Discord guild via the API,
  so "make me a Discord server" is interpreted as building out the
  invoking guild.

## Bundled utility: calculator.py

The repo also ships a tiny standalone Python calculator that predates the
bot.

`calculator.py` is a standalone Python 3 script — no third-party
dependencies are required. Make sure you have Python 3 installed, then
run it in one of two modes.

### One-shot mode

```sh
python3 calculator.py 3 + 4
# 7.0

python3 calculator.py "6 * 7"
# 42.0
```

Because most shells treat `*` as a glob, quote expressions that use
multiplication or exponentiation.

### Interactive mode (REPL)

```sh
python3 calculator.py
```

```
Simple Calculator (type 'quit' or 'exit' to stop)
Supported operators: +, -, *, /, //, %, **
> 3 + 4
7.0
> quit
```

Each expression must be exactly `<number> <operator> <number>` with spaces
around the operator. Supported operators: `+`, `-`, `*`, `/`, `//`, `%`,
`**`.

---

$${\color{red}\Huge{\textsf{adelnon}}}$$
