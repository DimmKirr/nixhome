# git — current branch + dirty indicator for pane's working dir.
# No caching — branch info changes between commands; cache would feel stale.
{ lib, pkgs, palette, icons, style }:
let
  base = import ./_base.nix { inherit lib; };
  raw = pkgs.writeShellApplication {
    name = "tmux-widget-git";
    runtimeInputs = [ pkgs.coreutils pkgs.git ];
    text = builtins.readFile ./scripts/git.sh;
  };
in
base.defaults palette // {
  icon = base.mkIcon icons {
    nerdFont = " ";   # nf-fa-code_branch
    ascii    = "[G] ";
    emoji    = "🌿 ";
    none     = "";
  };
  iconBg = palette.pink;
  # Pass pane's current path as argument so script knows which repo to inspect.
  text   = " #(${raw}/bin/tmux-widget-git #{pane_current_path}) ";
  inherit style;
}
