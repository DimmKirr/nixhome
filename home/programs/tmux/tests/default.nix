# Snapshot tests for the tmux theming framework.
#
# Run with: nix-build home/programs/tmux/tests/default.nix
#
# Each test renders a widget under a specific palette/style/separator/icons
# combination and compares the output to a fixture file. Fixtures are stored
# at fixtures/<palette>/<style>/<widget>.txt.
#
# TDD workflow:
#   1. Write fixture (paste expected tmux string)
#   2. Run test — should pass
#   3. Modify widget — test fails with a diff
#   4. Update widget code OR update fixture (intentional change)
{ pkgs ? import <nixpkgs> {}, lib ? pkgs.lib }:
let
  mkFramework = preset: import ../. {
    inherit lib pkgs;
    theme = import ../../theme.nix { inherit lib; inherit preset; };
  };

  # A single test = one renderWidget call vs. one fixture file.
  mkTest = { name, preset, widget }:
    let
      framework = mkFramework preset;
      actual    = framework.renderWidget widget;
      fixture   = ./fixtures + "/${preset}/${widget}.txt";
    in
    pkgs.runCommand "tmux-test-${name}" {} ''
      expected="$(cat ${fixture})"
      actual=${lib.escapeShellArg actual}

      if [ "$expected" = "$actual" ]; then
        echo "PASS: ${name}"
        touch "$out"
      else
        echo "FAIL: ${name}"
        echo "Expected: $expected"
        echo "Actual:   $actual"
        echo "Diff:"
        diff <(echo "$expected") <(echo "$actual") || true
        exit 1
      fi
    '';
in
{
  host-catppuccin = mkTest {
    name    = "host-catppuccin-mocha";
    preset  = "catppuccin";
    widget  = "host";
  };

  host-dracula = mkTest {
    name    = "host-dracula";
    preset  = "dracula";
    widget  = "host";
  };
}
