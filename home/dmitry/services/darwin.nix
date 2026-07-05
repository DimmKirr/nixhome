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
}
