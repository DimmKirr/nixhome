{pkgs, ...}: let


  tmuxStatusWidgets = {
    clima = "#[fg=#ffb86c,bg=#00075a]#(${clima}/share/tmux-plugins/tmux-clima/scripts/clima.sh)#[default]";
    nowPlaying = "#[fg=#ff79c6,bg=#00075a]#(${now-playing}/share/tmux-plugins/tmux-now-playing/scripts/now-playing.sh)#[default]";
  };

  tmuxDraculaPlugins = {
    public = "custom:now-playing.sh weather time";
    private = "network-public-ip custom:now-playing.sh weather time";
  };
#
#  now-playing = pkgs.tmuxPlugins.mkTmuxPlugin {
#    pluginName = "tmux-now-playing";
#    version = "local-2025-09-17";
#    rtpFilePath = "now-playing.tmux"; # Plugin has unconventional RTP file name
#    src = /Users/dmitry/dev/dimmkirr/tmux-now-playing;
#  };


  now-playing = pkgs.tmuxPlugins.mkTmuxPlugin {
    pluginName = "tmux-now-playing";
    version = "unstable-2025-09-17";
    rtpFilePath = "now-playing.tmux"; # Plugin has unconventional RTP file name
    src = pkgs.fetchFromGitHub {
      owner = "DimmKirr";
      repo = "tmux-now-playing";
      rev = "5077d4e103e63ef1b3a9cf54e634d3900eafd02f";
      sha256 = "hXh4zvCUitFsal3FWLuumbuDn85cCQWIDI/YNJtlKxE=";
    };
  };


  colortag = pkgs.tmuxPlugins.mkTmuxPlugin {
    pluginName = "tmux-colortag";
    version = "unstable-2025-08-08";
#    rtpFilePath = "now-playing.tmux"; # Plugin has unconventional RTP file name
    src = pkgs.fetchFromGitHub {
      owner = "Determinant";
      repo = "tmux-colortag";
      rev = "72ef7174f63dcf8e2809376f8f8a39ca1d910efc";
      sha256 = "aN2UzJVnKoYw5dlqHRoHkYK/zGMoa28qet/jnPAAAAA=";
    };
  };


  powerline = pkgs.tmuxPlugins.mkTmuxPlugin {
    pluginName = "tmux-powerline";
    version = "v3.1.0";
    rtpFilePath = "main.tmux"; # Plugin has unconventional RTP file name
    src = pkgs.fetchFromGitHub {
      owner = "erikw";
      repo = "tmux-powerline";
      rev = "cf1097754c57f2ef99c9087d72706ff6203ac8ab";
      sha256 = "BB/SdwP4EAWbeM1Yyz4bnMX6HvBIIu9QTp9H5ZO3XEY=";
    };
  };

  clima  = pkgs.tmuxPlugins.mkTmuxPlugin {
    pluginName = "tmux-clima";
    version = "unstable-2024-09-10";
    rtpFilePath = "clima.tmux"; # Plugin has unconventional RTP file name
    src = pkgs.fetchFromGitHub {
      owner = "vascomfnunes";
      repo = "tmux-clima";
      rev = "9052e5c475ba0815bef2367fb473324f3c4e6d84";
      sha256 = "icSLRz+voMTA1hSixNLFD0fmseOaltSQwKMdL5JhAk4=";
    };
  };



