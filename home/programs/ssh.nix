{pkgs, ...}: {
  enable = true;
  # Disable deprecated default config - set explicit defaults if needed
  enableDefaultConfig = false;

  # SSH client config. Attribute names are Host patterns; values use upstream
  # OpenSSH directive names (capitalized) directly. The old `matchBlocks` +
  # `extraOptions` form was deprecated in home-manager 26.05 in favour of
  # `settings`.
  settings = {
    # Default settings for all hosts
    "*" = pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin {
      # Use 1Password SSH agent (serves keys from vault + hardware keys).
      # macOS only: Linux hosts have no 1Password socket and must fall back to
      # $SSH_AUTH_SOCK (e.g. an agent forwarded with `ssh -A`).
      IdentityAgent = ''"~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"'';
      # Use internal FIDO2 provider for security keys
      # Disabled: IntelliJ prompts for it too often, 1Password handles auth instead
      # SecurityKeyProvider = "internal";
    };

    # TODO(NMD-51): Re-enable once public key is exported from 1Password to ~/.ssh/
    # Prevent 1Password agent from offering YubiKey ED25519-SK key to GitHub/GitLab
    # IdentitiesOnly=yes ensures only the explicitly listed IdentityFile is tried,
    # so the SK key won't block on physical touch confirmation
    # "github.com" = {
    #   IdentitiesOnly = "yes";
    #   IdentityFile = "~/.ssh/id_ed25519.pub";
    # };
    # "gitlab.com" = {
    #   IdentitiesOnly = "yes";
    #   IdentityFile = "~/.ssh/id_ed25519.pub";
    # };

    "nixie nixie.lan" = {
      User = "dmitry";
      # Forward the agent so git/ssh on nixie can use the Mac's keys
      # (server side: AllowAgentForwarding in hosts/nixie/default.nix).
      ForwardAgent = "yes";
    };

    "automationd.lan" = {
      User = "dmitry";
      # 1Password agent will offer matching keys automatically
    };

    "d*.kirr.dev" = {
      StrictHostKeyChecking = "no";
      UserKnownHostsFile = "/dev/null";
    };

    "w*.kirr.dev" = {
      StrictHostKeyChecking = "no";
      UserKnownHostsFile = "/dev/null";
    };
  };
}
