# Powerline separator glyph sets.
#
# Each variant exposes: left, right, middle.
#   left   — leading edge of a module (color block starts here)
#   middle — between icon-block and text-block within a two-tone module
#   right  — trailing edge of a module (color block ends here)
#
# Requires a Nerd Font for the round/sharp/soft variants; "none" works without.
{
  round = {
    left   = "";   # nf-pl-left_hard_divider  (rounded)
    right  = "";   # nf-pl-right_hard_divider (rounded)
    middle = "";   # nf-pl-right_soft_divider (rounded, between same-bg)
  };

  sharp = {
    left   = "";   # nf-pl-left_hard_divider  (sharp/chevron)
    right  = "";   # nf-pl-right_hard_divider (sharp/chevron)
    middle = "";   # nf-pl-right_soft_divider
  };

  soft = {
    left   = "░";  # block fade-in
    right  = "░";  # block fade-out
    middle = "▒";
  };

  none = {
    left   = "";
    right  = "";
    middle = " ";   # plain space between icon and text
  };
}
