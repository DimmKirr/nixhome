{pkgs, ...}: {
  enable = true;
  direnv = {
    enable = true;
  };



  #  package = pkgs.asdf-vm;
  nodejs = {
    enable = true;
    defaultPackages = [
      "yarn"
      "npm"
    ];
    defaultVersion = "22.10.0";
  };

  ruby = {
    enable = true;
    defaultPackages = [
      "bundler"
      "rails"
    ];
    defaultVersion = "3.4.8";
  };

  python = {
    enable = true;
    defaultVersion = "3.14.2";
    defaultPackages = [
      "pipx"
    ];
  };

  terraform = {
    enable = true;
    defaultVersion = "1.14.3";
  };

  opentofu = {
    enable = true;
    defaultVersion = "1.10.6";
  };

  golang = {
    enable = true;
    defaultVersion = "1.24.3";
  };

  config = {
    legacy_version_file = "yes";
    golang_mod_version_enabled = "yes";
  };
}
