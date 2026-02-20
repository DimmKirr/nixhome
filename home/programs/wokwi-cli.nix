{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  cfg = config.programs.wokwi-cli;
in
{
  meta.maintainers = with lib.maintainers; [ ];

  options.programs.wokwi-cli = {
    enable = mkEnableOption "wokwi-cli";

    package = mkOption {
      type = types.nullOr types.package;
      default = null; # Default is set lazily in config block
      description = ''
        The wokwi-cli package to use.
        Set to null to use the built-in package, or provide a custom package.
      '';
    };
  };

  # All pkgs access must be inside config block to avoid infinite recursion
  config = mkIf cfg.enable (
    let
      # Platform detection - safe here because config is lazily evaluated
      osName = if pkgs.stdenv.isDarwin then "macos" else "linuxstatic";
      archName = if pkgs.stdenv.isAarch64 then "arm64" else "x64";

      # Build the wokwi-cli package
      defaultPackage = pkgs.stdenv.mkDerivation rec {
        pname = "wokwi-cli";
        version = "0.18.0";

        src = pkgs.fetchurl {
          url = "https://github.com/wokwi/wokwi-cli/releases/download/v${version}/wokwi-cli-${osName}-${archName}";
          # Hash for macOS ARM64 (aarch64-darwin): v0.18.0
          sha256 = "sha256-Knca0hMb0I6XpyRGpp5EyPaC7YDRaGlUt5PbIYyPKPE=";
        };

        dontUnpack = true;
        dontBuild = true;
        dontStrip = true; # Don't strip the pre-built binary (causes crashes)
        dontPatchELF = true; # Don't patch ELF for pre-built binary
        dontPatchShebangs = true; # It's a binary, not a script

        installPhase = ''
          mkdir -p $out/bin
          cp $src $out/bin/wokwi-cli
          chmod +x $out/bin/wokwi-cli
        '';

        meta = with lib; {
          description = "Wokwi CLI - Hardware simulator command-line interface";
          homepage = "https://wokwi.com/";
          changelog = "https://github.com/wokwi/wokwi-cli/releases/tag/v${version}";
          license = licenses.unfree;
          platforms = [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux" "aarch64-linux" ];
          maintainers = [ ];
          mainProgram = "wokwi-cli";
        };
      };

      # Use provided package or default
      finalPackage = if cfg.package != null then cfg.package else defaultPackage;
    in {
      home.packages = [ finalPackage ];
    }
  );
}
