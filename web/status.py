"""Thread-safe snapshot of the bot's live state.

The Discord client runs in its own asyncio event loop; Flask serves requests
from a separate thread. Rather than reaching across threads into discord.py
objects (which isn't safe), the bot pushes a plain-data snapshot into this
holder whenever its state changes, and the web layer only ever reads that
snapshot under a lock.
"""

from __future__ import annotations

import threading
import time
from typing import Any, Dict, List, Optional


class BotStatus:
    """A small, lock-guarded view of the bot for the web front-end.

    Only JSON-serialisable primitives are stored here — never live discord.py
    objects — so the Flask thread can read it without touching the bot's loop.
    """

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._online: bool = False
        self._username: Optional[str] = None
        self._guild_count: int = 0
        self._member_count: int = 0
        self._guilds: List[Dict[str, Any]] = []
        # Wall-clock epoch seconds when the bot came online; None while offline.
        self._ready_since: Optional[float] = None

    def set_online(
        self,
        *,
        username: str,
        guilds: List[Dict[str, Any]],
        member_count: int,
    ) -> None:
        with self._lock:
            self._online = True
            self._username = username
            self._guilds = list(guilds)
            self._guild_count = len(guilds)
            self._member_count = member_count
            if self._ready_since is None:
                self._ready_since = time.time()

    def set_offline(self) -> None:
        with self._lock:
            self._online = False
            self._ready_since = None

    def snapshot(self) -> Dict[str, Any]:
        """Return a JSON-serialisable dict describing the current state."""
        with self._lock:
            uptime = (
                int(time.time() - self._ready_since)
                if self._online and self._ready_since is not None
                else 0
            )
            return {
                "online": self._online,
                "username": self._username,
                "guild_count": self._guild_count,
                "member_count": self._member_count,
                "uptime_seconds": uptime,
                "guilds": list(self._guilds),
            }
