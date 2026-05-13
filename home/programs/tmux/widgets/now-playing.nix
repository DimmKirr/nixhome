# now-playing — current music track via DimmKirr/tmux-now-playing.
#
# Pinned to the `feature/add-media-control` branch — that branch emits empty
# output when no player is running. We wrap music.sh in a tiny shell script
# that:
#   - emits nothing when output is empty (cyan block disappears entirely)
#   - emits a tmux-formatted cyan block with the track text otherwise
#
# Composer style = "minimal" so the framework doesn't draw its own always-on
# block — the wrapper draws colors inline via #[fg=...,bg=...] escapes which
# tmux honors inside #() output.
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
    [ "@MUSIC_SCRIPT@" "@FG@" "@BG@" ]
    [ musicScript palette.iconFgDefault palette.sky ]
    (builtins.readFile ./scripts/now-playing.sh);

  wrapped = pkgs.writeShellApplication {
    name = "tmux-widget-now-playing";
    runtimeInputs = [ pkgs.coreutils ];
    text = scriptText;
  };
in
base.defaults palette // {
  icon  = "";
  text  = "#(${wrapped}/bin/tmux-widget-now-playing)";
  style = "minimal";
}
