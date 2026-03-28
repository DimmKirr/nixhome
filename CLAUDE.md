# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Key Commands

### Build and Switch Configuration
```bash
# Build and switch to the new Darwin configuration (requires sudo for system activation)
sudo darwin-rebuild switch --flake .

# Build without switching (test changes, no sudo needed)
darwin-rebuild build --flake .

# If builds fail due to sandbox restrictions (common on macOS), try:
sudo darwin-rebuild switch --flake . --option sandbox false
```

### Format Nix Files
```bash
# Format all .nix files using nixfmt (configured in treefmt.toml)
treefmt
```

### Update Dependencies
```bash
# Update all flake inputs
nix flake update

# Update specific input
nix flake update nixpkgs
```

### Syntax Check and Validation

#### Quick Validation Commands
```bash
# Check flake syntax without building (fast validation)
nix flake check --no-build

# Full flake check including build validation
nix flake check

# Show flake outputs structure
nix flake show

# Display flake metadata and all inputs
nix flake metadata
```

#### Complete Validation Procedure

This is the comprehensive validation workflow to ensure the flake is syntactically correct and all dependencies are accessible:

**Step 1: Syntax Validation**
```bash
# Verify flake syntax and structure (no downloads, fast)
nix flake check --no-build

# Expected output:
# warning: Git tree '/path/to/nixhome' is dirty  (if uncommitted changes exist)
# evaluating flake...
# checking flake output 'darwinConfigurations'...
# all checks passed!
```

**Step 2: Verify Flake Structure**
```bash
# Display outputs to confirm structure is valid
nix flake show

# Expected output should show:
# └───darwinConfigurations: unknown
```

**Step 3: Test Dependency Resolution**
```bash
# Verify all inputs are defined and locked correctly
nix flake metadata

# Expected output shows all inputs with their locked revisions:
# Inputs:
# ├───asdf: path:/Users/dmitry/dev/dimmkirr/nix-asdf
# ├───claude-code: github:roman/claude-code.nix/...
# ├───home-manager: github:nix-community/home-manager/...
# ├───nix-darwin: github:LnL7/nix-darwin/...
# ├───nixpkgs: github:NixOS/nixpkgs/...
# ├───nixpkgs-edge: github:NixOS/nixpkgs/...
# ├───nixpkgs-unstable: github:NixOS/nixpkgs/...
# └───nixvim: github:nix-community/nixvim/...
```

**Step 4: Test Remote Dependency Downloads**

Verify each remote input can be downloaded (skip local paths like asdf):

```bash
# Test nixpkgs stable channel
nix flake metadata github:NixOS/nixpkgs/22d865d488f95600995c57dda921e16acd37825b

# Test nixpkgs unstable channel
nix flake metadata github:NixOS/nixpkgs/c633f572eded8c4f3c75b8010129854ed404a6ce

# Test nixpkgs edge (master)
nix flake metadata github:NixOS/nixpkgs/9ff59939390c6f52d9b129698ef5263a8fa733cb

# Test home-manager
nix flake metadata github:nix-community/home-manager/44831a7eaba4360fb81f2acc5ea6de5fde90aaa3

# Test nix-darwin
nix flake metadata github:LnL7/nix-darwin/d76299b2cd01837c4c271a7b5186e3d5d8ebd126

# Test nixvim
nix flake metadata github:nix-community/nixvim/75338e26c5c9faa8325d73f3187407892437d636

# Test claude-code
nix flake metadata github:roman/claude-code.nix/f4a27ea3427a5bb2896ae6c8357e6f99a74ebf05
```

Each command should output:
- `unpacking 'github:...' into the Git cache...` (first time)
- Resolved URL, Locked URL, Description
- Path in /nix/store
- Revision and last modified timestamp
- Inputs (if any)

**Expected Results:**
- ✅ All remote inputs download successfully
- ✅ Each shows a valid /nix/store path
- ✅ Revisions match flake.lock
- ❌ Local paths (asdf) will fail in non-macOS environments - this is expected

**Step 5: Prefetch Test**
```bash
# Test if the entire flake can be fetched and cached
nix flake prefetch --json

# Expected output (JSON):
# {
#   "hash": "sha256-...",
#   "locked": {
#     "dirtyRev": "...",
#     "lastModified": ...,
#     "type": "git",
#     "url": "file:///path/to/nixhome"
#   },
#   "storePath": "/nix/store/...-source"
# }
```

#### Common Issues and Solutions

**Issue: "path does not exist" for asdf input**
- **Cause**: Local path `/Users/dmitry/dev/dimmkirr/nix-asdf` only exists on macOS system
- **Solution**: Expected behavior; skip asdf validation in non-macOS environments
- **Impact**: No impact on flake syntax or remote dependencies

**Issue: "Git tree is dirty" warning**
- **Cause**: Uncommitted changes in repository
- **Solution**: Normal during development; commit changes to remove warning
- **Impact**: No impact on validation

