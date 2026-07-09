# Kiara AI Task Bot

A minimal Discord bot with a single slash command, `/task`, that turns a natural-language
request into one of a small, fixed set of server actions using Claude.

```
/task make me a #announcements channel
/task create a role called "Events Team" in a nice purple
/task kick @someone for spamming links
```

## How it works

1. `/task <prompt>` is sent to Claude along with the current server/channel/user and a fixed
   list of tool definitions (`src/ai/tools.js`).
2. Claude picks at most one tool call, or replies with plain text if nothing fits or the
   request is unclear.
3. The bot re-checks real Discord permissions for both the invoking member and the bot itself
   before doing anything -- the model's tool choice is never trusted on its own.
4. Destructive actions (kick, ban, timeout, creating a new server) require an extra
   Confirm/Cancel button click before they run.
5. If `MOD_LOG_CHANNEL_ID` is set, every executed action is logged there with the prompt, the
   tool used, and the result.

## Safety scoping (read before extending)

Every moderation/management tool operates **only on the server the command was run in**. There
is intentionally no tool that acts across multiple servers -- e.g. no "ban this user from every
server the bot is in" action. A single natural-language command that can deplatform someone from
communities they have nothing to do with, based only on one server's moderator's say-so (or a
cleverly worded prompt), is a harassment vector, not a moderation feature. `src/ai/agent.js`'s
system prompt explicitly tells the model to refuse "all servers" style requests, and the
`ban_member`/`kick_member` tool schemas only accept a target user id, scoped to
`interaction.guild`.

If you have a legitimate need for cross-server bans (e.g. a shared abuse blocklist across a
family of servers you administer), build it as its own explicit, owner-only, audited command --
not as a side effect of free-text `/task` prompts.

## Setup

1. Create an application at the [Discord Developer Portal](https://discord.com/developers/applications),
   add a Bot user, and copy the bot token and application (client) id.
2. Invite the bot to your server with the `bot` and `applications.commands` OAuth2 scopes and
   whatever permissions you want it able to use (Manage Channels, Manage Roles, Kick Members,
   Ban Members, Moderate Members, etc. -- the bot can never do more than the permissions you
   grant it, regardless of what a prompt asks for).
3. Copy `.env.example` to `.env` and fill in `DISCORD_TOKEN`, `DISCORD_CLIENT_ID`,
   `ANTHROPIC_API_KEY`, and optionally `OWNER_ID` / `MOD_LOG_CHANNEL_ID`.
4. Install dependencies and register the command:
   ```
   npm install
   npm run deploy-commands
   ```
5. Start the bot:
   ```
   npm start
   ```

## Adding new actions

Add a new entry to `TOOL_DEFINITIONS` and a matching handler in `TOOL_HANDLERS`
(`src/ai/tools.js`). Handlers should always re-check Discord permissions themselves and call
`confirmAction()` for anything hard to reverse.
