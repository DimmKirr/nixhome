# Homebrew configuration (casks, brews, Mac App Store)
# Separate file because it doesn't need pkgs and avoids circular imports
{
  enable = true;
  onActivation = {
    cleanup = "uninstall";
    autoUpdate = true;
    upgrade = true;
  };

  taps = [
    "hazelops/ize"
    "automationd/tap"
    "jeffreywildman/homebrew-virt-manager"
    "gemfury/tap"
    "opencode-ai/tap"
    "smokris/getwindowid"
  ];

  casks = [
    "xquartz"
    "1password"
    "1password-cli"
    "bartender"
    "steam"
    "ghostty"
    "typefully"
    "setapp"
    "slack"
    "dropbox"
    "google-drive"
    "box-drive"
    "transmission"
    "whatsapp"
    "adobe-creative-cloud"
    "royal-tsx"
    "chatgpt"
    "firefox"
    "karabiner-elements" # Must use Homebrew - nix can't register app bundles with macOS
    "macfuse"
    "claude"
    "plex-media-server"
    "logi-options+"
    "lm-studio"
    "plex"
    "vlc"
    "mqttx"
    # "anydesk" # pinned — upgrade needs newer macOS # TODO: review if pin is still required
    "linear-linear"
    "windsurf"
    "goodsync"
    "readwise-ibooks"
    "inkscape"
    "sublime-text"
    "obs"
    "libreoffice"
    "vagrant"
    "gpg-suite"
    "tunnelblick"
    "gog-galaxy"
    "timemachineeditor"
    "nextcloud"
    "ungoogled-chromium"
    "virtualbox"
    "utm"
    "zoom"
    "codex" # nix should work, but needs an overlay for newer version, so this for now.
    "hubstaff"
    "Sikarugir-App/sikarugir/sikarugir"
  ];

  brews = [
    "ize-dev"
    "atun"
    "fury-cli"
    "zlib"
    "openssl@3"
    "readline"
    "libyaml"
    "secp256k1"
    "xz"
    "media-control"
    "timedog"
    "mint"
    "getwindowid"
    "tiger-vnc" # broken on darwin in nixpkgs, using homebrew instead
  ];

  masApps = {
    # "Slack" = 803453959; # pinned — mas 6.x removed 'get' command, install manually via App Store
    # "Telegram" = 747648890; # pinned — mas upgrade fails, App Store version is current # TODO: review if pin is still required
    # "Yubikey Authenticator" = 1497506650; # pinned at 7.3.0 — mas tries to upgrade to 7.3.2 which isn't available yet # TODO: review if pin is still required
#    "1Password Safari" = 1569813296; # Pinned
    "WireGuard" = 1451685025;
    "DigiDoc4 Client" = 1370791134;
    "Safari WebID" = 1576665083;
    "Canva" = 897446215;
#    "Tailscale" = 1475387142; # commented due to failed update/upgrade. Next time try nixpkgs darwin version again
    "Final Cut Pro" = 424389933;
  };
}
