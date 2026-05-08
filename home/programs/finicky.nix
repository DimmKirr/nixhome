{
  pkgs,
  lib,
  ...
}: {
  home.file.".config/finicky/finicky.local.example.js" = lib.mkIf pkgs.stdenv.isDarwin {
    text = ''
      // Copy to finicky.local.js and edit for private rules.
      // Export an array of handlers (not the full config object).
      // Loaded after nix-managed rules; first match wins.
      module.exports = [
        {
          match: "private.example.com/*",
          browser: "Safari",
        },
        {
          match: ({ url }) => url.host.endsWith("internal.example.org"),
          browser: "Firefox",
        },
      ];
    '';
  };

  home.file.".finicky.js" = lib.mkIf pkgs.stdenv.isDarwin {
    text = ''
      let localHandlers = [];
      try {
        localHandlers = require("./.config/finicky/finicky.local.js") || [];
      } catch (e) {
        // finicky.local.js is optional
      }

      module.exports = {
        defaultBrowser: "Brave Browser",
        handlers: [
          {
            match: [
              "instagram.com/*",
              "*.instagram.com/*",
              "*.aws.amazon.com/*",
              "aws.amazon.com/*",
            ],
            browser: "Firefox",
          },
          ...localHandlers,
        ],
      };
    '';
  };
}
