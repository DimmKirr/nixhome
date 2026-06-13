# Homebrew configuration (casks, brews, Mac App Store)
# Separate file because it doesn't need pkgs and avoids circular imports
{
  enable = true;
  onActivation = {
    cleanup = "uninstall";
    extraFlags = [ "--force" ]; # Homebrew 5.1.14+ requires --force with --cleanup (PR #22395)
    autoUpdate = false; # was true — disabled to prevent Homebrew self-updating past breaking changes (5.1.14 broke --cleanup)
    upgrade = true;
  };

  taps = [
    "hazelops/ize"
    "automationd/tap"
    "jeffreywildman/homebrew-virt-manager"
    "gemfury/tap"
    "opencode-ai/tap"
    "smokris/getwindowid"
    "sikarugir-app/sikarugir"
    "porter-dev/porter"
  ];

  casks = [
    # "xquartz"  # disabled: brew fetch fails during darwin-rebuild (cask load error)
    "scribus"
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
    "finicky"
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
    "qemu" # qemu-img and tools; nix qemu conflicts with androidsdk's bundled qemu-img
    "porter-dev/porter/porter" # porter.run CLI — not in nixpkgs
    "mas"
  ];

  masApps = {
    # "Slack" = 803453959; # pinned — mas 6.x removed 'get' command, install manually via App Store
    "Telegram" = 747648890;
    "Yubico Authenticator" = 1497506650;
#    "1Password Safari" = 1569813296; # Pinned
    # Re-enabled after mas overlay (nixpkgs-unstable.mas 7.x) added in
    # hosts/automationd/default.nix. Tracking: nix-darwin#1722, mas-cli#1221.
    "WireGuard" = 1451685025;
    "DigiDoc4 Client" = 1370791134;
    "Safari WebID" = 1576665083;
    "Final Cut Pro" = 424389933;
    "Numbers" = 361304891;
    "Pages" = 361309726;
    "Windows App" = 1295203466; # Microsoft RDP client (rebranded from "Microsoft Remote Desktop")
    "Xcode" = 497799835;
    "Tailscale" = 1475387142;
  };
}
