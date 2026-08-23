# hosts/devcell/default.nix — home-manager config for the `dmitry` session user
# inside a devcell container (cell-*).
#
# Activate with:
#   home-manager switch --flake .#devcell-aarch64    # aarch64 container (the current one)
#   home-manager switch --flake .#devcell            # x86_64 container
#
# This config ONLY manages /home/dmitry. /opt/devcell stays owned by the devcell
# base flake (https://github.com/DimmKirr/devcell/tree/main/nixhome), so the
# two are additive — see flake.nix for the homeConfigurations wiring.
#
# First-activation tip: devcell copies starter dotfiles (.zshrc, .gitconfig, …)
# into /home/dmitry at container start. home-manager refuses to overwrite
# pre-existing non-symlink files, so the first run typically needs `-b backup`:
#   home-manager switch --flake .#devcell-aarch64 -b backup
{
  pkgs,
  pkgsUnstable,
  pkgsEdge,
  pkgsLegacy,
  nixvim,
  lib,
  ...
}:
let
  commonPackages = import ../../home/dmitry/packages/common.nix {
    inherit pkgs pkgsUnstable pkgsEdge pkgsLegacy;
  };
  linuxPackages = import ../../home/dmitry/packages/linux.nix {
    inherit pkgs pkgsEdge;
  };
in
{
  home = {
    username = "dmitry";
    homeDirectory = "/home/dmitry";
    stateVersion = "24.11";

    sessionVariables = {
      TZ = "UTC";
      EDITOR = "nvim";
      TERM = "xterm-256color";
      PATH = builtins.concatStringsSep ":" [
        "$HOME/go/bin"
        "$HOME/.nix-profile/bin"
        "$HOME/.local/bin"
        "$PATH"
      ];
    };

    packages = commonPackages ++ linuxPackages;
  };

  fonts.fontconfig.enable = true;

  programs = {
    home-manager.enable = true;

    direnv   = import ../../home/programs/direnv.nix   { inherit pkgs; };
    git      = import ../../home/programs/git.nix      { inherit pkgs; };
    tmux     = import ../../home/programs/tmux.nix     { pkgs = pkgsUnstable; };
    nixvim   = import ../../home/programs/nixvim.nix   { inherit pkgs; };
    zoxide   = import ../../home/programs/zoxide.nix   { inherit pkgs; };
    zsh      = import ../../home/programs/zsh.nix      { inherit pkgs pkgsUnstable; };
    ssh      = import ../../home/programs/ssh.nix      { inherit pkgs; };
    mise     = import ../../home/programs/mise.nix     { inherit pkgs pkgsEdge; };
    starship = import ../../home/programs/starship.nix { };
    mc       = import ../../home/programs/mc.nix       { inherit pkgs; };
    k9s      = import ../../home/programs/k9s.nix      { inherit pkgsUnstable; };
    poetry   = import ../../home/programs/poetry.nix   { inherit pkgs; };
  };

  xdg.configFile."mc/skins/dracula256.ini".source = ../../home/programs/mc-skins/dracula256.ini;
  xdg.configFile."vifm/vifmrc".source             = ../../home/programs/vifm/vifmrc;
  xdg.configFile."vifm/colors".source             = ../../home/programs/vifm/colors;

  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.permittedInsecurePackages = [ "python-2.7.18.12" ];

  imports = [
    nixvim.homeManagerModules.nixvim
  ];
}
