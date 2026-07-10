#Requires AutoHotkey v2.0
#SingleInstance Force

CoordMode "Mouse", "Window"
CoordMode "Pixel", "Window"

; ── Config ─────────────────────────────────────────────────────────
WINDOW_TITLE := "Roblox"

; Scan region on the bar (window-relative). Keep this tight around
; the bar strip for fastest possible PixelSearch.
SCAN_X1 := 400
SCAN_Y1 := 490
SCAN_X2 := 1120
SCAN_Y2 := 510

; Target color on the bar (hex 0xRRGGBB) and tolerance.
TARGET_COLOR := 0xFF2828
COLOR_VARIATION := 25

; Key to hold while the target color is on the bar.
HOLD_KEY := "e"

; Grace period (ms): how long to keep holding after the color
; disappears, so fast bar flicker doesn't cause a micro-release.
HOLD_GRACE_MS := 120

; ── State ──────────────────────────────────────────────────────────
isActive := false
isHolding := false
lastSeenTick := 0

; ── Hotkeys ────────────────────────────────────────────────────────
F6::ToggleScan()
F7::ExitApp()

ToggleScan() {
    global isActive
    isActive := !isActive
    if isActive {
        ToolTip("Scan ON")
        SetTimer(ClearTip, -1500)
        ScanLoop()
    } else {
        ForceRelease()
        ToolTip("Scan OFF")
        SetTimer(ClearTip, -1500)
    }
}

ClearTip() {
    ToolTip()
}

; ── UnfullscreenIfActive ───────────────────────────────────────────
; Pulls the Roblox window out of borderless-fullscreen so
; window-relative PixelSearch coordinates work correctly.
UnfullscreenIfActive() {
    global WINDOW_TITLE
    if !WinExist(WINDOW_TITLE)
        return
    WinGetPos(&X, &Y, &W, &H, WINDOW_TITLE)
    if (X == 0 && Y == 0 && W == A_ScreenWidth && H == A_ScreenHeight) {
        WinRestore(WINDOW_TITLE)
        WinMove(50, 50, A_ScreenWidth - 100, A_ScreenHeight - 100, WINDOW_TITLE)
    }
}

; ── Core detection loop ────────────────────────────────────────────
; NO Sleep in the hot path. PixelSearch runs back-to-back so nothing
; on a fast-moving bar is missed. The hold stays active as long as
; the color keeps appearing; it only releases after HOLD_GRACE_MS of
; continuous absence — not after a fixed interval.
ScanLoop() {
    global isActive, isHolding, lastSeenTick
    global SCAN_X1, SCAN_Y1, SCAN_X2, SCAN_Y2
    global TARGET_COLOR, COLOR_VARIATION
    global HOLD_KEY, HOLD_GRACE_MS, WINDOW_TITLE

    UnfullscreenIfActive()

    while isActive {
        if !WinExist(WINDOW_TITLE) {
            ForceRelease()
            Sleep(200)
            continue
        }

        found := false
        try
            found := PixelSearch(&fX, &fY, SCAN_X1, SCAN_Y1, SCAN_X2, SCAN_Y2, TARGET_COLOR, COLOR_VARIATION)

        if found {
            lastSeenTick := A_TickCount
            if !isHolding {
                SendInput("{" HOLD_KEY " down}")
                isHolding := true
            }
        } else if isHolding {
            if (A_TickCount - lastSeenTick) >= HOLD_GRACE_MS {
                SendInput("{" HOLD_KEY " up}")
                isHolding := false
            }
        }
    }
}

ForceRelease() {
    global isHolding, HOLD_KEY
    if isHolding {
        SendInput("{" HOLD_KEY " up}")
        isHolding := false
    }
}
