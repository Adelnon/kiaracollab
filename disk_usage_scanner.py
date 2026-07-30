#!/usr/bin/env python3
"""Standalone dark-mode GUI that browses folders and shows file/folder sizes.

A tkinter-only (no third-party dependencies) disk usage explorer. It looks
and behaves like a normal file explorer tree: folders start collapsed and
are scanned on demand as you expand them, so opening it is instant even on
a large drive. Folder sizes are computed in a background thread (so the
GUI never freezes) and filled in once ready.

Each row also has a Delete checkbox. Clicking "AI Recommendations" sends the
currently-scanned entries to Claude (same ANTHROPIC_API_KEY / CLAUDE_MODEL
setup as bot.py, called directly over HTTPS with the stdlib) and pre-checks
whatever it flags as safe to delete; that call optionally uses
`python-dotenv` to load the .env file, but needs no other third-party
dependency, so plain browsing still needs nothing beyond the stdlib.
Folders sharing a name (e.g. a ".minecraft" under both Roaming and Local)
are treated as linked, so toggling one toggles the rest — except when the
match sits inside a "thunderstore" folder, which is a different app's data
and never linked in. Nothing is deleted until you press "Delete Checked"
and confirm.

With no start-path argument, it opens at the C: drive on Windows (the first
drive `list_drives()` finds) rather than the user's home folder. The mouse's
side buttons (back/forward, aka X1/X2) move through folder-navigation
history the same way they do in a file explorer or browser.

Run it with:

    python3 disk_usage_scanner.py [start-path]
"""

import json
import os
import queue
import shutil
import string
import sys
import textwrap
import threading
import tkinter as tk
import urllib.error
import urllib.request
from tkinter import messagebox, ttk

UNITS = ("B", "KB", "MB", "GB", "TB", "PB")

CHECK_ON = "[x]"
CHECK_OFF = "[ ]"

# Folder-name matches inside a path segment with this name are never linked
# into a group — e.g. a "Minecraft" folder living under "Thunderstore" is
# that mod manager's own data, not the real game folder.
GROUP_EXCLUDE_SEGMENT = "thunderstore"

DEFAULT_CLAUDE_MODEL = "claude-sonnet-5"
MAX_AI_ENTRIES = 150

AI_SYSTEM_PROMPT = textwrap.dedent(
    """
    You are a careful disk-cleanup assistant. You are given a list of files
    and folders (with type and size) scanned from one directory on a user's
    machine, and must recommend which ones are safe to delete to free up
    space.

    Only recommend items that are very likely safe to remove: caches, temp
    files, logs, crash dumps, old installers/downloads, build artifacts
    (node_modules, __pycache__, .venv, target, dist, build, .cache), and
    obviously stale or duplicate application data. Never recommend anything
    that could be unique user documents, save games, source code, media, or
    system/config files — when unsure, leave it out.

    Respond with ONLY compact JSON, no prose, no markdown fences, in exactly
    this shape:
    {"recommendations": [{"path": "<path exactly as given>", "reason": "<short reason>"}]}
    If nothing looks safe to delete, respond {"recommendations": []}.
    """
).strip()


def human_size(num_bytes):
    size = float(num_bytes)
    for unit in UNITS:
        if size < 1024 or unit == UNITS[-1]:
            return f"{size:.0f} {unit}" if unit == "B" else f"{size:.2f} {unit}"
        size /= 1024
    return f"{size:.2f} {UNITS[-1]}"


def list_drives():
    """Return likely scan roots: drive letters on Windows, '/' on POSIX."""
    if os.name == "nt":
        drives = []
        for letter in string.ascii_uppercase:
            path = f"{letter}:\\"
            if os.path.exists(path):
                drives.append(path)
        return drives or ["C:\\"]
    return ["/"]


def scandir_entries(path):
    """List (name, is_dir, size_or_none) for one directory, skipping unreadable entries."""
    entries = []
    try:
        with os.scandir(path) as it:
            for entry in it:
                try:
                    is_dir = entry.is_dir(follow_symlinks=False)
                except OSError:
                    continue
                size = None
                if not is_dir:
                    try:
                        size = entry.stat(follow_symlinks=False).st_size
                    except OSError:
                        size = 0
                entries.append((entry.name, is_dir, size))
    except (PermissionError, FileNotFoundError, NotADirectoryError, OSError):
        pass
    return entries


