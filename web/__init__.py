"""Small web front-end for the Kiara moderation bot.

`status.py` holds a thread-safe snapshot of the bot's live state that the
Discord client updates from its event loop, and `server.py` is a lightweight
Flask app (run in a daemon thread) that serves the static landing page and a
single `/api/status` JSON endpoint the page polls to show whether the bot is
online.
"""
