#!/usr/bin/env python3

import argparse
import hashlib
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import Adw, Gdk, Gio, GLib, Gtk, Pango


APP_ID = "dev.noxflow.ClipboardBrowser"
PREVIEW_WIDTH = 320
IPC_DIR = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "noxflow"
IPC_SOCKET_PATH = IPC_DIR / "clipboard-ui.sock"
STATE_PATH = (
    Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local" / "state"))
    / "noxflow"
    / "clipboard-ui.json"
)
FILTERS = ["all", "text", "images", "code", "links"]
TYPE_LABELS = {
    "text": "Text",
    "images": "Image",
    "code": "Code",
    "links": "Link",
}
TYPE_ICONS = {
    "text": "text-x-generic-symbolic",
    "images": "image-x-generic-symbolic",
    "code": "applications-development-symbolic",
    "links": "emblem-web-symbolic",
}
SEARCH_PREFIXES = {
    "img:": "images",
    "image:": "images",
    "code:": "code",
    "link:": "links",
    "url:": "links",
    "text:": "text",
}
DEFAULT_STATE = {
    "pins": [],
    "settings": {
        "dedupe": True,
        "hover_preview": True,
    },
}
CSS = """
window.clipboard-window {
  background: linear-gradient(180deg, rgba(17, 20, 27, 0.98), rgba(10, 12, 17, 0.98));
  color: #edf2f7;
}

.clipboard-shell {
  padding: 18px;
}

.clipboard-card,
.action-bar,
.topbar,
.preview-card,
.history-card {
  background: rgba(255, 255, 255, 0.055);
  border: 1px solid rgba(255, 255, 255, 0.10);
  border-radius: 18px;
}

.topbar {
  padding: 14px 16px 16px 16px;
}

.topbar-title {
  font-weight: 700;
  font-size: 18px;
}

.topbar-subtitle,
.muted-label,
.section-caption,
.meta-label {
  color: rgba(237, 242, 247, 0.72);
}

.topbar-subtitle {
  font-size: 12px;
}

.shortcut-hint {
  font-size: 11px;
  padding: 8px 12px;
  border-radius: 999px;
  background: rgba(255, 255, 255, 0.06);
  color: rgba(237, 242, 247, 0.74);
}

entry.search-box {
  min-height: 44px;
  border-radius: 14px;
  background: rgba(255, 255, 255, 0.05);
  border: 1px solid rgba(255, 255, 255, 0.08);
  padding: 0 10px;
}

.filter-chip {
  min-height: 34px;
  padding: 0 14px;
  border-radius: 999px;
  background: rgba(255, 255, 255, 0.05);
  border: 1px solid rgba(255, 255, 255, 0.08);
}

.filter-chip:checked {
  background: rgba(88, 166, 255, 0.18);
  border-color: rgba(88, 166, 255, 0.44);
  box-shadow: 0 0 0 1px rgba(88, 166, 255, 0.16);
}

.history-card,
.preview-card {
  padding: 10px;
}

.history-list {
  background: transparent;
}

.section-row {
  background: transparent;
  border: none;
  box-shadow: none;
}

.section-box {
  padding: 14px 10px 6px 10px;
}

.section-title {
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: rgba(237, 242, 247, 0.58);
}

.clip-row {
  background: transparent;
  border: none;
  border-radius: 16px;
  margin: 4px 0;
}

.clip-row:hover .clip-row-shell {
  background: rgba(255, 255, 255, 0.07);
}

.clip-row:selected .clip-row-shell,
.clip-row.active-preview .clip-row-shell {
  background: rgba(88, 166, 255, 0.16);
  border-color: rgba(88, 166, 255, 0.30);
  box-shadow: 0 0 0 1px rgba(88, 166, 255, 0.14);
}

.clip-row-shell {
  min-height: 76px;
  padding: 12px 14px;
  border-radius: 16px;
  border: 1px solid transparent;
  transition: 160ms ease;
}

.type-strip {
  min-width: 4px;
  min-height: 42px;
  border-radius: 999px;
  margin-right: 12px;
}

.type-strip.text {
  background: #6cc5ff;
}

.type-strip.images {
  background: #ffb84d;
}

.type-strip.code {
  background: #7de8a3;
}

.type-strip.links {
  background: #ff7aa2;
}

.type-icon {
  min-width: 24px;
  min-height: 24px;
  margin-right: 10px;
  opacity: 0.9;
}

.row-title {
  font-size: 14px;
  font-weight: 600;
}

.row-meta {
  font-size: 11px;
}

.row-action {
  min-width: 30px;
  min-height: 30px;
  padding: 0;
  border-radius: 999px;
  background: rgba(255, 255, 255, 0.05);
}

.row-action:hover {
  background: rgba(255, 255, 255, 0.12);
}

.preview-card {
  padding: 18px;
}

.preview-title {
  font-size: 20px;
  font-weight: 700;
}

.preview-summary {
  font-size: 13px;
  color: rgba(237, 242, 247, 0.78);
}

.preview-pane {
  background: rgba(5, 8, 12, 0.42);
  border-radius: 16px;
  border: 1px solid rgba(255, 255, 255, 0.08);
  padding: 14px;
}

textview.preview-text,
textview.editor-text {
  background: transparent;
  color: #edf2f7;
}

.preview-placeholder {
  color: rgba(237, 242, 247, 0.68);
  font-size: 14px;
}

.preview-chip {
  padding: 6px 10px;
  border-radius: 999px;
  background: rgba(255, 255, 255, 0.06);
  font-size: 11px;
  font-weight: 700;
}

.preview-chip.text {
  color: #82d1ff;
}

.preview-chip.images {
  color: #ffca72;
}

.preview-chip.code {
  color: #92efb1;
}

.preview-chip.links {
  color: #ff9bbb;
}

.action-bar {
  padding: 12px 14px;
}

.action-button {
  min-height: 36px;
  padding: 0 14px;
  border-radius: 999px;
}

.action-button.suggested-action {
  background: rgba(88, 166, 255, 0.18);
  border-color: rgba(88, 166, 255, 0.34);
}

.settings-popover {
  padding: 12px;
}

.settings-row {
  min-width: 240px;
  padding: 6px 4px;
}
"""


def run_command(args, input_bytes=None, check=True):
    return subprocess.run(
        args,
        input=input_bytes,
        capture_output=True,
        check=check,
    )


def find_paste_backend():
    if shutil.which("wtype") is not None:
        return {
            "name": "wtype",
            "command": ["wtype", "-M", "ctrl", "-k", "v", "-m", "ctrl"],
        }
    return None


