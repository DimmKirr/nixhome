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

    # pipx overlay — nixpkgs 26.05 ships pipx 1.8.0 whose test suite breaks
    # against the newer `packaging` lib: PEP 508 spec parsing now normalizes
    # `name@ url` to `name @ url`, so 7 test_package_specifier.py assertions
    # fail in checkPhase. The package itself is fine; skip the build-time tests.
    (_final: prev: {
      pipx = prev.pipx.overridePythonAttrs (_old: {
        doCheck = false;
        doInstallCheck = false;
      });
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
    # Latest upstream nix on the macOS host's nix-daemon — keeps daemon protocol
    # in sync with the VM's daemon so cross-builds don't hit version skew bugs.
    package = pkgs.nixVersions.latest;

    # BOOTSTRAP — bare config so cache.nixos.org's prebuilt VM image substitutes.
    # Any customization (memory/cores/sudo/GC overrides) forces an aarch64-linux
    # build that needs an existing linux-builder. After this switch, the VM is
    # online and we can re-add the full block below in a SECOND switch.
    #
    # ephemeral = true: VM disk wiped on every restart so 0-byte/corruption
    # can't accumulate across macOS sleep/wake. Runtime flag — doesn't trigger
    # an aarch64-linux build, safe for bootstrap.
    linux-builder = {
      enable = true;
      ephemeral = true;
      # 100 GiB sparse qcow2 ceiling (default is 20 GiB). ephemeral=true wipes
      # the disk on every VM restart, so actual on-disk usage starts at ~0 and
      # only grows during a build session — "thin" is automatic with qcow2.
      config.virtualisation.darwin-builder.diskSize = 100 * 1024;
    };
    # ---- Customized linux-builder config (apply on the SECOND switch) ----
    # linux-builder = {
    #   enable = true;
    #   # ephemeral = true → VM disk wiped on every restart, so 0-byte/corruption
    #   # can't accumulate across macOS sleep/wake or unclean shutdowns. Cost:
    #   # ~1–2 min cache repopulation from cache.nixos.org on each VM start.
    #   # See https://github.com/NixOS/nix/issues/2285 for the underlying race.
    #   ephemeral = true;
    #   maxJobs = 4;
    #   config = {
    #     nix.package = pkgs.nixVersions.latest;
    #     virtualisation = {
    #       darwin-builder.diskSize = 100 * 1024;
    #       darwin-builder.memorySize = 16 * 1024;
    #       cores = 8;
    #     };
    #     nix.gc.automatic = false;
    #     systemd.services.nix-gc-keep-1 = {
    #       description = "Keep only the current system generation and GC the nix store";
    #       serviceConfig.Type = "oneshot";
    #       script = ''
    #         ${pkgs.nix}/bin/nix-env --profile /nix/var/nix/profiles/system --delete-generations +1 || true
    #         ${pkgs.nix}/bin/nix-collect-garbage
    #       '';
    #     };
    #     systemd.timers.nix-gc-keep-1 = {
    #       wantedBy = [ "timers.target" ];
    #       timerConfig = { OnCalendar = "daily"; Persistent = true; RandomizedDelaySec = "30m"; };
    #     };
    #     nix.settings = {
    #       keep-derivations = lib.mkForce false;
    #       min-free = lib.mkForce 0;
    #       max-free = lib.mkForce 0;
    #     };
    #     security.sudo.extraRules = [{
    #       users = [ "builder" ];
    #       commands = [{ command = "ALL"; options = [ "NOPASSWD" ]; }];
    #     }];
    #   };
    # };

    # Built-in GC disabled — custom launchd daemon below keeps only the current generation.
    gc.automatic = false;

    settings =
      {
        "auto-optimise-store" = false;
        "keep-derivations" = false;
        # Auto-GC disabled — see Nix#2285. Daily launchd timer below handles GC.
        "min-free" = 0;
        "max-free" = 0;
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

  # Keep only the current system generation + GC. Runs daily at 3 AM.
  # `--delete-generations +1` keeps just the live one — minimizes disk
  # pressure so we never approach the threshold that risks GC-vs-build races
  # (Nix#2285). Rollback is sacrificed in exchange for predictable disk use.
  launchd.daemons.nix-gc-keep-1 = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/sh" "-c"
        ''
          /nix/var/nix/profiles/default/bin/nix-env \
            --profile /nix/var/nix/profiles/system \
            --delete-generations +1 || true
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
  # setapp = {
  #   enable = true;
  #   apps = [
  #     "Commander One"
  #   ];
  # };

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

    # Keyboard and input config
    NSGlobalDomain = {
      AppleKeyboardUIMode = 2; # Full keyboard access (tab through all controls). Was 3, but Sequoia+ only accepts 0 or 2 (nix-darwin#1378)
      "com.apple.keyboard.fnState" = true; # Fn key is function by default system-wise, but overriden by karabiner based on the app
      ApplePressAndHoldEnabled = true; # Long-press shows accent popup instead of key repeat
      # swipescrolldirection moved to postActivation — nix-darwin's userDefaults
      # step writes it too early and activateSettings -u flushes it (nix-darwin#1721)
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

  # Workaround for nix-darwin#1721: nix-darwin's userDefaults step (13/24)
  # writes NSGlobalDomain, but without an activateSettings flush those
  # writes only take effect at next login. We write our overrides in
  # postActivation (24/24) so they're the final word, then flush once.
  #
  # Order matters: all `defaults write` FIRST, then one cfprefsd restart
  # + activateSettings at the end. The old code killed cfprefsd before
  # activateSettings, which raced (activateSettings needs cfprefsd alive).
  system.activationScripts.postActivation.text = ''
    # --- Write overrides (plist DB writes, no daemon interaction) ---

    # Traditional (non-natural) scroll direction — both domains so it sticks
    sudo -u dmitry defaults write NSGlobalDomain com.apple.swipescrolldirection -bool false
    sudo -u dmitry defaults -currentHost write NSGlobalDomain com.apple.swipescrolldirection -bool false

    # Globe key = Change Input Source (0=Nothing, 1=Input Source, 2=Emoji, 3=Dictation)
    sudo -u dmitry defaults write com.apple.HIToolbox AppleFnUsageType -int 1
    sudo -u dmitry defaults -currentHost write com.apple.HIToolbox AppleFnUsageType -int 1

    # Disable Ctrl+Space (hotkey 60) and Ctrl+Option+Space (hotkey 61) for input switching
    sudo -u dmitry defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 60 \
      '<dict><key>enabled</key><false/><key>value</key><dict><key>type</key><string>standard</string><key>parameters</key><array><integer>32</integer><integer>49</integer><integer>262144</integer></array></dict></dict>'
    sudo -u dmitry defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 61 \
      '<dict><key>enabled</key><false/><key>value</key><dict><key>type</key><string>standard</string><key>parameters</key><array><integer>32</integer><integer>49</integer><integer>786432</integer></array></dict></dict>'

    # Disable Spotlight search Cmd+Space (hotkey 64) and Finder search Cmd+Option+Space (hotkey 65)
    # so Raycast owns Cmd+Space exclusively
    sudo -u dmitry defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 64 \
      '<dict><key>enabled</key><false/><key>value</key><dict><key>type</key><string>standard</string><key>parameters</key><array><integer>32</integer><integer>49</integer><integer>1048576</integer></array></dict></dict>'
    sudo -u dmitry defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 65 \
      '<dict><key>enabled</key><false/><key>value</key><dict><key>type</key><string>standard</string><key>parameters</key><array><integer>32</integer><integer>49</integer><integer>1572864</integer></array></dict></dict>'

    # TODO: Disable double-tap Cmd → Type to Siri. No known defaults write
    # key exists for the Sequoia Apple Intelligence shortcut. The legacy
    # com.apple.Siri KeyboardShortcutPreSAE does NOT control it.
    # Set manually: System Settings → Apple Intelligence & Siri → Keyboard
    # Shortcut → Globe+S (or Off). Use plistwatch to discover the real key.

    # --- Flush: restart cfprefsd so it re-reads plists, then activate ---
    sudo -u dmitry killall cfprefsd 2>/dev/null || true
    sleep 1
    sudo -u dmitry /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
  '';

  system.primaryUser = "dmitry";
}
# Inspired by:
# https://github.com/mirkolenz/nixos/blob/main/system/darwin/settings.nix
