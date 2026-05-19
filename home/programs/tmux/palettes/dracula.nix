# Dracula — palette shape matches Catppuccin's 26 slots.
# Dracula has 12 distinct colors; missing slots alias to closest match.
# Aliasing is intentional: widgets get a stable name (palette.mauve, palette.peach)
# that resolves to *some* Dracula color rather than crashing.
rec {
  name = "dracula";

  # Surfaces (Dracula has fewer surface shades than Catppuccin)
  bg        = "#282A36";  # background
  fg        = "#F8F8F2";  # foreground
  crust     = "#191A21";  # darker than bg
  mantle    = "#1E1F29";
  surface_0 = "#21222C";
  surface_1 = "#282A36";  # = bg
  overlay_0 = "#44475A";  # selection — Dracula's "Current Line"
  overlay_1 = "#54576C";
  overlay_2 = "#6272A4";  # comment
  subtext_0 = "#BFBFBF";
  subtext_1 = "#E2E2E2";

  # status-bg slot. Aliased to overlay_0 so they MUST move together — matches
  # the pre-framework Dracula plugin where window blocks blend into the bar.
  surface_2 = overlay_0;

  # Accents — Dracula has 8 distinct accents, alias the rest.
  # Mapping rationale:
  #   warm pink/red family → pink + red, alias maroon/rosewater/flamingo
  #   orange family       → peach
  #   yellow              → yellow
  #   green/teal          → green (Dracula has only one green)
  #   cyan family         → cyan/sky/sapphire (Dracula's cyan covers all)
  #   blue                → close to cyan (Dracula has no distinct blue)
  #   purple family       → mauve + lavender
  rosewater = "#FFB86C";  # alias peach (warmest neutral Dracula has)
  flamingo  = "#FF79C6";  # alias pink
  pink      = "#FF79C6";  # Dracula pink
  mauve     = "#BD93F9";  # Dracula light purple
  red       = "#FF5555";  # Dracula red
  maroon    = "#FF5555";  # alias red
  peach     = "#FFB86C";  # Dracula orange
  yellow    = "#F1FA8C";  # Dracula yellow
  green     = "#50FA7B";  # Dracula green
  teal      = "#50FA7B";  # alias green
  sky       = "#8BE9FD";  # Dracula cyan
  sapphire  = "#8BE9FD";  # alias cyan
  blue      = "#8BE9FD";  # alias cyan (no distinct blue in Dracula)
  lavender  = "#6272A4";  # Dracula dark purple / comment

  iconFgDefault = crust;

  flags = {
    # No icon for active — mauve bg + window number is identifier enough.
    active   = { icon = "";  color = mauve;     };  # matches screen 8
    last     = { icon = "·"; color = subtext_0; };
    zoomed   = { icon = "Z"; color = peach;     };
    bell     = { icon = "!"; color = red;       };
    activity = { icon = "•"; color = yellow;    };
    silence  = { icon = "~"; color = overlay_0; };
  };
}
