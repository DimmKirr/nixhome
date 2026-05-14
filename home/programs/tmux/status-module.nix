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
  # Optional: when true, wrap the rendered fragment in an emptiness check so the
  # widget collapses to nothing when its `text` evaluates to empty (e.g. shell
  # widgets with no music playing, weather offline). Defaults to false so static
  # widgets — session/host/date-time — don't pay the double-evaluation cost.
  # (Ticket: tmux-widgets-emit-stray-escapes-when-empty)
  skipWhenEmpty ? false,
  ...   # ignore widget-only metadata (cacheSeconds, _invisible, etc.)
}:
let
  s = separators;

  # tmux color-escape helpers — single source of truth so we never typo `#[fg=…]`.
  # IMPORTANT: emit fg and bg as TWO separate `#[...]` directives, not as
  # combined `#[fg=…,bg=…]`. tmux's `#{?cond,then,else}` parser splits on
  # commas; commas inside `#[…]` style attributes confuse that parser and
  # break our `skipWhenEmpty` wrappers (which are `#{?#{==:…,…},…,…}` —
  # commas inside the rendered block would be miscounted, truncating the
  # conditional). Matches the pre-framework Dracula plugin's pattern.
  fg     = c: "#[fg=${c}]";
  fgBg   = c: b: "#[fg=${c}]#[bg=${b}]";
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

  # Empty-skip wrapper. tmux's `#{?#{==:A,B},then,else}` compares two strings;
  # if `text` contains a `#()` command, tmux evaluates it before comparing,
  # so an empty command output collapses the entire block.
  #
  # IMPORTANT: pass the *bare* `#()` (no surrounding whitespace) into `#{==:…}`,
  # otherwise tmux's parser treats the padding spaces as part of the operand
  # and the comparison NEVER returns equal-to-empty (so the wrapper either
  # always renders, or — depending on tmux version — silently collapses
  # everything). The padded version stays in `${rendered}` for visual spacing.
  # This matches the pre-framework Dracula plugin's working pattern.
  # (Ticket: tmux-widgets-emit-stray-escapes-when-empty)
  bareCmd = lib.removeSuffix " " (lib.removePrefix " " text);
  guarded =
    if skipWhenEmpty
    then "#{?#{==:${bareCmd},},,${rendered}}"
    else rendered;
in
  assert lib.assertMsg (rendered != null)
    "status-module: unknown style '${style}' (must be twoTone | flat | minimal | powerline)";
  guarded
