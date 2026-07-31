"""Lightweight Flask front-end for the bot.

Serves the static landing page in ``static/`` and exposes one JSON endpoint,
``/api/status``, backed by the :class:`~web.status.BotStatus` snapshot the
Discord client keeps up to date.

The server is started from ``bot.py`` in a daemon thread so it lives alongside
the bot's asyncio loop without blocking it. It is entirely optional — the bot
runs fine with the web front-end disabled.
"""

from __future__ import annotations

import logging
import threading
from pathlib import Path

from flask import Flask, jsonify, send_from_directory

from .status import BotStatus

log = logging.getLogger("kiara.web")

STATIC_DIR = Path(__file__).resolve().parent / "static"


def create_app(status: BotStatus) -> Flask:
    """Build the Flask app bound to a shared :class:`BotStatus`."""
    app = Flask(__name__, static_folder=None)

    @app.route("/")
    def index() -> object:
        return send_from_directory(STATIC_DIR, "index.html")

    @app.route("/api/status")
    def api_status() -> object:
        return jsonify(status.snapshot())

    @app.route("/<path:filename>")
    def static_files(filename: str) -> object:
        # Serve CSS/JS/assets from the static directory.
        return send_from_directory(STATIC_DIR, filename)

    return app


def start_web_server(status: BotStatus, host: str, port: int) -> threading.Thread:
    """Run the Flask app in a daemon thread and return the thread.

    A daemon thread is used so the process exits cleanly when the bot stops.
    The built-in server is fine here: this only serves a small static page and
    a status endpoint for a handful of viewers, not production traffic.
    """
    app = create_app(status)

    def _run() -> None:
        log.info("web front-end listening on http://%s:%d", host, port)
        # use_reloader=False — the reloader spawns a second process, which we
        # never want inside the bot; threaded=True so status polls don't block.
        app.run(host=host, port=port, threaded=True, use_reloader=False, debug=False)

    thread = threading.Thread(target=_run, name="kiara-web", daemon=True)
    thread.start()
    return thread
