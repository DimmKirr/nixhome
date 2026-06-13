{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.chatterbox;

  configYaml = pkgs.writeText "chatterbox-config.yaml" ''
    server:
      host: "${cfg.host}"
      port: ${toString cfg.port}

    model:
      repo_id: "${cfg.model}"

    tts_engine:
      device: "auto"
  '';

  startScript = pkgs.writeShellScript "chatterbox-start" ''
    set -euo pipefail

    CHATTERBOX_DIR="${cfg.dataDir}"
    VENV_DIR="$CHATTERBOX_DIR/.venv"
    REPO_DIR="$CHATTERBOX_DIR/server"

    mkdir -p "$CHATTERBOX_DIR"

    # Clone or update server repo
    if [ ! -d "$REPO_DIR/.git" ]; then
      ${pkgs.git}/bin/git clone https://github.com/devnen/Chatterbox-TTS-Server.git "$REPO_DIR"
    fi

    # Create venv if missing
    if [ ! -d "$VENV_DIR" ]; then
      ${pkgs.uv}/bin/uv venv --python 3.10 "$VENV_DIR"
    fi

    export VIRTUAL_ENV="$VENV_DIR"
    export PATH="$VENV_DIR/bin:$PATH"

    # Install deps if needed (marker file)
    if [ ! -f "$CHATTERBOX_DIR/.deps-installed" ]; then
      cd "$REPO_DIR"
      ${pkgs.uv}/bin/uv pip install -r requirements.txt
      ${pkgs.uv}/bin/uv pip install --no-deps "chatterbox-tts-v2 @ git+https://github.com/devnen/chatterbox-v2.git@master" s3tokenizer==0.3.0 onnx==1.16.0
      touch "$CHATTERBOX_DIR/.deps-installed"
    fi

    # Link config
    cp -f ${configYaml} "$REPO_DIR/config.yaml"

    cd "$REPO_DIR"
    exec "$VENV_DIR/bin/python" server.py
  '';
in {
  options = {
    services.chatterbox = {
      enable = mkEnableOption "Chatterbox TTS Server";

      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Host address for the Chatterbox TTS server.";
      };

      port = mkOption {
        type = types.port;
        default = 8000;
        description = "Port for the Chatterbox TTS server.";
      };

      model = mkOption {
        type = types.str;
        default = "chatterbox-turbo";
        description = "Chatterbox model to use (chatterbox, chatterbox-turbo, chatterbox-multilingual-v3).";
      };

      dataDir = mkOption {
        type = types.str;
        default = "/Users/dmitry/.local/share/chatterbox";
        description = "Directory for Chatterbox server repo, venv, and model cache.";
      };

      environmentVariables = mkOption {
        type = types.attrsOf types.str;
        default = { };
        description = "Extra environment variables for the Chatterbox service.";
      };
    };
  };

  config = mkIf cfg.enable {
    launchd.user.agents.chatterbox = {
      path = [ config.environment.systemPath ];

      serviceConfig = {
        KeepAlive = true;
        RunAtLoad = true;
        ProgramArguments = [ "${startScript}" ];

        EnvironmentVariables = cfg.environmentVariables // {
          HOME = "/Users/dmitry";
          HF_HOME = "${cfg.dataDir}/huggingface";
        };

        StandardOutPath = "${cfg.dataDir}/server.log";
        StandardErrorPath = "${cfg.dataDir}/server.err";
      };
    };
  };
}
