{ pkgs, pkgsUnstable, ... }:
{
  enable = true;
  enableCompletion = true;

  autosuggestion = {
    enable = true;
  };

  syntaxHighlighting = {
    enable = true;
  };



  shellAliases = {
    ll = "ls -l";
    # idea = "open -na '${pkgsUnstable.jetbrains.idea-ultimate}/Applications/IntelliJ IDEA.app/' --args \"$@\""; # Use this path instead of idea cmd script in nix-profile/bin, as the latter messes up dock (thinks two separate Idea IDEs are running)
    ij = "idea .";
    subl = "open -na '/Applications/Sublime Text.app/' --args \"$@\"";

    # Nix/Darwin rebuild aliases
    darwin-rebuild-switch = "darwin-rebuild switch --flake ~/dev/n0mad/nixhome/";
    darwin-rebuild-build = "darwin-rebuild build --flake ~/dev/n0mad/nixhome/";

    nix-update-switch = "sudo $(which nix) flake update --impure --flake ~/dev/n0mad/nixhome/ && sudo $(which nix) run nix-darwin --impure -- switch --impure --flake ~/dev/n0mad/nixhome/ && source ~/.zshrc";
    nix-update-switch-gc = "sudo $(which nix) flake update --impure --flake ~/dev/n0mad/nixhome/ && sudo $(which nix) run nix-darwin --impure -- switch --impure --flake ~/dev/n0mad/nixhome/ && source ~/.zshrc";
    nix-switch = "sudo darwin-rebuild switch --flake ~/dev/n0mad/nixhome/ --offline && source ~/.zshrc";

    update-nix = "sudo $(which nix) flake update --impure --flake ~/dev/n0mad/nixhome/ && sudo $(which nix) run nix-darwin --impure -- switch --impure --flake ~/dev/n0mad/nixhome/ && source ~/.zshrc";
    vim = "nvim";
    ta = "tmux a";
    nix-develop = "nix develop -c ${pkgs.zsh}/bin/zsh";

    "rec" = "t-rec --quiet --video-only --decor=shadow --bg=white --output=$HOME/$(date +'%Y-%m-%d_%H-%M-%S')";
  };

  initContent = (builtins.readFile ./../scripts/zsh-init.zsh); # sessionVars and localVars don't seem to work, so using this

  # TODO: use https://nix-community.github.io/home-manager/options.xhtml#opt-programs.zsh.localVariables
  #  zplug = {
  #    enable = true;
  #    plugins = [
  #      "colorize"
  #      #          {
  #      #            name = "zsh-users/zsh-autosuggestions";
  #      #            src = pkgs.zsh-autosuggestions;
  #      #          }
  #      #          {
  #      #            name = "zsh-users/zsh-syntax-highlighting";
  #      #            src = pkgs.zsh-syntax-highlighting;
  #      #          }
  #      #          {
  #      #            name = "zsh-users/zsh-history-substring-search";
  #      #            src = pkgs.zsh-history-substring-search;
  #      #          }
  #    ];
  #  };

  plugins = [
    {
      name = "zsh-users/zsh-autosuggestions";
      src = pkgs.zsh-autosuggestions;
    }
    {
      name = "zsh-users/zsh-syntax-highlighting";
      src = pkgs.zsh-syntax-highlighting;
    }
    {
      name = "zsh-users/zsh-history-substring-search";
      src = pkgs.zsh-history-substring-search;
    }
    {
      name = "powerlevel10k";
      src = pkgs.zsh-powerlevel10k;
      file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
    }
    {
      name = "powerlevel10k-config";
      src = ./../configs/p10k-config;
      file = "p10k.zsh";
    }
    # fasd is unmaintained - using zoxide instead (configured in programs.zoxide)
    # {
    #   name = "fasd";
    #   src = pkgs.fasd;
    # }
    {
      name = "fzf";
      src = pkgs.fzf;
    }
    #    {
    #      name = "colorize";
    #      file = "colorize.plugin.zsh";
    #      src = builtins.fetchGit {
    #        # Updated 2020-12-31
    #        url = "https://github.com/momo-lab/zsh-abbrev-alias";
    #        rev = "2f3d218f426aff21ac888217b0284a3a1470e274";
    #      };
    #    }
  ];

}
