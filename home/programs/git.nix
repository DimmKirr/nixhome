{pkgs, ...}: {
  enable = true;
  lfs.enable = true;
  signing = {
    key = "981273078600BC70";
    signer = "/usr/local/MacGPG2/bin/gpg2";
    signByDefault = true;
  };

  # Renamed in home-manager 25.11: userName/userEmail/extraConfig → settings
  settings = {
    user = {
      name = "Dmitry Kireev";
      email = "dmitry@hazelops.com";
    };
    init = {
      defaultBranch = "main";
      # Disable reftable - libgit2 (used by Nix) doesn't support it yet
      # See: https://github.com/NixOS/nix/issues/14716
      defaultRefFormat = "files";
    };
    pull = {
      rebase = false;
    };
  };

  ignores = [
    "*~"
    ".DS_Store"
    ".idea/"
    ".scratch"
    ".secrets"
    "Makefile-ho"
    "hzl.mk"
    ".envrc"
    ".direnv"
    ".env"
    ".jira-config/"
    ".jira"
    ".claude"
    ".context"
    "CLAUDE.md"
    ".worktrees"
    ".env"
  ];
}
