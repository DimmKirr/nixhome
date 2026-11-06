# macOS-specific home-manager settings
{ config, lib, pkgs, pkgsUnstable, ... }: lib.mkIf pkgs.stdenv.isDarwin {

  # --- Colima: container runtime (Docker via lightweight VM) ---
  services.colima = {
    enable = true;
    package = pkgsUnstable.colima;
    profiles.default = {
      isActive = true;
      isService = true;
      setDockerHost = true;
      settings = {
        cpu = 10;
        memory = 16;
        disk = 120;
        rootDisk = 20; # restart does not apply start's default for omitted settings
        runtime = "docker";
        vmType = "vz";
        rosetta = true;
        nestedVirtualization = true;
        mounts = [
          { location = "/Users"; writable = true; }
          { location = "/Volumes"; writable = true; }
          # /tmp itself is a reserved guest path in lima; /private/tmp is the
          # real directory behind macOS's /tmp symlink
          { location = "/private/tmp"; writable = true; }
          { location = "/var/folders"; writable = true; }
        ];
        provision = [
          {
            mode = "system";
            script = ''
              #!/bin/bash
              set -eu
              if [ ! -f /swapfile ]; then
                fallocate -l 8G /swapfile
                chmod 600 /swapfile
                mkswap /swapfile
              fi
              swapon /swapfile 2>/dev/null || true
            '';
          }
        ];
      };
    };
    # GPU-accelerated profile: Mesa Venus -> virtio-gpu -> virglrenderer -> MoltenVK -> Metal
    # ~80% native Metal perf. Vulkan only (no native OpenGL). Apple Silicon + macOS 13+ required.
    # Usage: colima start --profile krunkit
    profiles.krunkit = {
      isActive = false;
      isService = false;
      setDockerHost = false;
      settings = {
        cpu = 8;
        memory = 16;
        disk = 120;
        rootDisk = 20;
        runtime = "docker";
        vmType = "krunkit";
        mounts = [
          { location = "/Users"; writable = true; }
          { location = "/Volumes"; writable = true; }
          { location = "/private/tmp"; writable = true; }
          { location = "/var/folders"; writable = true; }
        ];
        provision = [
          {
            mode = "system";
            script = ''
              #!/bin/bash
              set -eu
              if [ ! -f /swapfile ]; then
                fallocate -l 8G /swapfile
                chmod 600 /swapfile
                mkswap /swapfile
              fi
              swapon /swapfile 2>/dev/null || true
            '';
          }
        ];
      };
    };
  };

  # The home-manager colima module gives the launchd agent a nix-only PATH.
  # Colima gates nestedVirtualization (and rosetta) on host checks that shell
  # out to /usr/sbin/system_profiler and /usr/bin/pgrep; when those are not
  # found the check fails silently and the setting never reaches lima.yaml.
  # Keep the module's PATH and append the macOS system dirs.
  launchd.agents = let
    c = config.services.colima;
    modulePath = lib.makeBinPath [
      c.package
      c.perlPackage
      c.dockerPackage
      c.sshPackage
      c.coreutilsPackage
      c.curlPackage
      c.bashPackage
      c.kubectlPackage
      pkgs.darwin.DarwinTools
    ];
  in {
    colima-default.config.EnvironmentVariables.PATH =
      lib.mkForce "${modulePath}:/usr/sbin:/usr/bin:/bin:/sbin";

    # --- Sleepwatcher: stop Colima on sleep, restart on wake ---
    # sleepwatcher is installed via Homebrew (brews list). It monitors macOS
    # power events and runs ~/.sleep / ~/.wakeup scripts. This prevents
    # Colima's VM from consuming CPU while the lid is closed.
    sleepwatcher = {
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

    raycast = {
      enable = true;
      config = {
        Label = "com.raycast.launch";
        ProgramArguments = [ "${pkgs.raycast}/Applications/Raycast.app/Contents/Library/RaycastLauncher" ];
        RunAtLoad = true;
        KeepAlive = true;
      };
    };

    hidden-bar = {
      enable = true;
      config = {
        Label = "com.dwarvesv.minimalbar.launch";
        ProgramArguments = [ "${pkgs.hidden-bar}/Applications/Hidden Bar.app/Contents/MacOS/Hidden Bar" ];
        RunAtLoad = true;
        KeepAlive = true;
      };
    };

    libvirtd = {
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

  # Hidden Bar preferences (launchd handles autostart, so isAutoStart stays off)
  targets.darwin.defaults."com.dwarvesv.minimalbar" = {
    isAutoStart = false;
    isAutoHide = true;
  };

  home.file.".config/libvirt/libvirtd.conf".text = ''
    listen_tcp = 1
    listen_tls = 0
    listen_addr = "0.0.0.0"
    auth_tcp = "none"
  '';
}