**Issue: "command not found: nix"**
- **Cause**: Nix not in PATH
- **Solution**: Source Nix profile first
  ```bash
  . /home/dmitry/.nix-profile/etc/profile.d/nix.sh
  # OR
  export PATH="/home/dmitry/.nix-profile/bin:$PATH"
  ```

**Issue: Flake update fails**
- **Cause**: Usually local path dependencies (asdf) or network issues
- **Solution**: Use `--override-input` to skip problematic inputs:
  ```bash
  nix flake lock --override-input asdf github:asdf-vm/asdf/master
  ```

#### Validation Checklist

Use this checklist before committing flake changes:

- [ ] `nix flake check --no-build` passes
- [ ] `nix flake show` displays correct outputs
- [ ] `nix flake metadata` shows all inputs
- [ ] All remote inputs tested with `nix flake metadata github:...`
- [ ] `nix flake prefetch --json` succeeds
- [ ] No syntax errors in any .nix files
- [ ] Lock file is up-to-date (if inputs changed)

## Task Management

### Task Organization

Tasks are organized in the `.context/tasks/` directory:

```
.context/
└── tasks/
    ├── todo/           # Tasks that need to be done
    │   ├── 001-setup-feature.md
    │   ├── 002-implement-service.md
    │   └── 003-update-config.md
    └── done/           # Completed tasks
        └── 000-initial-setup.md
```

### Task Workflow

1. **Finding tasks**: Check `.context/tasks/todo/` for pending work
2. **Working on a task**: Read the task file, follow the requirements
3. **Completing a task**: When finished, move the file from `todo/` to `done/`
   ```bash
   mv .context/tasks/todo/2025-12-06T10-00-00-implement-feature.md .context/tasks/done/
   ```
4. **Creating new tasks**: Add new task files to `todo/` with **ISO datetime format**

**IMPORTANT: Task Naming Convention**

ALL tasks MUST use ISO datetime format:
```
<datetimeISO>-task-name.md

Format: YYYY-MM-DDTHH-MM-SS-task-name.md
Example: 2025-12-06T10-30-00-implement-audio-capture.md
```

This ensures:
- Chronological ordering
- No naming conflicts
- Clear creation time
- Easy to sort and find

### Task File Format

Each task file should follow this structure:

```markdown
# Task: [Task Title]

**Priority**: High | Medium | Low
**Estimated Effort**: Small | Medium | Large
**Dependencies**: [List any prerequisite tasks]

## Description

[Clear description of what needs to be done]

## Requirements

- [ ] Requirement 1
- [ ] Requirement 2
- [ ] Requirement 3

## Acceptance Criteria

- [ ] Criterion 1
- [ ] Criterion 2

## Implementation Notes

[Any technical notes, considerations, or approaches]

## Testing

[How to verify the task is complete]
```

## Architecture Overview

This is a Nix-based system configuration for macOS using:

1. **nix-darwin**: System-level macOS configuration
   - Located in `nix-darwin/` directory
   - Main entry: `nix-darwin/main.nix`
   - Manages system packages, services, and macOS preferences

2. **home-manager**: User-level configuration
   - Located in `home-manager/` directory
   - Main entry: `home-manager/main.nix`
   - Manages user packages and dotfiles

3. **Key Configuration Structure**:
   - `flake.nix`: Defines inputs (nixpkgs versions, home-manager, nix-darwin, etc.) and outputs
   - `home-manager/programs/`: Individual program configurations (git, tmux, zsh, etc.)
   - `home-manager/packages.nix`: User packages list
   - `nix-darwin/homebrew.nix`: Homebrew casks and App Store apps
   - `nix-darwin/services.nix`: System services configuration

4. **Special Integrations**:
   - nixvim: Neovim configuration as code
   - asdf: Version manager integration from local path
   - claude-code: Claude Code integration
   - Multiple nixpkgs channels: stable (25.05), unstable, and edge

5. **User Configuration**:
   - Primary user: dmitry
   - Machine name: automationd
   - Architecture: aarch64-darwin (Apple Silicon)

## Detailed Architecture Analysis

### Directory Structure

```
/Users/dmitry/dev/n0mad/nixhome/
├── flake.nix                 # Main flake configuration
├── flake.lock                # Locked dependencies
├── CLAUDE.md                 # This file
├── README.md                 # Project documentation
├── treefmt.toml              # Formatter configuration
├── home-manager/             # User-level configuration
│   ├── main.nix              # Main home-manager entry point
│   ├── packages.nix          # Package lists (stable, unstable, edge)
│   ├── programs/             # Program-specific configurations
│   │   ├── git.nix
│   │   ├── tmux.nix
│   │   ├── zsh.nix
│   │   ├── karabiner.nix     # macOS-specific keyboard remapping
│   │   ├── ghostty.nix       # Terminal with macOS-specific settings
│   │   └── ...
│   ├── modules/              # Custom home-manager modules
│   │   └── programs/
│   │       ├── opencode.nix
│   │       └── wokwi-cli.nix
│   ├── configs/              # Configuration files
│   │   └── p10k-config/
│   └── scripts/              # Shell scripts and initialization
│       ├── zsh-init.zsh
│       └── ...
└── nix-darwin/               # System-level macOS configuration
    ├── main.nix              # Main nix-darwin entry point
    ├── homebrew.nix          # Homebrew packages, casks, and Mac App Store apps
    ├── services.nix          # System services (ollama, etc.)
    └── modules/              # Custom nix-darwin modules
        └── services/
            └── ollama.nix
```

