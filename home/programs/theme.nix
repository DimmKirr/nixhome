# Theme — the single user-facing dial consumed by tmux, starship, ghostty.
#
# Four orthogonal aesthetic dimensions:
#   preset     — bundles a sensible combo of all dials below
#   palette    — color set (catppuccin-mocha, dracula, ...)
#   style      — module shape (twoTone, flat, minimal, powerline)
#   separators — glyph set (round, sharp, soft, none)
#   icons      — icon vocabulary (nerdFont, ascii, emoji, none)
#
# Set `preset` to pick all four. Override any individual dial by setting its
# attribute to a non-null value.
{
  lib ? (import <nixpkgs> {}).lib,
  # User overrides — all optional. null = use preset's default.
  preset     ? "catppuccin",
  palette    ? null,
  style      ? null,
  separators ? null,
  icons      ? null,
}:
let
  palettes = import ./tmux/palettes;

  presets = {
    catppuccin = {
      palette    = palettes.catppuccin-mocha;
      style      = "twoTone";
      separators = "round";
      icons      = "nerdFont";
    };
    dracula = {
      palette    = palettes.dracula;
      style      = "twoTone";   # we visually match current Dracula via twoTone
      separators = "round";
      icons      = "nerdFont";
    };
    # Future: nord, tokyo-night
  };

  presetDefaults =
    assert lib.assertMsg (presets ? ${preset})
      "theme.nix: unknown preset '${preset}'. Known: ${toString (lib.attrNames presets)}";
    presets.${preset};

  # Resolve each dial: explicit override wins, else preset's default.
  resolved = {
    palette    = if palette    != null then palette    else presetDefaults.palette;
    style      = if style      != null then style      else presetDefaults.style;
    separators = if separators != null then separators else presetDefaults.separators;
    icons      = if icons      != null then icons      else presetDefaults.icons;
  };
in
{
  inherit preset;
  inherit (resolved) palette style separators icons;

  # Convenience: validate enum-ish dials at eval time
  _validation =
    assert lib.assertMsg
      (builtins.elem resolved.style [ "twoTone" "flat" "minimal" "powerline" ])
      "theme.style must be one of: twoTone | flat | minimal | powerline (got '${resolved.style}')";
    assert lib.assertMsg
      (builtins.elem resolved.icons [ "nerdFont" "ascii" "emoji" "none" ])
      "theme.icons must be one of: nerdFont | ascii | emoji | none (got '${resolved.icons}')";
    "ok";
}
