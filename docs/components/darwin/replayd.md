# Disable replayd on the affected macOS instance

## Connections

`flake.nix` -> `darwinConfigurations.automationd` ->
`hosts/automationd/default.nix` -> `modules/darwin/replayd.nix`.

The module disables `gui/<primary-user-uid>/com.apple.replayd` through launchctl,
then boots out the existing job. A root post-activation hook applies it on
switch; a primary-user LaunchAgent applies it at GUI login. If no GUI domain
exists during activation, the hook explicitly defers to login.

`launchctl disable` is persistent; killing the PID alone is not. The Apple
LaunchAgent plist is not edited or shadowed. Permission/protection failures
return nonzero with diagnostics. No SIP changes are made. The user-agent log
is `~/Library/Logs/disable-replayd.log`.

This affects capture/recording/broadcast clients using the service. ReplayKit
is a capture framework; the available documentation does not establish that
replayd continuously buffers the display without a requesting client. A GPU
restart report naming replayd is evidence to investigate, not proof that it
is the root cause of the GPU failure.

## Apply and verify

Run in the macOS instance whose GPU report names replayd. Host and Tart guest
have separate launchd domains and configurations; changing one cannot disable
the other's replayd.

```sh
sudo darwin-rebuild switch --flake path:/Users/dmitry/dev/nmd/nixhome#automationd
launchctl print-disabled "gui/$(id -u)"
launchctl print "gui/$(id -u)/com.apple.replayd"
pgrep -u "$(id -u)" -x replayd
```

Expected: the disabled entry is true; the service lookup and pgrep report no
service/process. This must be checked live: a successful Nix evaluation is not
proof that the installed macOS permits unloading this Apple service.

To undo, first remove the module import and rebuild so the login agent is
removed; then run as the affected GUI user:

```sh
launchctl enable "gui/$(id -u)/com.apple.replayd"
launchctl bootstrap "gui/$(id -u)" /System/Library/LaunchAgents/com.apple.replayd.plist
```

## Drift and validation

- Label, domain and macOS service protections require live verification after OS upgrades.
- User UID comes from `id`, not a hardcoded 501.
- Removing the module does not remove launchctl's persistent disabled override; use the undo commands.
- L1 (seconds): Nix syntax, extracted shell syntax/ShellCheck, mocked loaded/unloaded/no-GUI/permission-denied/bootout-failed cases passed.
- L2/L3: real Darwin switch, disabled-state/process check and GPU workload observation remain outstanding. Container-to-Mac SSH access is unavailable.

Sources: [Apple ReplayKit](https://developer.apple.com/documentation/replaykit),
[Apple screen recording access controls](https://support.apple.com/guide/mac-help/control-access-screen-system-audio-recording-mchld6aa7d23/mac),
[Apple launchctl manual reproduced from Xcode](https://keith.github.io/xcode-man-pages/launchctl.1.html),
[nix-darwin launchd implementation](https://github.com/nix-darwin/nix-darwin/blob/master/modules/system/launchd.nix).
