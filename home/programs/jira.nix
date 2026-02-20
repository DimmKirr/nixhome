{ pkgs, config, ... }:

{
  home.file."${config.xdg.dataHome}/zsh/site-functions/_jira".text = (builtins.readFile ./../scripts/jira-compinit.zsh);
}
