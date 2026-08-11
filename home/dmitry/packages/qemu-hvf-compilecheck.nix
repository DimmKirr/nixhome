# Surgical compile-check of the HVF VHE glue (NMD-256).
#
# hvf.c compiles only on Darwin and only inside a configured QEMU tree, but
# we do NOT need to build all of QEMU (~25 target architectures) to verify
# ~120 lines of glue. This derivation:
#   1. restricts the build to the single aarch64-softmmu target (the one that
#      contains target/arm/hvf/hvf.c), so meson configure is fast;
#   2. compiles ONLY the hvf.c / vhe_core.c object files via ninja, then stops.
#
# Success => the glue compiles against the real Hypervisor.framework + QEMU
# headers. Failure => the compiler error is the thing to fix. Minutes, not 40.
#
# Used by `task debug:qemu:el2:qemu`. On non-Darwin (no HVF sources) it falls
# back to building the full aarch64-softmmu target so the file still evaluates.
{ pkgs, pkgsEdge }:
let
  base = import ./qemu-rc.nix { inherit pkgs pkgsEdge; };
in
base.overrideAttrs (o: {
  pname = "qemu-hvf-vhe-compilecheck";
  # One target instead of all — cuts meson configure and compile drastically.
  configureFlags = (o.configureFlags or [ ]) ++ [ "--target-list=aarch64-softmmu" ];
  # Compile only the HVF translation units, not the whole emulator.
  buildPhase = ''
    runHook preBuild
    # Find build.ninja — meson may build in-tree (.) or in a subdirectory
    BUILD_DIR="."
    for d in build builddir; do
      if [ -f "$d/build.ninja" ]; then BUILD_DIR="$d"; break; fi
    done
    if [ ! -f "$BUILD_DIR/build.ninja" ]; then
      echo "ERROR: no build.ninja in . or build/ or builddir/"
      ls -la
      exit 1
    fi
    objs=$(ninja -C "$BUILD_DIR" -t targets all 2>&1 \
             | grep -oE '[^ :|]*(hvf|vhe_core)\.c\.o' | sort -u || true)
    if [ -z "$objs" ]; then
      echo "no HVF objects found (non-Darwin build?) — compiling full target"
      ninja -C "$BUILD_DIR"
    else
      echo "compile-check objects: $objs"
      ninja -C "$BUILD_DIR" $objs
    fi
    runHook postBuild
  '';
  # No binaries produced; just satisfy every declared output with an empty dir
  # and drop a marker so the derivation has a result.
  installPhase = ''
    runHook preInstall
    for _o in $outputs; do mkdir -p "''${!_o}"; done
    echo "hvf glue compile-check passed" > "$out/COMPILE_OK"
    runHook postInstall
  '';
  postInstall = "";
  doCheck = false;
  dontFixup = true;
})
