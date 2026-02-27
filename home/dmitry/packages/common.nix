# Cross-platform packages (works on both macOS and Linux including aarch64-linux)
{
  pkgs,
  pkgsUnstable,
  pkgsEdge,
  ...
}:
let
  # Stable channel packages
  stable = with pkgs; [
    coreutils
    findutils
    tree
    unzip
    wget
    zstd
    nixd
    ripgrep
    htop
    tmux
    direnv
    nixfmt-rfc-style
    treefmt
    awscli2
    dive
    docker-compose
    gvproxy
    xz
    go-task

    kubectl
    k6
    obsidian
    git
    git-lfs
    git-secrets
    mc
    python2

    kubernetes-helm

    curl
    ets

    go-task

    asciinema
    termtosvg
    agg

    # fonts
    noto-fonts-color-emoji
    cantarell-fonts
    source-code-pro
    gentium

    inetutils
    nixfmt-rfc-style

    # Go
    go
    cobra-cli

    nil
    go-task

    # Kubernetes
    kubent
    kubepug
    kube-capacity

    spice
    virt-viewer

    vscode
    gh

    qrencode

    pandoc

    powershell

    localstack
    aria2
    agg
    asciinema
    termsvg

    terraform-docs

    yamllint
    yq-go
    nmap
    netcat-gnu
    gitleaks
    pre-commit

    # Yubikey support
    libfido2
    yubikey-manager
    yubikey-personalization
    openssh  # OpenSSH with FIDO2 support

    alejandra
    pkg-config
    autoconf
    autogen
    automake
    libtool
    postgresql
    gdbm

    # Build dependencies
    openssl
    zlib
    cmake
    gnumake
    ijhttp
    hurl
    fswatch
    home-assistant-cli
    shfmt
    ffmpeg
    tmuxp
    aws-vault
    graphviz
  ];

  # Unstable channel packages
  unstable = with pkgsUnstable; [
    jetbrains-toolbox
    vhs
    yt-dlp
    k9s
    t-rec
    goreleaser
    hcloud
    newman
    jira-cli-go
    secp256k1

    ffuf

    air
    expect
    hugo
    openai-whisper

    iodine
    postman
    drawio

    vagrant
    packer
    audacity

    wireguard-tools
    opencode

    google-cloud-sdk  # gcloud CLI including gcloud run
    google-cloud-sql-proxy

#    codex # using brew for now as nix version needs an overlay for a newer version
    #lmstudio using native macos install for now.
  ];

  # Edge channel packages (nixpkgs master)
  edge = with pkgsEdge; [
    # seclists  # Moved to darwin.nix - too large for devbox container
    # libngspice  # Conflicts with ngspice from other dependencies
    claude-code
  ];
in
stable ++ unstable ++ edge