#  menus = pkgs.tmuxPlugins.mkTmuxPlugin {
#    pluginName = "tmux-menus";
#    version = "v2.2.18";
#    rtpFilePath = "menus.tmux"; # Plugin has unconventional RTP file name
#    src = pkgs.fetchFromGitHub {
#      owner = "jaclu";
#      repo = "tmux-menus";
#      rev = "47b886104e8ebc50d7890d15320ac28477dace2e";
#      sha256 = "aN2UzJVnKoYw5dlqHRoHkYK/zGMoa28qet/jnP7zJzw=";
#    };
#  };

  # Override dracula to add now-playing as a custom script
  dracula = pkgs.tmuxPlugins.dracula.overrideAttrs (oldAttrs: {
    postInstall =
      (oldAttrs.postInstall or "")
      + ''
        # Create bash script that executes now-playing's music.sh from correct directory
        cat > $out/share/tmux-plugins/dracula/scripts/now-playing.sh << EOFNP
          #!${pkgs.bash}/bin/bash
          # Change to now-playing scripts directory so sourced files can be found
          cd "${now-playing}/share/tmux-plugins/tmux-now-playing/scripts"

          # Execute music.sh from the correct directory
          exec ./music.sh "\$@"
        EOFNP
        chmod +x $out/share/tmux-plugins/dracula/scripts/now-playing.sh

        # Create bash script that executes air from powerline
        cat > $out/share/tmux-plugins/dracula/scripts/air.sh << EOFAIR
          #!${pkgs.bash}/bin/bash
          # Change to now-playing scripts directory so sourced files can be found
          cd "${powerline}/share/tmux-plugins/tmux-powerline/segments"

          # Execute air.sh from the correct directory
          exec ./air.sh "\$@"
        EOFAIR
        chmod +x $out/share/tmux-plugins/dracula/scripts/air.sh

        # Create bash script that executes air from powerline
        cat > $out/share/tmux-plugins/dracula/scripts/clima.sh << EOFAIR
          #!${pkgs.bash}/bin/bash
          cd "${clima}/share/tmux-plugins/tmux-clima/scripts"

          # Execute air.sh from the correct directory
          exec ./clima.sh "\$@"
        EOFAIR
        chmod +x $out/share/tmux-plugins/dracula/scripts/clima.sh


        # Create bash script that creates a spacer (empty space)
        cat > $out/share/tmux-plugins/dracula/scripts/spacer.sh << EOFSPCR
          #!${pkgs.bash}/bin/bash
          printf "\033[P40m \033[0m"
        EOFSPCR
        chmod +x $out/share/tmux-plugins/dracula/scripts/spacer.sh


      '';
  });
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
        set -g pane-border-format '#{pane_index} #{?@label,#[fg=white]#{@label}#[default] | ,}#{pane_title}'

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
            "" "" "" \
            "Kill"            X "kill-pane" \
            "Respawn"         R "respawn-pane -k" \
            "Mark"            m "select-pane -m" \
            "Zoom"            z "resize-pane -Z" \
            "Rename Pane" n "command-prompt -I '#{@label}' 'set -pt \"#{mouse_pane}\" @label \"%%\"; refresh-client'" \
            "Clear Label" N "set -pt \"#{mouse_pane}\" @label \"\"; refresh-client"


        # Override default "prefix + ." menu
        bind-key > display-menu -T "#[align=centre]Pane Menu" -x W -y W \
          "Horizontal Split" h "split-window -h -c '#{pane_current_path}'" \
          "Vertical Split"   v "split-window -v -c '#{pane_current_path}'" \
          "" "" "" \
          "Swap Up"          u "swap-pane -U" \
          "Swap Down"        d "swap-pane -D" \
          "Swap Marked"      m "swap-pane -d -t '{marked}'" \
          "" "" "" \
          "Kill"             X "kill-pane" \
          "Respawn"          R "respawn-pane -k" \
          "Mark"             M "select-pane -m" \
          "Zoom"             z "resize-pane -Z" \
          "" "" "" \
          "Rename Pane" n "command-prompt -I '#{@label}' 'set -pt \"#{pane_id}\" @label \"%%\"; refresh-client'" \
          "Clear Label" N "set -pt \"#{pane_id}\" @label \"\"; refresh-client"

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


    # Initialize TMUX plugin manager (keep this line at the very bottom of tmux.conf)
    #    run '~/.tmux/plugins/tpm/tpm'

  '';

  plugins = with pkgs.tmuxPlugins; [
#    {
#      plugin = sidebar;
#      extraConfig = ''
#
#      '';
#    }
#    {
#      plugin = clima;
#      extraConfig = ''
#        set -g @clima_unit imperial
#        set -g @clima_location "NYC"
#        set -g @clima_show_icon 1
#        set -g @clima_use_nerd_font 1
#      '';
#    }
#    {
#      plugin = menus;
#      extraConfig = ''
#        set -g @menus_use_cache 'No'
#
#      '';
#    }

#    {
#      plugin = powerline;
#      extraConfig = ''
#
#
#      '';
#    }
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
        set -g @now-playing-play-pause-key ""
        set -g @now-playing-next-key ""
      '';
    }
    {
      plugin = dracula;
      extraConfig = ''
        # Dracula settings
        ###
        # Dracula Plugins: battery, cpu-usage, git, gpu-usage, ram-usage, tmux-ram-usage, network, network-bandwidth, network-ping, ssh-session, attached-clients, network-vpn, weather, time, mpc, spotify-tui, kubernetes-context, synchronize-panes
        # Now Playing Doc: https://github.com/spywhere/now-playing/blob/master/README.md
        # Dracula Settings: https://draculatheme.com/tmux
        # Unicode Symbols: https://symbl.cc/en/unicode/table/#miscellaneous-symbols


        # set -g @dracula-plugins "window time" # it can accept `hostname` (full hostname), `session`, `shortname` (short name), `smiley`, `window`, or any character.
        # set -g @dracula-plugins "weather time" # it can accept `hostname` (full hostname), `session`, `shortname` (short name), `smiley`, `window`, or any character.
        set -g @dracula-show-left-icon session
        set -g @dracula-time-format '%R %Z'
        set -g @dracula-show-timezone true
        set -g @dracula-show-powerline false
        set -g @dracula-show-flags true
        set -g @dracula-left-icon-padding 1
        set -g @dracula-show-empty-plugins false

        set -g @dracula-network-public-ip-label "ⓦ"


        # Weather
        set -g @dracula-fixed-location "NYC"
        set -g @dracula-show-fahrenheit true

        # 2-row status
        set -g status 2

        # ROW 1 (TOP)
        set -g status-format[0] '#[align=left range=left #{E:status-left-style}]#[push-default]#{T;=/#{status-left-length}:status-left}#[pop-default]#[norange default]#[list=on align=#{status-justify}]#[list=left-marker]<#[list=right-marker]>#[list=on]#{W:#[range=window|#{window_index} #{E:window-status-style}#{?#{&&:#{window_last_flag},#{!=:#{E:window-status-last-style},default}}, #{E:window-status-last-style},}#{?#{&&:#{window_bell_flag},#{!=:#{E:window-status-bell-style},default}}, #{E:window-status-bell-style},#{?#{&&:#{||:#{window_activity_flag},#{window_silence_flag}},#{!=:#{E:window-status-activity-style},default}}, #{E:window-status-activity-style},}}]#[push-default]#{T:window-status-format}#[pop-default]#[norange default]#{?window_end_flag,,#{window-status-separator}},#[range=window|#{window_index} list=focus #{?#{!=:#{E:window-status-current-style},default},#{E:window-status-current-style},#{E:window-status-style}}#{?#{&&:#{window_last_flag},#{!=:#{E:window-status-last-style},default}}, #{E:window-status-last-style},}#{?#{&&:#{window_bell_flag},#{!=:#{E:window-status-bell-style},default}}, #{E:window-status-bell-style},#{?#{&&:#{||:#{window_activity_flag},#{window_silence_flag}},#{!=:#{E:window-status-activity-style},default}}, #{E:window-status-activity-style},}}]#[push-default]#{T:window-status-current-format}#[pop-default]#[norange list=on default]#{?window_end_flag,,#{window-status-separator}}}'

        # ROW 2 (BOTTOM - Dracula plugins)
        set -g status-format[1] "#[align=centre]#[range=right]#{E:status-right}#[norange]"

        ### Status Plugins


        set -g @dracula-plugins "${tmuxDraculaPlugins.public}"


        # Cycle Dracula plugins between two sets
        bind P run-shell '
        current="$(tmux show -gv @dracula-plugins)"
        if [ "$current" = "${tmuxDraculaPlugins.private}" ]; then
          tmux set -g @dracula-plugins "${tmuxDraculaPlugins.public}"
        else
          tmux set -g @dracula-plugins "${tmuxDraculaPlugins.private}"
        fi

        # re-run Dracula init so it picks up new plugins
        tmux run-shell ${dracula}/share/tmux-plugins/dracula/dracula.tmux
        '
      '';
    }
    {
      plugin = resurrect;
      extraConfig = ''
        set -g @resurrect-strategy-vim 'session'
        set -g @resurrect-strategy-nvim 'session'
        set -g @resurrect-capture-pane-contents 'on'
      '';
    }

    {
      plugin = continuum;
      extraConfig = ''
        set -g @continuum-restore 'off'
        set -g @continuum-boot 'off'
        set -g @continuum-save-interval '10'
      '';
    }
    better-mouse-mode
    sensible
    yank

  ];
}
