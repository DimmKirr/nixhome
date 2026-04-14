{
  config,
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

    gc = {
      automatic = true;
      interval = {
        Weekday = 6; # Friday



        Hour = 3; # 3 AM
        Minute = 0;
      };
      options = "--delete-older-than 30d";
    };

    settings =
      {
        "auto-optimise-store" = false;
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

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 5;

  # Install fonts
  #fonts.fontDir.enable = true;
  fonts.packages = [
    pkgs.monaspace
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
