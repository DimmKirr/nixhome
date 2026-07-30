{pkgs, pkgsUnstable, ...}: {
  enable = true;
  package = pkgsUnstable.mise;
  enableZshIntegration = true;
  globalConfig = {
    tools = {
      node = "22.14.0";
      ruby = "3.4.9";
      python = "3.13.12";
      terraform = "1.14.7";
      opentofu = "1.11.5";
      go = "1.25.8";
    };
    settings = {
      experimental = true;
      legacy_version_file = true;
    };
  };
}
