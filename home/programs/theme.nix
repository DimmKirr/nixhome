# Theme — the single user-facing dial consumed by tmux, starship, ghostty.
#
# Four orthogonal aesthetic dimensions:
#   preset     — bundles a sensible combo of all dials below
#   palette    — color set (catppuccin-mocha, dracula, ...)
#   style      — module shape (twoTone, flat, minimal, powerline)
#   separators — glyph set (round, sharp, soft, none)
#   icons      — icon vocabulary (nerdFont, ascii, emoji, none)
#
# Plus one portability switch:
#   nerdFonts  — when false, force PUA-free output (ascii icons + non-PUA
#                separators). Use for SSH-in from Termius / JuiceSSH / PuTTY
#                / any client without a Nerd Font installed. Overrides icons
#                and separators if they would emit PUA glyphs.
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
  # Portability switch — default false so the config is SSH-safe by default.
  # Flip to true on machines where a Nerd Font is installed for the local UI.
  nerdFonts  ? false,
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

  # Layered resolution (lowest precedence first):
  #   1. preset defaults
  #   2. nerdFonts=false compat overrides   (only when active)
  #   3. explicit per-dial user overrides   (only when non-null)
  #
  # `//` is right-biased so later layers win. The compat layer sits between
  # the preset and explicit overrides so a user who *intentionally* sets
  # `separators = "round"` keeps PUA even with `nerdFonts = false`.
  compatOverrides = lib.optionalAttrs (!nerdFonts) {
    icons      = "ascii";   # drop nerdFont PUA glyphs
    separators = "none";    # drop powerline PUA glyphs (U+E0B0…)
  };

  explicitOverrides = lib.filterAttrs (_: v: v != null) {
    inherit palette style separators icons;
  };

  resolved = presetDefaults // compatOverrides // explicitOverrides;
in
{
  inherit preset nerdFonts;
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
