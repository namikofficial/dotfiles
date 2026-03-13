#!/usr/bin/env python3
import math
import os
import random
import time

import cairo
import gi

gi.require_version("Gdk", "4.0")
gi.require_version("Gtk", "4.0")
gi.require_version("Gtk4LayerShell", "1.0")
from gi.repository import Gdk, GLib, Gtk, Gtk4LayerShell


BG_TOP = (0.04, 0.06, 0.10)
BG_MID = (0.07, 0.11, 0.18)
BG_BOTTOM = (0.02, 0.04, 0.07)
TEXT = (0.95, 0.97, 1.0)
MUTED = (0.78, 0.83, 0.92)
ACCENT = (0.44, 0.58, 0.79)
ACCENT_2 = (0.40, 0.76, 0.72)
WARN = (1.0, 0.59, 0.42)
PINK = (1.0, 0.46, 0.50)

FPS = int(os.environ.get("NOXFLOW_SCREENSAVER_FPS", "30") or "30")
FPS = max(1, min(240, FPS))
FRAME_MS = max(1, int(round(1000 / FPS)))


class ScreenSaverWindow(Gtk.ApplicationWindow):
    def __init__(self, app: Gtk.Application) -> None:
        super().__init__(application=app, title="noxflow-screensaver")
        self.start_time = time.monotonic()
        self.stars = self._build_stars()
        self.set_decorated(False)
        self.set_resizable(False)
        self.set_default_size(1920, 1080)
        self._setup_layer_shell()

        overlay = Gtk.Overlay()
        overlay.set_hexpand(True)
        overlay.set_vexpand(True)
        self.set_child(overlay)

        drawing = Gtk.DrawingArea()
        drawing.set_hexpand(True)
        drawing.set_vexpand(True)
        drawing.set_content_width(1920)
        drawing.set_content_height(1080)
        drawing.set_draw_func(self.on_draw)
        overlay.set_child(drawing)
        self.drawing = drawing

        hero = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        hero.set_halign(Gtk.Align.CENTER)
        hero.set_valign(Gtk.Align.CENTER)
        hero.add_css_class("hero-card")

        title = Gtk.Label(label="NOXFLOW")
        title.add_css_class("hero-title")
        hero.append(title)

        subtitle = Gtk.Label(label="ambient mode")
        subtitle.add_css_class("hero-subtitle")
        hero.append(subtitle)

        hint = Gtk.Label(label="press any key, click, or q to return")
        hint.add_css_class("hero-hint")
        hero.append(hint)

        overlay.add_overlay(hero)

        css = Gtk.CssProvider()
        css.load_from_data(
            b"""
            window { background: transparent; }
            .hero-card {
              padding: 28px 42px 24px 42px;
              border-radius: 28px;
              background: rgba(10, 15, 24, 0.24);
              border: 1px solid rgba(255, 255, 255, 0.08);
              box-shadow: 0 20px 60px rgba(0, 0, 0, 0.22);
            }
            .hero-title {
              font-family: "JetBrainsMono Nerd Font Mono", monospace;
              font-size: 54px;
              font-weight: 800;
              letter-spacing: 0.42em;
              color: rgba(243, 247, 255, 0.97);
            }
            .hero-subtitle {
              font-family: "IBM Plex Sans", sans-serif;
              font-size: 15px;
              letter-spacing: 0.22em;
              text-transform: uppercase;
              color: rgba(102, 194, 184, 0.84);
            }
            .hero-hint {
              margin-top: 8px;
              font-family: "IBM Plex Sans", sans-serif;
              font-size: 12px;
              letter-spacing: 0.08em;
              color: rgba(199, 211, 235, 0.62);
            }
            """
        )
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(),
            css,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )

        key = Gtk.EventControllerKey()
        key.connect("key-pressed", self.on_key_pressed)
        self.add_controller(key)

        click = Gtk.GestureClick()
        click.connect("pressed", self.on_click)
        self.add_controller(click)

        self.connect("close-request", self.on_close_request)

        GLib.timeout_add(FRAME_MS, self.tick)

    def _setup_layer_shell(self) -> None:
        if os.environ.get("NOXFLOW_USE_LAYER_SHELL", "1").lower() in ("0", "false", "no"):
            return
        if not Gtk4LayerShell.is_supported():
            return
        try:
            Gtk4LayerShell.init_for_window(self)
            if not Gtk4LayerShell.is_layer_window(self):
                return
            Gtk4LayerShell.set_layer(self, Gtk4LayerShell.Layer.OVERLAY)
            Gtk4LayerShell.set_keyboard_mode(self, Gtk4LayerShell.KeyboardMode.ON_DEMAND)
            Gtk4LayerShell.auto_exclusive_zone_enable(self)
            for edge in (
                Gtk4LayerShell.Edge.TOP,
                Gtk4LayerShell.Edge.RIGHT,
                Gtk4LayerShell.Edge.BOTTOM,
                Gtk4LayerShell.Edge.LEFT,
            ):
                Gtk4LayerShell.set_anchor(self, edge, True)
        except Exception:
            # Fallback: fullscreen GTK window without layer-shell integration.
            return

    def _build_stars(self):
        rng = random.Random(11)
        stars = []
        for _ in range(140):
            stars.append(
                (
                    rng.random(),
                    rng.random(),
                    rng.uniform(0.6, 2.2),
                    rng.uniform(0.15, 0.85),
                    rng.uniform(0.2, 1.2),
                )
            )
        return stars

    def on_close_request(self, *_args) -> bool:
        app = self.get_application()
        if app is not None:
            app.quit()
        return False

    def on_click(self, *_args) -> None:
        self.close()

    def on_key_pressed(self, _controller, keyval, _keycode, _state) -> bool:
        if keyval in (Gdk.KEY_Escape, Gdk.KEY_q, Gdk.KEY_Q):
            self.close()
            return True
        self.close()
        return True

    def tick(self) -> bool:
        self.drawing.queue_draw()
        return True

    def _fill_background(self, ctx: cairo.Context, width: int, height: int) -> None:
        grad = cairo.LinearGradient(0, 0, 0, height)
        grad.add_color_stop_rgba(0.0, *BG_TOP, 1.0)
        grad.add_color_stop_rgba(0.55, *BG_MID, 1.0)
        grad.add_color_stop_rgba(1.0, *BG_BOTTOM, 1.0)
        ctx.rectangle(0, 0, width, height)
        ctx.set_source(grad)
        ctx.fill()

    def _draw_stars(self, ctx: cairo.Context, width: int, height: int, t: float) -> None:
        for sx, sy, radius, alpha, speed in self.stars:
            px = sx * width
            py = (sy * height + (t * 12 * speed)) % height
            shimmer = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(t * speed + sx * 10))
            ctx.set_source_rgba(TEXT[0], TEXT[1], TEXT[2], alpha * 0.45 * shimmer)
            ctx.arc(px, py, radius, 0, math.tau)
            ctx.fill()

    def _draw_aurora(self, ctx: cairo.Context, width: int, height: int, t: float) -> None:
        for idx, color in enumerate((ACCENT, ACCENT_2, WARN, PINK)):
            base_y = height * (0.18 + idx * 0.11)
            amp = height * (0.05 + idx * 0.008)
            phase = t * (0.18 + idx * 0.03) + idx * 1.2
            ctx.new_path()
            ctx.move_to(-120, base_y)
            step = 90
            for x in range(-120, width + 160, step):
                y = base_y + math.sin(x * 0.004 + phase) * amp
                ctx.curve_to(x + step * 0.35, y - amp * 0.3, x + step * 0.65, y + amp * 0.3, x + step, y)
            ctx.line_to(width + 160, 0)
            ctx.line_to(-120, 0)
            ctx.close_path()
            grad = cairo.LinearGradient(0, 0, 0, height * 0.55)
            grad.add_color_stop_rgba(0.0, color[0], color[1], color[2], 0.18)
            grad.add_color_stop_rgba(0.65, color[0], color[1], color[2], 0.03)
            grad.add_color_stop_rgba(1.0, color[0], color[1], color[2], 0.0)
            ctx.set_source(grad)
            ctx.fill()

    def _draw_grid(self, ctx: cairo.Context, width: int, height: int, t: float) -> None:
        horizon = height * 0.60
        base_y = height * 1.02
        ctx.set_line_width(1)
        for i in range(-12, 13):
            x = width * 0.5 + i * width * 0.05
            ctx.set_source_rgba(ACCENT_2[0], ACCENT_2[1], ACCENT_2[2], 0.10 if i == 0 else 0.06)
            ctx.move_to(x, base_y)
            ctx.line_to(width * 0.5 + i * width * 0.012, horizon)
            ctx.stroke()
        for row in range(18):
            p = (row / 17.0 + (t * 0.07)) % 1.0
            y = horizon + ((p * p) * (base_y - horizon))
            alpha = 0.18 * (1.0 - p)
            ctx.set_source_rgba(ACCENT[0], ACCENT[1], ACCENT[2], alpha)
            ctx.move_to(width * (0.08 + p * 0.20), y)
            ctx.line_to(width * (0.92 - p * 0.20), y)
            ctx.stroke()

    def _draw_core(self, ctx: cairo.Context, width: int, height: int, t: float) -> None:
        cx = width * 0.5
        cy = height * 0.52

        glow = cairo.RadialGradient(cx, cy, 30, cx, cy, min(width, height) * 0.26)
        glow.add_color_stop_rgba(0.0, ACCENT_2[0], ACCENT_2[1], ACCENT_2[2], 0.22)
        glow.add_color_stop_rgba(0.45, ACCENT[0], ACCENT[1], ACCENT[2], 0.12)
        glow.add_color_stop_rgba(1.0, ACCENT[0], ACCENT[1], ACCENT[2], 0.0)
        ctx.set_source(glow)
        ctx.arc(cx, cy, min(width, height) * 0.28, 0, math.tau)
        ctx.fill()

        ctx.save()
        ctx.translate(cx, cy)
        ctx.rotate(t * 0.12)
        for scale, alpha, color in (
            (1.0, 0.25, ACCENT),
            (0.78, 0.30, ACCENT_2),
            (0.56, 0.18, WARN),
        ):
            size = min(width, height) * 0.16 * scale
            ctx.set_line_width(2)
            ctx.set_source_rgba(color[0], color[1], color[2], alpha)
            ctx.move_to(0, -size)
            ctx.line_to(size * 0.78, 0)
            ctx.line_to(0, size)
            ctx.line_to(-size * 0.78, 0)
            ctx.close_path()
            ctx.stroke()
            ctx.rotate(0.42)
        ctx.restore()

        bar_w = min(width * 0.42, 620)
        bar_h = 16
        x = cx - bar_w / 2
        y = height * 0.73

        ctx.set_source_rgba(1, 1, 1, 0.04)
        radius = 8
        ctx.new_path()
        ctx.arc(x + bar_w - radius, y + radius, radius, -math.pi / 2, 0)
        ctx.arc(x + bar_w - radius, y + bar_h - radius, radius, 0, math.pi / 2)
        ctx.arc(x + radius, y + bar_h - radius, radius, math.pi / 2, math.pi)
        ctx.arc(x + radius, y + radius, radius, math.pi, 3 * math.pi / 2)
        ctx.close_path()
        ctx.fill()

        fill = 0.18 + 0.82 * (0.5 + 0.5 * math.sin(t * 0.9))
        grad = cairo.LinearGradient(x, y, x + bar_w, y)
        grad.add_color_stop_rgba(0.0, ACCENT_2[0], ACCENT_2[1], ACCENT_2[2], 0.92)
        grad.add_color_stop_rgba(0.55, ACCENT[0], ACCENT[1], ACCENT[2], 0.95)
        grad.add_color_stop_rgba(1.0, WARN[0], WARN[1], WARN[2], 0.92)
        ctx.new_path()
        fill_w = bar_w * fill
        r = 8
        ctx.arc(x + fill_w - r, y + r, r, -math.pi / 2, 0)
        ctx.arc(x + fill_w - r, y + bar_h - r, r, 0, math.pi / 2)
        ctx.arc(x + r, y + bar_h - r, r, math.pi / 2, math.pi)
        ctx.arc(x + r, y + r, r, math.pi, 3 * math.pi / 2)
        ctx.close_path()
        ctx.set_source(grad)
        ctx.fill()

    def _draw_vignette(self, ctx: cairo.Context, width: int, height: int) -> None:
        cx = width * 0.5
        cy = height * 0.5
        vignette = cairo.RadialGradient(cx, cy, min(width, height) * 0.16, cx, cy, min(width, height) * 0.72)
        vignette.add_color_stop_rgba(0.0, 0, 0, 0, 0.0)
        vignette.add_color_stop_rgba(1.0, 0, 0, 0, 0.52)
        ctx.set_source(vignette)
        ctx.rectangle(0, 0, width, height)
        ctx.fill()

    def on_draw(self, _area: Gtk.DrawingArea, ctx: cairo.Context, width: int, height: int) -> None:
        t = time.monotonic() - self.start_time
        self._fill_background(ctx, width, height)
        self._draw_aurora(ctx, width, height, t)
        self._draw_stars(ctx, width, height, t)
        self._draw_grid(ctx, width, height, t)
        self._draw_core(ctx, width, height, t)
        self._draw_vignette(ctx, width, height)


class ScreenSaverApp(Gtk.Application):
    def __init__(self) -> None:
        super().__init__(application_id="dev.noxflow.ScreenSaver")
        self.window = None

    def do_activate(self) -> None:
        if self.window is None:
            self.window = ScreenSaverWindow(self)
        self.window.present()
        self.window.fullscreen()


if __name__ == "__main__":
    app = ScreenSaverApp()
    raise SystemExit(app.run(None))
