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
    verbose = False

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
            # Seeing this line means Alexa found us and is reading the device
            # description — discovery reached the HTTP stage successfully.
            print(f"[{self.device_name}] Alexa fetched setup.xml "
                  f"(from {self.client_address[0]}) — device is being discovered")
            self._send(SETUP_XML.format(name=self.device_name, serial=self.serial))
        else:
            if self.verbose:
                print(f"[{self.device_name}] GET {self.path} -> 404")
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


def _make_handler(name: str, serial: str, on_trigger, verbose: bool):
    return type(
        "BoundDeviceHTTP",
        (_DeviceHTTP,),
        {
            "device_name": name,
            "serial": serial,
            "on_trigger": staticmethod(on_trigger),
            "verbose": verbose,
        },
    )


# The search/announce targets an Echo cares about when hunting for WeMo plugs.
# We answer M-SEARCHes for these and announce ourselves under each one.
_TARGETS = ("upnp:rootdevice", "urn:Belkin:device:**")


class SSDPResponder(threading.Thread):
    """Makes the device discoverable over UPnP/SSDP.

    Two independent mechanisms, because discovery fails in different ways:

    * We *listen* for the Echo's M-SEARCH broadcasts and reply. This is the
      classic path, but on Windows the built-in "SSDP Discovery" service often
      already owns UDP 1900 and swallows those packets before we see them.
    * We also *announce* ourselves with periodic NOTIFY ssdp:alive multicasts.
      The Echo picks these up passively, so discovery still works even when we
      can't receive M-SEARCH at all. This is the reliable path.
    """

    MCAST_GRP = "239.255.255.250"
    MCAST_PORT = 1900

    def __init__(self, ip: str, http_port: int, serial: str, verbose: bool = False):
        super().__init__(daemon=True)
        self.ip = ip
        self.http_port = http_port
        self.serial = serial
        self.verbose = verbose
        self.uuid = uuid.uuid5(uuid.NAMESPACE_DNS, "fauxmo-" + serial)
        self._stop = threading.Event()
        # Dedicated sender bound to our LAN interface, so multicast leaves the
        # right adapter. Independent of whether the listener below binds.
        self._tx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
        self._tx.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 4)
        try:
            self._tx.setsockopt(
                socket.IPPROTO_IP, socket.IP_MULTICAST_IF, socket.inet_aton(self.ip)
            )
        except OSError:
            pass

    # -- listening for M-SEARCH -------------------------------------------
    def _listen_socket(self):
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:  # harmless where unsupported (e.g. Windows)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
        except (AttributeError, OSError):
            pass
        try:
            sock.bind(("", self.MCAST_PORT))
        except OSError as exc:
            print(
                f"  ! Could not listen on UDP {self.MCAST_PORT} ({exc}).\n"
                "    Another program owns it — on Windows that's usually the\n"
                '    "SSDP Discovery" service. That\'s OK: this helper will still\n'
                "    announce itself, which is enough for Alexa to find it.",
                file=sys.stderr,
            )
            sock.close()
            return None
        mreq = struct.pack("4sl", socket.inet_aton(self.MCAST_GRP), socket.INADDR_ANY)
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
        sock.settimeout(1.0)
        return sock

    def run(self):
        sock = self._listen_socket()
        if sock is None:  # can't receive; announcements still carry discovery
            self._stop.wait()
            return
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
            if not any(t in text for t in _TARGETS) and "ssdp:all" not in text:
                continue
            if self.verbose:
                print(f"[ssdp] M-SEARCH from {addr[0]} -> replying")
            # Real WeMo answers once per target; mirror that.
            for target in _TARGETS:
                sock.sendto(self._search_response(target), addr)
        sock.close()

    # -- proactive announcements ------------------------------------------
    def announce(self, alive: bool = True):
        for target in _TARGETS:
            try:
                self._tx.sendto(self._notify(target, alive), (self.MCAST_GRP, self.MCAST_PORT))
            except OSError:
                pass

    def _usn(self, target: str) -> str:
        base = f"uuid:Socket-1_0-{self.serial}"
        return base if target == base else f"{base}::{target}"

    def _search_response(self, target: str) -> bytes:
        location = f"http://{self.ip}:{self.http_port}/setup.xml"
        msg = (
            "HTTP/1.1 200 OK\r\n"
            "CACHE-CONTROL: max-age=86400\r\n"
            "EXT:\r\n"
            f"LOCATION: {location}\r\n"
            'OPT: "http://schemas.upnp.org/upnp/1/0/"; ns=01\r\n'
            f"01-NLS: {self.uuid}\r\n"
            "SERVER: Unspecified, UPnP/1.0, Unspecified\r\n"
            f"ST: {target}\r\n"
            f"USN: {self._usn(target)}\r\n"
            "\r\n"
        )
        return msg.encode("utf-8")

    def _notify(self, target: str, alive: bool) -> bytes:
        location = f"http://{self.ip}:{self.http_port}/setup.xml"
        msg = (
            "NOTIFY * HTTP/1.1\r\n"
            f"HOST: {self.MCAST_GRP}:{self.MCAST_PORT}\r\n"
            "CACHE-CONTROL: max-age=86400\r\n"
            f"LOCATION: {location}\r\n"
            f"NT: {target}\r\n"
            f"NTS: ssdp:{'alive' if alive else 'byebye'}\r\n"
            "SERVER: Unspecified, UPnP/1.0, Unspecified\r\n"
            f"USN: {self._usn(target)}\r\n"
            "\r\n"
        )
        return msg.encode("utf-8")

    def stop(self):
        self._stop.set()


def _announce_loop(ssdp: "SSDPResponder", stop: threading.Event):
    """Announce at startup (a quick burst) and then every 30s until stopped."""
    for _ in range(3):
        ssdp.announce(alive=True)
        if stop.wait(1.0):
            break
    while not stop.wait(30.0):
        ssdp.announce(alive=True)
    ssdp.announce(alive=False)  # polite goodbye on shutdown


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
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Log every SSDP search and HTTP request (useful for debugging discovery).",
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

    handler = _make_handler(args.name, serial, toggle_mute, args.verbose)
    try:
        httpd = HTTPServer(("", args.port), handler)
    except OSError as exc:
        print(
            f"Could not start the device's HTTP server on port {args.port}: {exc}\n"
            f"Pick a free one with --port, e.g.  python3 alexa_discord_mute.py "
            f"--port {args.port + 1}",
            file=sys.stderr,
        )
        return 3
    http_thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    http_thread.start()

    ssdp = SSDPResponder(ip, args.port, serial, verbose=args.verbose)
    ssdp.start()
    announce_stop = threading.Event()
    announce_thread = threading.Thread(
        target=_announce_loop, args=(ssdp, announce_stop), daemon=True
    )
    announce_thread.start()

    print(f'Emulating a WeMo plug named "{args.name}" at http://{ip}:{args.port}')
    print(f'Mute hotkey: {args.hotkey}  (set the same combo in Discord as "Toggle Mute")')
    print("Announcing on the network so Alexa can find it...")
    print(f'Now say: "Alexa, discover devices"  — then "Alexa, turn on {args.name}"')
    print("Watch for a 'fetched setup.xml' line below — that's Alexa discovering it.")
    print("Make sure this PC and the Echo are on the SAME Wi-Fi (not a guest network),")
    print("and allow this program through the firewall if Windows asks. Ctrl+C to stop.")

    try:
        while True:
            http_thread.join(1.0)
    except KeyboardInterrupt:
        print("\nStopping...")
    finally:
        announce_stop.set()
        ssdp.stop()
        httpd.shutdown()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
