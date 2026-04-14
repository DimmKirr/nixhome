# macOS-only Nix packages
{
  pkgs,
  pkgsUnstable,
  ...
}:
with pkgs; [
  # mas # managed by homebrew (nix-darwin auto-installs via brew when masApps is non-empty)
  defaultbrowser
  raycast
  ext4fuse
  cocoapods
  # xquartz  # Using homebrew cask instead - nix build fails on 25.11
  # karabiner-elements  # Using homebrew - nix can't register app bundles with macOS properly

  keepassxc
  discord      # x86_64 only, doesn't work on aarch64-linux
  seclists     # Large wordlist package - only on darwin, too big for devbox

  # Android emulator (latest Pixel / Android 15, ARM64 native on Apple Silicon)
  (androidenv.composeAndroidPackages {
    platformVersions = [ "35" ];
    abiVersions = [ "arm64-v8a" ];
    includeEmulator = true;
    includeSystemImages = true;
    systemImageTypes = [ "google_apis_playstore" ];
    cmdLineToolsVersion = "11.0";
  }).androidsdk
] ++ (with pkgsUnstable; [
  monitorcontrol
  betterdisplay
#  zoom-us # Disabled b/c of issues with permissions (doesn't recognize them, likely b/c of symlinks)
])
