# macOS-specific home-manager settings
{ config, lib, pkgs, ... }: lib.mkIf pkgs.stdenv.isDarwin {
  launchd.agents.raycast = {
    enable = true;
    config = {
      Label = "com.raycast.launch";
      ProgramArguments = [ "${pkgs.raycast}/Applications/Raycast.app/Contents/Library/RaycastLauncher" ];
      RunAtLoad = true;
      KeepAlive = true;
    };
  };

  launchd.agents.hidden-bar = {
    enable = true;
    config = {
      Label = "com.dwarvesv.minimalbar.launch";
      ProgramArguments = [ "${pkgs.hidden-bar}/Applications/Hidden Bar.app/Contents/MacOS/Hidden Bar" ];
      RunAtLoad = true;
      KeepAlive = true;
    };
  };

  # Hidden Bar preferences (launchd handles autostart, so isAutoStart stays off)
  targets.darwin.defaults."com.dwarvesv.minimalbar" = {
    isAutoStart = false;
    isAutoHide = true;
  };

  launchd.agents.libvirtd = {
    enable = true;
    config = {
      Label = "org.libvirt.libvirtd";
      ProgramArguments = [
        "${pkgs.libvirt}/bin/libvirtd"
        "--listen"
        "--config" "${config.home.homeDirectory}/.config/libvirt/libvirtd.conf"
      ];
      RunAtLoad = true;
      KeepAlive = true;
    };
  };

  home.file.".config/libvirt/libvirtd.conf".text = ''
    listen_tcp = 1
    listen_tls = 0
    listen_addr = "0.0.0.0"
    auth_tcp = "none"
  '';
}
