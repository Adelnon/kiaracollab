"""
Fast power-bar automation for Roblox soccer kick game.
Replaces AHK PixelSearch with mss + numpy for sub-5ms detection.

Install:  pip install mss numpy keyboard
Run:      python kick_bot.py

Hotkeys:
  F1  Start
  F2  Pause / Resume
  F3  Exit
"""

import ctypes
import ctypes.wintypes as wt
import sys
import threading
import time

import keyboard
import mss
import numpy as np

# ── Windows API ──────────────────────────────────────────────────────────

user32 = ctypes.windll.user32
gdi32 = ctypes.windll.gdi32


class MONITORINFO(ctypes.Structure):
    _fields_ = [
        ("cbSize", ctypes.c_ulong),
        ("rcMonitor", wt.RECT),
        ("rcWork", wt.RECT),
        ("dwFlags", ctypes.c_ulong),
    ]


MOUSEEVENTF_LEFTDOWN = 0x0002
MOUSEEVENTF_LEFTUP = 0x0004
GWL_STYLE = -16
WS_CAPTION = 0xC00000
WS_THICKFRAME = 0x40000
SW_RESTORE = 9

# ── Coordinates (window-relative, 1080p) ────────────────────────────────

KICK_X, KICK_Y = 597, 931

# Red zone: center of power bar — present when a kick is active
RED_X1, RED_Y1 = 574, 797
RED_X2, RED_Y2 = 600, 850

# Green zone: full bar width — appears at 100%
GREEN_X1, GREEN_Y1 = 375, 736
GREEN_X2, GREEN_Y2 = 806, 785

# Combined capture region (single grab covers both checks)
CAP_LEFT = min(RED_X1, GREEN_X1)
CAP_TOP = min(RED_Y1, GREEN_Y1)
CAP_RIGHT = max(RED_X2, GREEN_X2)
CAP_BOTTOM = max(RED_Y2, GREEN_Y2)
CAP_W = CAP_RIGHT - CAP_LEFT
CAP_H = CAP_BOTTOM - CAP_TOP

# Sub-region slices within the combined capture
_rs = np.s_[RED_Y1 - CAP_TOP : RED_Y2 - CAP_TOP, RED_X1 - CAP_LEFT : RED_X2 - CAP_LEFT]
_gs = np.s_[GREEN_Y1 - CAP_TOP : GREEN_Y2 - CAP_TOP, GREEN_X1 - CAP_LEFT : GREEN_X2 - CAP_LEFT]

# Target colors (RGB) and tolerances
RED_RGB = np.array([0xFF, 0x2C, 0x2C], dtype=np.int16)
GREEN_RGB = np.array([0x55, 0xFF, 0x00], dtype=np.int16)
RED_TOL = 1
GREEN_TOL = 0

# ── State ────────────────────────────────────────────────────────────────

_lock = threading.Lock()
_running = False
_paused = False
_held = False


# ── Helpers ──────────────────────────────────────────────────────────────


def _client_origin(hwnd):
    pt = wt.POINT(0, 0)
    user32.ClientToScreen(hwnd, ctypes.byref(pt))
    return pt.x, pt.y


def _unfullscreen(hwnd):
    wr = wt.RECT()
    user32.GetWindowRect(hwnd, ctypes.byref(wr))
    w = wr.right - wr.left
    h = wr.bottom - wr.top

    hmon = user32.MonitorFromWindow(hwnd, 2)
    mi = MONITORINFO(cbSize=ctypes.sizeof(MONITORINFO))
    user32.GetMonitorInfoW(hmon, ctypes.byref(mi))
    mw = mi.rcMonitor.right - mi.rcMonitor.left
    mh = mi.rcMonitor.bottom - mi.rcMonitor.top

    if w == mw and h == mh:
        user32.ShowWindow(hwnd, SW_RESTORE)
        style = user32.GetWindowLongW(hwnd, GWL_STYLE)
        user32.SetWindowLongW(hwnd, GWL_STYLE, style | WS_CAPTION | WS_THICKFRAME)
        nw, nh = int(mw * 0.8), int(mh * 0.8)
        nx = mi.rcMonitor.left + (mw - nw) // 2
        ny = mi.rcMonitor.top + (mh - nh) // 2
        user32.MoveWindow(hwnd, nx, ny, nw, nh, True)


def _mouse_down(sx, sy):
    global _held
    user32.SetCursorPos(sx, sy)
    user32.mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0)
    _held = True


def _mouse_up():
    global _held
    if _held:
        user32.mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0)
        _held = False


def _has_color(sub, rgb, tol):
    r = sub[:, :, 2].astype(np.int16)
    g = sub[:, :, 1].astype(np.int16)
    b = sub[:, :, 0].astype(np.int16)
    return np.any(
        (np.abs(r - rgb[0]) <= tol)
        & (np.abs(g - rgb[1]) <= tol)
        & (np.abs(b - rgb[2]) <= tol)
    )


# ── Main loop ────────────────────────────────────────────────────────────


def _main():
    global _running, _paused

    sct = mss.mss()

    while _running:
        if _paused:
            time.sleep(0.05)
            continue

        hwnd = user32.GetForegroundWindow()
        if not hwnd:
            time.sleep(0.1)
            continue

        _unfullscreen(hwnd)
        ox, oy = _client_origin(hwnd)

        region = {
            "left": ox + CAP_LEFT,
            "top": oy + CAP_TOP,
            "width": CAP_W,
            "height": CAP_H,
        }

        _mouse_down(ox + KICK_X, oy + KICK_Y)
        time.sleep(0.35)

        while _running and not _paused:
            frame = np.array(sct.grab(region))

            if not _has_color(frame[_rs], RED_RGB, RED_TOL):
                _mouse_up()
                break

            if _has_color(frame[_gs], GREEN_RGB, GREEN_TOL):
                _mouse_up()
                while _running and not _paused:
                    f = np.array(sct.grab(region))
                    if not _has_color(f[_rs], RED_RGB, RED_TOL):
                        time.sleep(0.5)
                        break
                break

    _mouse_up()


# ── Hotkeys ──────────────────────────────────────────────────────────────


def _on_f1():
    global _running
    with _lock:
        if _running:
            return
        _running = True
    print("[F1] Started")
    threading.Thread(target=_main, daemon=True).start()


def _on_f2():
    global _paused
    _paused = not _paused
    print(f"[F2] {'Paused' if _paused else 'Resumed'}")
    if _paused:
        _mouse_up()


def _on_f3():
    global _running
    print("[F3] Exiting")
    _running = False
    _mouse_up()
    time.sleep(0.1)
    sys.exit(0)


if __name__ == "__main__":
    print("Roblox Kick Bot")
    print("  F1  Start")
    print("  F2  Pause / Resume")
    print("  F3  Exit")
    print()

    keyboard.on_press_key("f1", lambda _: _on_f1(), suppress=True)
    keyboard.on_press_key("f2", lambda _: _on_f2(), suppress=True)
    keyboard.on_press_key("f3", lambda _: _on_f3(), suppress=True)

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        _running = False
        _mouse_up()
