{ pkgs, config, ... }:

{
  home.file."${config.xdg.dataHome}/zsh/site-functions/_op".text = (builtins.readFile ./../scripts/op-compinit.zsh);
}