def notify_send(summary, body=""):
    if shutil.which("notify-send") is None:
        return
    try:
        subprocess.run(
            ["notify-send", "-a", "Clipboard Browser", summary, body],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except OSError:
        return


def escape_markup(text):
    return GLib.markup_escape_text(text or "")


def clamp_text(text, limit=160):
    if len(text) <= limit:
        return text
    return text[: limit - 1].rstrip() + "..."


def classify_text_preview(text):
    lowered = text.lower()
    if re.search(r"https?://|www\.", lowered):
        return "links"
    code_markers = [
        "{",
        "}",
        "();",
        "=>",
        "import ",
        "from ",
        "const ",
        "let ",
        "class ",
        "def ",
        "function ",
        "#include",
        "select ",
        "</",
    ]
    line_count = text.count("\n") + 1
    if line_count > 1 and any(marker in lowered for marker in code_markers):
        return "code"
    if text.startswith("```") or text.startswith("#!/"):
        return "code"
    if re.search(r"^\s{2,}\S+", text, flags=re.MULTILINE):
        return "code"
    return "text"


def classify_summary(summary):
    lowered = summary.lower()
    if summary.startswith("[[ binary data"):
        if any(ext in lowered for ext in (" png ", " jpg", " jpeg", " gif", " webp", " avif", " bmp", " svg")):
            return "images"
        return "images"
    return classify_text_preview(summary)


def fingerprint_for_entry(kind, summary):
    digest = hashlib.sha256()
    digest.update(kind.encode("utf-8"))
    digest.update(b"\0")
    digest.update(summary.encode("utf-8", errors="ignore"))
    return digest.hexdigest()


def load_state():
    if not STATE_PATH.exists():
        return json.loads(json.dumps(DEFAULT_STATE))
    try:
        data = json.loads(STATE_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return json.loads(json.dumps(DEFAULT_STATE))
    state = json.loads(json.dumps(DEFAULT_STATE))
    if isinstance(data.get("pins"), list):
        state["pins"] = [str(item) for item in data["pins"] if isinstance(item, str)]
    if isinstance(data.get("settings"), dict):
        for key in state["settings"]:
            if isinstance(data["settings"].get(key), bool):
                state["settings"][key] = data["settings"][key]
    return state


def save_state(state):
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    STATE_PATH.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")


@dataclass
class ClipEntry:
    index: int
    entry_id: str
    raw_line: str
    summary: str
    kind: str
    fingerprint: str
    pinned: bool = False
    payload: Optional[bytes] = None
    payload_error: Optional[str] = None
    text_cache: Optional[str] = None

    @property
    def title(self):
        text = self.summary.replace("\n", " ").strip()
        return clamp_text(text or "Clipboard item", 120)

    @property
    def meta(self):
        parts = [TYPE_LABELS.get(self.kind, "Clip")]
        if self.pinned:
            parts.append("Pinned")
        return "  ".join(parts)


class IPCServer(threading.Thread):
    def __init__(self, app_window):
        super().__init__(daemon=True)
        self.app_window = app_window
        self.sock = None
        self.running = True

    def run(self):
        IPC_DIR.mkdir(parents=True, exist_ok=True)
        try:
            if IPC_SOCKET_PATH.exists():
                IPC_SOCKET_PATH.unlink()
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.bind(str(IPC_SOCKET_PATH))
            IPC_SOCKET_PATH.chmod(0o600)
            sock.listen(8)
            self.sock = sock
        except OSError:
            return

        while self.running:
            try:
                conn, _addr = self.sock.accept()
            except OSError:
                break
            with conn:
                try:
                    payload = conn.recv(128)
                except OSError:
                    continue
                command = payload.decode("utf-8", errors="replace").strip() or "ping"
                GLib.idle_add(self.app_window.handle_ipc_command, command)
                try:
                    conn.sendall(b"ok\n")
                except OSError:
                    continue

        self.cleanup()

    def stop(self):
        self.running = False
        if self.sock is not None:
            try:
                self.sock.close()
            except OSError:
                pass
            self.sock = None
        self.cleanup()

    def cleanup(self):
        try:
            if IPC_SOCKET_PATH.exists():
                IPC_SOCKET_PATH.unlink()
        except OSError:
            pass


class SectionHeaderRow(Gtk.ListBoxRow):
    def __init__(self, title, count):
        super().__init__()
        self.set_selectable(False)
        self.set_activatable(False)
        self.add_css_class("section-row")

        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        box.add_css_class("section-box")
        label = Gtk.Label(
            xalign=0,
            label=f"{title} ({count})",
        )
        label.add_css_class("section-title")
        box.append(label)
        self.set_child(box)


class ClipRow(Gtk.ListBoxRow):
    def __init__(self, app_window, entry):
        super().__init__()
        self.app_window = app_window
        self.entry = entry
        self.hovered = False

        self.set_selectable(True)
        self.set_activatable(True)
        self.add_css_class("clip-row")
        self.set_name(f"clip-row-{entry.entry_id}")

        shell = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        shell.add_css_class("clip-row-shell")
        self.shell = shell

        strip = Gtk.Box()
        strip.add_css_class("type-strip")
        strip.add_css_class(entry.kind)
        shell.append(strip)

        icon = Gtk.Image.new_from_icon_name(TYPE_ICONS.get(entry.kind, TYPE_ICONS["text"]))
        icon.add_css_class("type-icon")
        shell.append(icon)

        text_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        text_box.set_hexpand(True)

        title = Gtk.Label(xalign=0)
        title.set_ellipsize(Pango.EllipsizeMode.END)
        title.set_wrap(True)
        title.set_wrap_mode(Pango.WrapMode.WORD_CHAR)
        title.set_lines(2)
        title.add_css_class("row-title")
        title.set_text(entry.title)
        text_box.append(title)

        meta = Gtk.Label(xalign=0, label=entry.meta)
        meta.add_css_class("row-meta")
        meta.add_css_class("meta-label")
        text_box.append(meta)

        shell.append(text_box)

        self.action_revealer = Gtk.Revealer()
        self.action_revealer.set_transition_type(Gtk.RevealerTransitionType.CROSSFADE)
        self.action_revealer.set_reveal_child(False)

        actions = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)

        pin_button = self.make_icon_button("view-pin-symbolic", "Pin")
        pin_button.connect("clicked", self.on_pin_clicked)
        actions.append(pin_button)

        copy_button = self.make_icon_button("edit-copy-symbolic", "Copy")
        copy_button.connect("clicked", self.on_copy_clicked)
        actions.append(copy_button)

        delete_button = self.make_icon_button("user-trash-symbolic", "Delete")
        delete_button.connect("clicked", self.on_delete_clicked)
        actions.append(delete_button)

        more_button = Gtk.MenuButton()
        more_button.add_css_class("row-action")
        more_button.set_tooltip_text("More")
        more_button.set_child(Gtk.Image.new_from_icon_name("open-menu-symbolic"))
        more_button.set_popover(self.build_more_popover())
        actions.append(more_button)

        self.action_revealer.set_child(actions)
        shell.append(self.action_revealer)
        self.set_child(shell)

        click = Gtk.GestureClick()
        click.set_button(0)
        click.connect("pressed", self.on_pressed)
        self.add_controller(click)

        motion = Gtk.EventControllerMotion()
        motion.connect("enter", self.on_hover_enter)
        motion.connect("leave", self.on_hover_leave)
        self.add_controller(motion)

    def make_icon_button(self, icon_name, tooltip):
        button = Gtk.Button()
        button.add_css_class("row-action")
        button.set_tooltip_text(tooltip)
        button.set_focus_on_click(False)
        button.set_child(Gtk.Image.new_from_icon_name(icon_name))
        return button

    def build_more_popover(self):
        popover = Gtk.Popover()
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        box.set_margin_top(10)
        box.set_margin_bottom(10)
        box.set_margin_start(10)
        box.set_margin_end(10)

        preview_button = Gtk.Button(label="Preview")
        preview_button.connect("clicked", lambda *_: self.app_window.set_preview_entry(self.entry, self))
        box.append(preview_button)

        if self.entry.kind == "links":
            open_button = Gtk.Button(label="Open link")
            open_button.connect("clicked", lambda *_: self.app_window.open_link(self.entry))
            box.append(open_button)

        pin_button = Gtk.Button(label="Toggle pin")
        pin_button.connect("clicked", lambda *_: self.app_window.toggle_entries([self.entry]))
        box.append(pin_button)

        popover.set_child(box)
        return popover

    def on_pressed(self, gesture, _n_press, _x, _y):
        self.app_window.last_interacted_row = self
        state = gesture.get_current_event_state()
        GLib.idle_add(self.app_window.after_row_input, self, bool(state & Gdk.ModifierType.SHIFT_MASK))

    def on_hover_enter(self, *_args):
        self.hovered = True
        self.sync_action_visibility()
        if self.app_window.settings["hover_preview"]:
            self.app_window.set_preview_entry(self.entry, self, hovered=True)

    def on_hover_leave(self, *_args):
        self.hovered = False
        self.sync_action_visibility()

    def on_pin_clicked(self, *_args):
        self.app_window.toggle_entries([self.entry])

    def on_copy_clicked(self, *_args):
        self.app_window.copy_entry(self.entry, close_after=False)

    def on_delete_clicked(self, *_args):
        self.app_window.delete_entries([self.entry])

    def sync_action_visibility(self):
        selected = self in self.app_window.listbox.get_selected_rows()
        self.action_revealer.set_reveal_child(self.hovered or selected)


class ClipboardWindow(Adw.ApplicationWindow):
    def __init__(self, app, daemon_mode=False):
        super().__init__(application=app)
        self.daemon_mode = daemon_mode
        self.state = load_state()
        self.settings = self.state["settings"]
        self.pins = set(self.state["pins"])
        self.entries = []
        self.filtered_entries = []
        self.item_rows = []
        self.row_by_fingerprint = {}
        self.preview_entry_item = None
        self.preview_row = None
        self.last_interacted_row = None
        self.temp_files = []
        self.current_filter = "all"
        self.filter_buttons = {}
        self.editing_entry = None
        self.paste_backend = find_paste_backend()
        self.loading_entries = False
        self.ipc_server = None

        self.set_title("Clipboard Browser")
        self.set_default_size(1160, 740)
        self.set_resizable(True)
        self.set_decorated(False)
        self.add_css_class("clipboard-window")
        self.connect("close-request", self.on_close_request)

        self.toast_overlay = Adw.ToastOverlay()
        self.set_content(self.toast_overlay)

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        root.add_css_class("clipboard-shell")
        self.toast_overlay.set_child(root)

        root.append(self.build_topbar())

        paned = Gtk.Paned.new(Gtk.Orientation.HORIZONTAL)
        paned.set_wide_handle(True)
        root.append(paned)

        history_card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        history_card.add_css_class("history-card")

        history_header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        history_header.set_margin_top(4)
        history_header.set_margin_start(4)
        history_header.set_margin_end(4)
        title_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        history_title = Gtk.Label(xalign=0, label="History")
        history_title.add_css_class("topbar-title")
        title_box.append(history_title)
        self.history_summary = Gtk.Label(xalign=0, label="")
        self.history_summary.add_css_class("topbar-subtitle")
        title_box.append(self.history_summary)
        history_header.append(title_box)
        history_card.append(history_header)

        self.listbox = Gtk.ListBox()
        self.listbox.add_css_class("history-list")
        self.listbox.set_selection_mode(Gtk.SelectionMode.MULTIPLE)
        self.listbox.connect("selected-rows-changed", self.on_selected_rows_changed)

        history_scroll = Gtk.ScrolledWindow()
        history_scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        history_scroll.set_vexpand(True)
        history_scroll.set_child(self.listbox)
        history_card.append(history_scroll)
        paned.set_start_child(history_card)

        self.preview_revealer = Gtk.Revealer()
        self.preview_revealer.set_reveal_child(True)
        self.preview_revealer.set_transition_type(Gtk.RevealerTransitionType.SLIDE_LEFT)
        self.preview_revealer.set_transition_duration(220)
        self.preview_revealer.set_hexpand(True)
        self.preview_revealer.set_child(self.build_preview_panel())
        paned.set_end_child(self.preview_revealer)
        paned.set_position(520)

        root.append(self.build_action_bar())
        self.filter_buttons["all"].set_active(True)

        key_controller = Gtk.EventControllerKey()
        key_controller.connect("key-pressed", self.on_key_pressed)
        self.add_controller(key_controller)

        self.show_loading_state()
        GLib.idle_add(self.start_async_reload)
        if self.daemon_mode:
            self.start_ipc_server()
        if not self.daemon_mode:
            self.present()

    def build_topbar(self):
        topbar = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        topbar.add_css_class("topbar")

        top_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)

        titles = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        title = Gtk.Label(xalign=0, label="Clipboard Browser")
        title.add_css_class("topbar-title")
        titles.append(title)
        subtitle = Gtk.Label(
            xalign=0,
            label="Pinned at the top, full preview on the right, and keyboard-first actions.",
        )
        subtitle.add_css_class("topbar-subtitle")
        titles.append(subtitle)
        titles.set_hexpand(True)
        top_row.append(titles)

        hint = Gtk.Button(label="/ Search")
        hint.add_css_class("shortcut-hint")
        hint.connect("clicked", lambda *_: self.focus_search())
        top_row.append(hint)

        self.shortcut_label = Gtk.Label(
            label="j/k move   Enter copy   Shift+Enter paste   Esc close   x delete   p pin"
        )
        self.shortcut_label.add_css_class("shortcut-hint")
        top_row.append(self.shortcut_label)

        close_button = Gtk.Button()
        close_button.set_tooltip_text("Close")
        close_button.set_child(Gtk.Image.new_from_icon_name("window-close-symbolic"))
        close_button.connect("clicked", lambda *_: self.close())
        top_row.append(close_button)

        settings_button = Gtk.MenuButton()
        settings_button.set_child(Gtk.Image.new_from_icon_name("emblem-system-symbolic"))
        settings_button.set_tooltip_text("Settings")
        settings_button.set_popover(self.build_settings_popover())
        top_row.append(settings_button)

        clear_button = Gtk.Button()
        clear_button.set_tooltip_text("Clear history")
        clear_button.set_child(Gtk.Image.new_from_icon_name("edit-clear-all-symbolic"))
        clear_button.connect("clicked", self.confirm_clear_history)
        top_row.append(clear_button)

        topbar.append(top_row)

        filter_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        filter_row.set_homogeneous(False)
        filter_row.set_hexpand(True)

        for filter_name in FILTERS:
            button = Gtk.ToggleButton(label=TYPE_LABELS.get(filter_name, "All"))
            button.add_css_class("filter-chip")
            button.connect("toggled", self.on_filter_toggled, filter_name)
            self.filter_buttons[filter_name] = button
            filter_row.append(button)

        topbar.append(filter_row)

        self.search_entry = Gtk.SearchEntry()
        self.search_entry.add_css_class("search-box")
        self.search_entry.set_placeholder_text(
            "Search clipboard history. Try code:, img:, link:, or text:."
        )
        self.search_entry.connect("search-changed", self.on_search_changed)
        topbar.append(self.search_entry)

        return topbar

    def build_settings_popover(self):
        popover = Gtk.Popover()
        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        content.add_css_class("settings-popover")

        title = Gtk.Label(xalign=0, label="Browser settings")
        title.add_css_class("row-title")
        content.append(title)

        self.dedupe_switch = Gtk.Switch(active=self.settings["dedupe"])
        self.dedupe_switch.connect("notify::active", self.on_dedupe_changed)
        content.append(self.settings_row("Hide duplicate clips", "Collapse identical previews into one row.", self.dedupe_switch))

        self.hover_preview_switch = Gtk.Switch(active=self.settings["hover_preview"])
        self.hover_preview_switch.connect("notify::active", self.on_hover_preview_changed)
        content.append(
            self.settings_row(
                "Preview on hover",
                "Move through the list and update the preview without selecting.",
                self.hover_preview_switch,
            )
        )

        popover.set_child(content)
        return popover

    def settings_row(self, title, subtitle, widget):
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        row.add_css_class("settings-row")

        labels = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        labels.set_hexpand(True)

        title_label = Gtk.Label(xalign=0, label=title)
        title_label.add_css_class("row-title")
        labels.append(title_label)

        subtitle_label = Gtk.Label(xalign=0, label=subtitle)
        subtitle_label.add_css_class("row-meta")
        subtitle_label.add_css_class("meta-label")
        subtitle_label.set_wrap(True)
        labels.append(subtitle_label)

        row.append(labels)
        row.append(widget)
        return row

    def build_preview_panel(self):
        preview = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        preview.add_css_class("preview-card")

        header = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)

        chips = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.preview_type_chip = Gtk.Label(label="Preview")
        self.preview_type_chip.add_css_class("preview-chip")
        chips.append(self.preview_type_chip)

        self.preview_meta_chip = Gtk.Label(label="Hover a row to inspect it.")
        self.preview_meta_chip.add_css_class("preview-chip")
        chips.append(self.preview_meta_chip)

        self.preview_detail_chip = Gtk.Label(label="No payload")
        self.preview_detail_chip.add_css_class("preview-chip")
        chips.append(self.preview_detail_chip)
        header.append(chips)

        self.preview_title = Gtk.Label(xalign=0, label="No selection")
        self.preview_title.add_css_class("preview-title")
        self.preview_title.set_wrap(True)
        header.append(self.preview_title)

        self.preview_summary = Gtk.Label(
            xalign=0,
            label="Search, hover, or select a clipboard item to inspect the full payload here.",
        )
        self.preview_summary.add_css_class("preview-summary")
        self.preview_summary.set_wrap(True)
        header.append(self.preview_summary)
        preview.append(header)

        self.preview_stack = Gtk.Stack()
        self.preview_stack.set_vexpand(True)

        placeholder = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        placeholder.add_css_class("preview-pane")
        placeholder.set_valign(Gtk.Align.CENTER)
        placeholder.set_halign(Gtk.Align.FILL)
        placeholder_label = Gtk.Label(
            label="Pinned clips stay on top. Filter by type, use / for search, or hit Enter to copy the active row."
        )
        placeholder_label.add_css_class("preview-placeholder")
        placeholder_label.set_wrap(True)
        placeholder.append(placeholder_label)
        self.preview_stack.add_named(placeholder, "placeholder")

        text_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        text_box.add_css_class("preview-pane")
        text_scroll = Gtk.ScrolledWindow()
        text_scroll.set_vexpand(True)
        self.preview_text = Gtk.TextView()
        self.preview_text.add_css_class("preview-text")
        self.preview_text.set_editable(False)
        self.preview_text.set_cursor_visible(False)
        self.preview_text.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
        self.preview_text.set_monospace(False)
        text_scroll.set_child(self.preview_text)
        text_box.append(text_scroll)
        self.preview_stack.add_named(text_box, "text")

        image_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        image_box.add_css_class("preview-pane")
        image_scroll = Gtk.ScrolledWindow()
        image_scroll.set_vexpand(True)
        self.preview_image = Gtk.Picture()
        self.preview_image.set_can_shrink(True)
        self.preview_image.set_keep_aspect_ratio(True)
        self.preview_image.set_hexpand(True)
        self.preview_image.set_vexpand(True)
        image_scroll.set_child(self.preview_image)
        image_box.append(image_scroll)
        self.preview_stack.add_named(image_box, "image")

        binary_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        binary_box.add_css_class("preview-pane")
        self.preview_binary_label = Gtk.Label(xalign=0, label="Preview unavailable for this clipboard item.")
        self.preview_binary_label.set_wrap(True)
        binary_box.append(self.preview_binary_label)
        self.preview_stack.add_named(binary_box, "binary")

        editor_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        editor_box.add_css_class("preview-pane")
        editor_scroll = Gtk.ScrolledWindow()
        editor_scroll.set_vexpand(True)
        self.editor_text = Gtk.TextView()
        self.editor_text.add_css_class("editor-text")
        self.editor_text.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
        editor_scroll.set_child(self.editor_text)
        editor_box.append(editor_scroll)
        self.preview_stack.add_named(editor_box, "editor")

        preview.append(self.preview_stack)
        self.preview_stack.set_visible_child_name("placeholder")
        return preview

    def build_action_bar(self):
        bar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        bar.add_css_class("action-bar")

        self.selection_label = Gtk.Label(
            xalign=0,
            label="0 items",
        )
        self.selection_label.add_css_class("muted-label")
        self.selection_label.set_hexpand(True)
        bar.append(self.selection_label)

        self.copy_button = Gtk.Button(label="Copy")
        self.copy_button.add_css_class("action-button")
        self.copy_button.add_css_class("suggested-action")
        self.copy_button.connect("clicked", lambda *_: self.copy_selected(close_after=False))
        bar.append(self.copy_button)

        self.paste_button = Gtk.Button(label="Paste")
        self.paste_button.add_css_class("action-button")
        self.paste_button.connect("clicked", lambda *_: self.paste_selected())
        bar.append(self.paste_button)

        self.open_link_button = Gtk.Button(label="Open link")
        self.open_link_button.add_css_class("action-button")
        self.open_link_button.connect("clicked", lambda *_: self.open_active_link())
        bar.append(self.open_link_button)

        self.edit_button = Gtk.Button(label="Edit")
        self.edit_button.add_css_class("action-button")
        self.edit_button.connect("clicked", lambda *_: self.start_edit())
        bar.append(self.edit_button)

        self.save_edit_button = Gtk.Button(label="Save edit")
        self.save_edit_button.add_css_class("action-button")
        self.save_edit_button.connect("clicked", lambda *_: self.save_edit())
        bar.append(self.save_edit_button)

        self.cancel_edit_button = Gtk.Button(label="Cancel")
        self.cancel_edit_button.add_css_class("action-button")
        self.cancel_edit_button.connect("clicked", lambda *_: self.stop_edit())
        bar.append(self.cancel_edit_button)

        self.delete_button = Gtk.Button(label="Delete")
        self.delete_button.add_css_class("action-button")
        self.delete_button.connect("clicked", lambda *_: self.delete_selected())
        bar.append(self.delete_button)

        self.pin_button = Gtk.Button(label="Pin")
        self.pin_button.add_css_class("action-button")
        self.pin_button.connect("clicked", lambda *_: self.toggle_entries(self.selected_entries()))
        bar.append(self.pin_button)

        self.update_action_bar()
        return bar

    def show_loading_state(self):
        self.history_summary.set_text("Loading clipboard history...")
        self.preview_stack.set_visible_child_name("placeholder")
        self.preview_title.set_text("Loading clipboard history")
        self.preview_summary.set_text("Opening the overlay first, then filling history in the background.")
        self.preview_meta_chip.set_text("Starting up")
        self.preview_detail_chip.set_text("Loading")
        self.selection_label.set_text("Loading...")

    def start_async_reload(self):
        self.reload_entries()
        return False

    def on_close_request(self, *_args):
        if self.daemon_mode:
            self.hide_overlay()
            return True
        self.shutdown_runtime()
        return False

    def cleanup_temp_files(self):
        while self.temp_files:
            path = self.temp_files.pop()
            try:
                os.unlink(path)
            except OSError:
                continue

    def shutdown_runtime(self):
        self.cleanup_temp_files()
        if self.ipc_server is not None:
            self.ipc_server.stop()
            self.ipc_server = None

    def start_ipc_server(self):
        if self.ipc_server is not None:
            return
        self.ipc_server = IPCServer(self)
        self.ipc_server.start()

    def handle_ipc_command(self, command):
        if command == "toggle":
            if self.get_visible():
                self.hide_overlay()
            else:
                self.show_overlay()
        elif command == "show":
            self.show_overlay()
        elif command == "hide":
            self.hide_overlay()
        elif command == "refresh":
            self.reload_entries()
        elif command == "quit":
            self.shutdown_runtime()
            app = self.get_application()
            if app is not None:
                app.quit()
        return False

    def show_overlay(self):
        self.present()
        self.reload_entries(
            preserve_fingerprint=self.preview_entry_item.fingerprint if self.preview_entry_item is not None else None
        )

    def hide_overlay(self):
        self.cleanup_temp_files()
        self.hide()

    def add_toast(self, title, timeout=2):
        toast = Adw.Toast.new(title)
        toast.set_timeout(timeout)
        self.toast_overlay.add_toast(toast)

    def on_dedupe_changed(self, widget, _param_spec):
        self.settings["dedupe"] = widget.get_active()
        self.save_state()
        self.reload_entries()

    def on_hover_preview_changed(self, widget, _param_spec):
        self.settings["hover_preview"] = widget.get_active()
        self.save_state()

    def save_state(self):
        self.state["pins"] = sorted(self.pins)
        self.state["settings"] = dict(self.settings)
        save_state(self.state)

    def focus_search(self):
        self.search_entry.grab_focus()

    def update_filter_labels(self):
        counts = {
            "all": len(self.entries),
            "text": 0,
            "images": 0,
            "code": 0,
            "links": 0,
        }
        for entry in self.entries:
            counts[entry.kind] += 1
        for filter_name, button in self.filter_buttons.items():
            base = TYPE_LABELS.get(filter_name, "All")
            button.set_label(f"{base} {counts.get(filter_name, 0)}")

    def on_filter_toggled(self, button, filter_name):
        if not button.get_active():
            if self.current_filter == filter_name:
                button.set_active(True)
            return
        self.current_filter = filter_name
        for name, other_button in self.filter_buttons.items():
            if name != filter_name:
                other_button.set_active(False)
        self.apply_filters()

    def on_search_changed(self, *_args):
        self.apply_filters()

    def parse_search(self):
        query = self.search_entry.get_text().strip()
        forced_filter = None
        lowered = query.lower()
        for prefix, filter_name in SEARCH_PREFIXES.items():
            if lowered.startswith(prefix):
                forced_filter = filter_name
                query = query[len(prefix) :].strip()
                break
        return query.lower(), forced_filter

    def fetch_entries(self):
        try:
            result = run_command(["cliphist", "-preview-width", str(PREVIEW_WIDTH), "list"])
        except (subprocess.CalledProcessError, FileNotFoundError) as exc:
            self.add_toast(f"Unable to read cliphist: {exc}", timeout=3)
            return []

        entries = []
        seen = set()
        for idx, raw_line in enumerate(result.stdout.decode("utf-8", errors="replace").splitlines(), start=1):
            if not raw_line.strip():
                continue
            try:
                entry_id, summary = raw_line.split("\t", 1)
            except ValueError:
                continue
            kind = classify_summary(summary)
            fingerprint = fingerprint_for_entry(kind, summary)
            if self.settings["dedupe"] and fingerprint in seen:
                continue
            seen.add(fingerprint)
            entries.append(
                ClipEntry(
                    index=idx,
                    entry_id=entry_id,
                    raw_line=raw_line,
                    summary=summary,
                    kind=kind,
                    fingerprint=fingerprint,
                    pinned=fingerprint in self.pins,
                )
            )
        return entries

    def reload_entries(self, preserve_fingerprint=None):
        if preserve_fingerprint is None and self.preview_entry_item is not None:
            preserve_fingerprint = self.preview_entry_item.fingerprint
        if self.loading_entries:
            return
        self.loading_entries = True
        worker = threading.Thread(
            target=self._reload_entries_worker,
            args=(preserve_fingerprint,),
            daemon=True,
        )
        worker.start()

    def _reload_entries_worker(self, preserve_fingerprint):
        entries = self.fetch_entries()
        GLib.idle_add(self.finish_reload_entries, entries, preserve_fingerprint)

    def finish_reload_entries(self, entries, preserve_fingerprint):
        self.loading_entries = False
        self.entries = entries
        self.update_filter_labels()
        self.apply_filters(prefer_fingerprint=preserve_fingerprint)
        return False

    def apply_filters(self, prefer_fingerprint=None):
        search_query, forced_filter = self.parse_search()
        active_filter = forced_filter or self.current_filter
        selected_rows = self.listbox.get_selected_rows()
        selected_fingerprints = {
            row.entry.fingerprint for row in selected_rows if isinstance(row, ClipRow)
        }
        if prefer_fingerprint:
            selected_fingerprints.add(prefer_fingerprint)

        filtered = []
        for entry in self.entries:
            if active_filter != "all" and entry.kind != active_filter:
                continue
            haystack = f"{entry.summary}\n{entry.meta}".lower()
            if search_query and search_query not in haystack:
                continue
            filtered.append(entry)

        pinned = [entry for entry in filtered if entry.pinned]
        history = [entry for entry in filtered if not entry.pinned]
        self.filtered_entries = pinned + history

        while True:
            child = self.listbox.get_first_child()
            if child is None:
                break
            self.listbox.remove(child)

        self.item_rows = []
        self.row_by_fingerprint = {}

        if pinned:
            self.listbox.append(SectionHeaderRow("Pinned", len(pinned)))
            for entry in pinned:
                self.append_entry_row(entry)

        if history:
            self.listbox.append(SectionHeaderRow("History", len(history)))
            for entry in history:
                self.append_entry_row(entry)

        if not filtered:
            self.preview_entry_item = None
            self.preview_row = None
            self.preview_stack.set_visible_child_name("placeholder")
            self.preview_title.set_text("No matching clips")
            self.preview_summary.set_text("Change the filter, clear the search, or copy something new.")
            self.preview_type_chip.set_text("Empty")
            self.preview_detail_chip.set_text("No payload")
            self.preview_type_chip.remove_css_class("text")
            self.preview_type_chip.remove_css_class("images")
            self.preview_type_chip.remove_css_class("code")
            self.preview_type_chip.remove_css_class("links")
        else:
            restored = False
            for row in self.item_rows:
                if row.entry.fingerprint in selected_fingerprints:
                    self.listbox.select_row(row)
                    self.last_interacted_row = row
                    self.set_preview_entry(row.entry, row)
                    restored = True
                    break
            if not restored and self.item_rows:
                row = self.item_rows[0]
                self.listbox.select_row(row)
                self.last_interacted_row = row
                self.set_preview_entry(row.entry, row)

        visible_count = len(self.filtered_entries)
        self.history_summary.set_text(
            f"{visible_count} visible   {len(pinned)} pinned   {len(history)} history"
        )
        self.update_action_bar()

    def append_entry_row(self, entry):
        row = ClipRow(self, entry)
        self.item_rows.append(row)
        self.row_by_fingerprint[entry.fingerprint] = row
        self.listbox.append(row)

    def selected_entries(self):
        return [
            row.entry for row in self.listbox.get_selected_rows() if isinstance(row, ClipRow)
        ]

    def active_entry(self):
        if self.preview_entry_item is not None:
            return self.preview_entry_item
        selected = self.selected_entries()
        return selected[0] if selected else None

    def on_selected_rows_changed(self, *_args):
        for row in self.item_rows:
            row.sync_action_visibility()

        selected = self.selected_entries()
        if self.last_interacted_row in self.listbox.get_selected_rows():
            self.set_preview_entry(self.last_interacted_row.entry, self.last_interacted_row)
        elif selected:
            row = self.row_by_fingerprint.get(selected[0].fingerprint)
            self.set_preview_entry(selected[0], row)
        else:
            self.stop_edit()

        self.update_action_bar()

    def after_row_input(self, row, _shift_pressed):
        if row in self.listbox.get_selected_rows():
            self.set_preview_entry(row.entry, row)
        return False

    def ensure_payload(self, entry):
        if entry.payload is not None or entry.payload_error is not None:
            return
        try:
            result = run_command(["cliphist", "decode", entry.entry_id])
        except subprocess.CalledProcessError as exc:
            entry.payload_error = exc.stderr.decode("utf-8", errors="replace") or str(exc)
            return
        entry.payload = result.stdout

    def ensure_text_payload(self, entry):
        if entry.text_cache is not None:
            return entry.text_cache
        self.ensure_payload(entry)
        if entry.payload_error is not None:
            entry.text_cache = ""
            return entry.text_cache
        entry.text_cache = (entry.payload or b"").decode("utf-8", errors="replace")
        return entry.text_cache

    def set_preview_entry(self, entry, row=None, hovered=False):
        self.preview_entry_item = entry
        self.preview_row = row
        if row is not None:
            self.last_interacted_row = row
        for item_row in self.item_rows:
            if item_row == row:
                item_row.add_css_class("active-preview")
            else:
                item_row.remove_css_class("active-preview")

        for kind_name in TYPE_LABELS:
            self.preview_type_chip.remove_css_class(kind_name)
        self.preview_type_chip.add_css_class(entry.kind)
        self.preview_type_chip.set_text(TYPE_LABELS.get(entry.kind, "Clip"))

        hover_text = "Hover preview" if hovered else ("Pinned" if entry.pinned else "Selected")
        self.preview_meta_chip.set_text(hover_text)
        self.preview_title.set_text(entry.title)
        self.preview_summary.set_text(entry.summary)
        self.preview_revealer.set_reveal_child(True)

        if self.editing_entry is not None and self.editing_entry.fingerprint != entry.fingerprint:
            self.stop_edit()

        if entry.kind == "images":
            self.ensure_payload(entry)
            if entry.payload_error or not entry.payload:
                self.preview_binary_label.set_text(entry.payload_error or "Unable to decode image clip.")
                self.preview_detail_chip.set_text("Image preview unavailable")
                self.preview_stack.set_visible_child_name("binary")
                self.update_action_bar()
                return
            try:
                suffix = ".png"
                for ext in ("png", "jpg", "jpeg", "gif", "webp", "bmp", "svg"):
                    if f" {ext}" in entry.summary.lower():
                        suffix = f".{ext}"
                        break
                handle = tempfile.NamedTemporaryFile(prefix="cliphist-preview-", suffix=suffix, delete=False)
                handle.write(entry.payload)
                handle.flush()
                handle.close()
                self.temp_files.append(handle.name)
                self.preview_image.set_filename(handle.name)
                self.preview_detail_chip.set_text(clamp_text(entry.summary.replace("[[ binary data ", "").replace(" ]]", ""), 56))
                self.preview_stack.set_visible_child_name("image")
            except OSError as exc:
                self.preview_binary_label.set_text(f"Unable to render image preview: {exc}")
                self.preview_detail_chip.set_text("Image preview unavailable")
                self.preview_stack.set_visible_child_name("binary")
        else:
            text = self.ensure_text_payload(entry)
            buffer_ = self.preview_text.get_buffer()
            buffer_.set_text(text)
            self.preview_text.set_monospace(entry.kind == "code")
            lines = max(1, text.count("\n") + 1)
            self.preview_detail_chip.set_text(f"{len(text)} chars   {lines} lines")
            self.preview_stack.set_visible_child_name("text")
        self.update_action_bar()

    def update_action_bar(self):
        if self.loading_entries:
            self.selection_label.set_text("Loading...")
            self.copy_button.set_sensitive(False)
            self.paste_button.set_sensitive(False)
            self.open_link_button.set_sensitive(False)
            self.edit_button.set_sensitive(False)
            self.delete_button.set_sensitive(False)
            self.pin_button.set_sensitive(False)
            self.save_edit_button.set_visible(False)
            self.cancel_edit_button.set_visible(False)
            self.copy_button.set_visible(True)
            self.paste_button.set_visible(True)
            self.open_link_button.set_visible(False)
            self.edit_button.set_visible(True)
            return

        selected = self.selected_entries()
        total = len(self.filtered_entries)
        if not selected:
            self.selection_label.set_text(f"{total} items")
        elif len(selected) == 1:
            self.selection_label.set_text(f"{total} items   1 selected")
        else:
            self.selection_label.set_text(f"{total} items   {len(selected)} selected")

        active = self.active_entry()
        text_like = active is not None and active.kind in {"text", "code", "links"}
        paste_available = self.paste_backend is not None
        self.copy_button.set_sensitive(active is not None)
        self.paste_button.set_sensitive(active is not None and paste_available)
        self.paste_button.set_tooltip_text(
            "Paste with Ctrl+V using wtype" if paste_available else "Install with: sudo pacman -S --noconfirm wtype"
        )
        self.open_link_button.set_sensitive(active is not None and active.kind == "links")
        self.edit_button.set_sensitive(text_like and len(selected) <= 1 and self.editing_entry is None)
        self.delete_button.set_sensitive(bool(selected))
        self.pin_button.set_sensitive(bool(selected))
        self.pin_button.set_label("Unpin" if selected and all(item.pinned for item in selected) else "Pin")

        editing = self.editing_entry is not None
        self.save_edit_button.set_visible(editing)
        self.cancel_edit_button.set_visible(editing)
        self.copy_button.set_visible(not editing)
        self.paste_button.set_visible(not editing)
        self.open_link_button.set_visible(not editing and active is not None and active.kind == "links")
        self.edit_button.set_visible(not editing)
        if active is None:
            self.preview_meta_chip.set_text("Hover or select")
            self.preview_detail_chip.set_text("No payload")

    def write_clipboard(self, payload):
        subprocess.run(["wl-copy"], input=payload, check=True)

    def copy_entry(self, entry, close_after):
        self.ensure_payload(entry)
        if entry.payload_error is not None:
            self.add_toast("Copy failed")
            notify_send("Clipboard Browser", entry.payload_error)
            return
        try:
            self.write_clipboard(entry.payload or b"")
        except (subprocess.CalledProcessError, FileNotFoundError) as exc:
            self.add_toast("wl-copy failed")
            notify_send("Clipboard Browser", str(exc))
            return
        self.add_toast("Copied to clipboard")
        if close_after:
            GLib.timeout_add(120, self.close_after_copy)

    def close_after_copy(self):
        if self.daemon_mode:
            self.hide_overlay()
        else:
            self.close()
        return False

    def copy_selected(self, close_after):
        active = self.active_entry()
        if active is None:
            return
        self.copy_entry(active, close_after=close_after)

    def delete_entries(self, entries):
        if not entries:
            return
        removed = 0
        for entry in entries:
            try:
                run_command(["cliphist", "delete"], input_bytes=(entry.raw_line + "\n").encode("utf-8"))
                removed += 1
            except subprocess.CalledProcessError:
                continue
        if removed:
            self.stop_edit()
            self.add_toast(f"Deleted {removed} clip{'s' if removed != 1 else ''}")
            keep = None
            if self.preview_entry_item and self.preview_entry_item.fingerprint not in {item.fingerprint for item in entries}:
                keep = self.preview_entry_item.fingerprint
            self.reload_entries(preserve_fingerprint=keep)

    def delete_selected(self):
        self.delete_entries(self.selected_entries())

    def toggle_entries(self, entries):
        if not entries:
            return
        make_pinned = any(entry.fingerprint not in self.pins for entry in entries)
        changed = 0
        for entry in entries:
            if make_pinned:
                self.pins.add(entry.fingerprint)
                entry.pinned = True
            else:
                self.pins.discard(entry.fingerprint)
                entry.pinned = False
            changed += 1
        self.save_state()
        self.apply_filters(prefer_fingerprint=self.active_entry().fingerprint if self.active_entry() else None)
        self.add_toast(("Pinned" if make_pinned else "Unpinned") + f" {changed} item{'s' if changed != 1 else ''}")

    def confirm_clear_history(self, *_args):
        dialog = Adw.MessageDialog.new(
            self,
            "Clear clipboard history?",
            "This wipes cliphist history. Pinned labels remain on disk, but the history rows will be removed.",
        )
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("clear", "Clear history")
        dialog.set_default_response("cancel")
        dialog.set_close_response("cancel")
        dialog.set_response_appearance("clear", Adw.ResponseAppearance.DESTRUCTIVE)
        dialog.connect("response", self.on_clear_history_response)
        dialog.present()

    def on_clear_history_response(self, _dialog, response):
        if response != "clear":
            return
        try:
            run_command(["cliphist", "wipe"])
        except subprocess.CalledProcessError as exc:
            self.add_toast("Unable to clear history")
            notify_send("Clipboard Browser", str(exc))
            return
        self.stop_edit()
        self.add_toast("Clipboard history cleared")
        self.reload_entries()

    def start_edit(self):
        entry = self.active_entry()
        if entry is None or entry.kind not in {"text", "code", "links"}:
            return
        text = self.ensure_text_payload(entry)
        buffer_ = self.editor_text.get_buffer()
        buffer_.set_text(text)
        self.editor_text.set_monospace(entry.kind == "code")
        self.preview_stack.set_visible_child_name("editor")
        self.editing_entry = entry
        self.update_action_bar()
        self.editor_text.grab_focus()

    def stop_edit(self):
        if self.editing_entry is None:
            return
        self.editing_entry = None
        if self.preview_entry_item is None:
            self.preview_stack.set_visible_child_name("placeholder")
        else:
            self.set_preview_entry(self.preview_entry_item, self.preview_row)
        self.update_action_bar()

    def save_edit(self):
        if self.editing_entry is None:
            return
        buffer_ = self.editor_text.get_buffer()
        start = buffer_.get_start_iter()
        end = buffer_.get_end_iter()
        text = buffer_.get_text(start, end, True)
        try:
            self.write_clipboard(text.encode("utf-8"))
        except (subprocess.CalledProcessError, FileNotFoundError) as exc:
            self.add_toast("Edit save failed")
            notify_send("Clipboard Browser", str(exc))
            return
        self.add_toast("Edited clip copied")
        self.stop_edit()
        GLib.timeout_add(180, self.reload_after_edit)

    def reload_after_edit(self):
        self.reload_entries()
        return False

    def open_link(self, entry):
        text = self.ensure_text_payload(entry).strip()
        if not text:
            return
        if not re.match(r"^[a-z]+://", text, flags=re.IGNORECASE):
            text = f"https://{text}"
        Gio.AppInfo.launch_default_for_uri(text, None)

    def open_active_link(self):
        entry = self.active_entry()
        if entry is None or entry.kind != "links":
            return
        self.open_link(entry)

    def move_selection(self, delta):
        if not self.item_rows:
            return
        if self.last_interacted_row in self.item_rows:
            current_row = self.last_interacted_row
        elif self.listbox.get_selected_rows():
            current_row = next(
                (row for row in self.listbox.get_selected_rows() if isinstance(row, ClipRow)),
                self.item_rows[0],
            )
        else:
            current_row = self.item_rows[0]
        current_idx = self.item_rows.index(current_row)
        next_idx = max(0, min(len(self.item_rows) - 1, current_idx + delta))
        next_row = self.item_rows[next_idx]
        self.listbox.unselect_all()
        self.listbox.select_row(next_row)
        self.last_interacted_row = next_row
        self.set_preview_entry(next_row.entry, next_row)
        next_row.grab_focus()

    def paste_selected(self):
        entry = self.active_entry()
        if entry is None:
            return
        if self.paste_backend is None:
            self.add_toast("Install wtype with: sudo pacman -S --noconfirm wtype", timeout=3)
            return
        self.ensure_payload(entry)
        if entry.payload_error is not None:
            self.add_toast("Copy failed")
            notify_send("Clipboard Browser", entry.payload_error)
            return
        try:
            self.write_clipboard(entry.payload or b"")
            subprocess.run(self.paste_backend["command"], check=True)
        except (subprocess.CalledProcessError, FileNotFoundError) as exc:
            self.add_toast("Paste failed")
            notify_send("Clipboard Browser", str(exc))
            return
        self.add_toast("Pasted clipboard")
        GLib.timeout_add(120, self.close_after_copy)

    def on_key_pressed(self, _controller, keyval, _keycode, state):
        focus = self.get_focus()
        search_focused = focus == self.search_entry
        editor_focused = focus == self.editor_text

        if keyval == Gdk.KEY_Escape:
            if self.editing_entry is not None:
                self.stop_edit()
                return True
            if self.daemon_mode:
                self.hide_overlay()
            else:
                self.close()
            return True

        if keyval == Gdk.KEY_slash and not search_focused:
            self.focus_search()
            return True

        if search_focused or editor_focused:
            return False

        if keyval == Gdk.KEY_a and state & Gdk.ModifierType.CONTROL_MASK:
            self.listbox.unselect_all()
            for row in self.item_rows:
                self.listbox.select_row(row)
            self.add_toast(f"Selected {len(self.item_rows)} clips")
            return True

        if keyval == Gdk.KEY_j:
            self.move_selection(1)
            return True
        if keyval == Gdk.KEY_k:
            self.move_selection(-1)
            return True
        if keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
            if state & Gdk.ModifierType.SHIFT_MASK:
                self.paste_selected()
            else:
                self.copy_selected(close_after=True)
            return True
        if keyval == Gdk.KEY_Right:
            if self.editing_entry is not None:
                self.editor_text.grab_focus()
            elif self.preview_entry_item is not None and self.preview_stack.get_visible_child_name() == "text":
                self.preview_text.grab_focus()
            return True
        if keyval == Gdk.KEY_x:
            self.delete_selected()
            return True
        if keyval == Gdk.KEY_p:
            self.toggle_entries(self.selected_entries())
            return True
        return False


