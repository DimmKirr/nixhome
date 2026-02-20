{
  config,
  pkgs,
  inputs,
  pkgsUnstable,
  ...
}: {
  # Allow unfree system packages
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.permittedInsecurePackages = [ "python-2.7.18.12" ];

  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Networking
  networking.hostName = "jump";
  networking.networkmanager.enable = true;

  # Set your time zone
  time.timeZone = "UTC";

  # Select internationalisation properties
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

  # Define a user account
  users.users.dmitry = {
    isNormalUser = true;
    description = "Dmitry Kireev";
    extraGroups = ["networkmanager" "wheel" "docker"];
    shell = pkgs.zsh;
  };

  # System packages
  environment.systemPackages = with pkgs; [
    vim
    wget
    git
    curl
    htop
  ];

  # Enable programs
  programs.zsh.enable = true;
  programs.gnupg.agent.enable = true;

  # Enable services
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  # Enable Docker
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

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  system.stateVersion = "24.11";
}
