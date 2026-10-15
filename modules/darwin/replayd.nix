# Disable Apple's per-user ReplayKit service on the GPU-sensitive Tart machine.
# This affects recording/sharing clients that depend on replayd, not just games.
{ config, lib, pkgs, ... }:
let
  user = config.system.primaryUser;
  disableReplayd = pkgs.writeShellScript "disable-replayd" ''
    set -eu
    target_uid="''${1:-$(/usr/bin/id -u)}"
    domain="gui/$target_uid"
    service="$domain/com.apple.replayd"

    if ! /bin/launchctl print "$domain" >/dev/null 2>&1; then
      echo "disable-replayd: $domain is not active; deferring until GUI login" >&2
      exit 0
    fi

    # disable persists across boots; bootout also removes the current job.
    # Never hide permission/SIP errors or modify Apple's protected plist.
    if ! /bin/launchctl disable "$service"; then
      echo "disable-replayd: macOS rejected the persistent disable for $service" >&2
      exit 1
    fi
    if /bin/launchctl print "$service" >/dev/null 2>&1; then
      if ! /bin/launchctl bootout "$service"; then
        echo "disable-replayd: disabled for future loads, but bootout failed; current job may still be running" >&2
        exit 1
      fi
    fi
    if /bin/launchctl print "$service" >/dev/null 2>&1; then
      echo "disable-replayd: service is still registered after bootout" >&2
      exit 1
    fi
    /bin/launchctl print-disabled "$domain"
    echo "disable-replayd: $service disabled and unloaded"
  '';
in {
  # Run on every switch, including when this module was already enabled.
  system.activationScripts.postActivation.text = lib.mkAfter ''
    echo "disabling ReplayKit capture service..." >&2
    ${disableReplayd} "$(/usr/bin/id -u ${lib.escapeShellArg user})"
  '';

  # Covers switches made with no GUI session, and subsequent logins.
  launchd.user.agents.disable-replayd = {
    serviceConfig = {
      ProgramArguments = [ disableReplayd ];
      RunAtLoad = true;
      StandardOutPath = "/Users/${user}/Library/Logs/disable-replayd.log";
      StandardErrorPath = "/Users/${user}/Library/Logs/disable-replayd.log";
    };
  };
}
