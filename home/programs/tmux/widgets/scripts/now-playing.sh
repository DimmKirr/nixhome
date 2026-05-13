#!/usr/bin/env bash
# now-playing wrapper. Calls upstream music.sh and prints a tmux-formatted
# colored block ONLY when the script returns non-empty output — otherwise
# prints nothing so the cyan block disappears entirely from the status bar.
#
# @MUSIC_SCRIPT@, @FG@, @BG@ are substituted at nix eval time.

out="$("@MUSIC_SCRIPT@" 2>/dev/null || true)"

# Trim leading/trailing whitespace to handle scripts that emit just spaces.
trimmed="${out#"${out%%[![:space:]]*}"}"
trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"

[ -z "$trimmed" ] && exit 0

# tmux interprets `#[...]` escapes inside #() output, so we draw the block
# inline. `style = "minimal"` on the widget prevents the framework composer
# from drawing its own (always-on) block.
printf '#[fg=@FG@,bg=@BG@] %s #[default]' "$out"
