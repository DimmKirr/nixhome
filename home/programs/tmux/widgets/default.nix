# Widget registry. Each entry: name → function `{ lib, pkgs, palette, icons, style } → widgetSpec`.
{
  # Static (tmux-native, no shell fork)
  host        = import ./host.nix;
  session     = import ./session.nix;
  directory   = import ./directory.nix;
  date-time   = import ./date-time.nix;
  user        = import ./user.nix;
  application = import ./application.nix;

  # Shell-backed (writeShellApplication, with optional caching)
  attached-clients = import ./attached-clients.nix;
  uptime           = import ./uptime.nix;
  battery          = import ./battery.nix;
  cpu              = import ./cpu.nix;
  ram              = import ./ram.nix;
  weather          = import ./weather.nix;
  world-clock      = import ./world-clock.nix;
  # One block per zone so each gets its own color.
  world-clock-ny   = args: import ./world-clock.nix (args // { zones = [ "America/New_York" ];    accent = "mauve"; });
  world-clock-la   = args: import ./world-clock.nix (args // { zones = [ "America/Los_Angeles" ]; accent = "pink"; });
  kubernetes       = import ./kubernetes.nix;
  git              = import ./git.nix;
  network          = import ./network.nix;

  # Custom / invisible
  now-playing   = import ./now-playing.nix;
  snapshot-tick = import ./snapshot-tick.nix;
}
