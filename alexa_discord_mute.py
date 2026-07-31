"""Say "Alexa, Stummschaltung" and it toggles your Discord mic mute.

Alexa can't run a command on your PC on its own. What it *can* do out of the
box is switch smart-home plugs on and off — no cloud skill, no account
linking. This script pretends to be one of those plugs (a Belkin WeMo
socket). When Alexa turns the plug on or off, we press Discord's "Toggle
Mute" hotkey, which mutes/unmutes your microphone (a self-mute — it does
*not* deafen you, so you still hear everyone).

How it fits together:

    "Alexa, Stummschaltung"  ->  Alexa flips the emulated plug
                             ->  this script presses a global hotkey
                             ->  Discord toggles your mic mute

One-time setup:

1. Install the one dependency this needs to press keys:

       pip install pynput

2. In Discord: User Settings -> Keybinds -> Add a Keybind ->
   action "Toggle Mute" -> record the SAME combo this script sends
   (default: Ctrl+Alt+M). Discord keybinds are global, so they work even
   when Discord isn't the focused window.

3. Run this script on the PC that runs Discord, on the same Wi-Fi/LAN as
   your Echo:

       python3 alexa_discord_mute.py

4. Say "Alexa, discover devices" (or use the Alexa app -> Devices -> +).
   A plug called "Stummschaltung" shows up.

5. Optional but nicer phrasing: in the Alexa app create a Routine with the
   spoken phrase "Stummschaltung" that turns the "Stummschaltung" plug on.
   Then just saying "Alexa, Stummschaltung" toggles your mute. Because this
   is a toggle, every trigger flips the mic — on or off, it's the same key.

Everything except the key-press uses only the Python standard library.

    python3 alexa_discord_mute.py                 # defaults
    python3 alexa_discord_mute.py --name "Mute"   # rename the device
    python3 alexa_discord_mute.py --hotkey ctrl+shift+alt+m
    python3 alexa_discord_mute.py --test          # fire the hotkey once and exit
"""

from __future__ import annotations

import argparse
import socket
import struct
import sys
import threading
import uuid
from http.server import BaseHTTPRequestHandler, HTTPServer


# ---------------------------------------------------------------------------
# Pressing the Discord mute hotkey
# ---------------------------------------------------------------------------

# Map the words people write in a hotkey string to pynput key objects. Anything
# not in here (letters, digits) is sent as a literal character.
_MODIFIER_NAMES = {"ctrl", "control", "alt", "shift", "cmd", "win", "super"}


def _parse_hotkey(spec: str):
    """Turn "ctrl+alt+m" into (modifier keys, main key), resolved lazily.

    We import pynput only inside the functions that actually press keys so the
    WeMo emulation can still be inspected / tested on machines without it.
    """
    from pynput.keyboard import Key

    alias = {
        "ctrl": Key.ctrl,
        "control": Key.ctrl,
        "alt": Key.alt,
        "shift": Key.shift,
        "cmd": Key.cmd,
        "win": Key.cmd,
        "super": Key.cmd,
    }

    parts = [p.strip().lower() for p in spec.split("+") if p.strip()]
    if not parts:
        raise ValueError("empty hotkey")

    modifiers = [alias[p] for p in parts[:-1] if p in alias]
    main = parts[-1]

    # A named key (e.g. "f13", "enter") vs. a literal character (e.g. "m").
    if main in alias:
        raise ValueError("hotkey needs a non-modifier key at the end, e.g. ...+m")
    key = getattr(Key, main, None) if main not in _MODIFIER_NAMES else None
    if key is None:
        key = main  # a plain character like "m"
    return modifiers, key


def press_hotkey(spec: str) -> None:
    """Press and release the configured hotkey once (a mute toggle)."""
    from pynput.keyboard import Controller

    modifiers, key = _parse_hotkey(spec)
    kb = Controller()
    for mod in modifiers:
        kb.press(mod)
    try:
        kb.press(key)
        kb.release(key)
    finally:
        for mod in reversed(modifiers):
            kb.release(mod)


# ---------------------------------------------------------------------------
# WeMo emulation
# ---------------------------------------------------------------------------

