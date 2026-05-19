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
# == Comma-in-style invariant ==
# tmux's `#[...]` style attribute parser splits on commas (`fg=red,bg=blue` →
# two attrs). Format expressions can also contain commas (`#{?cond,A,B}`,
# `#{==:X,Y}`). Mixing the two breaks the parser. Two consequences enforced
# below:
#   1. `fgBg` emits TWO directives `#[fg=…]#[bg=…]` instead of combined
#      `#[fg=…,bg=…]` — keeps each `#[…]` to a single attribute so the
#      `skipWhenEmpty` wrapper's `#{?#{==:…,…},…,…}` doesn't split inside.
#   2. When `iconBg` itself is a conditional (`#{?client_prefix,A,B}`), it
#      can NOT live inside `#[bg=…]` because the inner commas would split
#      the style attr. We render the whole module twice (once per branch)
#      and wrap in a top-level `#{?cond,<full-A-block>,<full-B-block>}`.
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
  # `fgBg` keeps fg and bg as separate `#[…]` directives — see file header.
  fg     = c: "#[fg=${c}]";
  fgBg   = c: b: "#[fg=${c}]#[bg=${b}]";
  reset  = "#[default]";

  # When icon is empty, collapse to single-tone (skip the icon block + middle
  # separator) so we don't render a stray empty colored block. Use iconFg
  # (the high-contrast color paired with iconBg) for the text so it's readable
  # on bright bg colors like peach/pink/sky — matches stock Dracula's
  # "dark text on accent block" style.
  twoToneOf = bg:
    if icon == ""
    then ''
      ${fg bg}${s.left}${fgBg iconFg bg}${text}${fg bg}${s.right}${reset}''
    else ''
      ${fg bg}${s.left}${fgBg iconFg bg}${icon}${fgBg textFg textBg}${s.middle}${text}${fg textBg}${s.right}${reset}'';

  flatOf = bg: ''
    ${fg bg}${s.left}${fgBg iconFg bg} ${icon} ${text} ${fg bg}${s.right}${reset}'';

  minimal = ''
    ${fg iconFg}${icon}${fg textFg}${text}${reset}'';

  styleRender = bg: {
    twoTone   = twoToneOf bg;
    flat      = flatOf bg;
    minimal   = minimal;
    powerline = twoToneOf bg;  # same as twoTone, visual diff comes from sharp separators
  }.${style};

  # Conditional-iconBg lift — see file header for the comma-in-style invariant.
  # Limitation: only handles a SIMPLE `#{?cond,A,B}` (3 comma-separated parts).
  # A nested conditional (e.g. `#{?#{==:foo,bar},A,B}`) would mis-split.
  isConditionalBg = lib.hasPrefix "#{?" iconBg;
  parsed =
    let
      inner = lib.removeSuffix "}" (lib.removePrefix "#{?" iconBg);
      parts = lib.splitString "," inner;
    in
      if isConditionalBg && builtins.length parts == 3
      then {
        cond    = builtins.elemAt parts 0;
        thenBg  = builtins.elemAt parts 1;
        elseBg  = builtins.elemAt parts 2;
      }
      else null;

  rendered =
    if parsed != null
    then "#{?${parsed.cond},${styleRender parsed.thenBg},${styleRender parsed.elseBg}}"
    else styleRender iconBg;

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