def folder_size(path):
    """Recursively sum file sizes under path, skipping anything unreadable."""
    total = 0
    try:
        with os.scandir(path) as it:
            for entry in it:
                try:
                    if entry.is_dir(follow_symlinks=False):
                        total += folder_size(entry.path)
                    else:
                        total += entry.stat(follow_symlinks=False).st_size
                except OSError:
                    continue
    except (PermissionError, FileNotFoundError, NotADirectoryError, OSError):
        pass
    return total


def _group_key_for(path, is_dir):
    """Return the linking key for a folder, or None if it shouldn't be linked.

    Two folders with the same normalized name link together (so toggling one
    toggles the other) unless the match sits inside a `GROUP_EXCLUDE_SEGMENT`
    folder, which is a different app's data reusing the same name.
    """
    if not is_dir:
        return None
    name = os.path.basename(path.rstrip(os.sep))
    normalized = name.lower().lstrip(".")
    if not normalized:
        return None
    segments = [p.lower() for p in path.split(os.sep) if p]
    if GROUP_EXCLUDE_SEGMENT in segments:
        return None
    return normalized


def _parse_ai_response(text, valid_paths):
    text = text.strip()
    if text.startswith("```"):
        text = text.strip("`")
        if "\n" in text:
            text = text.split("\n", 1)[1]
    data = json.loads(text)
    recs = []
    for rec in data.get("recommendations", []):
        path = rec.get("path")
        if path in valid_paths:
            recs.append({"path": path, "reason": str(rec.get("reason", "")).strip()})
    return recs


DARK_BG = "#1e1e1e"
DARK_FG = "#e0e0e0"
DARK_SELECT_BG = "#3a6ea5"
DARK_HEADER_BG = "#2d2d2d"
DARK_ENTRY_BG = "#2b2b2b"


