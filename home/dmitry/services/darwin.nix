# macOS-specific home-manager settings
{ config, lib, pkgs, ... }: {
  # Launch agents for macOS services
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
