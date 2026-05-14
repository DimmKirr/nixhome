# now-playing — current music track via DimmKirr/tmux-now-playing.
#
# Pinned to the `feature/add-media-control` branch — that branch emits empty
# output when no player is running. The wrapper script emits plain text
# (no color escapes); the framework composer draws the cyan bg block in
# the standard twoTone shape, matching pre-framework Dracula visuals.
#
# `skipWhenEmpty = true` makes the composer wrap the rendered fragment in
# `#{?#{==:#(...),},,...}` — so when music.sh returns empty, the whole
# block (including bg) collapses to nothing.
# (Ticket: tmux-widgets-emit-stray-escapes-when-empty)
{ lib, pkgs, palette, icons, style }:
let
  base = import ./_base.nix { inherit lib; };

  nowPlayingPlugin = pkgs.tmuxPlugins.mkTmuxPlugin {
    pluginName = "tmux-now-playing";
    version = "unstable-feature-add-media-control-2025-09-17";
    rtpFilePath = "now-playing.tmux";
    src = pkgs.fetchFromGitHub {
      owner = "DimmKirr";
      repo = "tmux-now-playing";
      rev = "c731e8478ac4ffd6076785b40be6e5ab0701fa90";
      sha256 = "78kgQq4wfzWevHn2OhgJ8XmiYTGvvGOSs+zoGIoLDgw=";
    };
  };

  musicScript = "${nowPlayingPlugin}/share/tmux-plugins/tmux-now-playing/scripts/music.sh";

  scriptText = lib.replaceStrings
    [ "@MUSIC_SCRIPT@" ]
    [ musicScript ]
    (builtins.readFile ./scripts/now-playing.sh);

  wrapped = pkgs.writeShellApplication {
    name = "tmux-widget-now-playing";
    runtimeInputs = [ pkgs.coreutils ];
    text = scriptText;
  };
in
base.defaults palette // {
  icon   = "";
  iconBg = palette.sky;     # Dracula cyan (#8BE9FD) — matches pre-framework Dracula now-playing block
  iconFg = palette.crust;   # dark text (#191A21) on cyan bg
  text   = " #(${wrapped}/bin/tmux-widget-now-playing) ";
  inherit style;            # use theme style (twoTone) so the composer draws the bg block
  skipWhenEmpty = true;     # collapse the whole block when no music is playing
}
