#!/usr/bin/env python3
"""Standalone dark-mode GUI that browses folders and shows file/folder sizes.

A tkinter-only (no third-party dependencies) disk usage explorer. It looks
and behaves like a normal file explorer tree: folders start collapsed and
are scanned on demand as you expand them, so opening it is instant even on
a large drive. Folder sizes are computed in a background thread (so the
GUI never freezes) and filled in once ready.

Run it with:

    python3 disk_usage_scanner.py [start-path]
"""

import os
import queue
import string
import sys
import threading
import tkinter as tk
from tkinter import ttk

UNITS = ("B", "KB", "MB", "GB", "TB", "PB")


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
        self._node_path = {}
        self._loaded = set()

        self._build_style()
        self._build_widgets()
        self.root.after(100, self._drain_size_queue)

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

        columns = ("size", "type")
        self.tree = ttk.Treeview(self.root, columns=columns, show="tree headings")
        self.tree.heading("#0", text="Name")
        self.tree.heading("size", text="Size")
        self.tree.heading("type", text="Type")
        self.tree.column("#0", width=480, anchor=tk.W)
        self.tree.column("size", width=120, anchor=tk.E)
        self.tree.column("type", width=100, anchor=tk.W)
        self.tree.pack(fill=tk.BOTH, expand=True, padx=6, pady=(0, 6))

        self.tree.bind("<<TreeviewOpen>>", self._on_open)
        self.tree.bind("<Double-1>", self._on_double_click)

        self.status_var = tk.StringVar(value="Ready")
        status = ttk.Label(self.root, textvariable=self.status_var, anchor=tk.W)
        status.pack(fill=tk.X, padx=6, pady=(0, 6))

    # -- Navigation ----------------------------------------------------

    def navigate(self, path):
        path = os.path.abspath(os.path.expanduser(path)) if path else list_drives()[0]
        if not os.path.isdir(path):
            self.status_var.set(f"Not a folder: {path}")
            return
        self.tree.delete(*self.tree.get_children())
        self._node_path.clear()
        self._loaded.clear()
        self.current_root = path
        self.path_var.set(path)
        self._populate_children("", path)
        self.status_var.set(f"Browsing {path}")

    def _go_up(self):
        parent = os.path.dirname(self.current_root.rstrip(os.sep))
        if parent and parent != self.current_root:
            self.navigate(parent)

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
                    node_id, tk.END, text=name, values=("...", "Folder"), open=False
                )
                self._node_path[item] = full_path
                self.tree.insert(item, tk.END, text="", values=("", ""))  # placeholder child
                self._request_folder_size(item, full_path)
            else:
                self.tree.insert(
                    node_id, tk.END, text=name, values=(human_size(size or 0), "File")
                )

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
                updated += 1
        except queue.Empty:
            pass
        if updated:
            self.status_var.set(f"Updated {updated} folder size(s)")
        self.root.after(200, self._drain_size_queue)


def main():
    start_path = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~")
    if not os.path.isdir(start_path):
        start_path = list_drives()[0]

    root = tk.Tk()
    DiskUsageApp(root, start_path)
    root.mainloop()


if __name__ == "__main__":
    main()
