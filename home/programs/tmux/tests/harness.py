#!/usr/bin/env python3
"""
TDD harness for the tmux theming framework — Python mirror of the Nix composer.

This script implements the SAME composition logic as status-module.nix, so we
can verify the framework end-to-end without requiring a working Nix evaluation
environment. It also converts tmux's #[fg=…,bg=…] escapes into ANSI 24-bit
color codes for visual verification in any terminal.

Run:
  python3 harness.py            # run all tests, compare against fixtures
  python3 harness.py --render   # also print colored output to stdout
  python3 harness.py --update   # regenerate fixtures from current code

Source of truth is still the .nix files; this is a parallel implementation
that mirrors them faithfully. When you change a widget or composer, update
both — the harness catches palette/composer drift before nix builds it.
"""

from __future__ import annotations
import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

ROOT = Path(__file__).resolve().parent.parent  # …/tmux
FIXTURES = Path(__file__).resolve().parent / "fixtures"


# ─── Palettes ──────────────────────────────────────────────────────────────
# Mirror of home/programs/tmux/palettes/*.nix. Keep in sync.

CATPPUCCIN_MOCHA = {
    "name": "catppuccin-mocha",
    "bg":        "#1e1e2e", "fg":        "#cdd6f4",
    "crust":     "#11111b", "mantle":    "#181825",
    "surface_0": "#313244", "surface_1": "#45475a", "surface_2": "#585b70",
    "overlay_0": "#6c7086", "overlay_1": "#7f849c", "overlay_2": "#9399b2",
    "subtext_0": "#a6adc8", "subtext_1": "#bac2de",
    "rosewater": "#f5e0dc", "flamingo":  "#f2cdcd", "pink":     "#f5c2e7",
    "mauve":     "#cba6f7", "red":       "#f38ba8", "maroon":   "#eba0ac",
    "peach":     "#fab387", "yellow":    "#f9e2af", "green":    "#a6e3a1",
    "teal":      "#94e2d5", "sky":       "#89dceb", "sapphire": "#74c7ec",
    "blue":      "#89b4fa", "lavender":  "#b4befe",
    "iconFgDefault": "#11111b",
}

DRACULA = {
    "name": "dracula",
    "bg":        "#282A36", "fg":        "#F8F8F2",
    "crust":     "#191A21", "mantle":    "#1E1F29",
    "surface_0": "#21222C", "surface_1": "#282A36", "surface_2": "#373844",
    "overlay_0": "#44475A", "overlay_1": "#54576C", "overlay_2": "#6272A4",
    "subtext_0": "#BFBFBF", "subtext_1": "#E2E2E2",
    "rosewater": "#FFB86C", "flamingo":  "#FF79C6", "pink":     "#FF79C6",
    "mauve":     "#BD93F9", "red":       "#FF5555", "maroon":   "#FF5555",
    "peach":     "#FFB86C", "yellow":    "#F1FA8C", "green":    "#50FA7B",
    "teal":      "#50FA7B", "sky":       "#8BE9FD", "sapphire": "#8BE9FD",
    "blue":      "#8BE9FD", "lavender":  "#6272A4",
    "iconFgDefault": "#191A21",
}

PALETTES = {
    "catppuccin": CATPPUCCIN_MOCHA,
    "dracula":    DRACULA,
}


# ─── Separators ────────────────────────────────────────────────────────────
SEPARATORS = {
    "round": {"left": "", "right": "", "middle": ""},
    "sharp": {"left": "", "right": "", "middle": ""},
    "soft":  {"left": "░",  "right": "░",  "middle": "▒"},
    "none":  {"left": "",   "right": "",   "middle": " "},
}


# ─── Composer ──────────────────────────────────────────────────────────────
def compose(spec: dict, separators: dict) -> str:
    """Mirror of home/programs/tmux/status-module.nix."""
    s = separators
    style = spec["style"]

    def fg(c):     return f"#[fg={c}]"
    def fgbg(c, b): return f"#[fg={c},bg={b}]"
    reset = "#[default]"

    if style in ("twoTone", "powerline"):
        return (
            f"{fg(spec['iconBg'])}{s['left']}"
            f"{fgbg(spec['iconFg'], spec['iconBg'])}{spec['icon']}"
            f"{fgbg(spec['textFg'], spec['textBg'])}{s['middle']}{spec['text']}"
            f"{fg(spec['textBg'])}{s['right']}{reset}"
        )
    elif style == "flat":
        return (
            f"{fg(spec['iconBg'])}{s['left']}"
            f"{fgbg(spec['iconFg'], spec['iconBg'])} {spec['icon']} {spec['text']} "
            f"{fg(spec['iconBg'])}{s['right']}{reset}"
        )
    elif style == "minimal":
        return f"{fg(spec['iconFg'])}{spec['icon']}{fg(spec['textFg'])}{spec['text']}{reset}"
    raise ValueError(f"unknown style: {style}")


