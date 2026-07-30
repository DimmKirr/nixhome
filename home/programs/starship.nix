{ pkgs ? {}, lib ? {}, ... }:
let
  isLinux = pkgs ? stdenv && pkgs.stdenv.isLinux;
in {
  enable = true;

  settings = {
    # Dracula palette — https://draculatheme.com
    # bg=#282A36 fg=#F8F8F2 muted=#6272A4 cyan=#8BE9FD green=#50FA7B
    # orange=#FFB86C pink=#FF79C6 purple=#BD93F9 red=#FF5555 yellow=#F1FA8C

    # Left: dir → git_branch → git_status → character
    format = "$directory$git_branch$git_status$character";
    # Right: ENV var → context (user@host on SSH/root) → cmd_duration
    # username + hostname removed from the right-prompt — they were
    # surfacing `dmitry@automationd` on every prompt line (1Password SSH
    # agent / passthrough sets SSH_CONNECTION even on local shells,
    # tripping starship's ssh_only=true and show_always=false defaults).
    # Re-add `$username$hostname` here when you want it back on actual
    # remote sessions.
    right_format = if isLinux
      then "$hostname$env_var$cmd_duration"
      else "$env_var$cmd_duration";
    add_newline = false;

    character = {
      success_symbol = "[❯](bold #FF79C6)"; # pink
      error_symbol   = "[❯](bold #FF5555)"; # red
    };

    directory = {
      style             = "bold #BD93F9"; # purple
      truncation_length = 1;
      truncate_to_repo  = false;
      format            = "[$path]($style) ";
    };

    git_branch = {
      format = "[$branch]($style) ";
      style  = "#50FA7B";  # green
      symbol = "";
    };

    git_status = {
      style       = "#6272A4"; # muted
      format      = "([$all_status$ahead_behind]($style) )";
      conflicted  = "[=](#FF5555)";   # red
      ahead       = "[⇡](#50FA7B)";   # green
      behind      = "[⇣](#FFB86C)";   # orange
      diverged    = "[⇡⇣](#FF5555)";
      up_to_date  = "";
      untracked   = "[?](#F1FA8C)";   # yellow
      stashed     = "[\\$](#BD93F9)"; # purple
      modified    = "[!](#FFB86C)";   # orange
      staged      = "[+](#50FA7B)";   # green
      renamed     = "[»](#8BE9FD)";   # cyan
      deleted     = "[✘](#FF5555)";   # red
    };

    cmd_duration = {
      min_time          = 5000;
      format            = "[$duration]($style) ";
      style             = "bold #F1FA8C"; # yellow
      show_milliseconds = false;
    };

    env_var = {
      ENV = {
        variable = "ENV";
        format   = "[$env_value]($style) ";
        style    = "bold #F1FA8C"; # yellow
        disabled = false;
      };
    };

    username = {
      format      = "[$user]($style)";
      style_user  = "#6272A4"; # muted
      style_root  = "bold #FF5555"; # red — danger
      show_always = false;
      disabled    = false;
    };

    hostname = {
      format   = "[$hostname]($style) ";
      style    = "#8BE9FD"; # cyan
      ssh_only = !isLinux;
      disabled = false;
    };

    direnv.disabled = true;
  };
}
