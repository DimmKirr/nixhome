{
  pkgs,
  #  draculaZedTheme,
  #  catppuccinZedTheme,
  ...
}: {
  # https://wiki.nixos.org/wiki/Zed
  enable = true;

  # This populates the userSettings "auto_install_extensions"
  extensions = [
    "nix"
    "toml"
    "elixir"
    "make"
    "ruby"
    "dracula"
    "catppuccin"
    "catppuccin-icons"
    "intellij-newui-theme"
    "jetbrains-new-ui-icons"
    "dockerfile"

    "gem"
    "mcp-server-context7"
    "mcp-server-puppeteer"
    "mcp-server-sequential-thinking"
  ];

  userSettings = {
    agent = {
      enabled = true;
      version = "2";

      ### PROVIDER OPTIONS
      ### zed.dev models { claude-3-5-sonnet-latest } requires github connected
      ### anthropic models { claude-3-5-sonnet-latest claude-3-haiku-latest claude-3-opus-latest  } requires API_KEY
      ### copilot_chat models { gpt-4o gpt-4 gpt-3.5-turbo o1-preview } requires github connected
      default_model = {
        provider = "ollama";
        model = "qwen2.5-coder";
      };

      inline_alternatives = [
        {
          provider = "ollama";
          model = "qwen2.5-coder";
        }
      ];
    };

    # Ollama configuration
    language_models = {
      ollama = {
        api_url = "http://localhost:11434";
        available_models = [
          {
            name = "qwen2.5-coder";
            display_name = "qwen 2.5 coder 32K";
            max_tokens = 32768;
            supports_tools = true;
            supports_thinking = true;
            supports_images = true;
            capabilities = {
              edit = true; # Enable code editing capabilities
              chat = true; # Enable chat functionality
              search = true; # Enable web search capabilities
            };
            parameters = {
              temperature = 0.7; # Control creativity vs. determinism (0.0 to 1.0)
              top_p = 0.9; # Nucleus sampling parameter
              frequency_penalty = 0.0;
              presence_penalty = 0.0;
            };
          }
        ];
      };
      langchain = {
        api_url = "http://127.0.0.1:1234";
        available_models = [
          {
            name = "gpt-oss-20b";
            display_name = "OpenAI GPT OSS 20B";
            max_tokens = 32768;
            supports_tools = true;
            supports_thinking = true;
            supports_images = true;
            capabilities = {
              edit = true; # Enable code editing capabilities
              chat = true; # Enable chat functionality
              search = true; # Enable web search capabilities
            };
            parameters = {
              temperature = 0.7; # Control creativity vs. determinism (0.0 to 1.0)
              top_p = 0.9; # Nucleus sampling parameter
              frequency_penalty = 0.0;
              presence_penalty = 0.0;
            };
          }
        ];
      };
    };

    # Keybindings for agentic editing
    keymap = {
      "cmd-shift-a" = "editor:submit-edit"; # Submit the current edit
      "cmd-shift-r" = "editor:reject-edit"; # Reject the current edit
      "cmd-shift-e" = "editor:explain-edit"; # Explain the proposed edit
    };

    theme = {
      mode = "dark";
      # light = "Dracula";
      # dark = "Dracula";
      light = "Catppuccin Latte";
      dark = "Catppuccin Mocha";
    };

    # Icon theme configuration
    icon_theme = {
      mode = "light"; # or "dark" or "system"
      light = "Catppuccin Latte";
      dark = "Catppuccin Mocha";
    };
  };

  #  themes = {
  #    dracula = draculaZedTheme;
  #    catppuccin = catppuccinZedTheme;
  #  };
}
