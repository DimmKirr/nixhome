{
  config,
  lib,
  pkgs,
  inputs,
  pkgsUnstable,
  ...
}: let
  githubToken = builtins.getEnv "GITHB_TOKEN";
in {
  # Allow unfree system packages
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.permittedInsecurePackages = [ "python-2.7.18.12" ];
  nixpkgs.config.android_sdk.accept_license = true;

  environment.systemPackages = with pkgs; [
    home-manager
    defaultbrowser
    #    karabiner-elements #v15 is broken, using homebrew
  ];

  # Use a custom configuration.nix location.
  #environment.darwinConfig = "$HOME/dev/automationd/dotfiles/nix/nix-darwin";

  # Karabiner Elements 15 is broken https://github.com/LnL7/nix-darwin/issues/1041
  nixpkgs.overlays = [
    # mas overlay — nixpkgs 25.05 ships mas 2.2.2 which Apple broke when installd
    # was hardened in macOS 14.8.2+/15.7.2+/26.1+. Pull current mas (7.x) from
    # nixpkgs-unstable. Tracking: nix-darwin#1722, mas-cli#1221.
    (final: _prev: {
      mas = (import inputs.nixpkgs-unstable {
        inherit (final.stdenv.hostPlatform) system;
        config.allowUnfree = true;
      }).mas;
    })

    #    # karabiner
    #    (self: super: {
    #      karabiner-elements = super.karabiner-elements.overrideAttrs (old: {
    ##        version = "15.3.0";
    #        version = "14.13.0";
    #
    #        src = super.fetchurl {
    #          inherit (old.src) url;
    #          hash = "sha256-gmJwoht/Tfm5qMecmq1N6PSAIfWOqsvuHU8VDJY8bLw=";
    #        };
    #      });
    #    })
  ];

  # Import reusable modules
  imports = [
    ../../modules/darwin/services.nix
    ../../modules/darwin/setapp.nix
    # ../../modules/darwin/karabiner-elements.nix  # Custom module doesn't register app bundles properly
  ];
  # Karabiner-Elements requires Homebrew - nix packages don't register app bundles with macOS correctly

  nix = {
    enable = true;
    package = pkgs.nix;

    # Sized for Apple M4 Pro / 13-core / 48 GB host — leaves 3 cores & ~32 GB for macOS.
    linux-builder = {
      enable = true;
      ephemeral = false;
      maxJobs = 4;
      config = {
        virtualisation = {
          darwin-builder.diskSize = 100 * 1024;  # 100 GB (sparse)
          darwin-builder.memorySize = 16 * 1024; # 16 GB (ballooned when idle)
          cores = 8;  # qemu mach-virt caps at 8 vCPUs
        };
        # Built-in nix.gc disabled — custom systemd service below keeps exactly 2 generations.
        nix.gc.automatic = false;
        systemd.services.nix-gc-keep-2 = {
          description = "Keep 2 system generations and GC the nix store";
          serviceConfig.Type = "oneshot";
          script = ''
            ${pkgs.nix}/bin/nix-env \
              --profile /nix/var/nix/profiles/system \
              --delete-generations +2 || true
            ${pkgs.nix}/bin/nix-collect-garbage
          '';
        };
        systemd.timers.nix-gc-keep-2 = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "daily";
            Persistent = true;
            RandomizedDelaySec = "30m";
          };
        };
        # mkForce overrides both the nix-builder-vm profile defaults (3 GB)
        # and the host's nix.settings auto-forwarded into the VM.
        nix.settings = {
          keep-derivations = lib.mkForce false;
          min-free = lib.mkForce 53687091200;   # 50 GB free — triggers GC
          max-free = lib.mkForce 64424509440;   # 60 GB free — GC stops here
        };
      };
    };

    # Built-in GC disabled — custom launchd daemon below keeps exactly 2 generations.
    gc.automatic = false;

    settings =
      {
        "auto-optimise-store" = false;
        "keep-derivations" = false;
        "min-free" = 5368709120;  # 5 GB
        "max-free" = 10737418240; # 10 GB
        "extra-experimental-features" = [
          "nix-command"
          "flakes"
        ];
        "trusted-users" = ["@admin" "dmitry"];
      }
      // (
        if githubToken != ""
        then {"access-tokens" = "github.com=${githubToken}";}
        else {}
      );
  };

  users.users.dmitry = {
    description = "Dmitry Kireev";
    shell = pkgs.zsh;
    home = "/Users/dmitry";
  };

  # Enable gnupg agent
  programs = {
    gnupg.agent.enable = true;
  };

  # Keep 2 system generations + GC. Runs daily at 3 AM.
  launchd.daemons.nix-gc-keep-2 = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/sh" "-c"
        ''
          /nix/var/nix/profiles/default/bin/nix-env \
            --profile /nix/var/nix/profiles/system \
            --delete-generations +2 || true
          /nix/var/nix/profiles/default/bin/nix-collect-garbage
        ''
      ];
      StartCalendarInterval = [{ Hour = 3; Minute = 0; }];
      StandardOutPath = "/var/log/nix-gc.log";
      StandardErrorPath = "/var/log/nix-gc.log";
    };
  };


  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 5;

  # Install fonts
  #fonts.fontDir.enable = true;
  fonts.packages = with pkgs; [
    monaspace
    # Nerd Font variants — required for tmux/starship/Ghostty status bar glyphs.
    # symbols-only is the safety net: even if primary font lacks coverage,
    # terminal falls back to it for icon ranges.
    nerd-fonts.monaspace
    nerd-fonts.symbols-only
  ];

  # Use homebrew to install casks and Mac App Store apps
  homebrew = import ../../home/dmitry/packages/homebrew.nix;

  # Setapp-managed applications (requires Setapp cask above)
  setapp = {
    enable = true;
    apps = [
      "Commander One"
    ];
  };

  # OSX preferences
  system.defaults = {
    # Dock
    dock = {
      autohide = false;
      autohide-delay = 0.0;
      autohide-time-modifier = 0.15;
      dashboard-in-overlay = false;
      enable-spring-load-actions-on-all-items = false;
      expose-animation-duration = 0.2;
      expose-group-apps = false;
      launchanim = true;
      mineffect = "genie";
      minimize-to-application = false;
      mouse-over-hilite-stack = true;
      mru-spaces = false;
      orientation = "bottom";
      show-process-indicators = true;
      show-recents = true;
      showhidden = true;
      static-only = false;
      tilesize = 48;
      wvous-bl-corner = 1;
      wvous-br-corner = 1;
      wvous-tl-corner = 1;
      wvous-tr-corner = 1;

      persistent-apps = [
        "/Applications/Brave Browser.app"
        "/Applications/Firefox.app"
        "/System/Cryptexes/App/System/Applications/Safari.app"
        "/System/Applications/Calendar.app"
        #        "/System/Applications/Mail.app"

        "/Applications/Ghostty.app"
        "/Users/dmitry/Applications/IntelliJ IDEA.app"
        # "${pkgsUnstable.jetbrains.idea-ultimate}/Applications/IntelliJ IDEA.app"
      ];
    };

    finder = {
      _FXShowPosixPathInTitle = false;
      _FXSortFoldersFirst = true;
      AppleShowAllExtensions = true;
      AppleShowAllFiles = false;
      CreateDesktop = true;
      FXDefaultSearchScope = "SCcf";
      FXEnableExtensionChangeWarning = false;
      FXPreferredViewStyle = "clmv";
      QuitMenuItem = false;
      ShowPathbar = true;
      ShowStatusBar = false;
    };

    # Tab between form controls and function keys config
    NSGlobalDomain = {
      AppleKeyboardUIMode = 3;
      "com.apple.keyboard.fnState" = true; # Fn key is function by default system-wise, but overriden by karabiner based on the app
    };
  };

  # Use TouchID for sudo authentication
  security = {
    pam.services.sudo_local.touchIdAuth = true;
    sudo.extraConfig = ''
      Defaults timestamp_timeout=30
      Defaults timestamp_type=global
    '';
  };

  environment = {
    etc."ssh/sshd_config.d/locale.conf".text = ''
      AcceptEnv LANG LC_*
    '';
    # Allow TouchID in tmux
    etc."pam.d/sudo_local".text = ''
      # Managed by Nix Darwin
      auth       optional       ${pkgs.pam-reattach}/lib/pam/pam_reattach.so ignore_ssh # Enable reattach to user namespace (fixes tmux Touch ID)
      auth       sufficient     pam_tid.so
    '';
  };

  system.startup = {
    chime = false; # Disable startup chime
  };


  system.primaryUser = "dmitry";
}
# Inspired by:
# https://github.com/mirkolenz/nixos/blob/main/system/darwin/settings.nix
