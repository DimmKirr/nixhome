# Linux-only packages
{
  pkgs,
  pkgsEdge,
  ...
}:
with pkgs; [
  # Clipboard utilities
  xclip          # X11 clipboard
  wl-clipboard   # Wayland clipboard
  xdg-utils      # Default apps and desktop integration

  # System utilities
  rofi           # App launcher (like raycast)
  ddcutil        # Monitor control

  # Remote desktop
  tigervnc       # vncviewer (broken on darwin)

  # Virtualization
  (import ./qemu-rc.nix { inherit pkgs pkgsEdge; })

  # Additional Linux tools
  alsa-utils     # Audio control
  pciutils       # lspci
  usbutils       # lsusb
]
