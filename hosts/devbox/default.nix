{
  pkgs,
  pkgsUnstable,
  pkgsEdge,
  nixvim,
  lib,
  ...
}:
let
  # Cross-platform packages
  commonPackages = import ../../home/dmitry/packages/common.nix {
    inherit pkgs pkgsUnstable pkgsEdge;
  };

  # Linux-specific packages
  linuxPackages = import ../../home/dmitry/packages/linux.nix {
    inherit pkgs;
  };

  # Container-specific packages
  containerExtras = with pkgs; [
    tini          # Docker entrypoint
    chromium      # For Playwright
    ngspice       # Circuit simulation
    # kicad       # EDA - disabled, not available for aarch64-linux
  ];
in
{
  home = {
    username = "dmitry";
    homeDirectory = "/home/dmitry";
    stateVersion = "24.11";

    sessionVariables = {
      TZ = "UTC";
      EDITOR = "nvim";
      GOPATH = "$HOME/go";
      DISPLAY = "host.docker.internal:0";
      PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
      PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH = "${pkgs.chromium}/bin/chromium";
      TERM = "xterm-256color";
      PATH = builtins.concatStringsSep ":" [
        "$HOME/go/bin"
        "$HOME/.nix-profile/bin"
        "$HOME/.local/bin"
        "$HOME/npm-tools/node_modules/.bin"
        "$HOME/python-tools/.venv/bin"
        "$PATH"
      ];
    };

    packages = commonPackages ++ linuxPackages ++ containerExtras;
  };

  fonts.fontconfig.enable = true;

  # Reuse all program configs from main home-manager setup
  programs = {
    home-manager.enable = true;

    direnv = import ../../home/programs/direnv.nix { inherit pkgs; };
    git = import ../../home/programs/git.nix { inherit pkgs; };
    tmux = import ../../home/programs/tmux.nix { pkgs = pkgsUnstable; };
    nixvim = import ../../home/programs/nixvim.nix { inherit pkgs; };
    zoxide = import ../../home/programs/zoxide.nix { inherit pkgs; };
    zsh = import ../../home/programs/zsh.nix { inherit pkgs pkgsUnstable; };
    k9s = import ../../home/programs/k9s.nix { inherit pkgsUnstable; };
    ssh = import ../../home/programs/ssh.nix { inherit pkgs; };
    poetry = import ../../home/programs/poetry.nix { inherit pkgs; };
  };

  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.permittedInsecurePackages = [ "python-2.7.18.12" ];

  imports = [
    nixvim.homeManagerModules.nixvim
    ../../home/programs/ghostty.nix
  ];
}
