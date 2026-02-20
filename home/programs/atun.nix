{ pkgs, config, ... }:

{
  home.file."${config.xdg.dataHome}/zsh/site-functions/_atun".text = (builtins.readFile ./../scripts/atun-compinit.zsh);
}
