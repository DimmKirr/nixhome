# QEMU 11.1.0-rc3 override — building from GitLab source archive
# with pre-fetched meson wrap subprojects (release tarballs bundle these;
# GitLab archives don't).
{ pkgs, pkgsEdge }:
let
  inherit (pkgs) fetchurl fetchzip lib;
  inherit (pkgs) stdenv;

  wrapSubprojects = {
    keycodemapdb = fetchzip {
      url = "https://gitlab.com/qemu-project/keycodemapdb/-/archive/f5772a62ec52591ff6870b7e8ef32482371f22c6/keycodemapdb-f5772a62ec52591ff6870b7e8ef32482371f22c6.tar.gz";
      hash = "sha256-GbZ5mrUYLXMi0IX4IZzles0Oyc095ij2xAsiLNJwfKQ=";
    };
    berkeley-softfloat-3 = fetchzip {
      url = "https://gitlab.com/qemu-project/berkeley-softfloat-3/-/archive/b64af41c3276f97f0e181920400ee056b9c88037/berkeley-softfloat-3-b64af41c3276f97f0e181920400ee056b9c88037.tar.gz";
      hash = "sha256-Yflpx+mjU8mD5biClNpdmon24EHg4aWBZszbOur5VEA=";
    };
    berkeley-testfloat-3 = fetchzip {
      url = "https://gitlab.com/qemu-project/berkeley-testfloat-3/-/archive/e7af9751d9f9fd3b47911f51a5cfd08af256a9ab/berkeley-testfloat-3-e7af9751d9f9fd3b47911f51a5cfd08af256a9ab.tar.gz";
      hash = "sha256-inQAeYlmuiRtZm37xK9ypBltCJ+ycyvIeIYZK8a+RYU=";
    };
    dtc = fetchzip {
      url = "https://gitlab.com/qemu-project/dtc/-/archive/b6910bec11614980a21e46fbccc35934b671bd81/dtc-b6910bec11614980a21e46fbccc35934b671bd81.tar.gz";
      hash = "sha256-gx9LG3U9etWhPxm7Ox7rOu9X5272qGeHqZtOe68zFs4=";
    };
    libblkio = fetchzip {
      url = "https://gitlab.com/libblkio/libblkio/-/archive/f84cc963a444e4cb34813b2dcfc5bf8526947dc0/libblkio-f84cc963a444e4cb34813b2dcfc5bf8526947dc0.tar.gz";
      hash = "sha256-suN0EvFzDi17HJSHUFRl8kVFicOxGaji8grlo1DoT8E=";
    };
    libvfio-user = fetchzip {
      url = "https://gitlab.com/qemu-project/libvfio-user/-/archive/4d9f663450fa80ff375612dbbafe073700e3d3d8/libvfio-user-4d9f663450fa80ff375612dbbafe073700e3d3d8.tar.gz";
      hash = "sha256-fHD5tY6R0vU6bE4/FQTFkskRYzEKgYfVrkItoEJTL9Q=";
    };
    slirp = fetchzip {
      url = "https://gitlab.freedesktop.org/slirp/libslirp/-/archive/26be815b86e8d49add8c9a8b320239b9594ff03d/libslirp-26be815b86e8d49add8c9a8b320239b9594ff03d.tar.gz";
      hash = "sha256-6LX3hupZQeg3tZdY1To5ZtkOXftwgboYul792mhUmds=";
    };
  };

  copySubprojects = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: src: ''
      cp -r --no-preserve=mode ${src} $sourceRoot/subprojects/${name}
    '') wrapSubprojects
  );

  applyPackagefiles = ''
    for pf in $sourceRoot/subprojects/packagefiles/*/; do
      name=$(basename "$pf")
      if [ -d "$sourceRoot/subprojects/$name" ]; then
        cp -r --no-preserve=mode "$pf"/* "$sourceRoot/subprojects/$name/"
      fi
    done
  '';
in
pkgsEdge.qemu.overrideAttrs (old: {
  version = "11.1.0-rc3";
  src = fetchurl {
    url = "https://gitlab.com/qemu-project/qemu/-/archive/v11.1.0-rc3/qemu-v11.1.0-rc3.tar.gz";
    hash = "sha256-JHXEmURJhJaouBY1JUlQfK8NnqfPP0WyGMczSLNokrY=";
  };
  # QEMU 11.1 uses Hypervisor.framework GIC APIs (hv_gic_*) added in macOS 15.
  # Default SDK is 14.4; apple-sdk_26 provides the required headers.
  buildInputs = old.buildInputs ++ lib.optionals stdenv.isDarwin [ pkgsEdge.apple-sdk_26 ];
  patches = (old.patches or [ ]) ++ [
    # NMD-251 Phase 1: JSON-line trace of EC_SYSTEMREGISTERTRAP exits,
    # gated by QEMU_HVF_SYSREG_TRACE env var (inert when unset).
    # hvf.c only compiles on Darwin; on Linux this just verifies the
    # patch applies.
    ./patches/hvf-sysreg-trace.patch
    # NMD-251 Phase 2: FEAT_VHE emulation, gated by -accel hvf,fake-el2=on.
    # Applied after the trace patch (both touch the EC_SYSTEMREGISTERTRAP
    # case). Depends on vhe_core.{c,h}, injected below.
    ./patches/hvf-vhe-emulation.patch
  ];
  postUnpack = (old.postUnpack or "") + ''
    ${copySubprojects}
    ${applyPackagefiles}
  '';
  # The VHE emulation core is maintained as standalone, Linux-tested C in the
  # nixhome repo (home/scripts/qemu/vhe). Inject it into the QEMU tree after
  # patching so meson (referenced by hvf-vhe-emulation.patch) can compile it.
  postPatch = (old.postPatch or "") + ''
    cp ${../../scripts/qemu/vhe/vhe_core.c} target/arm/hvf/vhe_core.c
    cp ${../../scripts/qemu/vhe/vhe_core.h} target/arm/hvf/vhe_core.h
    chmod -R u+w target/arm/hvf
  '';
})
