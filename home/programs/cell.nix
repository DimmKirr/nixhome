{ pkgs, config, ... }:

{
  home.file."${config.xdg.dataHome}/zsh/site-functions/_cell".text = (builtins.readFile ./../scripts/cell-compinit.zsh);
}