def _local_ip() -> str:
    """Best-effort LAN IP of this machine (the address the Echo will call)."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        # No packets are actually sent; this just picks the outbound interface.
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


SETUP_XML = """<?xml version="1.0"?>
<root xmlns="urn:Belkin:device-1-0">
  <device>
    <deviceType>urn:Belkin:device:controllee:1</deviceType>
    <friendlyName>{name}</friendlyName>
    <manufacturer>Belkin International Inc.</manufacturer>
    <modelName>Emulated Socket</modelName>
    <modelNumber>3.1415</modelNumber>
    <UDN>uuid:Socket-1_0-{serial}</UDN>
    <serialNumber>{serial}</serialNumber>
    <binaryState>0</binaryState>
    <serviceList>
      <service>
        <serviceType>urn:Belkin:service:basicevent:1</serviceType>
        <serviceId>urn:Belkin:serviceId:basicevent1</serviceId>
        <controlURL>/upnp/control/basicevent1</controlURL>
        <eventSubURL>/upnp/event/basicevent1</eventSubURL>
        <SCPDURL>/eventservice.xml</SCPDURL>
      </service>
    </serviceList>
  </device>
</root>
"""

# Alexa reads BinaryState back after acting; we always report "off" so that a
# spoken "turn on" is never optimised away as "already on". Every trigger then
# reaches us and toggles the mic.
SOAP_RESPONSE = """<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:{action}Response xmlns:u="urn:Belkin:service:basicevent:1">
      <BinaryState>0</BinaryState>
    </u:{action}Response>
  </s:Body>
