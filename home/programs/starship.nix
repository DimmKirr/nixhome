{ ... }:
{
  enable = true;

  settings = {
    # Left: dir → git_branch → git_status → direnv → character
    format = "$directory$git_branch$git_status$direnv$character";
    # Right: ENV var (custom_env_name) → context (user@host, ssh/root only) → cmd_duration
    right_format = "$env_var$username$hostname$cmd_duration";
    add_newline = false;

    character = {
      success_symbol = "[❯](bold #FF6AC1)"; # magenta, matches p10k
      error_symbol   = "[❯](bold #FF5C57)"; # red, matches p10k
    };

    directory = {
      style             = "bold #57C7FF"; # blue, matches p10k
      truncation_length = 1;              # truncate_to_last — only show current segment
      truncate_to_repo  = false;
      format            = "[$path]($style) ";
    };

    git_branch = {
      format = "[$branch]($style)";
      style  = "242";      # grey, matches p10k POWERLEVEL9K_VCS_FOREGROUND
      symbol = "";         # no branch icon, matches p10k POWERLEVEL9K_VCS_BRANCH_ICON=
    };

    git_status = {
      # Matches p10k: dirty=*, ahead=:⇡, behind=:⇣, diverged=:⇡⇣, commit=@
      format    = "([$all_status$ahead_behind]($style) )";
      style     = "242";
      modified  = "*";
      staged    = "*";
      untracked = "*";
      deleted   = "*";
      renamed   = "*";
      conflicted = "*";
      ahead     = ":⇡";
      behind    = ":⇣";
      diverged  = ":⇡⇣";
    };

    cmd_duration = {
      min_time            = 5000; # 5s threshold, matches p10k COMMAND_EXECUTION_TIME_THRESHOLD
      format              = "[$duration]($style)";
      style               = "bold #F3F99D"; # yellow, matches p10k
      show_milliseconds   = false;
    };

    # Replaces p10k custom_env_name (echo $ENV) — shown on right when $ENV is set
    env_var = {
      ENV = {
        variable = "ENV";
        format   = "[$env_value]($style) ";
        style    = "bold yellow";
        disabled = false;
      };
    };

    # Replaces p10k context — grey user@host, hidden by default, shown for root/SSH
    username = {
      format      = "[$user]($style)";
      style_user  = "242";
      style_root  = "bold #F1F1F0";
      show_always = false;
      disabled    = false;
    };

    hostname = {
      format   = "[@$hostname]($style) ";
      style    = "242";
      ssh_only = true;
      disabled = false;
    };

    direnv = {
      disabled = false;
      format   = "[$symbol$loaded/$allowed]($style) ";
      style    = "242";
      symbol   = "";
    };
  };
}
