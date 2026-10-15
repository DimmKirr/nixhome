# WebView2 for Wine

Home Manager installs `winetricks-webview2` through
`home/dmitry/packages/darwin.nix`. Wine and Winetricks remain managed by
`home/dmitry/packages/homebrew.nix` (`wine-stable` and `winetricks`).

After rebuilding the macOS configuration:

```sh
WINEPREFIX="$HOME/.wine-myapp" winetricks-webview2 -q
WINEPREFIX="$HOME/.wine-myapp" wine your-app.exe
```

The helper honors `WINEPREFIX`, `WINE`, and `WINETRICKS` (an executable name
or path). Without `WINEPREFIX`, Winetricks uses its usual default prefix.
It accepts Winetricks options such as `-q` and `--force`.

## Install flow

1. Ask Wine's `cmd.exe` for `PROCESSOR_ARCHITECTURE`, selecting x64 for AMD64,
   arm64 for ARM64, or x86 for x86. Host CPU architecture is not used:
   Apple Silicon running x64 Wine needs the x64 runtime.
2. Download the pinned `webview2.runtime.<arch>` and
   `webview2.runtime.<arch>.core` NuGet packages into Winetricks' cache.
   Winetricks verifies their SHA-256 hashes.
3. Extract and merge only `contentFiles/any/any/WebView2/`, discard
   other architectures' `EBWebView` DLLs, and check the executable, core DLL,
   ICU data, and architecture-specific WebView DLL are present before copying into the prefix.
4. Install to `C:/Program Files/Microsoft/EdgeWebView/Application/154.0.4258.53`
   and register `HKLM\Software\Microsoft\EdgeUpdate\ClientState\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}`
   with `EBWebView` pointing to that directory, in both registry views.
   Wails uses the 32-bit view and parses the final directory component as
   the runtime version. Also set the HKCU WebView2 `BrowserExecutableFolder`
   wildcard policy for standard Microsoft SDK consumers. These discovery
   settings apply to WebView2 applications in this prefix.

To enable the reported Wine DComposition workaround for the browser subprocess:

```sh
WEBVIEW2_WINE_WIN7=1 WINEPREFIX="$HOME/.wine-myapp" winetricks-webview2 -q
```

This sets `HKCU\Software\Wine\AppDefaults\msedgewebview2.exe` value `Version`
to `win7`. It is opt-in and persists in the prefix. The DLL-only smoke test
cannot validate the workaround's effect on rendering. Application-specific
browser argument passthrough fixes belong in the application, not this installer.

This installs a fixed runtime, with no Evergreen updater. Installation does
not establish that Chromium rendering works with a particular Wine version.
No Wine prefix is modified during a Nix build or Home Manager activation.

## Cheap Wine validation

Use a Windows probe under Wine to read Wails’ `ClientState/EBWebView` registration with `WOW64_32KEY`,
load `EBWebView/<arch>/EmbeddedBrowserWebView.dll` with `LoadLibraryExW`,
and resolve `CreateWebViewEnvironmentWithOptionsInternal` and
`DllCanUnloadNow`. This checks actual DLL loading and dependency resolution
without starting Chromium. It does not establish that creating a browser
environment or rendering will work.

The prepared host runner and prebuilt x64/ARM64/x86 probes are in the devcell
home checkout at `.scratch/tools/webview2/`. Run on the Mac:

```sh
bash /Users/dmitry/dev/devcell-sh/home/.scratch/tools/webview2/validate-host.sh
```

The runner builds this Nix package, installs into a fresh temporary Wine
prefix, then runs the matching probe. The prefix and `validation.log` are
retained at the printed path for diagnosis. A failure returns nonzero.

The package is portable to Linux with an existing Wine/Winetricks installation:
`pkgs.callPackage ./pkgs/winetricks-webview2 { }`.
The verb itself is installed in the helper's closure at
`share/winetricks/webview2fixed.verb` and uses the standard custom-verb API.

## Sources and updates

- [go-winkit download/extraction code](https://github.com/devcell-sh/go-winkit/blob/main/winpe/fetch_webview2.go)
- [Wails registry discovery](https://github.com/wailsapp/wails/blob/v3.0.0-beta.27/v3/internal/webview2/webviewloader/find_dll_installed.go)
- [Winetricks custom verbs](https://github.com/Winetricks/winetricks#custom-verb-files)
- [Microsoft WebView2 runtime override policy](https://learn.microsoft.com/en-us/microsoft-edge/webview2/reference/win32/webview2-idl)

To update, select a version present in both NuGet packages for all three
architectures, download all six archives, recompute SHA-256, and update the
version and checksums in `webview2fixed.verb`, the helper's help text, and this
file together. The NuGet packages are the same repackaged fixed runtime source
used by go-winkit.
