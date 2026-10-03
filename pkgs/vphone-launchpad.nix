# vphone-launchpad: official notarized release of the vphone-cli workstation
# app (https://github.com/Lakr233/vphone-cli), plus a `vphone-cli` shim.
#
# Why prebuilt, not source: the build needs full Xcode + the iPhoneOS SDK
# (guest vphoned), a workspace of handwritten .xcodeproj files (xcbuild can't
# drive it), SwiftPM deps resolved over the network, and private entitlements.
# Launchpad's SMJobBless helper also requires the Developer ID signature that
# only the upstream notarized zip carries.
#
# Scope: only the Launchpad app is packaged. VPhone.bundle (vphone-cli,
# vphone-vm, ...) is installed by Launchpad itself into the root-owned store
# /Library/Application Support/vphone-launchpad/Bundles/<version>, with
# receipt-pinned cdhashes for the AMFI allowlist. Packaging the bundle here
# would bypass that flow, so `bin/vphone-cli` just execs the bundle Launchpad
# marked active (override with VPHONE_BUNDLE_VERSION=<version>).
#
# Host prerequisites (manual, from Recovery): see upstream
# Documents/Guides/host-setup.md
#   csrutil enable --without debug
#   csrutil allow-research-guests enable
#
# Install via nix-darwin environment.systemPackages: nix-darwin rsync-copies
# apps into "/Applications/Nix Apps" (a real copy, not a store symlink), which
# keeps notarization and SMJobBless happy.
#
# Updating: pick a version that has a `-notarized` zip (see upstream
# Documents/Downloads/README.md), bump `version`, refresh `hash` with
#   nix hash file --sri --type sha256 <(curl -sL https://github.com/Lakr233/vphone-cli/releases/download/<VERSION>/vphone-launchpad-<VERSION>-notarized.zip)
# Launchpad x.y works with VPhone.bundle x.y.* only; Launchpad does not
# self-update.
{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
  coreutils,
  version ? "2.2.4",
  hash ? "sha256-GSD5KKVgydyV0FOBbpXcyy2ZZwRkTa07ULggUmSfaK8=",
}:
stdenvNoCC.mkDerivation {
  pname = "vphone-launchpad";
  inherit version;

  src = fetchurl {
    url = "https://github.com/Lakr233/vphone-cli/releases/download/${version}/vphone-launchpad-${version}-notarized.zip";
    inherit hash;
  };

  nativeBuildInputs = [ unzip ];
  sourceRoot = ".";

  dontPatch = true;
  dontConfigure = true;
  dontBuild = true;
  # No fixup: the app is Developer ID signed, notarized and stapled; stripping
  # or patching would break the seal and Gatekeeper/SMJobBless would reject it.
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    # The zip (made by ditto) carries AppleDouble `._*` files holding only
    # com.apple.provenance. Left in place they are unsealed bundle contents
    # and fail codesign verification, so drop them.
    find vphone-launchpad.app -name '._*' -delete

    mkdir -p $out/Applications $out/bin
    cp -R vphone-launchpad.app $out/Applications/

    # Stateless client of the running app over a same-user Unix socket.
    ln -s $out/Applications/vphone-launchpad.app/Contents/MacOS/vphone-launchpad-cli \
      $out/bin/vphone-launchpad-cli

    cat > $out/bin/vphone-cli <<'EOF'
    #!/bin/sh
    # Runs vphone-cli from the VPhone.bundle that Launchpad installed and
    # marked active. Falls back to the newest installed bundle.
    store="/Library/Application Support/vphone-launchpad/Bundles"
    exe() { printf '%s/%s/VPhone.bundle/Contents/MacOS/vphone-cli' "$store" "$1"; }

    version="''${VPHONE_BUNDLE_VERSION:-$(/usr/bin/defaults read com.vphone.launchpad VPhoneLaunchpadActiveBundleVersion 2>/dev/null)}"
    if [ -z "$version" ] || [ ! -x "$(exe "$version")" ]; then
      version="$(/bin/ls -1 "$store" 2>/dev/null | @sort@ -V | @tail@ -n 1)"
    fi
    if [ -z "$version" ] || [ ! -x "$(exe "$version")" ]; then
      echo "vphone-cli: no VPhone.bundle installed in $store" >&2
      echo "Open vphone-launchpad > Core Bundle > Download and Install." >&2
      exit 1
    fi
    exec "$(exe "$version")" "$@"
    EOF
    substituteInPlace $out/bin/vphone-cli \
      --replace-fail '@sort@' '${coreutils}/bin/sort' \
      --replace-fail '@tail@' '${coreutils}/bin/tail'
    chmod +x $out/bin/vphone-cli

    runHook postInstall
  '';

  meta = {
    description = "Run a virtual iPhone on Apple Silicon (vphone-cli Launchpad, notarized prebuilt)";
    homepage = "https://github.com/Lakr233/vphone-cli";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "aarch64-darwin" ];
    mainProgram = "vphone-cli";
  };
}