# ─── Widgets ──────────────────────────────────────────────────────────────
def widget_host(palette, icons, style):
    """Mirror of home/programs/tmux/widgets/host.nix."""
    icon_variants = {
        "nerdFont": "󰒋 ",
        "ascii":    "[H] ",
        "emoji":    "💻 ",
        "none":     "",
    }
    return {
        "icon":   icon_variants[icons],
        "iconFg": palette["iconFgDefault"],
        "iconBg": palette["mauve"],
        "text":   " #H ",
        "textFg": palette["fg"],
        "textBg": palette["surface_0"],
        "style":  style,
    }

def widget_session(palette, icons, style):
    """Mirror of widgets/session.nix."""
    icon_variants = {"nerdFont": " ", "ascii": "[S] ", "emoji": "🪟 ", "none": ""}
    return {
        "icon":   icon_variants[icons],
        "iconFg": palette["iconFgDefault"],
        "iconBg": "#{?client_prefix," + palette["red"] + "," + palette["green"] + "}",
        "text":   " #S ",
        "textFg": palette["fg"],
        "textBg": palette["surface_0"],
        "style":  style,
    }

def widget_directory(palette, icons, style):
    """Mirror of widgets/directory.nix."""
    icon_variants = {"nerdFont": "󰉋 ", "ascii": "[D] ", "emoji": "📁 ", "none": ""}
    return {
        "icon":   icon_variants[icons],
        "iconFg": palette["iconFgDefault"],
        "iconBg": palette["peach"],
        "text":   " #{b:pane_current_path} ",
        "textFg": palette["fg"],
        "textBg": palette["surface_0"],
        "style":  style,
    }

def widget_date_time(palette, icons, style, format="%R %Z"):
    """Mirror of widgets/date-time.nix."""
    icon_variants = {"nerdFont": "󰥔 ", "ascii": "[T] ", "emoji": "🕐 ", "none": ""}
    return {
        "icon":   icon_variants[icons],
        "iconFg": palette["iconFgDefault"],
        "iconBg": palette["lavender"],
        "text":   f" {format} ",
        "textFg": palette["fg"],
        "textBg": palette["surface_0"],
        "style":  style,
    }

def _shell_widget(name, icon_variants, accent_slot, *, args=""):
    """Factory for shell-backed widgets — text becomes #(<script:NAME>).

    The Nix evaluation substitutes <script:NAME> with the actual /nix/store
    path of the writeShellApplication output. Tests assert composition
    structure with the placeholder; per-script behavior is tested separately
    via the .sh files run with bash directly.
    """
    def factory(palette, icons, style):
        return {
            "icon":   icon_variants[icons],
            "iconFg": palette["iconFgDefault"],
            "iconBg": palette[accent_slot],
            "text":   f" #(<script:{name}>{args}) ",
            "textFg": palette["fg"],
            "textBg": palette["surface_0"],
            "style":  style,
        }
    return factory

def widget_user(palette, icons, style):
    return {
        "icon":   {"nerdFont": " ", "ascii": "[U] ", "emoji": "👤 ", "none": ""}[icons],
        "iconFg": palette["iconFgDefault"],
        "iconBg": palette["sky"],
        "text":   " #(whoami) ",
        "textFg": palette["fg"],
        "textBg": palette["surface_0"],
        "style":  style,
    }

def widget_application(palette, icons, style):
    return {
        "icon":   {"nerdFont": "󰘔 ", "ascii": "[A] ", "emoji": "📦 ", "none": ""}[icons],
        "iconFg": palette["iconFgDefault"],
        "iconBg": palette["teal"],
        "text":   " #{pane_current_command} ",
        "textFg": palette["fg"],
        "textBg": palette["surface_0"],
        "style":  style,
    }

def widget_snapshot_tick(palette, icons, style):
    return {
        "icon": "", "iconFg": "default", "iconBg": "default",
        "text": "#(<script:snapshot-tick>)",
        "textFg": "default", "textBg": "default", "style": "minimal",
    }

