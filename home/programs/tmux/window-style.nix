# window-status-format / current-format.
#
# Shape: ` #I:#W{flags} ` — same visible width for active and inactive, only
# colors differ. Uses tmux's built-in `#{window_flags}` for compact flag
# rendering (*, -, !, Z, ~) — a single inline string instead of four
# conditional `#{?…}` segments. Cuts escape-sequence noise on thin SSH
# clients (Termius, JuiceSSH, PuTTY) that have imperfect ANSI parsers.
# (Ticket: tmux-thin-ssh-client-status-bar-distortion)
{ lib, palette, separators }:
{
  # Inactive: bg=default so the block inherits the status bar bg — matches
  # the original Dracula plugin where inactive tabs blend into the bar
  # (only the active tab gets a colored block). Avoids the visible-block
  # look that appears when overlay_0 and surface_2 happen to differ.
  format = ''#[fg=${palette.subtext_0},bg=default] #I:#W#{?window_flags,#[fg=${palette.overlay_2}]#{window_flags}#[default],} '';

  # Active: flat block with overlay_2 (Dracula's "comment" / #6272a4) bg + bold.
  # Matches pre-framework Dracula's current-window look. Flag color uses mauve
  # to stand out against the lighter bg.
  currentFormat = ''#[fg=${palette.fg},bg=${palette.overlay_2},bold] #I:#W#{?window_flags,#[fg=${palette.mauve}]#{window_flags}#[default],} '';

  separator = "";  # windows sit flush — no bar bg between them
}
