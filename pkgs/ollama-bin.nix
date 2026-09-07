# Official prebuilt ollama release for macOS — includes the MLX backend.
#
# Why not nixpkgs' ollama: the MLX backend needs the closed-source Metal
# shader toolchain (`xcrun metal` / `metallib`), unavailable in the nix
# build sandbox, so nixpkgs disables it with -DOLLAMA_MLX_BACKENDS=""
# (nixpkgs PR #529079). The upstream release tarball ships prebuilt
# mlx.metallib payloads (mlx_metal_v3/ and mlx_metal_v4/), so repackaging
# the binary sidesteps the toolchain entirely.
#
# Updating: bump `version`, then refresh `hash` with
#   nix hash file --sri --type sha256 <(curl -sL https://github.com/ollama/ollama/releases/download/v<VERSION>/ollama-darwin.tgz)
# or set hash to lib.fakeHash and copy the correct one from the build error.
# Both can also be overridden at the callPackage site without editing this file.
{
  lib,
  stdenvNoCC,
  fetchurl,
  version ? "0.33.3",
  hash ? "sha256-NC2wPfgLuduE/2QkYDG9X3DAm1n/UvpcyaquNHbMSp0=",
}:
stdenvNoCC.mkDerivation {
  pname = "ollama-bin";
  inherit version;

  src = fetchurl {
    url = "https://github.com/ollama/ollama/releases/download/v${version}/ollama-darwin.tgz";
    inherit hash;
  };

  # Tarball has no top-level directory — extract straight into $out in
  # installPhase instead of using the stock unpackPhase (which would
  # also sweep up stdenv's env-vars file from the build dir).
  dontUnpack = true;
  dontPatch = true;
  dontConfigure = true;
  dontBuild = true;
  # No fixup: binaries and dylibs are Apple-codesigned; stripping or
  # patching them would invalidate the signature and macOS would kill
  # the process on launch.
  dontFixup = true;

  # Everything (binary + dylibs + mlx_metal_* payloads) goes to
  # lib/ollama, matching ollama's runtime library detection: it searches
  # the executable's own directory and ../lib/ollama, both of which
  # resolve correctly through the bin/ symlink.
  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/ollama $out/bin
    tar -xzf $src -C $out/lib/ollama
    ln -s ../lib/ollama/ollama $out/bin/ollama
    runHook postInstall
  '';

  meta = {
    description = "Ollama (official prebuilt macOS binary, with MLX backend)";
    homepage = "https://github.com/ollama/ollama";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [
      "aarch64-darwin"
      "x86_64-darwin"
    ];
    mainProgram = "ollama";
  };
}
