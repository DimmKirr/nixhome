{
  pkgs,
  inputs,
  pkgsUnstable,
  pkgsEdge,
  pkgsLegacy,
  nixvim,
  lib,
  ...
}: {
  # NOTE: Do NOT use pkgs.stdenv.isDarwin in imports section - causes infinite recursion
  # Platform-specific logic must be inside each module's config block
  home = {
    sessionVariables = {
      TZ = "UTC";
      PIPX_HOME = "$HOME/.local/pipx";
      PIPX_BIN_DIR = "$HOME/.local/bin";
      DEVCELL_NIXHOME_PATH = "$HOME/dev/devcell-sh/devcell/nixhome";
      PYTHONPATH = builtins.concatStringsSep ":" [
        "$HOME/dev/dimmkirr/yt-dl-plugins"
        "$PYTHONPATH"
      ];

      PKG_CONFIG_PATH = builtins.concatStringsSep ":" [
        "$HOME/.nix-profile/lib/pkgconfig"
        "$HOME/.nix-profile/share/pkgconfig"
        "/opt/homebrew/lib/pkgconfig"
        "$PKG_CONFIG_PATH"
      ];

      PATH = builtins.concatStringsSep ":" [
        "$HOME/dev/dimmkirr/atun/bin"
        "/run/wrappers/bin"
        "/run/current-system/sw/bin"
        "/nix/var/nix/profiles/default/bin"
        "$HOME/.local/share/mise/shims"
        "$HOME/.local/bin"
        "$HOME/.cargo/bin"
        "$HOME/.rbenv/bin"
        "$HOME/.nix-profile/sbin"
        "$HOME/.nix-profile/bin"
        "$HOME/.cache/npm/global/bin"
        "/usr/local/sbin"
        "/usr/local/bin"
        "/opt/homebrew/bin"
        "/opt/homebrew/sbin"
        "$PATH"
      ];
    };

    packages =
      (import ./packages/common.nix { inherit pkgs pkgsUnstable pkgsEdge pkgsLegacy; })
      ++ (lib.optionals pkgs.stdenv.isDarwin (import ./packages/darwin.nix { inherit pkgs pkgsUnstable pkgsEdge; }))
      ++ (lib.optionals pkgs.stdenv.isLinux (import ./packages/linux.nix { inherit pkgs pkgsEdge; }))
      ;

    stateVersion = "24.11";
  };

  fonts = {
    fontconfig = {
      enable = true;
      defaultFonts.emoji = [
        "Noto Color Emoji"
      ];
      defaultFonts.monospace = ["Noto Sans Mono"];
      defaultFonts.sansSerif = ["Noto Sans"];
      defaultFonts.serif = ["Noto Serif"];
    };
  };

  programs = {
    # Easy shell environments
    direnv = import ../programs/direnv.nix {inherit pkgs;};
    git = import ../programs/git.nix {inherit pkgs;};
    tmux = import ../programs/tmux.nix {pkgs = pkgsUnstable;};
    nixvim = import ../programs/nixvim.nix {inherit pkgs;};
    zoxide = import ../programs/zoxide.nix {inherit pkgs;};
    poetry = import ../programs/poetry.nix {inherit pkgs;};
    mise = import ../programs/mise.nix {inherit pkgs pkgsUnstable;};
    ssh = import ../programs/ssh.nix {inherit pkgs;};
    k9s = import ../programs/k9s.nix {inherit pkgsUnstable;};
    zellij = import ../programs/zellij.nix {inherit pkgs;};

    zsh = import ../programs/zsh.nix {inherit pkgs pkgsUnstable;};
    mc = import ../programs/mc.nix {inherit pkgs;};
    starship = import ../programs/starship.nix { inherit pkgs; };
  };

  xdg.configFile."mc/skins/dracula256.ini".source = ../programs/mc-skins/dracula256.ini;
  xdg.configFile."mc/menu".source = ../programs/mc.menu;
  xdg.configFile."vifm/vifmrc".source = ../programs/vifm/vifmrc;
  xdg.configFile."vifm/colors".source = ../programs/vifm/colors;

  services = {
  # Ollama disabled for now, ollama-0.12.11 fails
#    ollama = {
#      enable = true;
#      package = pkgsEdge.ollama;
#    };
  } // lib.optionalAttrs pkgs.stdenv.isDarwin {
    colima = {
      enable = true;
      package = pkgsUnstable.colima;
      profiles.default = {
        isActive = true;
        isService = true;
        setDockerHost = false;
        settings = {
          cpu = 8;
          memory = 24;
          disk = 60;
          runtime = "docker";
          vmType = "vz";
          rosetta = true;
          nestedVirtualization = true;
          mounts = [
            { location = "/Users"; writable = true; }
            { location = "/Volumes"; writable = true; }
            # /tmp itself is a reserved guest path in lima; /private/tmp is the
            # real directory behind macOS's /tmp symlink
            { location = "/private/tmp"; writable = true; }
            { location = "/var/folders"; writable = true; }
          ];
          provision = [
            {
              mode = "system";
              script = ''
                #!/bin/bash
                set -eu
                if [ ! -f /swapfile ]; then
                  fallocate -l 8G /swapfile
                  chmod 600 /swapfile
                  mkswap /swapfile
                fi
                swapon /swapfile 2>/dev/null || true
              '';
            }
          ];
        };
      };
    };
  };

  # All modules imported unconditionally - each module handles platform logic internally
  imports = [
    ../programs/ghostty.nix
    ../programs/ize.nix
    ../programs/karabiner.nix
    ../programs/finicky.nix
    ../programs/claude-code.nix
    # ../programs/opencode.nix  # Removed: home-manager 25.11 has built-in programs.opencode
    ../programs/wokwi-cli.nix
    ./services/darwin.nix
    ./services/linux.nix
    nixvim.homeModules.nixvim
    inputs.devcell.homeManagerModules.default
  ];

  devcell = {
    enable = true;
    cell.default_command = "claude";
    env = {
      CLAUDE_CODE_DISABLE_AGENT_VIEW = "1";
      CLAUDE_CODE_DISABLE_BACKGROUND_TASKS = "1";
      CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN = "1";
      CLAUDE_CODE_DISABLE_MOUSE = "1";
      CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
    };
    volumes = [
      { mount = "/Users/dmitry/dev/dimmkirr/skills/"; }
      { mount = "/Users/dmitry/dev/kirr/skills/"; }
      { mount = "/Users/dmitry/dev/mad/skills/"; }
      { mount = "/Users/dmitry/dev/ptc/skills/"; }
      { mount = "/Users/dmitry/dev/kiwa/skills/"; }
      { mount = "/Users/dmitry/dev/nmd/private-skills/"; }
      { mount = "/Users/dmitry/dev/hazelops/skills/"; }
      { mount = "/Users/dmitry/.cache:/home/dmitry/.cache"; }
    ];
    # Layered on top of Claude Code's built-in system prompt (--append-system-prompt-file).
    # Do NOT use llm.system_prompt / prompt here — that REPLACES the built-in prompt entirely.
    appendPrompt = ''
      # Rules

      - Never publish artifacts. Deliver all work as files in the working directory or scratchpad, and summarize results in the response.
      - Never commit changes unless instructed by a user. Never add "Co-Authored-By" to any commit message.
      - Do not use emdash (—) as it doesn't match the user's writing style. Use `:` instead or a different sentence structure.
      - Present information in a concise, clean, to-the-point format: the user will ask to elaborate if needed. If the information contains multiple points, use markdown to list them sequentially. The user will ask about specifics and you elaborate as requested. This is needed for more efficient communication.
        - Default: "top 3 idiomatic" options (~100 words), to help define the direction.
        - If asked to break it down: top 5, to see the variety.
        - Fit the whole response into one screen: max ~35 terminal lines, including blank lines and separator/graphic lines.
      - If a directory contains an `.aiignore` file, treat it exactly like a `.gitignore` (Cursor's `.aiignore` format): parse it with gitignore syntax and exclude everything it matches from your work. Do not read, edit, or reference matched files, directories, sub-directories, or wildcard paths.
      - If a project has `AGENTS.md`, treat it as `CLAUDE.md`: read it when you start.
      - If the Web Search tool is failing for any reason, use the playwright MCP tool instead.

      # Scripts and Tools you create

      - Any scripts you need to create for executing actions (e.g. Python scripts, shell scripts, temporary wrappers) must reside in `.scratch/tools/<task-you-needed-it-for>/<tool-name>.<ext>`. This structure keeps the repository clean from interim scripts and tools.
      - Any screenshots taken during visual QA should go into `.scratch/screenshots/<dateISO>/<datetimeISO>-<ticket|purpose>-<image-content-desc>-<index>.<ext>`.
      - Any illustrations or generated images should go into `.scratch/illustrations/<dateISO>/<datetimeISO>-<ticket|purpose>-<image-content-desc>-<index>.<ext>`.
    '';
  };
}
# Inspired by
# https://github.com/evantravers/dotfiles/blob/4e9bc7a25ebc73389130567ab46b9cab78b5783e/home-manager/home.nix
# https://github.com/the-nix-way/nome
# https://github.com/Th0rgal/horus-nix-home
# https://github.com/Yumasi/nixos-home/blob/main/zsh.nix
