# Universal tmux theming framework.
#
# Usage from home-manager (data-style import):
#
#   theme     = import ../theme.nix { inherit lib; preset = "dracula"; };
#   framework = import ./tmux       { inherit lib pkgs theme; };
#
#   # Inside programs.tmux.extraConfig:
#   set -g status-left  '${framework.composeBar [ "session" ]}'
#   set -g status-right '${framework.composeBar [ "now-playing" "weather" "date-time" ]}'
#   set -g window-status-format         '${framework.windowStyle.format}'
#   set -g window-status-current-format '${framework.windowStyle.currentFormat}'
#
# The framework is theme-aware but theme-agnostic in code — it never references
# "catppuccin" or "dracula" by name. Swapping themes = changing theme.nix.
{ lib, pkgs, theme }:
let
  separatorsAll = import ./separators.nix;
  separators    = separatorsAll.${theme.separators};

  widgets = import ./widgets;

  composeModule = import ./status-module.nix { inherit lib separators; };

  # Render a widget by name. Returns the tmux status-string fragment.
  renderWidget = name:
    let
      widgetFn = widgets.${name} or (throw "tmux framework: unknown widget '${name}'");
      spec = widgetFn {
        inherit lib pkgs;
        inherit (theme) palette icons style;
      };
    in
      composeModule spec;

  composeBar = widgetNames:
    lib.concatStringsSep "" (map renderWidget widgetNames);

  windowStyle = import ./window-style.nix {
    inherit lib separators;
    inherit (theme) palette;
  };
in
{
  inherit theme separators widgets composeModule renderWidget composeBar windowStyle;
}
