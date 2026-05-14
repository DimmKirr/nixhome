# Opt-in tmpfs cache wrapper for widget scripts.
#
# Wraps a shell command so it only runs at most every N seconds; otherwise
# returns the cached output. Reduces fork rate on `status-interval` ticks
# for slow widgets (weather, public IP, etc.).
#
# Usage from a widget:
#   let
#     cache = import ./_cache.nix { inherit pkgs; };
#     raw = pkgs.writeShellApplication { ... };
#     cached = cache.wrap { name = "weather"; seconds = 600; script = raw; };
#   in
#   { ...; text = " #(${cached}) "; }
{ pkgs }:
{
  # Returns a derivation that, when executed, prints either fresh or cached output.
  wrap = { name, seconds, script }:
    let
      # Tie the cache filename to the script's nix-store hash so a content
      # change (e.g. nerdFonts true→false) invalidates the cache. Without
      # this, the cache wrapper sees a "fresh" file (age < max_age) and
      # serves stale PUA output across rebuilds. The 8-char prefix of the
      # store hash is unique enough in practice.
      # (Ticket: weather widget served stale PUA glyphs after nerdFonts flip)
      contentKey = builtins.substring 0 8 (baseNameOf "${script}");
    in
    pkgs.writeShellApplication {
      name = "${name}-cached";
      runtimeInputs = [ pkgs.coreutils ];
      text = ''
        # Predictable cache location (survives reboots; same on Linux + macOS).
        # Falls back to /tmp only if $HOME is unset (shouldn't happen).
        cache_dir="''${XDG_CACHE_HOME:-''${HOME:-/tmp}/.cache}/tmux-widget"
        mkdir -p "$cache_dir"
        # Filename includes a content-derived suffix — when the underlying
        # script changes, the cache path changes, so stale output from prior
        # builds is naturally orphaned (not deleted; just no longer read).
        cache_file="$cache_dir/${name}-${contentKey}"
        max_age=${toString seconds}

        # Refresh if missing OR older than max_age. `date -r FILE +%s` reads the
        # file's mtime on both BSD (macOS) and GNU (Linux) date — avoids the
        # stat -f / -c divergence (and GNU `stat -f` does something entirely
        # different than BSD `stat -f`).
        needs_refresh=1
        if [ -f "$cache_file" ]; then
          mtime=$(date -r "$cache_file" +%s 2>/dev/null || echo 0)
          age=$(( $(date +%s) - mtime ))
          [ "$age" -lt "$max_age" ] && needs_refresh=0
        fi

        if [ "$needs_refresh" = 1 ]; then
          # Run in background to keep ticks fast; serve last cache for now.
          # Only replace cache if the fetch actually returned content — empty
          # results (transient network failure, rate limit, etc.) preserve the
          # last known good value.
          (
            ${script}/bin/${name} > "$cache_file.new" 2>/dev/null
            if [ -s "$cache_file.new" ]; then
              mv "$cache_file.new" "$cache_file"
            else
              rm -f "$cache_file.new"
            fi
          ) &
        fi

        # Print whatever's currently cached. Empty on first-ever call until the
        # background fetch completes.
        [ -f "$cache_file" ] && cat "$cache_file" || printf ""
      '';
    };
}
