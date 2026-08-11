# macOS-only Nix packages
{
  pkgs,
  pkgsUnstable,
  pkgsEdge,
  ...
}:
with pkgs; [
  # mas # managed by homebrew (nix-darwin auto-installs via brew when masApps is non-empty)
  defaultbrowser
  raycast
  ext4fuse
  cocoapods
  fastlane
  # xquartz  # Using homebrew cask instead - nix build fails on 25.11
  # karabiner-elements  # Using homebrew - nix can't register app bundles with macOS properly

  docker-client
  libvirt
  swtpm

  keepassxc
  discord      # x86_64 only, doesn't work on aarch64-linux
  seclists     # Large wordlist package - only on darwin, too big for devbox
] ++ (with pkgsUnstable; [
  (import ./qemu-rc.nix { inherit pkgs pkgsEdge; })
  lima
  monitorcontrol
  betterdisplay
#  zoom-us # Disabled b/c of issues with permissions (doesn't recognize them, likely b/c of symlinks)
])
