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
  kubernetes       = import ./kubernetes.nix;
  git              = import ./git.nix;
  network          = import ./network.nix;

  # Custom / invisible
  now-playing   = import ./now-playing.nix;
  snapshot-tick = import ./snapshot-tick.nix;
}
