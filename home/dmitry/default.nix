{
  pkgs,
  inputs,
  pkgsUnstable,
  pkgsEdge,
  nixvim,
  lib,
  ...
}: {
  # NOTE: Do NOT use pkgs.stdenv.isDarwin in imports section - causes infinite recursion
  # Platform-specific logic must be inside each module's config block
  home = {
    sessionVariables = {
      TZ = "UTC";
      PIPX_HOME = "$HOME/.local/pipx";
      PIPX_BIN_DIR = "$HOME/.local/bin";
      DEVCELL_NIXHOME_PATH = "/Users/dmitry/dev/dimmkirr/devcell/nixhome";
      PYTHONPATH = builtins.concatStringsSep ":" [
        "$HOME/dev/dimmkirr/yt-dl-plugins"
        "$PYTHONPATH"
      ];

      PKG_CONFIG_PATH = builtins.concatStringsSep ":" [
        "$HOME/.nix-profile/lib/pkgconfig"
        "$HOME/.nix-profile/share/pkgconfig"
        "/opt/homebrew/lib/pkgconfig"
        "$PKG_CONFIG_PATH"
      ];

      PATH = builtins.concatStringsSep ":" [
        "$HOME/dev/dimmkirr/atun/bin"
        "/run/current-system/sw/bin"
        "/nix/var/nix/profiles/default/bin"
        "$HOME/.local/share/mise/shims"
        "$HOME/.nix-profile/sbin"
        "$HOME/.nix-profile/bin"
        "$HOME/.cargo/bin"
        "$HOME/.local/bin"
        "$HOME/.rbenv/bin"
        "$HOME/.cache/npm/global/bin"
        "/usr/local/sbin"
        "/usr/local/bin"
        "/opt/homebrew/bin"
        "/opt/homebrew/sbin"
        "$PATH"
      ];
    };

    packages =
      (import ./packages/common.nix { inherit pkgs pkgsUnstable pkgsEdge; })
      ++ (lib.optionals pkgs.stdenv.isDarwin (import ./packages/darwin.nix { inherit pkgs pkgsUnstable; }))
      ++ (lib.optionals pkgs.stdenv.isLinux (import ./packages/linux.nix { inherit pkgs; }));

    stateVersion = "24.11";
  };

  fonts = {
    fontconfig = {
      enable = true;
      defaultFonts.emoji = [
        "Noto Color Emoji"
      ];
      defaultFonts.monospace = ["Noto Sans Mono"];
      defaultFonts.sansSerif = ["Noto Sans"];
      defaultFonts.serif = ["Noto Serif"];
    };
  };

  programs = {
    # Easy shell environments
    direnv = import ../programs/direnv.nix {inherit pkgs;};
    git = import ../programs/git.nix {inherit pkgs;};
    tmux = import ../programs/tmux.nix {pkgs = pkgsUnstable;};
    nixvim = import ../programs/nixvim.nix {inherit pkgs;};
    zoxide = import ../programs/zoxide.nix {inherit pkgs;};
    poetry = import ../programs/poetry.nix {inherit pkgs;};
    mise = import ../programs/mise.nix {inherit pkgs pkgsEdge;};
    ssh = import ../programs/ssh.nix {inherit pkgs;};
    k9s = import ../programs/k9s.nix {inherit pkgsUnstable;};

    zsh = import ../programs/zsh.nix {inherit pkgs pkgsUnstable;};
    mc = import ../programs/mc.nix {inherit pkgs;};
    starship = import ../programs/starship.nix {};
  };

  xdg.configFile."mc/skins/dracula256.ini".source = ../programs/mc-skins/dracula256.ini;

  services = {
  # Ollama disabled for now, ollama-0.12.11 fails
#    ollama = {
#      enable = true;
#      package = pkgsEdge.ollama;
#    };
  };

  # All modules imported unconditionally - each module handles platform logic internally
  imports = [
    ../programs/ghostty.nix
    ../programs/ize.nix
    ../programs/atun.nix
    ../programs/karabiner.nix
    ../programs/claude-code.nix
    # ../programs/opencode.nix  # Removed: home-manager 25.11 has built-in programs.opencode
    ../programs/wokwi-cli.nix
    ./services/darwin.nix
    ./services/linux.nix
    nixvim.homeModules.nixvim
  ];
}
# Inspired by
# https://github.com/evantravers/dotfiles/blob/4e9bc7a25ebc73389130567ab46b9cab78b5783e/home-manager/home.nix
# https://github.com/the-nix-way/nome
# https://github.com/Th0rgal/horus-nix-home
# https://github.com/Yumasi/nixos-home/blob/main/zsh.nix
