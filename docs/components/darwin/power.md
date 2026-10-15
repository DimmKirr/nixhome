# Always-awake Tart host

## Connections

`flake.nix` -> `darwinConfigurations.automationd` ->
`hosts/automationd/default.nix` -> `modules/darwin/power.nix`.

- nix-darwin `power.sleep` sets computer/display/disk sleep to never and disables power-button sleep.
- Post-activation applies `pmset -a`: sleep/display/disk timers zero, sleep disabled. Supported standby, autopoweroff, hibernation, Power Nap, Low Power Mode and dimming settings are disabled.
- `org.nixos.always-awake` is a root launch daemon. At boot it reapplies the same policy, then runs `caffeinate -dims`. launchd restarts it if it exits. Assertions survive logout; the daemon returns after reboot.
- Optional settings absent from `pmset -g custom` are logged and skipped, avoiding Intel-only assumptions on Apple Silicon. Real pmset errors fail the script and are logged to `/var/log/always-awake.log`.

This targets sleep-induced Tart GPU problems. It does not disable hardware clock gating, thermal protection or forced emergency shutdown. GPU recovery/rendering still requires a live Tart check.

## Activate and verify on the Mac

The `path:` flake reference includes newly created, not-yet-tracked module files.

```sh
sudo darwin-rebuild switch --flake path:/Users/dmitry/dev/nmd/nixhome#automationd
pmset -g custom
pmset -g assertions
sudo launchctl print system/org.nixos.always-awake
```

Expected: sleep/displaysleep/disksleep are zero for every listed power source; supported optional settings are zero; the daemon is running. `pmset -g` shows `SleepDisabled 1`; assertions include display and idle-system sleep prevention from caffeinate, plus system-sleep prevention on AC power.

## Drift points

- GUI/pmset changes after activation can change persistent settings. The next switch or daemon restart reapplies policy; caffeinate assertions remain active in between.
- Import removal alone does not reset pmset preferences. To revert, remove the daemon/module and explicitly restore the desired timers and optional settings, including `pmset -a disablesleep 0`.
- OS/hardware support changes affect the optional settings reported by `pmset -g custom`.

## Validation

| Level | Check | Cost |
|---|---|---|
| L1 | Nix syntax, generated policy/daemon shell syntax and ShellCheck, configured timers/assertions | Seconds |
| L2 | Darwin rebuild on the Mac | Minutes |
| L3 | Live pmset/assertion/launchd inspection, then leave a GPU-using Tart VM idle past the former sleep interval | Minutes or longer |

Local syntax, configuration extraction and shell checks passed. Full flake evaluation/build and live activation were not completed in the container: its Nix daemon socket refused connections, and host SSH authentication was unavailable.

References: [nix-darwin power options](https://nix-darwin.github.io/nix-darwin/manual/), [Apple pmset](https://github.com/apple-oss-distributions/PowerManagement/blob/main/pmset/pmset.1), [Apple caffeinate](https://github.com/apple-oss-distributions/PowerManagement/blob/main/caffeinate/caffeinate.8).
