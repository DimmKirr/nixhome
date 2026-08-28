# hosts/steam/default.nix — standalone home-manager config for SteamOS.
#
# SteamOS uses the `deck` user. Nix is installed via the Determinate Systems
# installer (not NixOS), so this is a standalone homeConfiguration like devbox/devcell.
#
# Activate with:
#   home-manager switch --flake .#steam
{
  pkgs,
  pkgsUnstable,
  pkgsEdge,
  pkgsLegacy,
  nixvim,
  lib,
  ...
}:
let
  # GE-Proton: full DualSense haptics + controller-speaker support (11-4+),
  # 11-5 fixes the EAC regression from 11-4. Newer than nixpkgs' proton-ge-bin.
  # Update: bump version, refresh hash from the release's *-x86_64.sha512sum
  # (or nix store prefetch-file <url>).
  proton-ge = pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "proton-ge-bin";
    version = "GE-Proton11-5";
    src = pkgs.fetchurl {
      url = "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${finalAttrs.version}/${finalAttrs.version}-x86_64.tar.gz";
      hash = "sha256-3kPEsl88BH20m5bETYR1mVLFoBMypogFoJ5p+V3DinU=";
    };
    dontConfigure = true;
    dontBuild = true;
    # Proton ships prebuilt binaries; stripping/patchelf would corrupt them
    dontFixup = true;
    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r ./* $out/
      runHook postInstall
    '';
  });
in
{
  home = {
    username = "deck";
    homeDirectory = "/home/deck";
    stateVersion = "24.11";

    sessionVariables = {
      TZ = "UTC";
      EDITOR = "nvim";
      TERM = "xterm-256color";
      TMPDIR = "/home/deck/.tmp";
      PATH = builtins.concatStringsSep ":" [
        "$PATH"
        "$HOME/.nix-profile/bin"
        "$HOME/.local/bin"
        "$HOME/go/bin"
      ];
    };

    packages = with pkgs; [
      tree
      unzip
      wget
      ripgrep
      htop
      curl
      git
      lazygit
      gh
      go-task
      fzf
      yazi
      nettools

      # Kubernetes
      k3s
      kubernetes-helm
    ] ++ (with pkgsUnstable; [
      k9s
    ]);

    # Steam picks up compat tools from compatibilitytools.d; symlink into the store
    file.".local/share/Steam/compatibilitytools.d/GE-Proton11-5".source = proton-ge;

    file.".config/environment.d/10-nix.conf".text = ''
      PATH=$PATH:$HOME/.local/bin:$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin
      TMPDIR=/home/deck/.tmp
      gamescope_hdr_enabled=true
      SCREEN_WIDTH=3840
      SCREEN_HEIGHT=2160
    '';

    # Template only; activate-persistent-fixes resolves the nix binary
    # and writes the actual unit to /etc/systemd/system/k3s-agent.service.
    file.".config/k3s/agent.service".text = ''
      [Unit]
      Description=K3s Agent
      After=network-online.target
      Wants=network-online.target

      [Service]
      Type=exec
      EnvironmentFile=-/home/deck/.config/k3s/env.local
      # native duplicates every layer chain (~1M inodes); overlayfs is blocked
      # by casefold on /home, so use fuse-overlayfs (/usr/bin/fuse-overlayfs)
      ExecStart=/home/deck/.nix-profile/bin/k3s agent --data-dir /home/.rancher/k3s --snapshotter=fuse-overlayfs
      Restart=always
      RestartSec=5
      KillMode=process
      Delegate=yes
      LimitNOFILE=1048576
      LimitNPROC=infinity
      LimitCORE=infinity

      [Install]
      WantedBy=multi-user.target
    '';

    # env.local is created manually on the machine (not committed).
    # Contains: K3S_URL=https://... and K3S_TOKEN=...
    file.".config/k3s/env.local.example".text = ''
      K3S_URL=https://192.168.8.150:6443
      K3S_TOKEN=<node-token>
    '';

    file.".local/bin/activate-persistent-fixes" = {
      executable = true;
      text = ''
        #!/bin/bash
        # SteamOS persistent fixes for GPU passthrough to external display.
        # Managed by home-manager, lives on /home (survives OS updates).
        # Run once with: sudo ~/.local/bin/activate-persistent-fixes
        # After that, the system service re-applies on every boot.

        set -euo pipefail

        if [ "$(id -u)" -ne 0 ]; then
          echo "Run as root: sudo $0" >&2
          exit 1
        fi

        changed=0
        steamos-readonly disable

        # --- 1. System service (re-applies patches on boot, before sddm) ---
        svc=/etc/systemd/system/activate-persistent-fixes.service
        printf '%s\n' \
          '[Unit]' \
          'Description=SteamOS persistent fixes (GPU passthrough)' \
          'Before=sddm.service' \
          'After=local-fs.target' \
          ' ' \
          '[Service]' \
          'Type=oneshot' \
          'ExecStart=/bin/bash /home/deck/.local/bin/activate-persistent-fixes' \
          'RemainAfterExit=true' \
          ' ' \
          '[Install]' \
          'WantedBy=multi-user.target' \
          > "$svc"
        systemctl daemon-reload
        systemctl enable activate-persistent-fixes.service 2>/dev/null

        # Clean up old/renamed services
        for old in steamos-persistent-fixes gamescope-session-patch; do
          if [ -f "/etc/systemd/system/$old.service" ]; then
            systemctl disable "$old.service" 2>/dev/null || true
            rm -f "/etc/systemd/system/$old.service"
          fi
        done
        systemctl daemon-reload

        # --- 2. Sudoers (passwordless sudo for deck user) ---
        sudoers=/etc/sudoers.d/zz-deck-nopasswd
        echo 'deck ALL=(ALL) NOPASSWD: ALL' > "$sudoers"
        chmod 440 "$sudoers"
        rm -f /etc/sudoers.d/deck-persistent-fixes /etc/sudoers.d/deck-nopasswd
        if ! grep -qE '@includedir|#includedir' /etc/sudoers; then
          echo '@includedir /etc/sudoers.d' >> /etc/sudoers
        fi
        if ! visudo -c >/dev/null 2>&1; then
          echo "activate-persistent-fixes: WARNING sudoers validation failed" >&2
        fi
        if sudo -n -U deck -l 2>/dev/null | grep -q NOPASSWD; then
          echo "activate-persistent-fixes: NOPASSWD verified"
        else
          echo "activate-persistent-fixes: NOPASSWD not yet active (reboot may be needed)"
        fi

        # --- 3. Keeplist (preserve service + sudoers + keeplist itself across SteamOS updates) ---
        mkdir -p /etc/atomic-update.conf.d
        printf '%s\n' \
          'systemd/system/activate-persistent-fixes.service' \
          'sudoers.d/zz-deck-nopasswd' \
          'atomic-update.conf.d/keep-persistent-fixes.conf' \
          'modprobe.d/amdgpu-4k120.conf' \
          'systemd/system/gpu-teardown.service' \
          'systemd/system/plugin_loader.service' \
          'systemd/system/k3s-agent.service' \
          > /etc/atomic-update.conf.d/keep-persistent-fixes.conf

        # --- 4. amdgpu module params (FRL + DSC + FreeSync + deep color) ---
        modprobe_conf=/etc/modprobe.d/amdgpu-4k120.conf
        modprobe_want="options amdgpu dcfeaturemask=0x41a deep_color=1"
        if [ ! -f "$modprobe_conf" ] || [ "$(cat "$modprobe_conf")" != "$modprobe_want" ]; then
          echo "$modprobe_want" > "$modprobe_conf"
          changed=1
          echo "activate-persistent-fixes: modprobe.d updated (reboot required)"
        fi

        # --- 5. GPU teardown service (NMD-299: clean release before shutdown) ---
        gpu_svc=/etc/systemd/system/gpu-teardown.service
        printf '%s\n' \
          '[Unit]' \
          'Description=Release GPU before shutdown' \
          'DefaultDependencies=no' \
          'Before=shutdown.target reboot.target halt.target' \
          ' ' \
          '[Service]' \
          'Type=oneshot' \
          'ExecStart=/bin/bash -c "echo 0000:01:00.0 > /sys/bus/pci/drivers/amdgpu/unbind 2>/dev/null; echo 1 > /sys/bus/pci/devices/0000:01:00.0/reset; sleep 1; echo 1 > /sys/bus/pci/devices/0000:01:00.0/remove"' \
          ' ' \
          '[Install]' \
          'WantedBy=shutdown.target reboot.target halt.target' \
          > "$gpu_svc"
        systemctl daemon-reload
        systemctl enable gpu-teardown.service 2>/dev/null

        # --- 6. Dereference Lua display profile symlinks ---
        lua=/home/deck/.config/gamescope/scripts/00-gamescope/displays/sony.bravia.lua
        if [ -L "$lua" ]; then
          cp --dereference "$lua" "$lua.tmp" && mv "$lua.tmp" "$lua"
          changed=1
        fi

        # --- 7. Patch gamescope-session (HDR) ---
        src=/usr/lib/steamos/gamescope-session

        # Clean stale resolution patches from earlier versions
        sed -i 's/-w 1920 -h 1080/-w 1280 -h 800/' "$src"
        sed -i '/-W [0-9]\+.*-H [0-9]\+/d' "$src"

        # HDR tone-mapping
        sed -i '/--hdr-itm/d' "$src"
        sed -i '/-O .*/i\    --hdr-itm-enable --hdr-itm-target-nits 1000 \\' "$src"

        # --- 8. K3s Agent ---
        k3s_env=/home/deck/.config/k3s/env.local
        k3s_svc=/etc/systemd/system/k3s-agent.service
        if [ -f "$k3s_env" ] && grep -q '^K3S_TOKEN=' "$k3s_env" 2>/dev/null; then
          k3s_bin=$(readlink -f /home/deck/.local/state/nix/profiles/profile/bin/k3s 2>/dev/null || true)
          if [ -z "$k3s_bin" ] || [ ! -x "$k3s_bin" ]; then
            echo "activate-persistent-fixes: SKIP k3s-agent (nix k3s binary not found)"
          else
            printf '%s\n' \
              '[Unit]' \
              'Description=K3s Agent' \
              'After=network-online.target' \
              'Wants=network-online.target' \
              ' ' \
              '[Service]' \
              'Type=exec' \
              "EnvironmentFile=$k3s_env" \
              "ExecStart=$k3s_bin agent --data-dir /home/.rancher/k3s --snapshotter=fuse-overlayfs" \
              'Restart=always' \
              'RestartSec=5' \
              'KillMode=process' \
              'Delegate=yes' \
              'LimitNOFILE=1048576' \
              'LimitNPROC=infinity' \
              'LimitCORE=infinity' \
              ' ' \
              '[Install]' \
              'WantedBy=multi-user.target' \
              > "$k3s_svc"

            systemctl daemon-reload
            systemctl enable k3s-agent.service 2>/dev/null
            systemctl restart k3s-agent.service 2>/dev/null || true
            echo "activate-persistent-fixes: k3s-agent enabled (binary=$k3s_bin)"
          fi
        else
          echo "activate-persistent-fixes: SKIP k3s-agent (create $k3s_env with K3S_URL and K3S_TOKEN)"
        fi

        # --- 9. Decky Loader ---
        decky_dir=/home/deck/homebrew/services
        decky_bin="$decky_dir/PluginLoader"
        if [ ! -f "$decky_bin" ]; then
          echo "activate-persistent-fixes: downloading Decky Loader"
          mkdir -p "$decky_dir"
          tag=$(curl -fsSL -o /dev/null -w '%{redirect_url}' https://github.com/SteamDeckHomebrew/decky-loader/releases/latest | grep -oP 'v[\d.]+')
          curl -fsSL "https://github.com/SteamDeckHomebrew/decky-loader/releases/download/$tag/PluginLoader" -o "$decky_bin"
          chmod 755 "$decky_bin"
          chown -R deck:deck /home/deck/homebrew
        fi
        decky_svc=/etc/systemd/system/plugin_loader.service
        printf '%s\n' \
          '[Unit]' \
          'Description=SteamDeck Plugin Loader' \
          'After=network.target' \
          ' ' \
          '[Service]' \
          'Type=simple' \
          'User=root' \
          'Restart=always' \
          'KillMode=process' \
          'TimeoutStopSec=15' \
          "ExecStart=$decky_bin" \
          "WorkingDirectory=$decky_dir" \
          'Environment=UNPRIVILEGED_PATH=/home/deck/homebrew' \
          'Environment=PRIVILEGED_PATH=/home/deck/homebrew' \
          'Environment=LOG_LEVEL=INFO' \
          ' ' \
          '[Install]' \
          'WantedBy=multi-user.target' \
          > "$decky_svc"
        systemctl daemon-reload
        systemctl enable plugin_loader.service 2>/dev/null
        systemctl start plugin_loader.service 2>/dev/null || true

        steamos-readonly enable
        echo "activate-persistent-fixes: done"
      '';
    };
  };

  xdg.configFile."gamescope/scripts/00-gamescope/displays/sony.bravia.lua".text = ''
    gamescope.config.known_displays.sony_bravia = {
        pretty_name = "Sony BRAVIA TV",
        dynamic_refresh_rates = { 60, 120 },
        hdr = {
            supported = true,
            force_enabled = true,
            eotf = gamescope.eotf.gamma22,
            max_content_light_level = 1000,
            max_frame_average_luminance = 800,
            min_content_light_level = 0.005
        },
        dynamic_modegen = function(base_mode, refresh)
            debug("Generating mode "..refresh.."Hz for Sony BRAVIA TV")
            local mode = base_mode
            gamescope.modegen.set_resolution(mode, 3840, 2160)
            -- CTA-861-G standard blanking (htotal=4400, vtotal=2250)
            gamescope.modegen.set_h_timings(mode, 176, 88, 296)
            gamescope.modegen.set_v_timings(mode, 8, 10, 72)
            -- Hardcode exact CTA-861-G pixel clocks (calc_max_clock gets them wrong)
            if refresh == 120 then
                mode.clock = 1188000  -- VIC 118: 4400*2250*120 = 1188 MHz
            elseif refresh == 60 then
                mode.clock = 594000   -- VIC 97: 4400*2250*60 = 594 MHz
            else
                mode.clock = gamescope.modegen.calc_max_clock(mode, refresh)
            end
            mode.vrefresh = gamescope.modegen.calc_vrefresh(mode)
            return mode
        end,
        matches = function(display)
            if display.vendor == "SNY" and display.product == 0xc105 then
                debug("[sony_bravia] Matched vendor: "..display.vendor.." product: "..display.product)
                return 5000
            end
            return -1
        end
    }
    debug("Registered Sony BRAVIA TV as a known display")
  '';

  systemd.user.services.persistent-fixes-watchdog = {
    Unit = {
      Description = "Check if persistent fixes need re-bootstrapping after SteamOS update";
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = toString (pkgs.writeShellScript "persistent-fixes-watchdog" ''
        if sudo -n /home/deck/.local/bin/activate-persistent-fixes 2>/dev/null; then
          exit 0
        fi
        # Sudoers rule is missing (wiped by SteamOS update)
        ${pkgs.libnotify}/bin/notify-send \
          --urgency=critical \
          --app-name="SteamOS Fixes" \
          "SteamOS was updated" \
          "Persistent fixes need re-bootstrapping. Run:\nsudo ~/.local/bin/activate-persistent-fixes"
      '');
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "--delete-older-than 7d";
  };


  fonts.fontconfig.enable = true;

  programs = {
    home-manager.enable = true;

    direnv   = import ../../home/programs/direnv.nix   { inherit pkgs; };
    git      = import ../../home/programs/git.nix      { inherit pkgs; };
    tmux     = import ../../home/programs/tmux.nix     { pkgs = pkgsUnstable; };
    nixvim   = lib.recursiveUpdate (import ../../home/programs/nixvim.nix { inherit pkgs; }) {
      plugins.lsp.servers.basedpyright.enable = false;
    };
    zoxide   = import ../../home/programs/zoxide.nix   { inherit pkgs; };
    bash = {
      enable = true;
      shellAliases = {
        sudo = ''sudo env PATH="$PATH"'';
        hms = "cd ~/.config/home-manager && git pull && find ~ -maxdepth 5 -name '*.backup*' -delete 2>/dev/null; home-manager switch --flake .#steam -b backup && find ~ -maxdepth 5 -name '*.backup' -delete 2>/dev/null";
      };
    };
    zsh      = (import ../../home/programs/zsh.nix      { inherit pkgs pkgsUnstable; }) // {
      shellAliases.sudo = ''sudo env PATH="$PATH"'';
      shellAliases.hms = "cd ~/.config/home-manager && git pull && find ~ -maxdepth 5 -name '*.backup*' -delete 2>/dev/null; home-manager switch --flake .#steam -b backup && find ~ -maxdepth 5 -name '*.backup' -delete 2>/dev/null";
    };
    ssh      = import ../../home/programs/ssh.nix      { inherit pkgs; };
    starship = import ../../home/programs/starship.nix { };
    mc       = import ../../home/programs/mc.nix       { inherit pkgs; };
    k9s      = import ../../home/programs/k9s.nix      { inherit pkgsUnstable; };
  };

  xdg.configFile."mc/skins/dracula256.ini".source = ../../home/programs/mc-skins/dracula256.ini;
  xdg.configFile."vifm/vifmrc".source             = ../../home/programs/vifm/vifmrc;
  xdg.configFile."vifm/colors".source             = ../../home/programs/vifm/colors;

  services.flatpak = {
    enable = true;
    remotes = [
      {
        name = "flathub";
        location = "https://flathub.org/repo/flathub.flatpakrepo";
      }
      {
        name = "GeForceNOW";
        location = "https://international.download.nvidia.com/GFNLinux/flatpak/geforcenow.flatpakrepo";
      }
    ];
    packages = [
      { appId = "com.nvidia.geforcenow"; origin = "GeForceNOW"; }
      "net.davidotek.pupgui2"
    ];
    update.onActivation = true;
  };

  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.permittedInsecurePackages = [ "python-2.7.18.12" ];

  targets.genericLinux.enable = true;

  imports = [
    nixvim.homeManagerModules.nixvim
  ];
}