class DiskUsageApp:
    def __init__(self, root, start_path):
        self.root = root
        self.root.title("Disk Usage Explorer")
        self.root.geometry("900x600")

        self._size_queue = queue.Queue()
        self._ai_queue = queue.Queue()
        self._node_path = {}
        self._is_dir = {}
        self._size_bytes = {}
        self._checked = {}
        self._group_key = {}
        self._groups = {}
        self._loaded = set()
        self._back_history = []
        self._forward_history = []

        self._build_style()
        self._build_widgets()
        self._bind_mouse_navigation()
        self.root.after(100, self._drain_size_queue)
        self.root.after(300, self._drain_ai_queue)

        self.navigate(start_path)

    # -- UI setup ----------------------------------------------------

    def _build_style(self):
        self.root.configure(bg=DARK_BG)
        style = ttk.Style(self.root)
        style.theme_use("clam")

        style.configure(
            "Treeview",
            background=DARK_ENTRY_BG,
            fieldbackground=DARK_ENTRY_BG,
            foreground=DARK_FG,
            bordercolor=DARK_BG,
            borderwidth=0,
            rowheight=22,
        )
        style.map(
            "Treeview",
            background=[("selected", DARK_SELECT_BG)],
            foreground=[("selected", "#ffffff")],
        )
        style.configure(
            "Treeview.Heading",
            background=DARK_HEADER_BG,
            foreground=DARK_FG,
            borderwidth=0,
        )
        style.map("Treeview.Heading", background=[("active", DARK_HEADER_BG)])
        style.configure("TFrame", background=DARK_BG)
        style.configure("TButton", background=DARK_HEADER_BG, foreground=DARK_FG)
        style.configure(
            "TEntry",
            fieldbackground=DARK_ENTRY_BG,
            foreground=DARK_FG,
            insertcolor=DARK_FG,
        )
        style.configure("TLabel", background=DARK_BG, foreground=DARK_FG)

    def _build_widgets(self):
        toolbar = ttk.Frame(self.root)
        toolbar.pack(fill=tk.X, padx=6, pady=6)

        ttk.Label(toolbar, text="Path:").pack(side=tk.LEFT)
        self.path_var = tk.StringVar()
        path_entry = ttk.Entry(toolbar, textvariable=self.path_var)
        path_entry.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=6)
        path_entry.bind("<Return>", lambda _e: self.navigate(self.path_var.get()))

        ttk.Button(toolbar, text="Go", command=lambda: self.navigate(self.path_var.get())).pack(
            side=tk.LEFT, padx=(0, 4)
        )
        ttk.Button(toolbar, text="Up", command=self._go_up).pack(side=tk.LEFT, padx=(0, 4))
        ttk.Button(toolbar, text="Refresh", command=self._refresh_root).pack(side=tk.LEFT)
        ttk.Button(
            toolbar, text="AI Recommendations", command=self._start_ai_recommendations
        ).pack(side=tk.LEFT, padx=(12, 4))
        ttk.Button(toolbar, text="Delete Checked", command=self._delete_checked).pack(
            side=tk.LEFT
        )

        columns = ("size", "type", "del")
        self.tree = ttk.Treeview(self.root, columns=columns, show="tree headings")
        self.tree.heading("#0", text="Name")
        self.tree.heading("size", text="Size")
        self.tree.heading("type", text="Type")
        self.tree.heading("del", text="Delete?")
        self.tree.column("#0", width=460, anchor=tk.W)
        self.tree.column("size", width=110, anchor=tk.E)
        self.tree.column("type", width=90, anchor=tk.W)
        self.tree.column("del", width=60, anchor=tk.CENTER)
        self.tree.pack(fill=tk.BOTH, expand=True, padx=6, pady=(0, 6))

        self.tree.bind("<<TreeviewOpen>>", self._on_open)
        self.tree.bind("<Double-1>", self._on_double_click)
        self.tree.bind("<Button-1>", self._on_tree_click)

        self.status_var = tk.StringVar(value="Ready")
        status = ttk.Label(self.root, textvariable=self.status_var, anchor=tk.W)
        status.pack(fill=tk.X, padx=6, pady=(0, 6))

    def _bind_mouse_navigation(self):
        # Tk maps a mouse's side "back"/"forward" (X1/X2) buttons to button
        # numbers 8 and 9 on Windows; some Tk/X11 builds don't recognize
        # those button numbers at all, so a failed bind there is non-fatal.
        bindings = (("<Button-8>", self._go_back), ("<Button-9>", self._go_forward))
        for widget in (self.root, self.tree):
            for sequence, handler in bindings:
                try:
                    widget.bind(sequence, lambda _e, handler=handler: handler())
                except tk.TclError:
                    pass

    # -- Navigation ----------------------------------------------------

    def navigate(self, path, _record_history=True):
        path = os.path.abspath(os.path.expanduser(path)) if path else list_drives()[0]
        if not os.path.isdir(path):
            self.status_var.set(f"Not a folder: {path}")
            return
        if _record_history and getattr(self, "current_root", None) and path != self.current_root:
            self._back_history.append(self.current_root)
            self._forward_history.clear()
        self.tree.delete(*self.tree.get_children())
        self._node_path.clear()
        self._loaded.clear()
        self._is_dir.clear()
        self._size_bytes.clear()
        self._checked.clear()
        self._group_key.clear()
        self._groups.clear()
        self.current_root = path
        self.path_var.set(path)
        self._populate_children("", path)
        self.status_var.set(f"Browsing {path}")

    def _go_up(self):
        parent = os.path.dirname(self.current_root.rstrip(os.sep))
        if parent and parent != self.current_root:
            self.navigate(parent)

    def _go_back(self):
        if not self._back_history:
            return
        self._forward_history.append(self.current_root)
        previous = self._back_history.pop()
        self.navigate(previous, _record_history=False)

    def _go_forward(self):
        if not self._forward_history:
            return
        self._back_history.append(self.current_root)
        next_path = self._forward_history.pop()
        self.navigate(next_path, _record_history=False)

    def _refresh_root(self):
        self.navigate(self.current_root)

    # -- Tree population ----------------------------------------------------

    def _populate_children(self, node_id, path):
        entries = scandir_entries(path)
        entries.sort(key=lambda e: (not e[1], e[0].lower()))
        for name, is_dir, size in entries:
            full_path = os.path.join(path, name)
            if is_dir:
                item = self.tree.insert(
                    node_id, tk.END, text=name, values=("...", "Folder", CHECK_OFF), open=False
                )
                self._node_path[item] = full_path
                self._is_dir[item] = True
                self.tree.insert(item, tk.END, text="", values=("", "", ""))  # placeholder child
                self._request_folder_size(item, full_path)
            else:
                item = self.tree.insert(
                    node_id,
                    tk.END,
                    text=name,
                    values=(human_size(size or 0), "File", CHECK_OFF),
                )
                self._node_path[item] = full_path
                self._is_dir[item] = False
                self._size_bytes[item] = size or 0

            key = _group_key_for(full_path, is_dir)
            if key:
                self._group_key[item] = key
                self._groups.setdefault(key, []).append(item)

    def _on_open(self, _event):
        item = self.tree.focus()
        if item in self._loaded:
            return
        path = self._node_path.get(item)
        if not path:
            return
        self._loaded.add(item)
        children = self.tree.get_children(item)
        for child in children:
            self.tree.delete(child)
        self._populate_children(item, path)

    def _on_double_click(self, _event):
        item = self.tree.focus()
        path = self._node_path.get(item)
        if path and os.path.isdir(path):
            self.navigate(path)

    # -- Background folder-size computation ----------------------------------------------------

    def _request_folder_size(self, item, path):
        def worker():
            size = folder_size(path)
            self._size_queue.put((item, size))

        threading.Thread(target=worker, daemon=True).start()

    def _drain_size_queue(self):
        updated = 0
        try:
            while True:
                item, size = self._size_queue.get_nowait()
                if self.tree.exists(item):
                    self.tree.set(item, "size", human_size(size))
                    self._size_bytes[item] = size
                updated += 1
        except queue.Empty:
            pass
        if updated:
            self.status_var.set(f"Updated {updated} folder size(s)")
        self.root.after(200, self._drain_size_queue)

    # -- Delete checkbox + linked-folder toggling ----------------------------------------------------

    def _on_tree_click(self, event):
        if self.tree.identify_region(event.x, event.y) != "cell":
            return
        if self.tree.identify_column(event.x) != "#3":  # "del" is the 3rd values column
            return
        item = self.tree.identify_row(event.y)
        if item:
            self._toggle_checked(item)

    def _toggle_checked(self, item):
        if item not in self._node_path:
            return
        self._set_checked(item, not self._checked.get(item, False))

    def _set_checked(self, item, state, _cascaded=False):
        if not self.tree.exists(item):
            return
        self._checked[item] = state
        self.tree.set(item, "del", CHECK_ON if state else CHECK_OFF)
        if _cascaded:
            return
        key = self._group_key.get(item)
        if not key:
            return
        for other in self._groups.get(key, []):
            if other != item:
                self._set_checked(other, state, _cascaded=True)

    # -- AI cleanup recommendations ----------------------------------------------------

    def _collect_entries_for_ai(self):
        entries = []
        for item, path in self._node_path.items():
            if not self.tree.exists(item):
                continue
            entries.append(
                {
                    "item": item,
                    "path": os.path.relpath(path, self.current_root),
                    "type": "dir" if self._is_dir.get(item) else "file",
                    "size": self.tree.set(item, "size") or "unknown",
                    "size_bytes": self._size_bytes.get(item, 0),
                }
            )
        entries.sort(key=lambda e: e["size_bytes"], reverse=True)
        return entries[:MAX_AI_ENTRIES]

    def _start_ai_recommendations(self):
        entries = self._collect_entries_for_ai()
        if not entries:
            messagebox.showinfo(
                "AI Recommendations", "Nothing scanned yet — expand some folders first."
            )
            return
        self.status_var.set("Asking Claude for cleanup recommendations…")
        threading.Thread(target=self._ai_worker, args=(entries,), daemon=True).start()

    def _ai_worker(self, entries):
        try:
            recs = self._ask_claude_for_recommendations(entries)
            self._ai_queue.put(("ok", recs))
        except Exception as exc:  # noqa: BLE001 — surface every failure back to the UI
            self._ai_queue.put(("error", f"{type(exc).__name__}: {exc}"))

    def _ask_claude_for_recommendations(self, entries):
        try:
            from dotenv import load_dotenv

            load_dotenv()
        except ImportError:
            pass

        api_key = os.getenv("ANTHROPIC_API_KEY")
        if not api_key:
            raise RuntimeError("ANTHROPIC_API_KEY isn't set (see .env.example).")
        model = os.getenv("CLAUDE_MODEL", DEFAULT_CLAUDE_MODEL).strip() or DEFAULT_CLAUDE_MODEL

        listing = "\n".join(f"- {e['path']} ({e['type']}, {e['size']})" for e in entries)
        body = json.dumps(
            {
                "model": model,
                "max_tokens": 1500,
                "system": AI_SYSTEM_PROMPT,
                "messages": [
                    {
                        "role": "user",
                        "content": f"Current folder: {self.current_root}\n\nEntries:\n{listing}",
                    }
                ],
            }
        ).encode("utf-8")
        request = urllib.request.Request(
            "https://api.anthropic.com/v1/messages",
            data=body,
            method="POST",
            headers={
                "content-type": "application/json",
                "x-api-key": api_key,
                "anthropic-version": "2023-06-01",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as resp:
                response = json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            raise RuntimeError(f"Claude API request failed: {exc.code} {exc.reason}") from exc

        text = "".join(
            block.get("text", "")
            for block in response.get("content", [])
            if block.get("type") == "text"
        )
        valid_paths = {e["path"] for e in entries}
        return _parse_ai_response(text, valid_paths)

    def _drain_ai_queue(self):
        try:
            while True:
                status, payload = self._ai_queue.get_nowait()
                if status == "ok":
                    self._apply_ai_recommendations(payload)
                else:
                    self.status_var.set("AI recommendation request failed.")
                    messagebox.showerror("AI Recommendations", payload)
        except queue.Empty:
            pass
        self.root.after(300, self._drain_ai_queue)

    def _apply_ai_recommendations(self, recs):
        if not recs:
            self.status_var.set("Claude didn't flag anything as safe to delete.")
            messagebox.showinfo(
                "AI Recommendations", "Claude didn't flag anything as safe to delete."
            )
            return

        path_to_item = {
            os.path.relpath(path, self.current_root): item
            for item, path in self._node_path.items()
            if self.tree.exists(item)
        }
        applied = []
        for rec in recs:
            item = path_to_item.get(rec["path"])
            if item:
                self._set_checked(item, True)
                applied.append(rec)

        self.status_var.set(
            f"Claude recommended {len(applied)} item(s) for deletion — review the Delete column."
        )
        self._show_recommendations_window(applied)

    def _show_recommendations_window(self, recs):
        win = tk.Toplevel(self.root)
        win.title("AI Recommendations")
        win.configure(bg=DARK_BG)
        win.geometry("520x360")

        text = tk.Text(win, bg=DARK_ENTRY_BG, fg=DARK_FG, wrap=tk.WORD, insertbackground=DARK_FG)
        text.pack(fill=tk.BOTH, expand=True, padx=8, pady=8)
        text.insert(
            tk.END,
            "Pre-checked in the Delete column below — uncheck anything you want to keep.\n\n",
        )
        for rec in recs:
            text.insert(tk.END, f"[x] {rec['path']}\n    {rec['reason']}\n\n")
        text.configure(state=tk.DISABLED)

        ttk.Button(win, text="Close", command=win.destroy).pack(pady=(0, 8))

    # -- Deletion ----------------------------------------------------

    def _delete_checked(self):
        targets = [
            (item, path, self._is_dir.get(item, False))
            for item, path in self._node_path.items()
            if self._checked.get(item) and self.tree.exists(item)
        ]
        if not targets:
            messagebox.showinfo("Delete Checked", "Nothing is checked for deletion.")
            return

        preview = "\n".join(f"- {path}" for _, path, _ in targets[:20])
        if len(targets) > 20:
            preview += f"\n… and {len(targets) - 20} more"
        confirmed = messagebox.askyesno(
            "Confirm deletion",
            f"Permanently delete {len(targets)} item(s)? This cannot be undone.\n\n{preview}",
            icon="warning",
        )
        if not confirmed:
            return

        deleted, failed = 0, []
        for item, path, is_dir in targets:
            try:
                if is_dir:
                    shutil.rmtree(path)
                else:
                    os.remove(path)
                deleted += 1
                if self.tree.exists(item):
                    self.tree.delete(item)
                self._node_path.pop(item, None)
                self._is_dir.pop(item, None)
                self._size_bytes.pop(item, None)
                self._checked.pop(item, None)
                key = self._group_key.pop(item, None)
                if key and item in self._groups.get(key, []):
                    self._groups[key].remove(item)
            except OSError as exc:
                failed.append(f"{path}: {exc}")

        status = f"Deleted {deleted} item(s)."
        if failed:
            status += f" {len(failed)} failed."
            messagebox.showerror("Some deletions failed", "\n".join(failed[:10]))
        self.status_var.set(status)


def main():
    start_path = sys.argv[1] if len(sys.argv) > 1 else list_drives()[0]
    if not os.path.isdir(start_path):
        start_path = list_drives()[0]

    root = tk.Tk()
    DiskUsageApp(root, start_path)
    root.mainloop()


if __name__ == "__main__":
    main()
