# macOS-only Nix packages
{
  pkgs,
  pkgsUnstable,
  pkgsEdge,
  ...
}:
with pkgs; [
  mas
  defaultbrowser
  raycast
  ext4fuse
  cocoapods
  # xquartz  # Using homebrew cask instead - nix build fails on 25.11
  # karabiner-elements  # Using homebrew - nix can't register app bundles with macOS properly

  keepassxc
  discord      # x86_64 only, doesn't work on aarch64-linux
] ++ (with pkgsUnstable; [
  monitorcontrol
  betterdisplay
]) ++ (with pkgsEdge; [
  seclists     # Large wordlist package - only on darwin, too big for devbox
#  zoom-us # Disabled b/c of issues with permissions (doesn't recognize them, likely b/c of symlinks)
])
