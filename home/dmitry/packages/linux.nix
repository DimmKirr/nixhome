# Linux-only packages
{
  pkgs,
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
  qemu           # qemu-img and other QEMU tools

  # Additional Linux tools
  alsa-utils     # Audio control
  pciutils       # lspci
  usbutils       # lsusb
]
