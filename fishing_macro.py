"""Two priority-aware repeating timers for a Roblox macro: one that keeps
casting/fishing, and one that fires periodically to use an item — pausing
the fishing timer for the duration of the item use and resuming it right
after.

This is the *scheduling* skeleton only. `start_fishing()` and `use_item()`
below are placeholders — replace their bodies with your actual input
sequence (e.g. `adb shell input`/`sendevent` calls).

A note on "interrupt": each timer's callback is treated as a short,
non-blocking action. A higher-priority timer pauses lower-priority timers
*between* their calls, not mid-callback — true mid-call preemption would
need the callback itself to check in periodically, which only makes sense
once you know what `start_fishing()` actually does. If your fishing
sequence is long-running (e.g. it blocks waiting for a bite), have it poll
a shared `threading.Event` and bail out early; ask and this can be wired in.

    python3 fishing_macro.py                        # run both timers
    python3 fishing_macro.py --fish-every 5 --item-every 60
"""

from __future__ import annotations

import argparse
import threading
import time


class SetTimer:
    """Repeatedly calls `callback` every `interval` seconds on its own thread.

    Can be paused between cycles by a higher-priority timer and resumed
    afterward — `pause()` blocks the loop before its next callback fires;
    `resume()` lets it continue from there.
    """

    def __init__(self, name: str, interval: float, callback, priority: int = 0):
        self.name = name
        self.interval = interval
        self.callback = callback
        self.priority = priority
        self._running = False
        self._allowed = threading.Event()
        self._allowed.set()
        self._thread: threading.Thread | None = None

    def start(self) -> None:
        self._running = True
        self._thread = threading.Thread(target=self._loop, name=self.name, daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._running = False
        self._allowed.set()  # unblock a paused thread so it can exit
        if self._thread:
            self._thread.join(timeout=self.interval + 1)

    def pause(self) -> None:
        self._allowed.clear()

    def resume(self) -> None:
        self._allowed.set()

    def _loop(self) -> None:
        while self._running:
            self._allowed.wait()
            if not self._running:
                break
            self.callback()
            time.sleep(self.interval)


class PriorityTimerManager:
    """Runs several `SetTimer`s together. When a higher-priority timer's
    callback fires, every lower-priority timer is paused for the duration
    of that callback and resumed right after — so the fishing loop gets
    interrupted to use an item, then picks back up where it left off."""

    def __init__(self):
        self._timers: dict[str, SetTimer] = {}

    def add_timer(self, name: str, interval: float, callback, priority: int = 0) -> SetTimer:
        timer = SetTimer(name, interval, self._with_interrupt(callback, priority), priority)
        self._timers[name] = timer
        return timer

    def _with_interrupt(self, callback, priority: int):
        def wrapped():
            lower = [t for t in self._timers.values() if t.priority < priority]
            for t in lower:
                t.pause()
            try:
                callback()
            finally:
                for t in lower:
                    t.resume()
        return wrapped

    def start_all(self) -> None:
        for t in self._timers.values():
            t.start()

    def stop_all(self) -> None:
        for t in self._timers.values():
            t.stop()


# ---------------------------------------------------------------------------
# The two timers requested: fishing (low priority, keeps looping) and item
# use (higher priority — interrupts fishing, then lets it continue).
# ---------------------------------------------------------------------------

def start_fishing() -> None:
    """Placeholder — put your cast/wait-for-bite/reel-in sequence here."""
    print("[fishing] casting...")


def use_item() -> None:
    """Placeholder — put your item-use input sequence here."""
    print("[item] using item...")


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--fish-every", type=float, default=5.0,
        help="Seconds between fishing timer calls (default: 5).",
    )
    parser.add_argument(
        "--item-every", type=float, default=60.0,
        help="Seconds between item-use timer calls (default: 60).",
    )
    args = parser.parse_args(argv)

    manager = PriorityTimerManager()
    manager.add_timer("fishing", args.fish_every, start_fishing, priority=0)
    manager.add_timer("item", args.item_every, use_item, priority=1)

    print(
        f"Fishing every {args.fish_every}s, item use every {args.item_every}s "
        "(item use interrupts fishing, then fishing resumes). Ctrl+C to stop."
    )
    manager.start_all()
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nStopping...")
    finally:
        manager.stop_all()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
