{ pkgs, config, ... }:

{
  home.file."${config.xdg.dataHome}/zsh/site-functions/_ize".text = (builtins.readFile ./../scripts/ize-compinit.zsh);
}