### Flake Architecture

The `flake.nix` defines:

1. **Inputs** (Dependencies):
   - `nixpkgs` (25.05-darwin): Main package source
   - `nixpkgs-unstable`: Bleeding-edge packages
   - `nixpkgs-edge` (master): Very latest packages
   - `nix-darwin` (25.05): macOS system configuration framework
   - `home-manager` (25.05): User environment configuration
   - `nixvim`: Neovim as code configuration
   - `asdf`: Local path integration for version manager
   - `claude-code`: Claude Code integration

2. **Outputs**:
   - `darwinConfigurations.automationd`: The main system configuration
   - Currently hardcoded to `aarch64-darwin` (Apple Silicon)
   - Integrates both nix-darwin and home-manager modules
   - Passes `pkgsUnstable` and `pkgsEdge` as special arguments

### Platform-Specific Components

#### macOS-Only Components

1. **nix-darwin Module** (`nix-darwin/main.nix`):
   - System-level macOS configuration
   - macOS system preferences:
     - Dock settings (autohide, size, orientation, persistent apps)
     - Finder settings (view style, show extensions, etc.)
     - Global domain (keyboard UI mode, function keys)
   - Security configuration:
     - TouchID for sudo authentication (`security.pam.services.sudo_local.touchIdAuth`)
     - PAM reattach for tmux TouchID support
   - System startup configuration
   - Fonts (system-level installation)
   - User account management

2. **Homebrew** (`nix-darwin/homebrew.nix`):
   - Completely macOS-specific
   - Manages:
     - **Casks**: GUI applications not available or well-supported in Nix
     - **masApps**: Mac App Store applications
     - **Brews**: Some formula that work better through Homebrew

3. **macOS-Specific Packages**:
   - `mas`: Mac App Store CLI
   - `defaultbrowser`: macOS default browser setter
   - `raycast`: macOS launcher (with launchd agent)
   - `monitorcontrol`: macOS display brightness control
   - `betterdisplay`: Advanced macOS display management
   - `cocoapods`: iOS/macOS development dependency manager
   - `pam-reattach`: Enables TouchID in tmux

4. **macOS-Specific Program Configurations**:
   - **Karabiner Elements** (`home-manager/programs/karabiner.nix`):
     - Keyboard remapping and customization
     - Function key behavior per application
     - Complex keyboard modifications
   - **Ghostty** (`home-manager/programs/ghostty.nix`):
     - Has macOS-specific settings:
       - `macos-titlebar-style = transparent`
       - `macos-titlebar-proxy-icon = hidden`
       - `macos-option-as-alt = left`
       - `cmd+` keybindings (macOS command key)

5. **launchd Agents** (`home-manager/main.nix:122-132`):
   - macOS-specific service management
   - Example: Raycast auto-launch agent

#### Cross-Platform Compatible Components

Most of the configuration is actually cross-platform compatible:

1. **Packages** (`home-manager/packages.nix`):
   - Development tools: go, kubectl, k9s, helm
   - CLI utilities: ripgrep, htop, tree, wget, curl
   - Container tools: docker-compose, dive
   - Cloud tools: awscli2, terraform-docs
   - Version control: git, git-lfs, git-secrets, gh
   - Text editors: vscode, vim (via nixvim)
   - Media tools: ffmpeg, yt-dlp
   - Security tools: nmap, wireguard-tools
   - Most of these packages work on both macOS and Linux

2. **Program Configurations**:
   - **git** (`home-manager/programs/git.nix`)
   - **tmux** (`home-manager/programs/tmux.nix`)
   - **zsh** (`home-manager/programs/zsh.nix`)
   - **direnv** (`home-manager/programs/direnv.nix`)
   - **nixvim** (`home-manager/programs/nixvim.nix`)
   - **ssh** (`home-manager/programs/ssh.nix`)
   - **k9s** (`home-manager/programs/k9s.nix`)
   - **poetry** (`home-manager/programs/poetry.nix`)
   - **asdf** (`home-manager/programs/asdf.nix`)
   - All of these are cross-platform

3. **Environment Variables** (`home-manager/main.nix:36-67`):
   - PATH configuration
   - PYTHONPATH
   - PKG_CONFIG_PATH
   - TZ (timezone)
   - Most are portable, though some paths reference macOS-specific locations

### Multi-Channel Package Management

The configuration uses three nixpkgs channels:

1. **Stable (25.05-darwin)**: Default, most packages
2. **Unstable**: Newer packages (jetbrains-toolbox, k9s, etc.)
3. **Edge (master)**: Very latest (seclists, etc.)

Packages from different channels are combined in `packages.nix`:
```nix
basic ++ basicUnstable ++ basicEdge
```