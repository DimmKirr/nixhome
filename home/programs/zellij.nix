# Zellij — home-manager config. Reference current as of zellij 0.44.3.
#
# Two layers of options:
#   1. home-manager module options (programs.zellij.*) — the attrs returned
#      directly below (enable, package, themes, layouts, integrations, …).
#   2. zellij's own config.kdl knobs — go inside `settings`, which is rendered
#      to ~/.config/zellij/config.kdl via lib.hm.generators.toKDL.
#
# Only the uncommented lines are active; everything commented shows the option,
# its zellij default, and a one-line note so you can uncomment to enable.
# Dump the upstream defaults any time with: `zellij setup --dump-config`.
{pkgs, ...}: let
  # Session cycler: sorted next/prev via `zellij action switch-session`.
  # Bound to Alt+Tab / Shift+Alt+Tab below. Shares the raw keystroke
  # with tmux's `bind -n M-Tab switch-client -n` so Ghostty sends the
  # same Alt+Tab to whichever multiplexer is active.
  zellij-cycle-session = pkgs.writeShellApplication {
    name = "zellij-cycle-session";
    runtimeInputs = [pkgs.zellij pkgs.coreutils];
    text = builtins.readFile ../scripts/zellij-cycle-session.sh;
  };

  # Minimal nvim config for EditScrollback copy mode.
  # Opens scrollback at the bottom; Alt+y in visual mode copies selection
  # to system clipboard and exits back to zellij.
  zellij-copy-vim = pkgs.writeText "zellij-copy.vim" ''
    vnoremap <M-y> "+y<Esc>:q!<CR>
    normal G
  '';

  # Nix-pinned drop-in replacement for the stock `zellij:tab-bar` plugin that
  # renders tab indices (<1>, <2>, …) alongside names — stock tab-bar can't
  # (upstream zellij#3591 still open). Pinned to v0.44.3 to match the zellij
  # version above; fetched to the Nix store rather than pulled from "latest" at
  # runtime, so it stays reproducible/offline-safe. Bump tag + hash together.
  tab-bar-indexed = pkgs.fetchurl {
    url = "https://github.com/ivoronin/zellij-tab-bar-indexed/releases/download/v0.44.3/tab-bar.wasm";
    hash = "sha256-XMtxnpRheow9+u5GFbgFg5sFVkI95OO1xCHJ94lCBF8=";
  };
