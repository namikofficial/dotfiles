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
    "desc": "Main window, AI, and logs aligned together.",
    "icon": ICON_MAP["scene"],
    "accent": "card-scene",
    "cmd": ["bash", MANAGER, "toggle", "scene"],
}


def run(cmd):
    subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


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
        self.set_default_size(1280, 760)
        self.set_size_request(860, 560)
        self.set_opacity(0.0)
        self.set_focusable(True)

        overlay = Gtk.Overlay()
        self.set_child(overlay)

        backdrop = Gtk.Box()
        backdrop.add_css_class("scratch-backdrop")
        overlay.set_child(backdrop)

        shell = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=20)
        shell.add_css_class("scratch-shell")
        shell.set_hexpand(True)
        shell.set_vexpand(True)
        shell.set_margin_top(24)
        shell.set_margin_bottom(24)
        shell.set_margin_start(24)
        shell.set_margin_end(24)
        overlay.add_overlay(shell)

        header = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        title = Gtk.Label(label="Spatial Scratchpad")
        title.add_css_class("scratch-title")
        title.set_xalign(0)
        subtitle = Gtk.Label(label="Coding surface, side tools, and live output in one transient layer.")
        subtitle.add_css_class("scratch-subtitle")
        subtitle.set_xalign(0)
        header.append(title)
        header.append(subtitle)
        shell.append(header)

        grid = Gtk.Grid(column_spacing=14, row_spacing=14)
        grid.set_column_homogeneous(True)
        grid.set_row_homogeneous(True)
        grid.set_hexpand(True)
        grid.set_vexpand(True)
        shell.append(grid)

        state = read_state()
        self.cards = []

        scene = Gtk.Button()
        scene.add_css_class("scratch-card")
        scene.add_css_class("scratch-scene")
        scene.add_css_class(SCENE_CARD["accent"])
        scene.set_hexpand(True)
        scene.set_vexpand(True)
        scene.set_child(self.make_card(SCENE_CARD, state.get("scene", "idle")))
        scene.connect("clicked", self.on_activate, SCENE_CARD["cmd"])
        grid.attach(scene, 0, 0, 2, 2)
        self.cards.append(scene)

        for pad in SCRATCHPADS:
            card = Gtk.Button()
            card.add_css_class("scratch-card")
            card.add_css_class(pad["accent"])
            card.set_hexpand(True)
            card.set_vexpand(True)
            card.set_child(self.make_card(pad, state.get(pad["name"], "idle")))
            card.connect("clicked", self.on_activate, pad["cmd"])
            x, y, w, h = pad["rect"]
            grid.attach(card, x, y, w, h)
            self.cards.append(card)
            pad["button"] = card

        key = Gtk.EventControllerKey()
        key.connect("key-pressed", self.on_key_pressed)
        self.add_controller(key)

        GLib.timeout_add(16, self.fade_in)

    def make_card(self, pad, state):
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
        title.set_xalign(0)
        title.set_wrap(True)
        desc = Gtk.Label(label=pad["desc"])
        desc.add_css_class("scratch-card-desc")
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
