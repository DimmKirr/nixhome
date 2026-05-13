# Universal tmux theming framework.
#
# Usage from home-manager (data-style import):
#
#   theme = import ../programs/theme.nix { inherit lib; preset = "catppuccin"; };
#   tmuxFramework = import ../programs/tmux { inherit lib pkgs theme; };
#
#   programs.tmux = tmuxFramework.mkTmux {
#     leftWidgets  = [ "host" ];                       # currently only host
#     rightWidgets = [ ];                              # to be expanded
#     extraConfig  = "...";                            # user's existing keybinds/menus
#   };
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
  # Expose internals for tests and introspection
  inherit theme separators widgets composeModule renderWidget composeBar windowStyle;

  # Main entry — produces a programs.tmux attrset.
  mkTmux = {
    leftWidgets  ? [],
    rightWidgets ? [],
    extraConfig  ? "",
  }:
  let
    statusLeft  = composeBar leftWidgets;
    statusRight = composeBar rightWidgets;
  in
  {
    enable = true;
    statusBar = { left = statusLeft; right = statusRight; };  # exposed for debugging
    extraConfig = ''
      set -g status-left  '${statusLeft}'
      set -g status-right '${statusRight}'
      set -g status-bg    '${theme.palette.bg}'
      set -g status-fg    '${theme.palette.fg}'
      set -g status-interval 5

      # Window status
      set -g window-status-format         '${windowStyle.format}'
      set -g window-status-current-format '${windowStyle.currentFormat}'
      set -g window-status-separator      '${windowStyle.separator}'

      ${extraConfig}
    '';
  };
}