class ClipboardApplication(Adw.Application):
    def __init__(self, daemon_mode=False):
        super().__init__(application_id=APP_ID)
        self.daemon_mode = daemon_mode
        if daemon_mode:
            self.hold()
        self.connect("activate", self.on_activate)

    def on_activate(self, app):
        window = self.props.active_window
        if window is None:
            window = ClipboardWindow(app, daemon_mode=self.daemon_mode)
        if not self.daemon_mode:
            window.present()


def install_css():
    provider = Gtk.CssProvider()
    provider.load_from_data(CSS.encode("utf-8"))
    display = Gdk.Display.get_default()
    if display is None:
        return
    Gtk.StyleContext.add_provider_for_display(
        display,
        provider,
        Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
    )


def parse_args(argv):
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--daemon", action="store_true")
    return parser.parse_known_args(argv[1:])


def main():
    args, remaining = parse_args(sys.argv)
    if shutil.which("cliphist") is None:
        notify_send("Clipboard Browser", "cliphist is not installed.")
        return 0
    if shutil.which("wl-copy") is None:
        notify_send("Clipboard Browser", "wl-copy is not installed.")
        return 0

    if not Gtk.init_check():
        notify_send("Clipboard Browser", "A GTK display session is required.")
        return 1

    Adw.init()
    install_css()
    app = ClipboardApplication(daemon_mode=args.daemon)
    return app.run([sys.argv[0], *remaining])


if __name__ == "__main__":
    raise SystemExit(main())
