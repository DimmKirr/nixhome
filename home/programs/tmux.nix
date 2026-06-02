{pkgs, lib ? pkgs.lib, ...}: let

  # Universal tmux theming framework — palettes, widgets, composer.
  # User-facing knob lives in ./theme.nix.
  #
  # nerdFonts = false (default for portability) — uses BMP-Unicode glyphs that
  # render on every system font: ☁ ⛅ ☀ ❄ ⚡ etc. No drift between tmux's
  # column accounting and the terminal's actual rendering, so SSH-in from
  # Termius/JuiceSSH/PuTTY works without the phantom-bar / column-overflow
  # issues Nerd Font PUA glyphs cause (PUA chars have wcwidth()=1 but
  # render as 2-cell icons → status-right under-counted → layout corruption
  # on narrow clients).
  #
  # Flip to `true` ONLY if every client that attaches has a Nerd Font:
  #   nerdFonts = true;  # → rich icons (󰖐 󰖕 󰖙 …) + powerline separators
  theme     = import ./theme.nix {
    inherit lib;
    preset    = "dracula";
    nerdFonts = false;
  };
  framework = import ./tmux { inherit lib pkgs theme; };

  # Silent auto-save tick. Embedded in status-right so it fires on every
  # status refresh; only runs tmux-snapshot when @snapshot-save-interval
  # minutes have elapsed since @snapshot-last-save. Must emit nothing.
  snapshotTick = pkgs.writeShellScript "tmux-snapshot-tick" ''
    interval_min=$(tmux show -gqv @snapshot-save-interval)
    [ -z "$interval_min" ] && interval_min=10
    interval=$((interval_min * 60))

    last=$(tmux show -gqv @snapshot-last-save)
    [ -z "$last" ] && last=0

    now=$(date +%s)
    if [ "$((now - last))" -ge "$interval" ]; then
      if tmux-snapshot save-all >/dev/null 2>&1; then
        tmux set -g @snapshot-last-save "$now"
      fi
    fi
  '';

  # Restore counterpart for prefix + Ctrl-r. Loads any session in the
  # `.session-order` manifest that isn't currently live — never touches
  # existing sessions, so accidental presses are safe. Reports count via
  # tmux display-message at the end.
  snapshotRestoreCurrent = pkgs.writeShellScript "tmux-snapshot-restore-current" ''
    s="$1"
    DIR="$HOME/.config/tmuxp"
    yaml="$DIR/$s.yaml"
    if [ ! -f "$yaml" ]; then
      tmux display-message "tmux-snapshot: no snapshot for $s"
      exit 0
    fi
    # tmux normalizes session names — dots become underscores. Use only
    # underscore-safe chars so "$tmp" matches what tmux actually stores,
    # otherwise the cleanup `kill-session -t "$tmp"` finds nothing and
    # the bak session lingers.
    tmp="''${s}_bak_$$"
    tmux rename-session -t "$s" "$tmp" || {
      tmux display-message "tmux-snapshot: rename failed for $s"; exit 1; }
    if tmux-snapshot load "$yaml" >/dev/null 2>&1; then
      tmux switch-client -t "$s" 2>/dev/null
      tmux kill-session -t "$tmp" 2>/dev/null
      tmux display-message "tmux-snapshot: restored $s from snapshot"
    else
      tmux rename-session -t "$tmp" "$s"
      tmux display-message "tmux-snapshot: FAILED to restore $s — kept original"
    fi
  '';

  snapshotRestore = pkgs.writeShellScript "tmux-snapshot-restore" ''
    DIR="$HOME/.config/tmuxp"
    if [ ! -d "$DIR" ]; then
      tmux display-message "tmux-snapshot: no tmuxp dir at $DIR"
      exit 0
    fi

    manifest="$DIR/.session-order"
    if [ -f "$manifest" ]; then
      sessions=$(cat "$manifest")
    else
      # Fallback: every yaml in the dir, sorted by mtime (newest first).
      sessions=$(ls -t "$DIR"/*.yaml 2>/dev/null | sed 's|.*/||; s|\.yaml$||')
    fi

    restored=0
    skipped=0
    failed=0
    for s in $sessions; do
      yaml="$DIR/$s.yaml"
      [ -f "$yaml" ] || continue
      if tmux has-session -t "$s" 2>/dev/null; then
        skipped=$((skipped + 1))
        continue
      fi
      if tmux-snapshot load "$yaml" >/dev/null 2>&1; then
        restored=$((restored + 1))
      else
        failed=$((failed + 1))
      fi
    done

    msg="tmux-snapshot: restored $restored, skipped $skipped (already live)"
    [ "$failed" -gt 0 ] && msg="$msg, FAILED $failed"
    tmux display-message "$msg"
  '';

  cellConnect = pkgs.writeShellScript "cell-connect" ''
    proto="$1"
    wname="$2"
    wid="$3"
    # Prefer explicit binding stored on the window, fall back to name grep
    app=""
    if [ -n "$wid" ]; then
      app=$(tmux show-options -wqv -t "$wid" @cell-app 2>/dev/null)
    fi
    if [ -z "$app" ]; then
      app=$(cell "$proto" --list --format=json 2>&1 | jq -r '.[].app_name' | grep -i "^$wname" | head -1)
    fi
    if [ -n "$app" ]; then
      cell "$proto" "$app" >/dev/null 2>&1
    else
      tmux display-message "$(echo "$proto" | tr a-z A-Z): no app matching $wname — use 'Set Cell App' to bind manually"
    fi
  '';

  # Loaded as a tmux plugin (registers itself + provides defaults for
  # @now-playing-* runtime options that music.sh reads). NOTE: pinned to
  # master, while widgets/now-playing.nix pins the feature/add-media-control
  # branch for music.sh — different commits on purpose. The feature branch
  # has the "empty output when no player" fix the widget needs; the outer
  # plugin's master is fine for the option-defaults role.
  now-playing = pkgs.tmuxPlugins.mkTmuxPlugin {
    pluginName  = "tmux-now-playing";
    version     = "unstable-2025-09-17";
    rtpFilePath = "now-playing.tmux";
    src = pkgs.fetchFromGitHub {
      owner = "DimmKirr";
      repo  = "tmux-now-playing";
      rev   = "5077d4e103e63ef1b3a9cf54e634d3900eafd02f";
      sha256 = "hXh4zvCUitFsal3FWLuumbuDn85cCQWIDI/YNJtlKxE=";
    };
  };

  # fzf-based session picker — replaces the upstream `andersondanilo/tmuxp-fzf`
  # plugin which shelled out to raw `tmuxp load` and bypassed our post-load
  # fixups (@label, pane_title, mirrored-preset re-apply, @layout-6..9).
  # Same UX, same key (prefix + T), but routed through tmux-snapshot.
  snapshotPicker = pkgs.writeShellScript "tmux-snapshot-picker" ''
    set -eu
    DIR="$HOME/.config/tmuxp"
    if [ ! -d "$DIR" ]; then
      tmux display-message "tmux-snapshot: no tmuxp dir at $DIR"
      exit 0
    fi
    name=$(ls -1 "$DIR"/*.yaml 2>/dev/null \
             | xargs -n1 basename \
             | sed 's/\.yaml$//' \
             | ${pkgs.fzf}/bin/fzf --prompt='session> ' --reverse --height=100%)
    [ -n "$name" ] || exit 0
    if tmux has-session -t "$name" 2>/dev/null; then
      tmux switch-client -t "$name"
    elif tmux-snapshot load "$name" >/dev/null 2>&1; then
      tmux switch-client -t "$name" 2>/dev/null
      tmux display-message "tmux-snapshot: loaded and switched to $name"
    else
      tmux display-message "tmux-snapshot: FAILED to load $name"
    fi
  '';
in {
  enable = true;

  #    shortcut = "q";
  #    escapeTime = 10;
  keyMode = "vi";

  terminal = "tmux-256color";
  historyLimit = 50000;
  # TODO: Try https://github.com/sainnhe/tmux-fzf
  baseIndex = 1;
  extraConfig = ''


        set -g default-shell "/run/current-system/sw/bin/zsh"
        set -g default-command "/run/current-system/sw/bin/zsh"

        # Enable mouse support
        set -g mouse on

        # Window and Pane index starts with 1
        set -g base-index 1
        set -g pane-base-index 1

        # Faster windows switching
        bind -n M-[ previous-window
        bind -n M-] next-window

        # Alternative: Use Shift+Left/Right arrows (no prefix needed)
        bind -n S-Left previous-window
        bind -n S-Right next-window

        # iPad/Termius friendly: Ctrl+, and Ctrl+.
        bind -n C-, previous-window
        bind -n C-. next-window

        # Move window left/right and follow it (Ctrl+Shift+Arrow)
        bind-key -n C-S-Left swap-window -t -1\; select-window -t -1
        bind-key -n C-S-Right swap-window -t +1\; select-window -t +1

        # Send the bracketed paste mode when pasting
        bind ] paste-buffer -p

        # Kill session
        bind-key X kill-session

        set-option -g set-titles on

        bind C-y run-shell ' \
          ${pkgs.tmux}/bin/tmux show-buffer > /dev/null 2>&1 \
          && ${pkgs.tmux}/bin/tmux show-buffer | ${pkgs.xsel}/bin/xsel -ib'

        # Force true colors
        set-option -ga terminal-overrides "*:Tc"

        set-option -g mouse on
        set-option -g focus-events on


        # Stay in same directory when split
        bind % split-window -h -c "#{pane_current_path}"
        bind '"' split-window -v -c "#{pane_current_path}"

        # Two-key sequence for windows 10-19
        bind - switch-client -Tabove9
        bind -Tabove9 0 select-window -t:10
        bind -Tabove9 1 select-window -t:11
        bind -Tabove9 2 select-window -t:12
        bind -Tabove9 3 select-window -t:13
        bind -Tabove9 4 select-window -t:14
        bind -Tabove9 5 select-window -t:15
        bind -Tabove9 6 select-window -t:16
        bind -Tabove9 7 select-window -t:17
        bind -Tabove9 8 select-window -t:18
        bind -Tabove9 9 select-window -t:19

        #######################
        ######## Panes ########
        #######################
        # Enable Pane name
        set -g pane-border-status top
        # Subtle line + muted text — matches original Dracula's quiet pane
        # divider (overlay_2 = #6272A4 "comment" grey-blue). Active pane
        # picks up the brighter mauve so it's still visually identifiable
        # without shouting.
        set -g pane-border-style        'fg=${theme.palette.overlay_0}'
        set -g pane-active-border-style 'fg=${theme.palette.overlay_2}'
        # Layout: "<index> <@label> | <pane_title>".
        #   @label      — custom name set via "Rename Pane" (prefix + > → n)
        #   pane_title  — OSC-set terminal title (Claude's "✳ Claude …",
        #                 starship's shortened cwd, vim's filename, etc.)
        # The pane_title slot is suppressed when it equals #{host_short} —
        # tmux initializes new panes to the hostname, so this hides the
        # uninformative default until something explicitly sets a title.
        # Truncated to 40 chars so the border row width stays stable on
        # resize (prevents shifting from MC's long "mc [user@host]:cwd").
        # Text uses overlay_2 (muted) instead of white — pre-framework
        # Dracula rendered border text in the comment-grey shade, not bright
        # white. Keeps the divider quiet in peripheral vision.
        set -g pane-border-format '#{pane_index} #{?@label,#[fg=${theme.palette.overlay_2}]#{@label}#[default] | ,}#{?#{!=:#{pane_title},#{host_short}},#[fg=${theme.palette.overlay_2}]#{=40:pane_title}#[default],}'

        # Change Pane Menu with rename
        bind-key -n MouseDown3Pane display-menu -T "Pane Menu" -x R -y P \
            "Copy Line"       l "copy-mode" \
            "" "" "" \
            "Horizontal Split" h "split-window -v" \
            "Vertical Split"  v "split-window -h" \
            "" "" "" \
            "Swap Up"         u "swap-pane -U" \
            "Swap Down"       d "swap-pane -D" \
            "Swap Marked"     M "swap-pane -d -t '{marked}'" \
            "#{?pane_marked_set,,-}Join to Marked (V)" j "join-pane -v -t '{marked}'" \
            "#{?pane_marked_set,,-}Join to Marked (H)" J "join-pane -h -t '{marked}'" \
            "" "" "" \
            "Kill"            X "kill-pane" \
            "Respawn"         R "respawn-pane -k" \
            "Mark"            m "select-pane -m" \
            "Zoom"            z "resize-pane -Z" \
            "Rename Pane" n "select-pane -t '#{mouse_pane}'\; command-prompt -I '#{@label}' 'set -p @label \"%%\"; refresh-client'" \
            "Clear Label" N "select-pane -t '#{mouse_pane}'\; set -p @label \"\"\; refresh-client" \
            "" "" "" \
            "Connect to VNC" V "run-shell '${cellConnect} vnc \"#{window_name}\" #{window_id}'" \
            "Connect to RDP" r "run-shell '${cellConnect} rdp \"#{window_name}\" #{window_id}'" \
            "Set Cell App"   a "command-prompt -I '#{@cell-app}' -p 'Cell app name:' 'set -w -t #{window_id} @cell-app \"%%\"'"


        # Override default "prefix + ." menu
        bind-key > display-menu -T "#[align=centre]Pane Menu" -x W -y W \
          "Horizontal Split" h "split-window -h -c '#{pane_current_path}'" \
          "Vertical Split"   v "split-window -v -c '#{pane_current_path}'" \
          "" "" "" \
          "Swap Up"          u "swap-pane -U" \
          "Swap Down"        d "swap-pane -D" \
          "Swap Marked"      m "swap-pane -d -t '{marked}'" \
          "#{?pane_marked_set,,-}Join to Marked (V)" j "join-pane -v -t '{marked}'" \
          "#{?pane_marked_set,,-}Join to Marked (H)" J "join-pane -h -t '{marked}'" \
          "" "" "" \
          "Kill"             X "kill-pane" \
          "Respawn"          R "respawn-pane -k" \
          "Mark"             M "select-pane -m" \
          "Zoom"             z "resize-pane -Z" \
          "" "" "" \
          "Rename Pane" n "command-prompt -I '#{@label}' 'set -p @label \"%%\"; refresh-client'" \
          "Clear Label" N "set -p @label \"\"; refresh-client" \
          "" "" "" \
          "Connect to VNC" V "run-shell '${cellConnect} vnc \"#{window_name}\" #{window_id}'" \
          "Connect to RDP" r "run-shell '${cellConnect} rdp \"#{window_name}\" #{window_id}'" \
          "Set Cell App"   a "command-prompt -I '#{@cell-app}' -p 'Cell app name:' 'set -w -t #{window_id} @cell-app \"%%\"'"

        # Custom Session Menu (right-click on status left / session name)
        bind-key -n MouseDown3StatusLeft display-menu -T "#[align=centre]Session Menu" -x M -y W \
          "Next"             n "switch-client -n" \
          "Previous"         p "switch-client -p" \
          "" "" "" \
          "Renumber"         N "move-window -r" \
          "Rename"           r "command-prompt -I '#S' 'rename-session -- \"%%\"'" \
          "" "" "" \
          "New Session"      s "new-session" \
          "New Window"       w "new-window" \
          "" "" "" \
          "Kill Session"     X "kill-session"

        # Custom Window/Tab Menu (right-click on window in status bar)
        bind-key -n MouseDown3Status display-menu -T "#[align=centre]Window Menu" -t = -x W -y W \
          "Swap Left"        l "swap-window -t:-1; select-window -t:-1" \
          "Swap Right"       r "swap-window -t:+1; select-window -t:+1" \
          "Swap Marked"      s "swap-window" \
          "" "" "" \
          "New After"        a "new-window -a" \
          "New at End"       e "new-window" \
          "" "" "" \
          "Respawn"          R "respawn-window -k" \
          "Mark"             m "select-window -m" \
          "Rename"           n "command-prompt -I '#W' 'rename-window -- \"%%\"'" \
          "Kill"             X "kill-window"

        #######################
        ####### Layouts #######
        #######################
        # Layout menu: prefix + S
        bind S display-menu -T "#[align=centre]Layouts" -x C -y C \
          "Even Horizontal"           1 "select-layout even-horizontal" \
          "Even Vertical"             2 "select-layout even-vertical" \
          "Main Horizontal"           3 "select-layout main-horizontal" \
          "Main Vertical"             4 "select-layout main-vertical" \
          "Tiled"                     5 "select-layout tiled" \
          "Main Horizontal Mirrored"  h "run-shell 'tmux set-window-option main-pane-height 2; tmux select-layout main-horizontal-mirrored'" \
          "Main Vertical Mirrored"    v "select-layout main-vertical-mirrored" \
          "Spread Even"               e "select-layout -E" \
          "" "" "" \
          "Save to slot 6"     S "run-shell 'tmux set -g @layout-6 \"#{window_layout}\"; tmux display \"Saved to 6\"'" \
          "Save to slot 7"     s "run-shell 'tmux set -g @layout-7 \"#{window_layout}\"; tmux display \"Saved to 7\"'" \
          "Save to slot 8"     D "run-shell 'tmux set -g @layout-8 \"#{window_layout}\"; tmux display \"Saved to 8\"'" \
          "Save to slot 9"     d "run-shell 'tmux set -g @layout-9 \"#{window_layout}\"; tmux display \"Saved to 9\"'" \
          "" "" "" \
          "Restore slot 6"     6 "run-shell 'tmux select-layout \"$(tmux show -gv @layout-6)\"'" \
          "Restore slot 7"     7 "run-shell 'tmux select-layout \"$(tmux show -gv @layout-7)\"'" \
          "Restore slot 8"     8 "run-shell 'tmux select-layout \"$(tmux show -gv @layout-8)\"'" \
          "Restore slot 9"     9 "run-shell 'tmux select-layout \"$(tmux show -gv @layout-9)\"'"

        # Direct restore keybindings (M-8, M-9, M-0 are free; M-6, M-7 taken by built-in mirrored layouts)
        bind M-8 run-shell 'tmux select-layout "$(tmux show -gv @layout-8)"'
        bind M-9 run-shell 'tmux select-layout "$(tmux show -gv @layout-9)"'

        # Toggle main pane (pane 0) height between expanded (95%) and collapsed (5%)
        # z = zoom active pane (built-in), Z = toggle main pane size
        bind Z run-shell '\
          cur="$(tmux show-window-option -v main-pane-height 2>/dev/null)"; \
          if [ "$cur" = "95%" ]; then \
            tmux set-window-option main-pane-height 5%\; select-layout main-horizontal; \
          else \
            tmux set-window-option main-pane-height 95%\; select-layout main-horizontal; \
          fi'

        #######################
        ##### Hubstaff ######
        #######################
        # Auto-switch Hubstaff project when switching tmux sessions
        set-hook -g client-session-changed 'run-shell "/bin/sh ${../scripts/tmux/hs-hook.sh} #{session_name} #{client_name}"'

        ###############################
        ##### Framework Status Bar ####
        ###############################
        # 2-row status bar — top row shows session + windows, bottom row shows
        # framework status-right modules. Matches the original Dracula layout.
        set -g status              2
        set -g status-style        'bg=${theme.palette.surface_2},fg=${theme.palette.fg}'
        # Match status-bg so command-prompts/menus don't pop in tmux's
        # default yellow-on-black. (Ticket: tmux-message-style-defaults-to-yellow-black)
        set -g message-style       'bg=${theme.palette.surface_2},fg=${theme.palette.fg}'
        set -g status-interval     5
        set -g status-left-length  100
        # 100 (was 300). Combined with #{E:status-right} on format[1] this
        # avoids mid-escape truncation on narrow thin-client terminals.
        # (Ticket: tmux-thin-ssh-client-status-bar-distortion)
        set -g status-right-length 100

        # bold (not reverse) — `reverse` swaps fg/bg per cell, which flickers
        # on thin SSH clients (Termius, JuiceSSH, mosh). bold matches the
        # pre-framework Dracula behavior.
        # (Ticket: tmux-thin-ssh-client-status-bar-distortion)
        set -g window-status-activity-style bold
        set -g window-status-bell-style     bold

        # Weather city/unit are baked into the widget at Nix eval (NYC / "u")
        # via @CITY@/@UNIT@ substitution. Override at runtime by setting
        # TMUX_WIDGET_WEATHER_CITY / TMUX_WIDGET_WEATHER_UNIT — weather.sh
        # picks env up if present, falls through to the baked default otherwise.

        set -g status-left  '${framework.composeBar [ "session" ]}'
        # If thin-client distortion returns: trim status-right to a smaller
        # widget set (e.g. `[ "date-time" ]`) and inspect the test harness
        # output under home/programs/tmux/tests/.
        set -g status-right '${framework.composeBar [ "now-playing" "weather" "date-time" ]}'
        # Periodic auto-save tick — MUST come after the `set -g status-right`
        # above, otherwise that overwrite clobbers this appended #() command.
        # Previously lived inside a plugin's extraConfig where it ran BEFORE
        # the main block. (Ticket: tmux-snapshot-tick-silently-disabled)
        set -ag status-right '#(${snapshotTick})'

        set -g window-status-format         '${framework.windowStyle.format}'
        set -g window-status-current-format '${framework.windowStyle.currentFormat}'
        set -g window-status-separator      '${framework.windowStyle.separator}'

        # Row layout:
        #   format[0] (top)    : status-left + windows  (status-right OMITTED)
        #   format[1] (bottom) : status-right centered
        # status-left wrapped in `range=left` so right-click on NMD fires
        # MouseDown3StatusLeft → Session Menu. status-right wrapped in
        # `range=right` so clicks on row 1 fire MouseDown3StatusRight.
        # format[1] uses `#{E:status-right}` (plain evaluation) instead of
        # `#{T;=/#{status-right-length}:status-right}` (tmux-3.0-only
        # truncation directive that mangles on thin clients / older tmux).
        # (Ticket: tmux-thin-ssh-client-status-bar-distortion)
        set -g status-format[0] '#[align=left range=left #{E:status-left-style}]#[push-default]#{T;=/#{status-left-length}:status-left}#[pop-default]#[norange default]#[list=on align=#{status-justify}]#[list=left-marker]<#[list=right-marker]>#[list=on]#{W:#[range=window|#{window_index} #{E:window-status-style}]#[push-default]#{T:window-status-format}#[pop-default]#[norange default]#{?window_end_flag,,#{window-status-separator}},#[range=window|#{window_index} list=focus #{?#{!=:#{E:window-status-current-style},default},#{E:window-status-current-style},#{E:window-status-style}}]#[push-default]#{T:window-status-current-format}#[pop-default]#[norange list=on default]#{?window_end_flag,,#{window-status-separator}}}'
        set -g status-format[1] '#[align=centre]#[range=right]#{E:status-right}#[norange]'

    # Initialize TMUX plugin manager (keep this line at the very bottom of tmux.conf)
    #    run '~/.tmux/plugins/tpm/tpm'

  '';

  plugins = with pkgs.tmuxPlugins; [
    {
      plugin = now-playing;
      extraConfig = ''
        # Now Playing
        set -g @now-playing-playing-icon "⏵"
        set -g @now-playing-paused-icon "⏸"
        set -g @now-playing-stopped-icon "⏹"
        set -g @now-playing-scrollable-format "{artist} - {title}"
        set -g @now-playing-status-format "{icon} {scrollable}"
        set -g @now-playing-scrollable-threshold "30"
        set -g @now-playing-play-pause-key ""
        set -g @now-playing-stop-key ""
        set -g @now-playing-next-key ""
      '';
    }
    # `tmuxp-fzf` plugin removed — its launcher called raw `tmuxp load`,
    # bypassing tmux-snapshot's post-load restores (@label, pane_title,
    # mirrored-preset re-apply, @layout-6..9). Replacement: prefix + T
    # binding added below in the yank/tmux-snapshot block, routes through
    # `snapshotPicker` (defined in the `let` block at the top of this file).
    # Dracula plugin entry removed — framework owns the status bar.
    better-mouse-mode
    sensible
    {
      # tmux-snapshot save/auto-save. Replaces tmux-resurrect + tmux-continuum.
      # Bindings only — the periodic-save `set -ag status-right '#(snapshotTick)'`
      # was moved to the main extraConfig block (right after `set -g status-right`)
      # because the order of generated tmux.conf put this plugin's extraConfig
      # BEFORE the framework's `set -g status-right`, causing the appended
      # tick to be clobbered. See Ticket: tmux-snapshot-tick-silently-disabled.
      plugin = yank;
      extraConfig = ''
        # How often the silent tick actually fires save (minutes).
        set -g @snapshot-save-interval '10'

        # prefix + C-s : save CURRENT session.
        # prefix + M-s : save ALL sessions.
        bind C-s run-shell 'tmux-snapshot save "#S" >/dev/null 2>&1 \
          && tmux display-message "tmux-snapshot: saved #S to ~/.config/tmuxp/#S.yaml" \
          || tmux display-message "tmux-snapshot: FAILED to save #S — see ~/.config/tmuxp"'
        bind M-s run-shell 'tmux-snapshot save-all >/dev/null 2>&1 \
          && tmux display-message "tmux-snapshot: saved ALL sessions to ~/.config/tmuxp" \
          || tmux display-message "tmux-snapshot: FAILED to save all — see ~/.config/tmuxp"'

        # prefix + C-r : restore CURRENT session from its snapshot (overwrites
        # the live session by renaming it aside, loading the yaml, switching
        # the client over, and killing the old one).
        # prefix + M-r : restore ALL missing sessions from the manifest;
        # already-live sessions are skipped, never disturbed.
        bind C-r run-shell '${snapshotRestoreCurrent} "#S"'
        bind M-r run-shell '${snapshotRestore}'

        # prefix + T : fzf picker over ~/.config/tmuxp/*.yaml. Switches to
        # the session if it's already live, otherwise loads via
        # tmux-snapshot (so @label/pane_title/preset re-apply/@layout-6..9
        # all restore). Replaces the upstream tmuxp-fzf plugin.
        bind T display-popup -E -w 60% -h 60% '${snapshotPicker}'
      '';
    }

  ];
}
