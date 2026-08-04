# kiaracollab

A Discord bot built around a single slash command, **`/task`**, plus a small
`/uptime` utility command.

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

## Web front-end

The repo ships a small static website — the bot's landing page — served by a
lightweight Flask app that lives in [`web/`](web/). It's a moderation-focused
showcase (features, command reference, safety notes, setup) and it also shows
the bot's **live status**: whether it's online, how many servers and members
it's watching, and its uptime.

It's off by default. To serve it while the bot runs, set `WEB_ENABLED=true`
(and optionally `WEB_HOST`/`WEB_PORT`) in `.env`, then start the bot as usual:

```sh
python bot.py
# then open http://127.0.0.1:8080
```

How it fits together:

- The Discord client pushes a plain-data snapshot of its state into a
  thread-safe holder ([`web/status.py`](web/status.py)) whenever it becomes
  ready or joins/leaves a guild.
- The Flask app ([`web/server.py`](web/server.py)) runs in a daemon thread
  alongside the bot's asyncio loop. It serves the static page from
  [`web/static/`](web/static/) and one JSON endpoint, `/api/status`, backed by
  that snapshot.
- The page ([`web/static/app.js`](web/static/app.js)) polls `/api/status`
  every few seconds and updates the status pill and stat cards, falling back
  to an "offline" state if the bot isn't reachable.

| Variable | Meaning |
| --- | --- |
| `WEB_ENABLED` | Serve the landing page while the bot runs. Default `false`. |
| `WEB_HOST` | Interface to bind. `127.0.0.1` = local only; `0.0.0.0` to expose. |
| `WEB_PORT` | Port for the web front-end. Default `8080`. |

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

## Bundled utility: disk_usage_scanner.py

Another standalone tool unrelated to the bot: a dark-mode desktop GUI that
browses your folders and shows file/folder sizes, similar to a normal file
explorer.

`disk_usage_scanner.py` uses only Python's standard library (`tkinter`) —
no extra dependencies for browsing. On Linux, `tkinter` is often a separate
OS package (e.g. `sudo apt install python3-tk`); it's bundled with the
official Python installer on Windows and macOS.

Run it with:

```sh
python3 disk_usage_scanner.py            # starts at your home folder
python3 disk_usage_scanner.py /some/path # starts at a specific folder
```

Folders start collapsed and are scanned only when you expand them, so it
opens instantly even on a large drive. Each folder's total size is
computed in a background thread and fills in next to it once ready,
without freezing the window. Double-click a folder to browse into it, or
use the path bar / Up / Refresh controls at the top.

Every row has a **Delete?** checkbox (click the cell to toggle). Folders
that share a name — e.g. a `.minecraft` under both `AppData/Roaming` and
`AppData/Local` — are treated as the same app's data and toggle together;
a same-named folder nested inside a `Thunderstore` folder is *not* linked
in, since that's the mod manager's own cache, not the game's.

**AI Recommendations** sends the currently-scanned rows (name, type, size)
to Claude and pre-checks whatever it flags as safe to delete (caches, temp
files, build artifacts, stale data), showing its reasons in a popup. This
reuses the same `ANTHROPIC_API_KEY` / `CLAUDE_MODEL` setup as `/task` (see
`.env.example`) and additionally needs `python-dotenv` and `anthropic`
installed — browsing and manual deletion still don't need either.

**Delete Checked** permanently deletes every checked row after one
confirmation prompt listing what's about to go. There's no undo, so double
check the list — especially anything the AI pre-checked — before
confirming.

## Bundled utility: alexa_discord_mute.py

Say **"Alexa, Stummschaltung"** and it toggles your Discord microphone mute.

Alexa can't run a command on your PC directly, but it can switch smart-home
plugs on and off with no cloud skill or account linking. `alexa_discord_mute.py`
pretends to be one of those plugs (a Belkin WeMo socket). When Alexa turns the
plug on or off, the script presses Discord's *Toggle Mute* hotkey — a self-mute
of your mic only, so you still hear everyone (it does **not** deafen you).

```
"Alexa, Stummschaltung"  ->  Alexa flips the emulated plug
                         ->  the script presses a global hotkey
                         ->  Discord toggles your mic mute
```

