# Devbox: Debian Trixie + Home Manager
# Everything installed via home-manager, reusing existing config
FROM public.ecr.aws/docker/library/debian:trixie

# Minimal apt - only to bootstrap Nix
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    xz-utils \
    sudo \
    locales \
    && rm -rf /var/lib/apt/lists/*

# Locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Create user (macOS uid/gid for volume permissions)
ARG USER_NAME=dmitry
ARG USER_UID=501
ARG USER_GID=20
RUN groupadd -g ${USER_GID} usergroup 2>/dev/null || true && \
    useradd -u ${USER_UID} -g ${USER_GID} -m -s /bin/bash ${USER_NAME} && \
    echo "${USER_NAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER ${USER_UID}:${USER_GID}
ENV HOME=/home/${USER_NAME}
WORKDIR ${HOME}

# Install Nix
RUN curl -L https://nixos.org/nix/install | sh -s -- --no-daemon && \
    mkdir -p ~/.config/nix && \
    echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf

# Nix environment
ENV NIX_PROFILE="${HOME}/.nix-profile"
ENV PATH="${NIX_PROFILE}/bin:${HOME}/.local/bin:${PATH}"
RUN echo '. ~/.nix-profile/etc/profile.d/nix.sh' >> ~/.bashrc && \
    echo '. ~/.nix-profile/etc/profile.d/nix.sh' >> ~/.profile

# Copy nixhome flake (context = repo root)
COPY --chown=${USER_UID}:${USER_GID} . ${HOME}/nixhome

# Set USER env (required by home-manager)
ENV USER=${USER_NAME}

# Run home-manager - this installs EVERYTHING
# Use --impure to allow access to env vars, --no-write-lock-file to skip asdf local path issue
RUN . ~/.nix-profile/etc/profile.d/nix.sh && \
    cd ~/nixhome && \
    nix run home-manager -- switch \
        --flake .#devbox \
        --no-write-lock-file \
        --impure \
        -b backup

# Shell setup (zsh installed and configured by home-manager)
ENV SHELL="${NIX_PROFILE}/bin/zsh"

WORKDIR /app
ENTRYPOINT ["tini", "--"]
CMD ["zsh"]
