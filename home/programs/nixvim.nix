{ pkgs, ... }:
{
  enable = true;
  colorschemes.dracula.enable = true;
  plugins = {
    lualine.enable = true;
    nix.enable = false;
  };
}
