# Status-module composer.
#
# Given a widget spec + theme dials, returns a tmux status-string fragment
# with embedded color escapes. Pure function — output goes into status-left or
# status-right via `lib.concatStringsSep`.
#
# Style modes:
#   twoTone   — [sep][iconBg block + iconFg icon][middle][textBg block + textFg text][sep]
#   flat      — [sep][iconBg block][iconFg icon + space + textFg text][sep]
#   minimal   — bare "iconFg icon text" with no background blocks or separators
#   powerline — same as twoTone but uses sharp arrow separators (caller picks sep="sharp")
#
# Args:
#   separators : { left, right, middle }  — glyph set
#   lib        : nixpkgs lib
#
# Returns a function: widgetSpec → tmux string
{ lib, separators }:
{
  # The widget contract (every field required at this layer; widgets supply defaults).
  icon,
  iconFg,
  iconBg,
  text,
  textFg,
  textBg,
  style,
  ...   # ignore widget-only metadata (cacheSeconds, _invisible, etc.)
}:
let
  s = separators;

  # tmux color-escape helpers — single source of truth so we never typo `#[fg=…]`
  fg     = c: "#[fg=${c}]";
  fgBg   = c: b: "#[fg=${c},bg=${b}]";
  reset  = "#[default]";

  # When icon is empty, collapse to single-tone (skip the icon block + middle
  # separator) so we don't render a stray empty colored block. Use iconFg
  # (the high-contrast color paired with iconBg) for the text so it's readable
  # on bright bg colors like peach/pink/sky — matches stock Dracula's
  # "dark text on accent block" style.
  twoTone =
    if icon == ""
    then ''
      ${fg iconBg}${s.left}${fgBg iconFg iconBg}${text}${fg iconBg}${s.right}${reset}''
    else ''
      ${fg iconBg}${s.left}${fgBg iconFg iconBg}${icon}${fgBg textFg textBg}${s.middle}${text}${fg textBg}${s.right}${reset}'';

  flat = ''
    ${fg iconBg}${s.left}${fgBg iconFg iconBg} ${icon} ${text} ${fg iconBg}${s.right}${reset}'';

  minimal = ''
    ${fg iconFg}${icon}${fg textFg}${text}${reset}'';

  powerline = twoTone;  # visual difference comes from caller picking separators="sharp"

  rendered = {
    inherit twoTone flat minimal powerline;
  }.${style};
in
  assert lib.assertMsg (rendered != null)
    "status-module: unknown style '${style}' (must be twoTone | flat | minimal | powerline)";
  rendered
