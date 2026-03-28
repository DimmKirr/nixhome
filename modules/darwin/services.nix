{ pkgsEdge, ... }: {
  imports = [
    ./services/ollama.nix
  ];

  services = {
    ollama = {
      enable = true;
      package = pkgsEdge.ollama;  # edge (nixpkgs master) for latest version
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
