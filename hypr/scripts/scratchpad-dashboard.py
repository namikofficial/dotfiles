#!/usr/bin/env python3
import json
import os
import subprocess
import sys
from pathlib import Path

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
from gi.repository import Gtk, GLib, Gdk  # noqa: E402

def runtime_dir():
    explicit = os.environ.get("NOXFLOW_SCRATCH_RUNTIME")
    candidates = [
        Path(explicit) if explicit else None,
        Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "noxflow",
        Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))) / "noxflow",
        Path("/tmp") / f"noxflow-{os.getuid()}",
    ]
    for candidate in candidates:
        if candidate is None:
            continue
        try:
            candidate.mkdir(parents=True, exist_ok=True)
            probe = candidate / ".write-test"
            probe.write_text("ok")
            probe.unlink(missing_ok=True)
            return candidate
        except Exception:
            continue
    return Path("/tmp")


STATE_DIR = runtime_dir()
SCENE_FILE = STATE_DIR / "scratchpad-scene-state.json"
PID_FILE = STATE_DIR / "scratchpad-dashboard.pid"
CSS_FILE = Path.home() / ".config/hypr/scripts/scratchpad-dashboard.css"
REGISTRY_FILE = Path.home() / ".config/hypr/scripts/scratchpad-registry.toml"
MANAGER = str(Path.home() / ".config/hypr/scripts/scratchpad-manager.sh")

ICON_MAP = {
    "scene": "󰙀",
    "terminal": "",
    "ai": "󰞷",
    "logs": "󰆍",
    "notes": "󰈙",
    "obsidian": "󰠮",
    "database": "󰆼",
    "music": "󰝚",
    "browser": "󰓂",
}

PRIMARY_LAYOUT = [
    ("scene", 0, 0, 2, 1),
    ("ai", 2, 0, 1, 1),
    ("logs", 3, 0, 1, 1),
]

SECONDARY_LAYOUT = [
    ("terminal", 0, 0, 2, 1),
    ("browser-devtools", 2, 0, 1, 1),
    ("db", 3, 0, 1, 1),
    ("notes", 0, 1, 1, 1),
    ("obsidian", 1, 1, 1, 1),
    ("music", 2, 1, 1, 1),
]


def load_registry():
    import tomllib

    data = tomllib.loads(REGISTRY_FILE.read_text())
    pads = []
    for key, raw in data.get("scratchpads", {}).items():
        dashboard = raw.get("dashboard", {})
        pads.append(
            {
                "name": key,
                "title": raw.get("name", key),
                "desc": raw.get("description", ""),
                "icon": ICON_MAP.get(raw.get("icon", key), "•"),
                "class": raw.get("class", ""),
                "mode": raw.get("mode", "overlay"),
                "accent": dashboard.get("accent", f"card-{key}"),
                "rect": (
                    int(dashboard.get("x", 0)),
                    int(dashboard.get("y", 0)),
                    int(dashboard.get("w", 1)),
                    int(dashboard.get("h", 1)),
                ),
                "cmd": ["bash", MANAGER, "launch", key],
            }
        )
    return pads


SCRATCHPADS = load_registry()
SCENE_CARD = {
    "name": "scene",
    "title": "Full Scene",
    "desc": "Main window, AI, and runner aligned together.",
    "icon": ICON_MAP["scene"],
    "accent": "card-scene",
    "cmd": ["bash", MANAGER, "toggle", "scene"],
}


def run(cmd):
    subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def focused_monitor():
    try:
        monitors = json.loads(subprocess.check_output(["hyprctl", "-j", "monitors"], text=True))
    except Exception:
        return {}
    return next((monitor for monitor in monitors if monitor.get("focused")), monitors[0] if monitors else {})


def dashboard_window_size():
    monitor = focused_monitor()
    width = int(monitor.get("width", 1600))
    height = int(monitor.get("height", 900))
    reserved = list(monitor.get("reserved", [0, 0, 0, 0]) or [0, 0, 0, 0])
    reserved += [0] * (4 - len(reserved))
    left, top, right, bottom = [int(v or 0) for v in reserved[:4]]
    usable_w = max(900, width - left - right - 72)
    usable_h = max(560, height - top - bottom - 72)
    return (
        min(1180, round(usable_w * 0.74)),
        min(720, round(usable_h * 0.72)),
    )


