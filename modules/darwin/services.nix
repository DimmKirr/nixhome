{ ... }: {
  services = {
    # Enable and configure Ollama service
    /*ollama = {
      enable = true;

      # Optional configurations (uncomment and modify as needed):
      # package = pkgs.ollama;  # Use a specific Ollama package
      # host = "127.0.0.1";     # Change to "0.0.0.0" to listen on all interfaces
      # port = 11434;           # Custom port
      # models = "/path/to/models";  # Custom models directory
      # environmentVariables = {
      #   OLLAMA_LLM_LIBRARY = "cpu";  # Example: Force CPU mode
      #   OLLAMA_KEEP_ALIVE = "5m";    # Example: Set keep-alive timeout
      # };
    };*/

    # Other services can be added here
    # tailscale.enable = true;
  };
}