in {
  enable = true;

  ## ── home-manager module options ───────────────────────────────────────
  # package = pkgs.zellij;              # default: pkgs.zellij (stable). Set to pin a channel.

  # Shell integration is OFF on purpose. home-manager defaults
  # enableZshIntegration to true, which injects
  # `eval "$(zellij setup --generate-auto-start zsh)"` into zshrc and
  # launches zellij on every interactive shell. tmux is the primary
  # multiplexer here (see ../programs/tmux.nix), so autostart would
  # nest/conflict. Start it explicitly with `zellij` when wanted.
  enableZshIntegration = false;
  # enableBashIntegration  = false;    # default false — autostart eval in bashrc
  # enableFishIntegration  = false;    # default false — autostart eval in fish config
  # attachExistingSession  = false;    # default false — on autostart, attach to existing session instead of new (needs an integration on)
  # exitShellOnExit        = false;    # default false — close the shell when zellij exits (needs an integration on)

  # layouts.<name> = { … };            # → ~/.config/zellij/layouts/<name>.kdl (attrset/path/string). Run with `zellij --layout <name>`.
  # themes.<name>  = { … };            # → ~/.config/zellij/themes/<name>.kdl  (define a custom palette; then set settings.theme)
  # extraConfig = '' '';               # raw KDL appended verbatim to config.kdl — use for keybinds (see note at bottom)

  # Custom "bottom" layout: tab bar moved to the BOTTOM (the built-in
  # "default" layout puts tab-bar on top). Panes stack top→bottom in
  # declaration order, so `children` first pushes both bars below the
  # content — tab-bar (1 line) then status-bar / keybind hints (2 lines).
  # Activated via settings.default_layout = "bottom" below.
  # Renders to ~/.config/zellij/layouts/bottom.kdl.
  layouts.bottom = ''
    layout {
        default_tab_template {
            children
            pane size=1 borderless=true {
                plugin location="file:${tab-bar-indexed}" {
                    show_tab_indices true
                }
            }
            pane size=2 borderless=true { plugin location="zellij:status-bar"; }
        }
    }
  '';

  # settings → ~/.config/zellij/config.kdl. Active overrides first, then the
  # full commented catalog of every config.kdl option.
  settings = {
    ## ── active overrides (differ from zellij defaults) ──────────────────
    # Match the tmux Dracula preset (theme.nix preset = "dracula").
    # "dracula" is a built-in zellij theme, so colors stay consistent
    # across multiplexers without hand-maintaining a palette.
    theme = "dracula";

    # "classic" tab bar on top + status bar on bottom. The custom "bottom"
    # layout above is still available on demand via `zellij --layout bottom`;
    # "compact" gives a single-line bar.
    default_layout = "classic";

    # Default is 10000; bump to match tmux's historyLimit = 50000.
    scroll_buffer_size = 50000;

    # Default is square corners.
    ui.pane_frames.rounded_corners = true;

    ## ── startup / general (commented = zellij default shown) ────────────
    # default_shell = "zsh";           # default: $SHELL — shell for new panes
    # default_cwd = "";                # default: cwd — override working dir for new panes
    # default_mode = "normal";         # normal | locked | … — mode zellij starts in
    # on_force_close = "detach";       # detach (default) | quit — on SIGTERM/SIGINT/SIGHUP
    # auto_layout = true;              # default true — auto-arrange panes into preset layouts
    # stacked_resize = true;           # default true — stack panes when resizing past a threshold
    # show_release_notes = true;       # default true — show release notes on first run of a new version

    ## ── appearance / UI ─────────────────────────────────────────────────
    # pane_frames = true;              # default true — draw frames around panes (top-level toggle; distinct from ui.pane_frames styling)
    # ui.pane_frames.hide_session_name = false;  # default false — hide session name in the frame
    # simplified_ui = false;           # default false — ask plugins for an arrow-font-free UI
    # styled_underlines = true;        # default true — colored/curly underlines (undercurl); disable on unsupported terminals
    # theme_dir = "/path/to/themes";   # default: ~/.config/zellij/themes — where zellij looks for theme files
    # layout_dir = "/path/to/layouts"; # default: ~/.config/zellij/layouts — where zellij looks for layout files

    ## ── mouse / clipboard ────────────────────────────────────────────────
    # mouse_mode = true;               # default true — mouse support (can interfere with terminal text copy)
    # advanced_mouse_actions = true;   # default true — hover effects + pane grouping
    # mouse_hover_effects = true;      # default true — frame highlight + help text on hover
    # copy_on_select = true;           # default true — auto-copy selection on mouse release
    # copy_clipboard = "system";       # system (default) | primary — destination buffer (ignored if copy_command set)
    # copy_command = "pbcopy";         # unset by default; pbcopy (macOS) / wl-copy (wayland) / "xclip -selection clipboard" (x11)
    # osc8_hyperlinks = true;          # default true — emit OSC8 terminal hyperlinks

    ## ── scrollback / session serialization ──────────────────────────────
    scrollback_editor = "nvim -u ${zellij-copy-vim}";
    # scrollback_editor = "nvim";      # default: $EDITOR/$VISUAL — editor for "edit scrollback"
    # session_serialization = true;    # default true — persist sessions to cache for resurrection
    # serialize_pane_viewport = false; # default false — also serialize pane viewport contents
    # scrollback_lines_to_serialize = 10000;  # default: full scrollback (0) — lines kept when serialize_pane_viewport=true
    # disable_session_metadata = false;# default false — stop writing session metadata to disk
    # post_command_discovery_hook = "";# unset — post-process discovered RESURRECT_COMMAND on session resurrect

    ## ── terminal features / sessions ─────────────────────────────────────
    # support_kitty_keyboard_protocol = true;  # default true (if terminal supports it) — enhanced Kitty keyboard protocol
    # mirror_session = false;          # default false — multi-user: mirror one cursor (true) vs per-user cursors (false)
    # client_async_worker_tasks = 4;   # default 4 — async worker tasks per web client (0 = physical CPU cores)
    # web_client.font = "monospace";   # default "monospace" — font used by the web client

    ## ── web server / browser sharing (off by default) ───────────────────
    # web_server = false;              # default false — run a local web server (http://127.0.0.1:8082) to create/attach sessions
    # web_sharing = "off";             # off (default) | on | disabled — allow sharing terminal sessions via the web server
    # web_server_ip = "127.0.0.1";     # default 127.0.0.1 — listen address
    # web_server_port = 8082;          # default 8082 — listen port
    # enforce_https_for_localhost = false;  # default false — force HTTPS even on localhost (always enforced off-localhost)
    # web_server_cert = "/path/cert.pem";   # unset — TLS cert for HTTPS
    # web_server_key  = "/path/key.pem";    # unset — TLS key for HTTPS

    ## ── keybinds / plugins ───────────────────────────────────────────────
    # keybinds/plugins/load_plugins are deeply nested KDL. Two ways to set them:
    #   1. settings.keybinds via the toKDL _props/_args/_children encoding
    #      (see the module example: keybinds._props.clear-defaults = true; …)
    #   2. the module's `extraConfig` option (raw KDL appended to config.kdl) —
    #      usually easier to read for full keybind blocks. Example:
    #        extraConfig = ''
    #          keybinds {
    #            normal { bind "Alt n" { NewPane; } }
    #          }
    #        '';
  };

  # Raw KDL appended to config.kdl — easier than the toKDL encoding for
  # complex nested keybind blocks. Layered on top of zellij defaults
  # (NOT clear-defaults) so all built-in tmux-mode bindings stay active.
  extraConfig = ''
    keybinds {
      // ── No-prefix bindings ──────────────────────────────────────────
      shared_except "locked" {
        // Tab cycling — Alt+[ / Alt+] (matches tmux `bind -n M-[/M-]`).
        // Requires Kitty keyboard protocol for unambiguous Alt+[ (ESC+[
        // is CSI prefix in legacy mode). Ghostty + zellij both support it.
        bind "Alt [" { GoToPreviousTab; }
        bind "Alt ]" { GoToNextTab; }

        // Tab cycling — Shift+Left / Shift+Right
        // (matches tmux `bind -n S-Left/S-Right`)
        bind "Shift Left"  { GoToPreviousTab; }
        bind "Shift Right" { GoToNextTab; }

        // Session cycling — Alt+Tab / Shift+Alt+Tab. Same raw keystroke
        // as tmux's `bind -n M-Tab switch-client -n` — Ghostty sends
        // Alt+Tab to whichever multiplexer is active.
        bind "Alt Tab" {
          Run "${zellij-cycle-session}/bin/zellij-cycle-session" "next" {
            close_on_exit true
          }
        }
        bind "Shift Alt Tab" {
          Run "${zellij-cycle-session}/bin/zellij-cycle-session" "prev" {
            close_on_exit true
          }
        }
      }

      // ── Scroll mode additions ───────────────────────────────────────
      scroll {
        // CUTOVER: remove — switch Ghostty cmd+f to \x02\x2F (prefix+/)
        // Backwards compat: Ghostty cmd+f sends prefix+[+? which enters
        // Scroll mode (built-in [) then hits this binding. In tmux ? is
        // backward search; here it enters zellij search. Both work.
        bind "?" { SwitchToMode "EnterSearch"; SearchInput 0; }
      }

      // ── Tmux prefix-key mode additions ──────────────────────────────
      // Extends built-in tmux mode defaults — all stock bindings
      // (c, d, %, ", z, x, arrows, hjkl, 1-9, [, etc.) stay active.
      tmux {
        // Session picker — prefix+T (replaces tmux fzf picker)
        bind "T" {
          LaunchOrFocusPlugin "session-manager" {
            floating true
            move_to_focused_tab true
          };
          SwitchToMode "Normal";
        }

        // CUTOVER: remove w — switch Ghostty cmd+k to \x02\x54 (prefix+T)
        // Choose-tree equivalent — prefix+w. Ghostty cmd+k sends
        // prefix+w+/ ; the "/" is absorbed by the plugin's filter input.
        bind "w" {
          LaunchOrFocusPlugin "session-manager" {
            floating true
            move_to_focused_tab true
          };
          SwitchToMode "Normal";
        }

        // Kill session — prefix+X (matches tmux's kill-session)
        bind "X" { Quit; }

        // Forward search — prefix+/
        bind "/" { SwitchToMode "EnterSearch"; SearchInput 0; }

        // EditScrollback — prefix+e (skip entering Scroll mode first).
        // Opens pane scrollback in nvim with zellij-copy.vim config;
        // Alt+y in visual mode copies to clipboard and exits.
        bind "e" { EditScrollback; SwitchToMode "Normal"; }

        // Session prev/next — prefix+( / prefix+)
        // (stock tmux bindings, routed through cycle script)
        bind "(" {
          Run "${zellij-cycle-session}/bin/zellij-cycle-session" "prev" {
            close_on_exit true
          };
          SwitchToMode "Normal";
        }
        bind ")" {
          Run "${zellij-cycle-session}/bin/zellij-cycle-session" "next" {
            close_on_exit true
          };
          SwitchToMode "Normal";
        }
      }
    }
  '';
}