def read_state():
    state = {"scene": "idle", **{pad["name"]: "idle" for pad in SCRATCHPADS}}
    class_map = {pad["name"]: pad["class"] for pad in SCRATCHPADS if pad.get("class")}
    clients = []
    try:
        clients = json.loads(subprocess.check_output(["hyprctl", "-j", "clients"], text=True))
        addresses = {client.get("address", "") for client in clients}
        if SCENE_FILE.exists():
            try:
                scene = json.loads(SCENE_FILE.read_text())
                if scene.get("main", {}).get("address", "") in addresses:
                    state["scene"] = "active"
            except Exception:
                pass
        classes = {client.get("class", "").lower() for client in clients}
        for name, class_name in class_map.items():
            if class_name.lower() in classes:
                state[name] = "ready"
    except Exception:
        pass
    try:
        monitors = json.loads(subprocess.check_output(["hyprctl", "-j", "monitors"], text=True))
        spatial_visible = any(
            "scratch_spatial" in (monitor.get("specialWorkspace", {}).get("name", "") or "")
            for monitor in monitors
        )
        if spatial_visible:
            for name, status in list(state.items()):
                if status == "ready":
                    state[name] = "visible"
    except Exception:
        pass
    return state


def load_css():
    provider = Gtk.CssProvider()
    if CSS_FILE.exists():
        provider.load_from_path(str(CSS_FILE))
    else:
        provider.load_from_data(
            b"""
            .scratch-backdrop { background: rgba(2, 6, 23, 0.72); }
            .scratch-shell {
              background: rgba(15, 23, 42, 0.92);
              border-radius: 28px;
              padding: 24px;
              border: 1px solid rgba(148, 163, 184, 0.20);
            }
            .scratch-card {
              border-radius: 24px;
              border: 1px solid rgba(255,255,255,0.08);
              background: rgba(255,255,255,0.04);
              padding: 18px;
            }
            .scratch-card:hover {
              background: rgba(255,255,255,0.09);
            }
            .scratch-title { font-size: 30px; font-weight: 700; color: #f8fafc; }
            .scratch-subtitle, .scratch-footer { color: #cbd5e1; }
            .scratch-card-title { font-size: 17px; font-weight: 700; color: #f8fafc; }
            .scratch-card-desc { color: #cbd5e1; }
            .scratch-state { color: #a5b4fc; letter-spacing: 0.08em; font-size: 12px; }
            .scratch-icon { font-size: 24px; }
            .card-terminal { background: linear-gradient(135deg, rgba(45, 212, 191, 0.18), rgba(15,23,42,0.6)); }
            .card-ai { background: linear-gradient(135deg, rgba(96, 165, 250, 0.18), rgba(15,23,42,0.6)); }
            .card-logs { background: linear-gradient(135deg, rgba(251, 191, 36, 0.18), rgba(15,23,42,0.6)); }
            .card-notes { background: linear-gradient(135deg, rgba(251, 113, 133, 0.18), rgba(15,23,42,0.6)); }
            .card-db { background: linear-gradient(135deg, rgba(167, 139, 250, 0.18), rgba(15,23,42,0.6)); }
            .card-music { background: linear-gradient(135deg, rgba(34, 197, 94, 0.18), rgba(15,23,42,0.6)); }
            .card-browser { background: linear-gradient(135deg, rgba(148, 163, 184, 0.18), rgba(15,23,42,0.6)); }
            """
        )
    display = Gdk.Display.get_default()
    if display is not None:
        Gtk.StyleContext.add_provider_for_display(
            display, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )


