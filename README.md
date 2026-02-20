# nixhome

Nix configuration — macOS (nix-darwin) + NixOS + standalone home-manager.

## Hosts

| Host          | Type                                | Arch           | Config                                                |
|---------------|-------------------------------------|----------------|-------------------------------------------------------|
| `automationd` | macOS (nix-darwin)                  | aarch64-darwin | [`hosts/automationd/`](hosts/automationd/default.nix) |
| `jump`        | NixOS (Linux)                       | x86_64-linux   | [`hosts/jump/`](hosts/jump/default.nix)               |
| `devbox`      | Standalone home-manager (container) | aarch64-linux  | [`hosts/devbox/`](hosts/devbox/default.nix)           |

### Apply configuration

```bash
# macOS
darwin-rebuild switch --flake .

# NixOS
nixos-rebuild switch --flake .#jump

# Devbox (container)
home-manager switch --flake .#devbox
```

---

## Package Map

### Nix — Common (all platforms)

[`home/dmitry/packages/common.nix`](home/dmitry/packages/common.nix) — three channels:

| Channel            | Examples                                                                                          |
|--------------------|---------------------------------------------------------------------------------------------------|
| **stable** (25.11) | kubectl, helm, git, go, awscli2, terraform-docs, ffmpeg, tmux, vscode, gh, postgresql             |
| **unstable**       | k9s, jetbrains-toolbox, goreleaser, claude-code, google-cloud-sdk, wireguard-tools, postman, hugo |
| **edge** (master)  | *(reserved; seclists moved to darwin-only)*                                                       |

### Nix — macOS only

[`home/dmitry/packages/darwin.nix`](home/dmitry/packages/darwin.nix)

| Channel  | Packages                                                   |
|----------|------------------------------------------------------------|
| stable   | mas, defaultbrowser, raycast, ext4fuse, cocoapods, discord |
| unstable | monitorcontrol, betterdisplay                              |
| edge     | seclists                                                   |

### Nix — Linux only

[`home/dmitry/packages/linux.nix`](home/dmitry/packages/linux.nix)

xclip, wl-clipboard, xdg-utils, rofi, ddcutil, alsa-utils, pciutils, usbutils

### Homebrew — macOS only

[`home/dmitry/packages/homebrew.nix`](home/dmitry/packages/homebrew.nix)

| Type        | Notable entries                                                                                                        |
|-------------|------------------------------------------------------------------------------------------------------------------------|
| **casks**   | 1password, ghostty, slack, firefox, karabiner-elements, lm-studio, zoom, codex, linear-linear, windsurf, obs, vlc, utm |
| **brews**   | ize-dev, atun, fury-cli, openssl@3, media-control, mint                                                                |
| **masApps** | Telegram, Tailscale, WireGuard, Final Cut Pro, Canva, Trello, YubiKey Authenticator                                    |

> `karabiner-elements` must be Homebrew — nix can't register macOS app bundles properly.

---

## Home Manager Programs

[`home/programs/`](home/programs/) — imported in [`home/dmitry/default.nix`](home/dmitry/default.nix)

| Program     | Config                                             | Notes                                                                            |
|-------------|----------------------------------------------------|----------------------------------------------------------------------------------|
| zsh         | [`zsh.nix`](home/programs/zsh.nix)                 | aliases, plugins (autosuggestions, syntax-highlighting), init via `zsh-init.zsh` |
| git         | [`git.nix`](home/programs/git.nix)                 | settings, delta pager, `defaultRefFormat = files` (reftable workaround)          |
| tmux        | [`tmux.nix`](home/programs/tmux.nix)               | session/window menus, window switching bindings                                  |
| ssh         | [`ssh.nix`](home/programs/ssh.nix)                 | 1Password agent, FIDO2, host blocks (automationd.lan, *.kirr.dev)                |
| nixvim      | [`nixvim.nix`](home/programs/nixvim.nix)           | Neovim configured as code via nixvim                                             |
| k9s         | [`k9s.nix`](home/programs/k9s.nix)                 | Kubernetes TUI                                                                   |
| ghostty     | [`ghostty.nix`](home/programs/ghostty.nix)         | Terminal emulator (macOS-aware keybindings)                                      |
| karabiner   | [`karabiner.nix`](home/programs/karabiner.nix)     | Keyboard remapping, per-app fn key rules                                         |
| direnv      | [`direnv.nix`](home/programs/direnv.nix)           | Shell env loading                                                                |
| zoxide      | [`zoxide.nix`](home/programs/zoxide.nix)           | `z` smart directory jumping                                                      |
| asdf        | [`asdf.nix`](home/programs/asdf.nix)               | Version manager (ruby, python, terraform, node…)                                 |
| poetry      | [`poetry.nix`](home/programs/poetry.nix)           | Python packaging                                                                 |
| claude-code | [`claude-code.nix`](home/programs/claude-code.nix) | Claude Code CLI                                                                  |
| wokwi-cli   | [`wokwi-cli.nix`](home/programs/wokwi-cli.nix)     | Wokwi hardware simulator CLI                                                     |
| ize         | [`ize.nix`](home/programs/ize.nix)                 | Infra tooling                                                                    |
| atun        | [`atun.nix`](home/programs/atun.nix)               | Tunnel tooling                                                                   |
| jira        | [`jira.nix`](home/programs/jira.nix)               | Jira CLI config                                                                  |
| 1password   | [`1password.nix`](home/programs/1password.nix)     | 1Password CLI integration                                                        |
| zed         | [`zed.nix`](home/programs/zed.nix)                 | Zed editor config                                                                |
| opencode    | [`opencode.nix`](home/programs/opencode.nix)       | OpenCode AI editor                                                               |

### Shell scripts & init

[`home/scripts/zsh-init.zsh`](home/scripts/zsh-init.zsh) — loaded via `initContent`:

- SSH agent (1Password socket)
- Linear issue link helpers: `nmd()`, `kut()`, `core()`, `kirr()`, `tfk()`, `miska()`, `upe()`
- Jira link helper: `npt()`
- Pipeline helpers: `linear-links()`, `jira-links()`, `all-links()`
- tmux helpers: `tmuxsave`

---

## Nixpkgs Channels

| Variable       | Channel                | Used for             |
|----------------|------------------------|----------------------|
| `pkgs`         | `nixpkgs-25.11-darwin` | Default, stable      |
| `pkgsUnstable` | `nixpkgs-unstable`     | Newer packages       |
| `pkgsEdge`     | `nixpkgs master`       | Latest/bleeding edge |

## Key Inputs

| Input        | Source                                            |
|--------------|---------------------------------------------------|
| nix-darwin   | `github:LnL7/nix-darwin/nix-darwin-25.11`         |
| home-manager | `github:nix-community/home-manager/release-25.11` |
| nixvim       | `github:nix-community/nixvim/nixos-25.11`         |
| asdf         | local path `/Users/dmitry/dev/dimmkirr/nix-asdf`  |
| claude-code  | `github:roman/claude-code.nix`                    |
