# Fixed WebView2 runtime installer for an existing Wine/Winetricks installation.
# On macOS those are supplied by Homebrew; do not pull a second Wine into PATH.
{ lib, writeShellApplication, runCommand, coreutils, curl, unzip }:
let
  verbs = runCommand "webview2-winetricks-verbs" { } ''
    mkdir -p "$out/share/winetricks"
    cp ${./webview2fixed.verb} "$out/share/winetricks/webview2fixed.verb"
  '';
in
writeShellApplication {
  name = "winetricks-webview2";
  runtimeInputs = [ coreutils curl unzip ];
  text = ''
    if [[ "''${1:-}" == --help ]]; then
      echo 'Usage: WINEPREFIX=/path/to/prefix winetricks-webview2 [-q] [--force]'
      echo 'Installs WebView2 154.0.4258.53 for the Windows architecture exposed by Wine.'
      echo 'Requires Wine and Winetricks on PATH; honors WINE and WINETRICKS overrides.'
      exit 0
    fi
    installer="''${WINETRICKS:-winetricks}"
    if ! command -v "$installer" >/dev/null 2>&1; then
      echo "winetricks-webview2: install Wine and Winetricks first (macOS: brew install --cask wine-stable; brew install winetricks)." >&2
      exit 1
    fi
    exec "$installer" "$@" ${verbs}/share/winetricks/webview2fixed.verb
  '';
  meta = {
    description = "Install the matching fixed WebView2 runtime into a Wine prefix using Winetricks";
    platforms = lib.platforms.unix;
    mainProgram = "winetricks-webview2";
  };
}
