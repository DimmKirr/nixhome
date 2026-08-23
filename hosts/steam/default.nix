# hosts/steam/default.nix — standalone home-manager config for SteamOS.
#
# SteamOS uses the `deck` user. Nix is installed via the Determinate Systems
# installer (not NixOS), so this is a standalone homeConfiguration like devbox/devcell.
#
# Activate with:
#   home-manager switch --flake .#steam
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
    username = "deck";
    homeDirectory = "/home/deck";
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

    packages = commonPackages ++ linuxPackages ++ (with pkgs; [
      k3s
    ]);

    file.".config/environment.d/10-nix.conf".text = ''
      PATH=$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH
    '';
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
    starship = import ../../home/programs/starship.nix { };
    mc       = import ../../home/programs/mc.nix       { inherit pkgs; };
    k9s      = import ../../home/programs/k9s.nix      { inherit pkgsUnstable; };
  };

  xdg.configFile."mc/skins/dracula256.ini".source = ../../home/programs/mc-skins/dracula256.ini;
  xdg.configFile."vifm/vifmrc".source             = ../../home/programs/vifm/vifmrc;
  xdg.configFile."vifm/colors".source             = ../../home/programs/vifm/colors;

  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.permittedInsecurePackages = [ "python-2.7.18.12" ];

  targets.genericLinux.enable = true;

  imports = [
    nixvim.homeManagerModules.nixvim
  ];
}
