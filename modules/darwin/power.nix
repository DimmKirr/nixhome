# Always-awake virtualization host: display sleep can disrupt Tart's GPU path.
# pmset persists policy; launchd holds assertions across logout and reboot.
{ lib, pkgs, ... }:
let
  applyPolicy = pkgs.writeShellScript "darwin-always-awake-policy" ''
    set -eu
    /usr/bin/pmset -a sleep 0 displaysleep 0 disksleep 0
    /usr/bin/pmset -a disablesleep 1

    # Apple Silicon and Intel expose different knobs. Only write optional
    # settings advertised by this host, across all power sources (-a).
    settings=$(/usr/bin/pmset -g custom)
    for setting in standby autopoweroff hibernatemode powernap lowpowermode halfdim lessbright; do
      if printf '%s\n' "$settings" | /usr/bin/awk -v key="$setting" '
        $1 == key { found = 1 }
        END { exit !found }
      '; then
        /usr/bin/pmset -a "$setting" 0
      else
        echo "always-awake: $setting is not exposed on this Mac; skipping" >&2
      fi
    done
  '';

  keepAwake = pkgs.writeShellScript "darwin-always-awake" ''
    set -eu
    ${applyPolicy}
    # Display, idle system, idle disk, and AC system-sleep assertions.
    # No -u: it expires after five seconds unless given a timeout.
    exec /usr/bin/caffeinate -dims
  '';
in {
  power.sleep = {
    computer = "never";
    display = "never";
    harddisk = "never";
    allowSleepByPowerButton = false;
  };

  # Apply immediately on switch, after nix-darwin's systemsetup calls.
  system.activationScripts.postActivation.text = lib.mkAfter ''
    echo "applying always-awake power policy..." >&2
    ${applyPolicy}
  '';

  launchd.daemons.always-awake = {
    serviceConfig = {
      ProgramArguments = [ "${keepAwake}" ];
      RunAtLoad = true;
      KeepAlive = true;
      ThrottleInterval = 30;
      StandardOutPath = "/var/log/always-awake.log";
      StandardErrorPath = "/var/log/always-awake.log";
    };
  };
}