class ScratchDashboard(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app)
        self.set_title("Spatial Scratchpad")
        self.set_decorated(False)
        default_w, default_h = dashboard_window_size()
        self.set_default_size(default_w, default_h)
        self.set_size_request(820, 520)
        self.set_opacity(0.0)
        self.set_focusable(True)
        self.set_resizable(False)

        overlay = Gtk.Overlay()
        self.set_child(overlay)

        backdrop = Gtk.Box()
        backdrop.add_css_class("scratch-backdrop")
        overlay.set_child(backdrop)

        shell = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        shell.add_css_class("scratch-shell")
        shell.set_hexpand(True)
        shell.set_vexpand(True)
        shell.set_margin_top(18)
        shell.set_margin_bottom(18)
        shell.set_margin_start(18)
        shell.set_margin_end(18)
        overlay.add_overlay(shell)

        header = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        title = Gtk.Label(label="Spatial Scratchpad")
        title.add_css_class("scratch-title")
        title.set_xalign(0)
        subtitle = Gtk.Label(label="Compact launch surface for the current repo, runner, and side tools.")
        subtitle.add_css_class("scratch-subtitle")
        subtitle.set_xalign(0)
        header.append(title)
        header.append(subtitle)
        shell.append(header)

        state = read_state()
        pads_by_name = {pad["name"]: pad for pad in SCRATCHPADS}

        hero = Gtk.Grid(column_spacing=10, row_spacing=10)
        hero.add_css_class("scratch-grid")
        hero.set_column_homogeneous(True)
        hero.set_hexpand(True)
        hero.set_vexpand(True)
        shell.append(hero)

        self.cards = []

        scene = self.build_card_button(SCENE_CARD, state.get("scene", "idle"), hero=True)
        hero.attach(scene, 0, 0, 2, 1)

        for name, x, y, w, h in PRIMARY_LAYOUT[1:]:
            pad = pads_by_name.get(name)
            if not pad:
                continue
            hero.attach(self.build_card_button(pad, state.get(name, "idle"), hero=True), x, y, w, h)

        secondary = Gtk.Grid(column_spacing=10, row_spacing=10)
        secondary.add_css_class("scratch-grid")
        secondary.set_column_homogeneous(True)
        secondary.set_hexpand(True)
        secondary.set_vexpand(True)
        shell.append(secondary)

        for name, x, y, w, h in SECONDARY_LAYOUT:
            pad = pads_by_name.get(name)
            if not pad:
                continue
            secondary.attach(self.build_card_button(pad, state.get(name, "idle")), x, y, w, h)

        footer = Gtk.Label(label="Keys: S scene  A AI  L runner  T shell  B browser  D database  N notes  O Obsidian  M music  Esc close")
        footer.add_css_class("scratch-footer")
        footer.set_xalign(0)
        shell.append(footer)

        key = Gtk.EventControllerKey()
        key.connect("key-pressed", self.on_key_pressed)
        self.add_controller(key)

        GLib.timeout_add(16, self.fade_in)

    def build_card_button(self, pad, state, hero=False):
        card = Gtk.Button()
        card.add_css_class("scratch-card")
        card.add_css_class(pad["accent"])
        if hero:
            card.add_css_class("scratch-card-hero")
        card.set_hexpand(True)
        card.set_vexpand(True)
        card.set_child(self.make_card(pad, state, hero=hero))
        card.connect("clicked", self.on_activate, pad["cmd"])
        self.cards.append(card)
        return card

    def make_card(self, pad, state, hero=False):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.set_hexpand(True)
        box.set_vexpand(True)
        top = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        top.set_hexpand(True)
        icon = Gtk.Label(label=pad["icon"])
        icon.add_css_class("scratch-icon")
        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        text.set_hexpand(True)

        title = Gtk.Label(label=pad["title"])
        title.add_css_class("scratch-card-title")
        if hero:
            title.add_css_class("scratch-card-title-hero")
        title.set_xalign(0)
        title.set_wrap(True)
        desc = Gtk.Label(label=pad["desc"])
        desc.add_css_class("scratch-card-desc")
        if hero:
            desc.add_css_class("scratch-card-desc-hero")
        desc.set_xalign(0)
        desc.set_wrap(True)

        text.append(title)
        text.append(desc)
        top.append(icon)
        top.append(text)

        status = Gtk.Label(label=state.upper())
        status.add_css_class("scratch-state")
        status.set_xalign(0)

        box.append(top)
        box.append(status)
        return box

    def on_activate(self, _button, cmd):
        self.close()
        run(cmd)

    def on_key_pressed(self, _controller, keyval, _keycode, _state):
        if keyval == Gdk.KEY_Escape:
            self.close()
            return True
        hotkeys = {
            Gdk.KEY_s: "scene",
            Gdk.KEY_S: "scene",
            Gdk.KEY_t: "terminal",
            Gdk.KEY_T: "terminal",
            Gdk.KEY_o: "obsidian",
            Gdk.KEY_O: "obsidian",
            Gdk.KEY_n: "notes",
            Gdk.KEY_N: "notes",
            Gdk.KEY_l: "logs",
            Gdk.KEY_L: "logs",
            Gdk.KEY_a: "ai",
            Gdk.KEY_A: "ai",
            Gdk.KEY_d: "db",
            Gdk.KEY_D: "db",
            Gdk.KEY_m: "music",
            Gdk.KEY_M: "music",
            Gdk.KEY_b: "browser-devtools",
            Gdk.KEY_B: "browser-devtools",
        }
        if keyval in hotkeys:
            if hotkeys[keyval] == "scene":
                self.on_activate(None, SCENE_CARD["cmd"])
                return True
            for pad in SCRATCHPADS:
                if pad["name"] == hotkeys[keyval]:
                    self.on_activate(None, pad["cmd"])
                    return True
        if keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
            focused = self.get_focus()
            if isinstance(focused, Gtk.Button):
                focused.emit("clicked")
                return True
        return False

    def fade_in(self):
        opacity = self.get_opacity()
        opacity = min(1.0, opacity + 0.10)
        self.set_opacity(opacity)
        return opacity < 1.0


class ScratchApp(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="local.noxflow.scratchpad.dashboard")

    def do_activate(self):
        load_css()
        win = ScratchDashboard(self)
        win.present()


def main():
    PID_FILE.write_text(str(os.getpid()))
    if Gdk.Display.get_default() is None:
        print("scratchpad dashboard: no GTK display available")
        return 1
    try:
        app = ScratchApp()
        app.run(None)
    finally:
        try:
            PID_FILE.unlink()
        except Exception:
            pass


if __name__ == "__main__":
    sys.exit(main() or 0)
