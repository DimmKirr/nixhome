# Enable balloon free-page-reporting in Replace mode so macOS reclaims guest
# memory when containers exit.  Two pieces:
#
# 1. Bump libkrun-efi 1.19.4 → 1.19.8 to get krun_set_balloon_free_page_reporting_mode().
# 2. Patch krunkit to call that API with KRUN_FREE_PAGE_REPORTING_MODE_REPLACE.
#
# Tracking: https://github.com/libkrun/krunkit/issues/121
# Remove once krunkit ships balloon support and nixpkgs carries libkrun-efi >= 1.19.8.
_final: prev: {
  libkrun-efi = prev.libkrun-efi.overrideAttrs (old: rec {
    version = "1.19.8";

    src = prev.fetchFromGitHub {
      owner = "libkrun";
      repo = "libkrun";
      tag = "v${version}";
      hash = "sha256-JcMkgtoNlY2cK32ZjlyGCne2gIWXTSqQSEiOadUSd4E=";
    };

    cargoDeps = prev.rustPlatform.fetchCargoVendor {
      inherit src;
      hash = "sha256-FrHkBeTO1RL/hRT0H6okuGdbGiGNljwUOepBsQvrEug=";
    };
  });

  krunkit = prev.krunkit.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ./krunkit-balloon.patch
    ];
  });
}
