{pkgs, ...}:
# TODO: Optimize for default fn key behavior
let
  jsonFormat = pkgs.formats.json {};
  # F5 and F6 excluded - handled separately in specialFunctionKeysRules
  # (they require different key types: apple_vendor_keyboard_key_code and generic_desktop)
  keyCodes = [
    "f1"
    "f2"
    "f3"
    "f4"
    "f7"
    "f8"
    "f9"
    "f10"
    "f11"
    "f12"
  ];

  # All function keys including F5/F6 for fn_function_keys setting
  allFunctionKeyCodes = keyCodes ++ ["f5" "f6"];

  bundleIdentifiers = [
    "com.jetbrains.PhpStorm"
    "com.jetbrains.pycharm"
    "com.jetbrains.intellij"
    "com.mitchellh.ghostty"
    "com.lemonmojo.RoyalTSX.App"
  ];

  functionKeysAreFunctionKeysRules =
    builtins.concatMap (key_code: [
      {
        type = "basic";
        from = {
          key_code = key_code;
        };
        to = [{key_code = key_code;}];
        conditions = [
          {
            type = "frontmost_application_if";
            bundle_identifiers = bundleIdentifiers;
          }
        ];
      }
    ])
    keyCodes;

  functionKeysAreMediaKeysRules =
    builtins.concatMap
    (
      {
        key_code,
        consumer_key_code,
      }: [
        {
          type = "basic";
          from = {
            key_code = key_code;
          };
          to = [{consumer_key_code = consumer_key_code;}];
          conditions = [
            {
              type = "frontmost_application_unless";
              bundle_identifiers = bundleIdentifiers;
            }
          ];
        }
      ]
    )
    [
      {
        key_code = "f1";
        consumer_key_code = "display_brightness_decrement";
      }
      {
        key_code = "f2";
        consumer_key_code = "display_brightness_increment";
      }
      {
        key_code = "f3";
        consumer_key_code = "mission_control";
      }
      {
        key_code = "f4";
        consumer_key_code = "launchpad";
      }
      {
        key_code = "f7";
        consumer_key_code = "rewind";
      }
      {
        key_code = "f8";
        consumer_key_code = "play_or_pause";
      }
      {
        key_code = "f9";
        consumer_key_code = "fast_forward";
      }
      {
        key_code = "f10";
        consumer_key_code = "mute";
      }
      {
        key_code = "f11";
        consumer_key_code = "volume_decrement";
      }
      {
        key_code = "f12";
        consumer_key_code = "volume_increment";
      }
    ];

  # Enable media keys in bundleIdentifiers when "fn" is held
  functionKeysAreMediaKeysWhenFnIsPressedRules =
    builtins.concatMap
    (
      {
        key_code,
        consumer_key_code,
      }: [
        {
          type = "basic";
          from = {
            key_code = key_code;
            modifiers = {
              mandatory = ["fn"];
            }; # Only activate when "fn" is pressed
          };
          to = [{consumer_key_code = consumer_key_code;}];
          conditions = [
            {
              type = "frontmost_application_if";
              bundle_identifiers = bundleIdentifiers;
            }
          ];
        }
      ]
    )
    [
      {
        key_code = "f1";
        consumer_key_code = "display_brightness_decrement";
      }
      {
        key_code = "f2";
        consumer_key_code = "display_brightness_increment";
      }
      {
        key_code = "f3";
        consumer_key_code = "mission_control";
      }
      {
        key_code = "f4";
        consumer_key_code = "launchpad";
      }
      {
        key_code = "f7";
        consumer_key_code = "rewind";
      }
      {
        key_code = "f8";
        consumer_key_code = "play_or_pause";
      }
      {
        key_code = "f9";
        consumer_key_code = "fast_forward";
      }
      {
        key_code = "f10";
        consumer_key_code = "mute";
      }
      {
        key_code = "f11";
        consumer_key_code = "volume_decrement";
      }
      {
        key_code = "f12";
        consumer_key_code = "volume_increment";
      }
    ];

  remapOtherKeysRules = [
  # Remaps application key (menu key) to f50 so it can be used in tmux later
    {
      type = "basic";
      from = {
        key_code = "application";
      };
      to = [
        {
          key_code = "f20";
        }
      ];
    }
  ];

  # F5 (Dictation) and F6 (Do Not Disturb) - require special handling
  # Order matters: fn+key rules must come BEFORE plain key rules
  specialFunctionKeysRules = [
    # fn+F5 -> Dictation in bundleIdentifiers apps (must come first)
    {
      type = "basic";
      from = {
        key_code = "f5";
        modifiers = {
          mandatory = ["fn"];
        };
      };
      to = [{
        consumer_key_code = "dictation";
      }];
      conditions = [
        {
          type = "frontmost_application_if";
          bundle_identifiers = bundleIdentifiers;
        }
      ];
    }
    # fn+F6 -> shift+F15 in bundleIdentifiers apps (must come first)
    {
      type = "basic";
      from = {
        key_code = "f6";
        modifiers = {
          mandatory = ["fn"];
        };
      };
      to = [{
        key_code = "f15";
        modifiers = ["shift"];
      }];
      conditions = [
        {
          type = "frontmost_application_if";
          bundle_identifiers = bundleIdentifiers;
        }
      ];
    }
    # F5 as function key in bundleIdentifiers apps (for IDE shortcuts)
    {
      type = "basic";
      from = {
        key_code = "f5";
      };
      to = [{
        key_code = "f5";
      }];
      conditions = [
        {
          type = "frontmost_application_if";
          bundle_identifiers = bundleIdentifiers;
        }
      ];
    }
    # F6 as function key in bundleIdentifiers apps (for IDE shortcuts)
    {
      type = "basic";
      from = {
        key_code = "f6";
      };
      to = [{
        key_code = "f6";
      }];
      conditions = [
        {
          type = "frontmost_application_if";
          bundle_identifiers = bundleIdentifiers;
        }
      ];
    }
    # F5 -> Dictation outside bundleIdentifiers
    {
      type = "basic";
      from = {
        key_code = "f5";
      };
      to = [{
        consumer_key_code = "dictation";
      }];
      conditions = [
        {
          type = "frontmost_application_unless";
          bundle_identifiers = bundleIdentifiers;
        }
      ];
    }
    # F6 -> shift+F15 outside bundleIdentifiers (set macOS DnD shortcut to shift+F15)
    {
      type = "basic";
      from = {
        key_code = "f6";
      };
      to = [{
        key_code = "f15";
        modifiers = ["shift"];
      }];
      conditions = [
        {
          type = "frontmost_application_unless";
          bundle_identifiers = bundleIdentifiers;
        }
      ];
    }
  ];

  # CLI commands triggered by F13-F15
  cliCommandRules = [
    # Shift+F13 for hs-home-toggle (must come first to take priority)
    {
      type = "basic";
      from = {
        key_code = "f13";
        modifiers = {
          mandatory = ["shift"];
        };
      };
      to = [
        {
          shell_command = "/bin/zsh -i -c 'hs-home-toggle'";
        }
      ];
    }
    # F13 alone for hs-nmd-toggle
    {
      type = "basic";
      from = {
        key_code = "f13";
      };
      to = [
        {
          shell_command = "/bin/zsh -i -c 'hs-nmd-toggle'";
        }
      ];
    }
    # F14 for hs-hzl-toggle
    {
      type = "basic";
      from = {
        key_code = "f14";
      };
      to = [
        {
          shell_command = "/bin/zsh -i -c 'hs-hzl-toggle'";
        }
      ];
    }
    # F15 for hs-npt-toggle
    {
      type = "basic";
      from = {
        key_code = "f15";
      };
      to = [
        {
          shell_command = "/bin/zsh -i -c 'hs-npt-toggle'";
        }
      ];
    }
  ];

  # Function keys are set to themselves to disable macOS media key behavior globally
  disableFunctionKeys = builtins.listToAttrs (
    map (key_code: {
      name = key_code;
      value = key_code;
    })
    allFunctionKeyCodes
  );

  karabinerConfig = {
    global = {
      show_in_menu_bar = false;
    };
    profiles = [
      {
        name = "Functional Keys";
        selected = true;
        virtual_hid_keyboard = {
          keyboard_type = "ansi";
          keyboard_type_v2 = "ansi";
        };
        fn_function_keys = disableFunctionKeys; # Disable "Function Keys for all devices"
        complex_modifications = {
          rules = [
            {
              description = "Enable F1-F12 keys for specific apps";
              manipulators = functionKeysAreFunctionKeysRules;
            }
            {
              description = "Default Mac function keys in all other apps";
              manipulators = functionKeysAreMediaKeysRules;
            }
            {
              description = "Enable media keys inside specific apps when fn is held";
              manipulators = functionKeysAreMediaKeysWhenFnIsPressedRules;
            }
            {
              description = "Remap other keys";
              manipulators = remapOtherKeysRules;
            }
            {
              description = "F5 Spotlight and F6 Do Not Disturb";
              manipulators = specialFunctionKeysRules;
            }
            {
              description = "CLI commands on F13-F15";
              manipulators = cliCommandRules;
            }
          ];
        };
      }
    ];
  };

  generatedKarabinerJson = jsonFormat.generate "karabiner.json" karabinerConfig;
in {
  home.file.".config/karabiner/karabiner.json".source = generatedKarabinerJson;
}
