# Widget base — picks the right icon variant from { nerdFont, ascii, emoji, none }.
#
# Every widget calls `mkIcon` with all four variants so the right one is selected
# at eval time based on `theme.icons`. No runtime branching.
{ lib }:
{
  # Select icon glyph by active vocabulary.
  #   mkIcon icons { nerdFont = "󰒋 "; ascii = "[H] "; emoji = "💻 "; none = ""; }
  mkIcon = icons: variants:
    assert lib.assertMsg (variants ? ${icons})
      "widget icon: missing '${icons}' variant (provided: ${toString (lib.attrNames variants)})";
    variants.${icons};

  # Default widget shape — widgets spread this and override what they need.
  defaults = palette: {
    iconFg = palette.iconFgDefault;
    iconBg = palette.mauve;       # neutral-ish accent
    textFg = palette.fg;
    textBg = palette.surface_0;
    cacheSeconds = 0;             # 0 = not cached (static or fast widget)
    # skipWhenEmpty: shell-output widgets that can return empty (no music,
    # weather offline, no k8s context, no git branch) opt into this so the
    # composer wraps the rendered fragment in #{?#{==:<text>,},,<rendered>} —
    # tmux re-runs the #() to check emptiness, then emits the block only when
    # non-empty. Avoids stray #[fg=…]…#[default] escapes on empty widgets.
    # (Ticket: tmux-widgets-emit-stray-escapes-when-empty)
    skipWhenEmpty = false;
  };
}
