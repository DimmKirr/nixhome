# Setapp application manager module for nix-darwin
#
# Manages Setapp application installations declaratively, similar to homebrew.masApps.
# Requires Setapp.app to be installed first (e.g., via homebrew casks).
#
# Discovered CLI interface (from binary analysis + vendor confirmation):
#   -installApps "App1" "App2"   Install apps by name
#   -launchAfterInstall          Launch app after installing
#   -silentLaunch                Start Setapp without UI
#   -login <email> -password <p> Authenticate
#   SetappDiscoveryCLI           Embedded CLI: fetch apps info (JSON), install, uninstall, logout
#
# Usage:
#   setapp = {
#     enable = true;
#     apps = [
#       "Commander One"
#       "CleanMyMac X"
#     ];
#   };
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.setapp;

  setappBin = "/Applications/Setapp.app/Contents/MacOS/Setapp";

  # Build the -installApps argument list
  appsArgs = lib.concatMapStringsSep " " (app: ''"${app}"'') cfg.apps;
in
{
  options.setapp = {
    enable = lib.mkEnableOption "Setapp application manager";

    apps = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "Commander One"
        "CleanMyMac X"
        "Paste"
      ];
      description = ''
        List of Setapp application names to install.
        Names must match exactly as they appear in the Setapp catalog.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && cfg.apps != [ ]) {
    # Install each app individually so we can detect already-installed (-401004) vs real errors.
    # Runs as user via launchctl asuser for XPC access to SetappAgent.
    system.activationScripts.postActivation.text = ''
      # Setapp app installation
      if [ -x "${setappBin}" ]; then
        echo "setapp: ensuring ${toString (builtins.length cfg.apps)} app(s)..."
        _setapp_uid=$(id -u ${config.system.primaryUser})
        ${lib.concatMapStringsSep "\n" (app: ''
        _setapp_output=$(launchctl asuser "$_setapp_uid" sudo -u ${config.system.primaryUser} ${setappBin} -installApps "${app}" 2>&1)
        _setapp_rc=$?
        if [ $_setapp_rc -eq 0 ]; then
          if echo "$_setapp_output" | grep -q "Code=-401004"; then
            echo "setapp: ${app} — already installed"
          else
            echo "setapp: ${app} — installed"
          fi
        else
          echo "setapp: ${app} — error (exit $_setapp_rc)"
          echo "$_setapp_output" | grep -v "MachServices\|mach-port-object\|LimitLoadToSessionType\|OnDemand\|LastExitStatus\|ProgramArguments\|PerJobMachServices\|com\.apple\.\|com\.setapp\.\(Banners\|Dashboard\|Apps\|Team\|Remote\|shared\|System\|Command\|Recommendations\|Provisioning\|Notifications\|UI\)" | head -5
        fi
        '') cfg.apps}
        echo "setapp: done"
      else
        echo "setapp: Setapp.app not found, skipping (install via homebrew cask first)"
      fi
    '';
  };
}