Everything except the key-press uses only Python's standard library; the
key-press needs [`pynput`](https://pypi.org/project/pynput/):

```sh
pip install pynput
```

Setup, once:

1. In Discord: *User Settings → Keybinds → Add a Keybind*, choose action
   **Toggle Mute**, and record the same combo the script sends
   (default `Ctrl+Alt+M`). Discord keybinds are global, so they fire even when
   Discord isn't the focused window.
2. Run the script on the PC that runs Discord, on the same network as your
   Echo:

   ```sh
   python3 alexa_discord_mute.py
   ```

3. Say *"Alexa, discover devices"* (or Alexa app → *Devices → +*). A plug
   named **Stummschaltung** appears.
4. Say *"Alexa, turn on Stummschaltung"* to toggle your mute. For the exact
   phrase *"Alexa, Stummschaltung"*, make an Alexa **Routine** whose spoken
   phrase is `Stummschaltung` and whose action turns that plug on. Because the
   script treats every on/off as a toggle, each trigger simply flips your mic.

Handy flags:

```sh
python3 alexa_discord_mute.py --name "Mute"          # rename the device
python3 alexa_discord_mute.py --hotkey ctrl+shift+m  # match a different keybind
python3 alexa_discord_mute.py --test                 # fire the hotkey once and exit
```

Use `--test` first to confirm the hotkey actually flips your Discord mute
before wiring up Alexa.

### If Alexa can't find the device

WeMo-style discovery is the fiddly part. The script announces itself on the
network every 30 seconds (not just when Alexa asks), which is what lets an Echo
find it — but a few things still trip it up:

- **Same network.** The PC and the Echo must be on the *same* Wi-Fi and subnet.
  Guest networks and "AP/client isolation" block the discovery traffic. 2.4GHz
  vs 5GHz on the same router is usually fine.
- **Firewall.** When Windows first runs it, click **Allow access** on the
  firewall prompt (Private networks). If you dismissed it, allow
  `python.exe` through Windows Defender Firewall, or the Echo can't reach the
  device's little web server.
- **Port 1900 already in use.** On Windows the built-in *SSDP Discovery*
  service often owns UDP 1900. The script prints a note if so and keeps
  working via its own announcements, so this is usually harmless — but if
  discovery still fails you can stop that service (`services.msc` → *SSDP
  Discovery* → Stop) and restart the script.
- **Watch the log.** Run it, say *"Alexa, discover devices"*, and watch the
  window. A line like `Alexa fetched setup.xml … device is being discovered`
  means it worked. No such line after ~45 seconds points to network/firewall,
  not the script. Add `--verbose` to also see each incoming search.
- **Give it a moment / retry.** Discovery can take 20–45 seconds; if the first
  *"discover devices"* finds nothing, leave the script running and say it once
  more.
- **Port clash on startup.** If the script itself won't start because port
  52000 is taken, pass another one: `python3 alexa_discord_mute.py --port 52001`.

## Bundled utility: fishing_macro.py

A small priority-aware timer scheduler, meant as the skeleton for a Roblox
macro: one timer that keeps calling a fishing routine, and a second,
higher-priority timer that fires periodically to use an item — pausing the
fishing timer for the duration of the item use and resuming it right after.

`fishing_macro.py` uses only Python's standard library. `start_fishing()`
and `use_item()` are placeholders — fill them in with your actual input
sequence (e.g. `adb shell input`/`sendevent` calls).

```sh
python3 fishing_macro.py                        # run both timers
python3 fishing_macro.py --fish-every 5 --item-every 60
```

The two timers are plain `SetTimer` instances registered on a
`PriorityTimerManager`; add more by calling `manager.add_timer(name,
interval, callback, priority=...)` — any timer with a lower priority than
the one currently firing gets paused for that call and resumed after.

---

$$\Huge{\textsf{{\color{#e81416}a}{\color{#ffa500}d}{\color{#faeb36}e}{\color{#79c314}l}{\color{#487de7}n}{\color{#4b369d}o}{\color{#70369d}n}}}$$
