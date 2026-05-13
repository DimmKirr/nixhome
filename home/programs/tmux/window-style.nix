# window-status-format / current-format.
#
# Shape: ` #I:#W ` — same visible width for active and inactive, only colors differ.
# This matches the stock Dracula look we validated visually. Flag glyphs from
# palette.flags are appended (zoom/bell/activity/silence/last).
{ lib, palette, separators }:
let
  f = palette.flags;

  # tmux's #{?cond,then,else} interpolation — only renders flag icon if flag is set.
  flagOf = flag:
    "#{?window_${flag}_flag, #[fg=${f.${flag}.color}]${f.${flag}.icon}#[default],}";

  # `last` intentionally omitted — it indicates the previously-active window
  # (almost always set), which means every window-status block would render an
  # extra space-+-glyph. Stock Dracula doesn't show it either.
  flagsBlock = lib.concatStrings (map flagOf [ "zoomed" "bell" "activity" "silence" ]);
in
{
  # Inactive: flat block with dark-grey accent (Dracula: #44475a = overlay_0).
  format = ''#[fg=${palette.fg},bg=${palette.overlay_0}] #I:#W${flagsBlock} '';

  # Active: flat block with active.color accent + bold. Same shape as inactive
  # so widths match — only color and bold differ.
  currentFormat = ''#[fg=${palette.crust},bg=${f.active.color},bold] #I:#W${flagsBlock} '';

  separator = "";  # windows sit flush — no bar bg between them
}