WIDGETS: dict[str, Callable] = {
    # Static
    "host":        widget_host,
    "session":     widget_session,
    "directory":   widget_directory,
    "date-time":   widget_date_time,
    "user":        widget_user,
    "application": widget_application,

    # Shell-backed (mirror of accent_slot/icon choices in widgets/*.nix)
    "attached-clients": _shell_widget("attached-clients",
        {"nerdFont": "󰣀 ", "ascii": "[C] ", "emoji": "👥 ", "none": ""}, "sapphire"),
    "uptime": _shell_widget("uptime",
        {"nerdFont": "󰔟 ", "ascii": "[U] ", "emoji": "⏱ ", "none": ""}, "lavender"),
    "battery": _shell_widget("battery",
        {"nerdFont": "󰁹 ", "ascii": "[B] ", "emoji": "🔋 ", "none": ""}, "green"),
    "cpu": _shell_widget("cpu",
        {"nerdFont": "󱦘 ", "ascii": "[%] ", "emoji": "⚙️ ", "none": ""}, "red"),
    "ram": _shell_widget("ram",
        {"nerdFont": "󰍛 ", "ascii": "[M] ", "emoji": "💾 ", "none": ""}, "maroon"),
    "weather": _shell_widget("weather",
        {"nerdFont": "󰖕 ", "ascii": "[W] ", "emoji": "🌤 ", "none": ""}, "sky"),
    "kubernetes": _shell_widget("kubernetes",
        {"nerdFont": "󱃾 ", "ascii": "[K] ", "emoji": "☸ ", "none": ""}, "blue"),
    "git": _shell_widget("git",
        {"nerdFont": " ", "ascii": "[G] ", "emoji": "🌿 ", "none": ""}, "pink",
        args=" #{pane_current_path}"),
    "network": _shell_widget("network",
        {"nerdFont": "󰖩 ", "ascii": "[N] ", "emoji": "📶 ", "none": ""}, "flamingo"),

    # Special
    "snapshot-tick": widget_snapshot_tick,
}


# ─── Presets ───────────────────────────────────────────────────────────────
PRESETS = {
    "catppuccin": {"palette": "catppuccin", "style": "twoTone", "separators": "round", "icons": "nerdFont"},
    "dracula":    {"palette": "dracula",    "style": "twoTone", "separators": "round", "icons": "nerdFont"},
}


def render(preset_name: str, widget_name: str) -> str:
    preset = PRESETS[preset_name]
    palette = PALETTES[preset["palette"]]
    seps = SEPARATORS[preset["separators"]]
    spec = WIDGETS[widget_name](palette, preset["icons"], preset["style"])
    return compose(spec, seps)


# ─── ANSI render (for visual verification) ─────────────────────────────────
HEX_RE = re.compile(r"#[0-9A-Fa-f]{6}")

def hex_to_rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)

def tmux_to_ansi(s: str) -> str:
    """Convert tmux #[fg=…,bg=…] escapes into ANSI 24-bit color codes."""
    out = []
    i = 0
    while i < len(s):
        if s[i:i+2] == "#[":
            end = s.index("]", i)
            spec = s[i+2:end]
            if spec == "default":
                out.append("\033[0m")
            else:
                parts = spec.split(",")
                codes = []
                for p in parts:
                    if p.startswith("fg="):
                        c = p[3:]
                        if HEX_RE.fullmatch(c):
                            r, g, b = hex_to_rgb(c)
                            codes.append(f"38;2;{r};{g};{b}")
                    elif p.startswith("bg="):
                        c = p[3:]
                        if c == "default":
                            codes.append("49")
                        elif HEX_RE.fullmatch(c):
                            r, g, b = hex_to_rgb(c)
                            codes.append(f"48;2;{r};{g};{b}")
                if codes:
                    out.append(f"\033[{';'.join(codes)}m")
            i = end + 1
        else:
            out.append(s[i])
            i += 1
    out.append("\033[0m")  # safety reset
    return "".join(out)


# ─── Test runner ───────────────────────────────────────────────────────────
@dataclass
class TestCase:
    preset: str
    widget: str

    @property
    def fixture_path(self) -> Path:
        return FIXTURES / self.preset / f"{self.widget}.txt"

    @property
    def name(self) -> str:
        return f"{self.widget}@{self.preset}"


def all_tests():
    for preset in ("catppuccin", "dracula"):
        for widget in WIDGETS:
            yield TestCase(preset, widget)


def run_tests(update: bool, do_render: bool) -> int:
    fail = 0
    for tc in all_tests():
        actual = render(tc.preset, tc.widget)
        fp = tc.fixture_path
        fp.parent.mkdir(parents=True, exist_ok=True)

        if update:
            fp.write_text(actual)
            print(f"UPDATE {tc.name} → {fp.relative_to(ROOT)}")
        else:
            if not fp.exists():
                print(f"MISS   {tc.name} (no fixture at {fp.relative_to(ROOT)})")
                fail += 1
                continue
            expected = fp.read_text()
            if actual == expected:
                print(f"PASS   {tc.name}")
            else:
                print(f"FAIL   {tc.name}")
                print(f"       expected: {expected!r}")
                print(f"       actual:   {actual!r}")
                fail += 1

        if do_render:
            print(f"       render:   {tmux_to_ansi(actual)}")

    return fail


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--update", action="store_true", help="regenerate fixtures from current code")
    ap.add_argument("--render", action="store_true", help="show colored output for visual verification")
    args = ap.parse_args()
    sys.exit(0 if run_tests(args.update, args.render) == 0 else 1)
