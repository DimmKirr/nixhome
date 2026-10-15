{
  pkgs,
  inputs,
  pkgsUnstable,
  pkgsEdge,
  pkgsLegacy,
  nixvim,
  lib,
  config,
  ...
}: {
  # NOTE: Do NOT use pkgs.stdenv.isDarwin in imports section - causes infinite recursion
  # Platform-specific logic must be inside each module's config block
  home = {
    sessionVariables = {
      TZ = "UTC";
      PIPX_HOME = "$HOME/.local/pipx";
      PIPX_BIN_DIR = "$HOME/.local/bin";
      DEVCELL_NIXHOME_PATH = "$HOME/dev/devcell-sh/home";
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

  # Public half of the 1Password-managed ed25519 key. With IdentitiesOnly=yes an
  # IdentityFile pointing at a .pub makes the agent offer only that key, so the
  # YubiKey SK key is never tried (no touch prompt) for hosts that pin it.
  home.file.".ssh/id_ed25519_1password.pub".text =
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAgqQTngjpLZYFBBBu2z7N5s7+LCUjWZCfqkx5UrblKT dmitry@1password\n";

  # OpenCommit (oco) — AI commit messages via OpenRouter
  home.file.".opencommit".text = ''
    OCO_AI_PROVIDER=openrouter
    OCO_API_URL=https://openrouter.ai/api/v1
    OCO_MODEL=~deepseek/deepseek-flash-latest
    OCO_TOKENS_MAX_INPUT=128000
    OCO_TOKENS_MAX_OUTPUT=1000
    OCO_EMOJI=false
    OCO_LANGUAGE=en
    OCO_PROMPT_MODULE=conventional-commit
    OCO_ONE_LINE_COMMIT=false
    OCO_DESCRIPTION=false
    OCO_GITPUSH=true
  '';

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
        setDockerHost = true;
        settings = {
          cpu = 8;
          memory = 24;
          disk = 120;
          rootDisk = 20; # restart does not apply start's default for omitted settings
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

  # The home-manager colima module gives the launchd agent a nix-only PATH.
  # Colima gates nestedVirtualization (and rosetta) on host checks that shell
  # out to /usr/sbin/system_profiler and /usr/bin/pgrep; when those are not
  # found the check fails silently and the setting never reaches lima.yaml.
  # Keep the module's PATH and append the macOS system dirs.
  launchd.agents = lib.optionalAttrs pkgs.stdenv.isDarwin (
    let
      c = config.services.colima;
      modulePath = lib.makeBinPath [
        c.package
        c.perlPackage
        c.dockerPackage
        c.sshPackage
        c.coreutilsPackage
        c.curlPackage
        c.bashPackage
        c.kubectlPackage
        pkgs.darwin.DarwinTools
      ];
    in {
      colima-default.config.EnvironmentVariables.PATH =
        lib.mkForce "${modulePath}:/usr/sbin:/usr/bin:/bin:/sbin";
    }
  );

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
    # Primary binary `devcell`, `cell` kept as an alias. Mirrors the intended
    # upstream rename; drop this override once devcell-sh/devcell ships it.
    package = inputs.devcell.packages.${pkgs.stdenv.hostPlatform.system}.cell.overrideAttrs (old: {
      pname = "devcell";
      postInstall = ''
        mv $out/bin/cmd $out/bin/devcell
        ln -s devcell $out/bin/cell
      '';
      meta = old.meta // { mainProgram = "devcell"; };
    });
    cell.default_command = "claude";
    env = {
      CLAUDE_CODE_DISABLE_AGENT_VIEW = "1";
      CLAUDE_CODE_DISABLE_BACKGROUND_TASKS = "1";
      CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN = "1";
      CLAUDE_CODE_DISABLE_MOUSE = "1";
      CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
    };
    # Schema: [cell] volumes = ["/host", "/host:/container", "/host:/container:ro"].
    # Top-level [[volumes]] mount = … is deprecated.
    # macOS paths only; Linux hosts (nixie) get no extra volumes for now.
    cell.volumes = lib.optionals pkgs.stdenv.isDarwin [
      "/Users/dmitry/dev/dimmkirr/skills/"
      "/Users/dmitry/dev/kirr/skills/"
      "/Users/dmitry/dev/mad/skills/"
      "/Users/dmitry/dev/ptc/skills/"
      "/Users/dmitry/dev/kiwa/skills/"
      "/Users/dmitry/dev/fam/skills/"
      "/Users/dmitry/dev/nmd/private-skills/"
      "/Users/dmitry/dev/hazelops/skills/"
      "/Users/dmitry/.cache:/home/dmitry/.cache"
    ];
    # Layered on top of Claude Code's built-in system prompt (--append-system-prompt-file).
    # Do NOT use llm.system_prompt / prompt here — that REPLACES the built-in prompt entirely.
    appendPrompt = ''
      # Rules

      - When spawning sub-agents, match the model to the task's cognitive demand. Use Haiku or Sonnet for simple tasks (summarizing, tool calls, lookups, formatting). Reserve Fable or Opus for tasks that need deep reasoning (architecture decisions, complex debugging, nuanced code review). Default to Sonnet when unsure.
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
      - If the playwright MCP tool is also unavailable or failing, fall back to curl via the Bash tool.

      # Scripts and Tools you create

      - Any scripts you need to create for executing actions (e.g. Python scripts, shell scripts, temporary wrappers) must reside in `.scratch/tools/<task-you-needed-it-for>/<tool-name>.<ext>`. This structure keeps the repository clean from interim scripts and tools.
      - Any screenshots taken during visual QA should go into `.scratch/screenshots/<dateISO>/<datetimeISO>-<ticket|purpose>-<image-content-desc>-<index>.<ext>`.
      - Any illustrations or generated images should go into `.scratch/illustrations/<dateISO>/<datetimeISO>-<ticket|purpose>-<image-content-desc>-<index>.<ext>`.

      # Product research and specifications

      The `.product/` directory holds product (non-code) research and specifications about the product. Files cross-link each other via relative markdown links.

      Every `.product/*.md` file (except `research/`) has two parts, separated by a `---` line:

      1. Desired state: the ideal we aspire to, kept current. Rewrite it in place, don't append.
      2. Changes needed: an append-only log, one `## <dateISO>: <change title>` section per session. Each entry lists the gap between the desired state and reality, with what to change and where.

      ```markdown
      # Landing
      ## Voice rules
      ...
      ## Headline
      ...

      ---

      ## 2026-09-09: Needs README Copy Update
      ...
      ## 2026-09-10: Needs Website Copy Update
      ...
      ```

      - `.product/research/<dateISOUTC>/<researchResultFile>.md`: raw research results, one file per research question.
      - `.product/FEATURES.md`: what a person downloading or using the product sees. Follows strict 2026 marketing: no long list of equally weighted features. Exactly 3 killer features, then 2 additional ones (5 well-defined features total). Links to the personas each feature serves.
      - `.product/LANDING.md`: what a visitor gets on the landing (README.md or website): headline, value proposition, killer features, social proof, call to action. Derived from and links to `FEATURES.md` and `PERSONAS.md`.
      - `.product/VOCABULARY.md`: dry list of product terminology (term + one-line definition) and rules on terms and phrasings to avoid. No marketing prose. All other `.product/` files and product copy follow it.
      - `.product/PERSONAS.md`: the product's personas. Links to the features that matter to each persona.
      - `.product/COMPETITION.md`: top 3 direct (1:1) competitors and 10 market-adjacent products in total (including those 3), with each one's strong sides.
      - `.product/MARKET.md`: market conditions, demands and requirements, backed by data and source links.
      - `.product/launches/<dateISO>/<platform>.md`: launches (marketing campaigns) per platform. Link supporting data to the other `.product/` files.
    '';
  };
}
# Inspired by
# https://github.com/evantravers/dotfiles/blob/4e9bc7a25ebc73389130567ab46b9cab78b5783e/home-manager/home.nix
# https://github.com/the-nix-way/nome
# https://github.com/Th0rgal/horus-nix-home
# https://github.com/Yumasi/nixos-home/blob/main/zsh.nix
