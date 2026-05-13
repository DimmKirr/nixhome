# Palette registry. Add new palettes here.
#
# Every palette MUST expose the 26-slot shape defined by catppuccin-mocha.nix
# (the canonical reference). Palettes with fewer distinct colors alias slots.
{
  catppuccin-mocha = import ./catppuccin-mocha.nix;
  dracula          = import ./dracula.nix;
  # Future: nord, tokyo-night, catppuccin-{latte,frappe,macchiato}
}
