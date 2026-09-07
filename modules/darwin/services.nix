{ pkgs, ... }: {
  imports = [
    ./services/ollama.nix
  ];

  services = {
    ollama = {
      enable = true;
      # Official prebuilt binary — the only way to get the MLX backend:
      # nixpkgs' source build disables it (Metal toolchain unavailable in
      # the nix sandbox). Version/hash are pinned at this call site.
      package = pkgs.callPackage ../../pkgs/ollama-bin.nix {
        version = "0.33.3";
        hash = "sha256-NC2wPfgLuduE/2QkYDG9X3DAm1n/UvpcyaquNHbMSp0=";
      };
      # host = "0.0.0.0";  # to expose on all interfaces
      # models = "/path/to/models";
      environmentVariables = {
        OLLAMA_NUM_CTX = "32768";            # default context window for all models
        OLLAMA_KEEP_ALIVE = "1h";            # keep models loaded longer, avoid cold starts
        OLLAMA_FLASH_ATTENTION = "1";        # flash attention on Metal — faster, less memory
        OLLAMA_KV_CACHE_TYPE = "q8_0";       # ~50% context memory savings, negligible quality loss
        OLLAMA_NUM_PARALLEL = "4";           # concurrent requests (48GB has headroom)
        OLLAMA_MAX_LOADED_MODELS = "2";      # keep 2 models loaded simultaneously
      };
    };

    # tailscale.enable = true;
  };
}
