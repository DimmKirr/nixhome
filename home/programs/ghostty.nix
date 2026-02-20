{pkgs, ...}: {
  home.file.".config/ghostty/config".text = ''
      ## Generated via Nix
      command =  ~/.nix-profile/bin/zsh --login --interactive

      theme = Dracula

      font-family = "JetBrainsMonoNL Nerd Font Propo"

      background-opacity = 0.95

      mouse-hide-while-typing = true
      mouse-scroll-multiplier = 0.5
      macos-titlebar-style = transparent
      macos-titlebar-proxy-icon = hidden



      macos-option-as-alt = left
      keybind = alt+left=unbind

      window-padding-x = 4
      window-padding-y = 0
      window-height = 36
      window-width = 120
      keybind = cmd+t=unbind
      keybind = cmd+n=unbind
      keybind = cmd+k=unbind
      keybind = cmd+w=unbind
      keybind = cmd+d=unbind
      keybind = opt+tab=unbind
      keybind = shift+opt+tab=unbind
      keybind = f6=unbind


      # Panels - Unbind both spelled and digit_ versions
      keybind = cmd+digit_1=unbind
      keybind = cmd+digit_2=unbind
      keybind = cmd+digit_3=unbind
      keybind = cmd+digit_4=unbind
      keybind = cmd+digit_5=unbind
      keybind = cmd+digit_6=unbind
      keybind = cmd+digit_7=unbind
      keybind = cmd+digit_8=unbind
      keybind = cmd+digit_9=unbind
      keybind = cmd+digit_0=unbind


      keybind = cmd+one=text:\x021
      keybind = cmd+two=text:\x022
      keybind = cmd+three=text:\x023
      keybind = cmd+four=text:\x024
      keybind = cmd+five=text:\x025
      keybind = cmd+six=text:\x026
      keybind = cmd+seven=text:\x027
      keybind = cmd+eight=text:\x028
      keybind = cmd+nine=text:\x029
      keybind = cmd+zero=text:\x02\x2d0 # Doesn't work, sends "0"

      # Session Switch
      keybind = cmd+a=text:\x02\x70
      keybind = cmd+s=text:\x02\x6E

      keybind = shift+opt+tab=text:\x02(
      keybind = opt+tab=text:\x02)

      # Open Existing Windows
      keybind = cmd+k=text:\x02\x77/

      # New Window (ctrl+b, c)
      keybind = cmd+t=text:\x02\x63

      # Close Window (ctrl+b, x)
      keybind = cmd+w=text:\x02\x78\x79\x0D

      # Cmd + F -> Enter copy mode and start search
      keybind = cmd+f=text:\x02\x5B\x3F
      keybind = cmd+d=text:\x02\x25

      # Claude code shift+enter
      keybind = shift+enter=text:\n
  '';

}
