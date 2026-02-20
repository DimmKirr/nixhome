{
  pkgs,
  lib,
  ...
}: {
  # Linux-specific home-manager settings

  # Systemd user services could be added here in the future
  # Example:
  # systemd.user.services.example = {
  #   Unit = {
  #     Description = "Example service";
  #   };
  #   Service = {
  #     ExecStart = "${pkgs.example}/bin/example";
  #   };
  #   Install = {
  #     WantedBy = ["default.target"];
  #   };
  # };
}
