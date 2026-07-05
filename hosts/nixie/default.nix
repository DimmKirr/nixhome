{
  config,
  pkgs,
  inputs,
  pkgsUnstable,
  ...
}: {
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.permittedInsecurePackages = [ "python-2.7.18.12" ];

  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Networking
  networking.hostName = "nixie";
  networking.networkmanager.enable = true;
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];

  # Timezone
  time.timeZone = "UTC";

  # Locale
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # User account
  users.users.dmitry = {
    isNormalUser = true;
    description = "Dmitry Kireev";
    extraGroups = ["networkmanager" "wheel" "docker"];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIAqHIzvxRZ+bixPYtLSoiMYu49l+a3T1Ejxn2xGW2bvuAAAACnNzaDpkbWl0cnk= dmitry@kirr.io"
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDDvjdNAdToapXBfMfhW688y2YsijBCbvBFrV0pqmOV5u/AaCK8MOFJcGnqkMui7ihmAQbf0DZ794hfdTVRMAccR9zR1YwIOB1SH/DPBrnCtHk8Y1I3iVvLaVCrQFRJyzcVMTOwG6mKJJTzQuuzvKteuxeublJuDGY4uAeaztfXVE5AJurVN2Xwc1sw/0RR6gXAKe0uGn92X9s0kdB/nbV9bJP4RTdIEHbm3TaVghYevrXU/amsT112wp4eYQEIUSWpegYRIv5cRaBzyLsvDrC9yNJdzIV9Zy6jUbUoFGWmuisgTPwfkaa2/mAhyulUizdT6Oj6f8leRpW6iVTr+CCi5s4TUx6DKjeP5SI/DDI2RZEUiF7xW89Sqf0dVw9tdSdzdI1TU7m5NW3aIC1/sFJ0JF06fqJFZ5/PKb4LhWvdI+mhwFkWVQsVYUKZiOpH1iwEa3eevb1eZZEYThaMA0zt0hT0vloF7rEZN28/CaB4fUzks8PHn5Zc3Srdvzfux5E="
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAgqQTngjpLZYFBBBu2z7N5s7+LCUjWZCfqkx5UrblKT"
    ];
  };

  # System packages
  environment.systemPackages = with pkgs; [
    vim
    wget
    git
    curl
    htop
    tree
    unzip
    ripgrep
    fd
    jq
    tmux
    lsof
    iotop
    nmap
    dig
    traceroute
  ];

  # Programs
  programs.zsh.enable = true;
  programs.gnupg.agent.enable = true;
  programs.mtr.enable = true;

  # SSH
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  # Docker
  virtualisation.docker.enable = true;

  # Nix settings
  nix = {
    enable = true;
    package = pkgs.nix;

    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };

    settings = {
      "auto-optimise-store" = true;
      "experimental-features" = [
        "nix-command"
        "flakes"
      ];
      "trusted-users" = ["@wheel" "dmitry"];
    };
  };

  system.stateVersion = "24.11";
}
