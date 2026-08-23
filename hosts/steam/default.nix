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
        "$PATH"
        "$HOME/.nix-profile/bin"
        "$HOME/.local/bin"
        "$HOME/go/bin"
      ];
    };

    packages = with pkgs; [
      # Core utilities
      coreutils
      findutils
      tree
      unzip
      wget
      ripgrep
      htop
      curl
      git
      lazygit
      gh
      go-task
      fzf
      yazi

      # Kubernetes
      k3s
      kubernetes-helm
    ] ++ (with pkgsUnstable; [
      k9s
    ]);

    file.".config/environment.d/10-nix.conf".text = ''
      PATH=$PATH:$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin
    '';

    file.".config/k3s/agent.service".text = ''
      [Unit]
      Description=K3s Agent
      After=network-online.target
      Wants=network-online.target

      [Service]
      Type=exec
      EnvironmentFile=-/home/deck/.config/k3s/env
      ExecStart=/home/deck/.nix-profile/bin/k3s agent --snapshotter=native
      Restart=always
      RestartSec=5
      KillMode=process
      Delegate=yes
      LimitNOFILE=1048576
      LimitNPROC=infinity
      LimitCORE=infinity

      [Install]
      WantedBy=multi-user.target
    '';

    file.".config/k3s/env".text = ''
      # K3S_URL=https://192.168.8.150:6443
      # K3S_TOKEN=<node-token>
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
    zsh      = (import ../../home/programs/zsh.nix      { inherit pkgs pkgsUnstable; }) // {
      shellAliases.sudo = ''sudo env PATH="$PATH"'';
    };
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
