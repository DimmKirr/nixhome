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
    "*" = {
      # Use 1Password SSH agent (serves keys from vault + hardware keys)
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