</s:Envelope>
"""


class _DeviceHTTP(BaseHTTPRequestHandler):
    """Serves setup.xml and handles the on/off SOAP calls from Alexa."""

    # Injected by the server factory below.
    device_name = "Stummschaltung"
    serial = "000000000000"
    on_trigger = staticmethod(lambda: None)

    def log_message(self, *_args):  # silence per-request stderr spam
        pass

    def _send(self, body: str, content_type: str = "text/xml") -> None:
        payload = body.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):  # noqa: N802 (BaseHTTPRequestHandler API)
        if self.path.endswith("setup.xml"):
            self._send(SETUP_XML.format(name=self.device_name, serial=self.serial))
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):  # noqa: N802
        length = int(self.headers.get("Content-Length", 0) or 0)
        body = self.rfile.read(length).decode("utf-8", "ignore")
        soap_action = self.headers.get("SOAPACTION", "")

        if "SetBinaryState" in soap_action:
            # Alexa sends 1 for "on", 0 for "off". We treat *both* as a toggle
            # so either phrasing flips the mic.
            state = "on" if "<BinaryState>1</BinaryState>" in body else "off"
            print(f'[Stummschaltung] Alexa said "{state}" -> toggling Discord mute')
            try:
                self.on_trigger()
            except Exception as exc:  # pragma: no cover - defensive
                print(f"  ! could not press the mute hotkey: {exc}", file=sys.stderr)
            self._send(SOAP_RESPONSE.format(action="SetBinaryState"))
        elif "GetBinaryState" in soap_action:
            self._send(SOAP_RESPONSE.format(action="GetBinaryState"))
        else:
            self.send_response(400)
            self.end_headers()


def _make_handler(name: str, serial: str, on_trigger):
    return type(
        "BoundDeviceHTTP",
        (_DeviceHTTP,),
        {"device_name": name, "serial": serial, "on_trigger": staticmethod(on_trigger)},
    )


class SSDPResponder(threading.Thread):
    """Answers the Echo's UPnP/SSDP M-SEARCH broadcasts so it finds the device."""

    MCAST_GRP = "239.255.255.250"
    MCAST_PORT = 1900

    def __init__(self, ip: str, http_port: int, serial: str):
        super().__init__(daemon=True)
        self.ip = ip
        self.http_port = http_port
        self.serial = serial
        self.uuid = str(uuid.uuid4())
        self._stop = threading.Event()

    def run(self):
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind(("", self.MCAST_PORT))
        mreq = struct.pack("4sl", socket.inet_aton(self.MCAST_GRP), socket.INADDR_ANY)
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
        sock.settimeout(1.0)

        while not self._stop.is_set():
            try:
                data, addr = sock.recvfrom(2048)
            except socket.timeout:
                continue
            except OSError:
                break
            text = data.decode("utf-8", "ignore")
            if "M-SEARCH" not in text or "ssdp:discover" not in text:
                continue
            # Reply to the search targets Alexa uses when hunting for WeMo plugs.
            if not any(
                st in text
                for st in ("urn:Belkin:device:**", "upnp:rootdevice", "ssdp:all")
            ):
                continue
            sock.sendto(self._response(), addr)

        sock.close()

    def _response(self) -> bytes:
        location = f"http://{self.ip}:{self.http_port}/setup.xml"
        msg = (
            "HTTP/1.1 200 OK\r\n"
            "CACHE-CONTROL: max-age=86400\r\n"
            "EXT:\r\n"
            f"LOCATION: {location}\r\n"
            'OPT: "http://schemas.upnp.org/upnp/1/0/"; ns=01\r\n'
            f"01-NLS: {self.uuid}\r\n"
            "SERVER: Unspecified, UPnP/1.0, Unspecified\r\n"
            "ST: urn:Belkin:device:**\r\n"
            f"USN: uuid:Socket-1_0-{self.serial}::urn:Belkin:device:**\r\n"
            "\r\n"
        )
        return msg.encode("utf-8")

    def stop(self):
        self._stop.set()


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        description="Toggle your Discord mic mute by voice via Amazon Alexa."
    )
    parser.add_argument(
        "--name",
        default="Stummschaltung",
        help='Device name Alexa discovers (default: "Stummschaltung").',
    )
    parser.add_argument(
        "--hotkey",
        default="ctrl+alt+m",
        help='Key combo to send, matching Discord\'s "Toggle Mute" keybind '
        "(default: ctrl+alt+m).",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=52000,
        help="TCP port for the emulated device's HTTP server (default: 52000).",
    )
    parser.add_argument(
        "--test",
        action="store_true",
        help="Press the mute hotkey once and exit (verify the keybind works).",
    )
    args = parser.parse_args(argv)

    # Fail early with a friendly message if pynput isn't installed.
    try:
        import pynput  # noqa: F401
    except ImportError:
        print(
            "This helper needs the 'pynput' package to press keys.\n"
            "Install it with:  pip install pynput",
            file=sys.stderr,
        )
        return 1

    # Validate the hotkey spec up front.
    try:
        _parse_hotkey(args.hotkey)
    except (ValueError, AttributeError) as exc:
        print(f"Bad --hotkey {args.hotkey!r}: {exc}", file=sys.stderr)
        return 2

    def toggle_mute():
        press_hotkey(args.hotkey)

    if args.test:
        print(f"Pressing {args.hotkey} once...")
        toggle_mute()
        print("Done. If your Discord mic mute flipped, the keybind is set right.")
        return 0

    ip = _local_ip()
    # A stable 12-hex-digit serial derived from the device name so Alexa keeps
    # recognising the same plug across restarts instead of adding duplicates.
    serial = uuid.uuid5(uuid.NAMESPACE_DNS, args.name).hex[:12]

    handler = _make_handler(args.name, serial, toggle_mute)
    httpd = HTTPServer(("", args.port), handler)
    http_thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    http_thread.start()

    ssdp = SSDPResponder(ip, args.port, serial)
    ssdp.start()

    print(f'Emulating a WeMo plug named "{args.name}" at http://{ip}:{args.port}')
    print(f'Mute hotkey: {args.hotkey}  (set the same combo in Discord as "Toggle Mute")')
    print('Now say: "Alexa, discover devices"  — then "Alexa, turn on ' f'{args.name}"')
    print("Press Ctrl+C to stop.")

    try:
        while True:
            http_thread.join(1.0)
    except KeyboardInterrupt:
        print("\nStopping...")
    finally:
        ssdp.stop()
        httpd.shutdown()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
