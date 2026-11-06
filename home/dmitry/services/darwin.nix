# macOS-specific home-manager settings
{ config, lib, pkgs, ... }: lib.mkIf pkgs.stdenv.isDarwin {
  # --- Sleepwatcher: stop Colima on sleep, restart on wake ---
  # sleepwatcher is installed via Homebrew (brews list). It monitors macOS
  # power events and runs ~/.sleep / ~/.wakeup scripts. This prevents
  # Colima's VM from consuming CPU while the lid is closed.
  launchd.agents.sleepwatcher = {
    enable = true;
    config = {
      Label = "de.bernhard-baehr.sleepwatcher";
      ProgramArguments = [
        "/opt/homebrew/sbin/sleepwatcher"
        "-V"
        "-s" "${config.home.homeDirectory}/.sleep"
        "-w" "${config.home.homeDirectory}/.wakeup"
      ];
      RunAtLoad = true;
      KeepAlive = true;
    };
  };

  # ~/.sleep — executed by sleepwatcher before macOS goes to sleep
  home.file.".sleep" = {
    executable = true;
    text = ''
      #!/bin/bash
      # Stop Colima VM before sleep to prevent CPU drain and clock drift on wake.
      # The launchd-managed colima service (KeepAlive) would restart it, so we
      # unload the agent first, then stop the VM.
      COLIMA=/opt/homebrew/bin/colima
      if command -v ${config.home.homeDirectory}/.nix-profile/bin/colima &>/dev/null; then
        COLIMA=${config.home.homeDirectory}/.nix-profile/bin/colima
      fi
      launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/org.nix-community.home.colima-default.plist 2>/dev/null || true
      "$COLIMA" stop 2>/dev/null || true
      logger -t sleepwatcher "colima stopped for sleep"
    '';
  };

  # ~/.wakeup — executed by sleepwatcher after macOS wakes up
  home.file.".wakeup" = {
    executable = true;
    text = ''
      #!/bin/bash
      # Restart Colima after wake. Re-bootstrap the launchd agent so it
      # resumes its KeepAlive lifecycle.
      sleep 5  # let networking and disk settle
      launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/org.nix-community.home.colima-default.plist 2>/dev/null || true
      logger -t sleepwatcher "colima restarted after wake"
    '';
  };

  launchd.agents.raycast = {
    enable = true;
    config = {
      Label = "com.raycast.launch";
      ProgramArguments = [ "${pkgs.raycast}/Applications/Raycast.app/Contents/Library/RaycastLauncher" ];
      RunAtLoad = true;
      KeepAlive = true;
    };
  };

  launchd.agents.hidden-bar = {
    enable = true;
    config = {
      Label = "com.dwarvesv.minimalbar.launch";
      ProgramArguments = [ "${pkgs.hidden-bar}/Applications/Hidden Bar.app/Contents/MacOS/Hidden Bar" ];
      RunAtLoad = true;
      KeepAlive = true;
    };
  };

  # Hidden Bar preferences (launchd handles autostart, so isAutoStart stays off)
  targets.darwin.defaults."com.dwarvesv.minimalbar" = {
    isAutoStart = false;
    isAutoHide = true;
  };

  launchd.agents.libvirtd = {
    enable = true;
    config = {
      Label = "org.libvirt.libvirtd";
      ProgramArguments = [
        "${pkgs.libvirt}/bin/libvirtd"
        "--listen"
        "--config" "${config.home.homeDirectory}/.config/libvirt/libvirtd.conf"
      ];
      RunAtLoad = true;
      KeepAlive = true;
    };
  };

  home.file.".config/libvirt/libvirtd.conf".text = ''
    listen_tcp = 1
    listen_tls = 0
    listen_addr = "0.0.0.0"
    auth_tcp = "none"
  '';
}
