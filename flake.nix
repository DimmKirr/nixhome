{
  description = "Dmitry's multiplatform Nix configuration (macOS & NixOS)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs-edge.url = "github:NixOS/nixpkgs/master";


    nix-darwin = {
      url = "github:LnL7/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };


    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };


    #    _1password-shell-plugins.url = "github:1Password/shell-plugins";
    #    mac-app-util.url = "github:hraban/mac-app-util"; # Fixes home-manager symlinked apps

    nixvim = {
      #      url = "github:nix-community/nixvim";
      # If you are not running an unstable channel of nixpkgs, select the corresponding branch of nixvim.
      url = "github:nix-community/nixvim/nixos-26.05";
    };

    claude-code = {
      url = "github:roman/claude-code.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    comfyui = {
      url = "github:utensils/comfyui-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs =
    inputs@{
      self,
      nix-darwin,
      home-manager,
      nixpkgs,
      nixpkgs-unstable,
      nixpkgs-edge,
      #      mac-app-util,
      nixvim,
      ...
    }:
    {
      #      formatter.aarch64-darwin = nixpkgs.legacyPackages.aarch64-darwin.nixfmt-rfc-style;

      # NixOS configurations for Linux hosts
      nixosConfigurations = {
        "jump" = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            # Include the NixOS hardware and system configuration
            ./hosts/jump/hardware-configuration.nix
            ./hosts/jump/default.nix

            # Setup home-manager
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                # Use the system's nixpkgs (with allowUnfree from
                # hosts/jump/default.nix) instead of a separate HM instance —
                # otherwise unfree home packages like obsidian get rejected.
                # Mirrors the darwin config below.
                useGlobalPkgs = true;
                # Include the home-manager module
                users.dmitry = import ./home/dmitry/default.nix;
                extraSpecialArgs = {
                  inherit nixvim;
                  pkgsUnstable = import inputs.nixpkgs-unstable {
                    system = "x86_64-linux";
                    config = {
                      allowUnfree = true;
                      permittedInsecurePackages = [ "python-2.7.18.12" ];
                    };
                  };

                  pkgsEdge = import inputs.nixpkgs-edge {
                    system = "x86_64-linux";
                    config = {
                      allowUnfree = true;
                      permittedInsecurePackages = [ "python-2.7.18.12" ];
                    };
                  };
                };
              };
            }
          ];
          specialArgs = {
            inherit inputs;
            inherit nixvim;

            pkgsUnstable = import inputs.nixpkgs-unstable {
              system = "x86_64-linux";
              config = {
                allowUnfree = true;
                permittedInsecurePackages = [ "python-2.7.18.12" ];
              };
            };

            pkgsEdge = import inputs.nixpkgs-edge {
              system = "x86_64-linux";
              config = {
                allowUnfree = true;
                permittedInsecurePackages = [ "python-2.7.18.12" ];
              };
            };
          };
        };
      };

      # macOS configurations
      darwinConfigurations = {
        "automationd" = nix-darwin.lib.darwinSystem {
          system = "aarch64-darwin"; # alternatively "aarch64-darwin"
          modules = [

            # include the darwin module
            ./hosts/automationd/default.nix

            # setup home-manager
            home-manager.darwinModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                # include the home-manager module
                users.dmitry = import ./home/dmitry/default.nix;
                sharedModules = [
                  #                  mac-app-util.homeManagerModules.default # disabled trampolines for now.
                ];
                extraSpecialArgs = {
                  inherit nixvim;
                  # TODO refactor to have packages config in one place for both stable and unstable
                  pkgsUnstable = import inputs.nixpkgs-unstable {
                    system = "aarch64-darwin";
                    config = {
                      allowUnfree = true;
                      permittedInsecurePackages = [ "python-2.7.18.12" ];
                    };
                  };

                  pkgsEdge = import inputs.nixpkgs-edge {
                    system = "aarch64-darwin";
                    config = {
                      allowUnfree = true;
                      permittedInsecurePackages = [ "python-2.7.18.12" ];
                    };
                  };

                };
              };
            }
            #            mac-app-util.darwinModules.default

          ];
          specialArgs = {
            inherit inputs;
            inherit nixvim;

            pkgsUnstable = import inputs.nixpkgs-unstable {
              system = "aarch64-darwin";
              config = {
                allowUnfree = true;
                permittedInsecurePackages = [ "python-2.7.18.12" ];
              };
            };

            pkgsEdge = import inputs.nixpkgs-edge {
              system = "aarch64-darwin";
              config = {
                allowUnfree = true;
                permittedInsecurePackages = [ "python-2.7.18.12" ];
              };
            };
          };
        };
      };

      # Standalone home-manager configurations (for containers, non-NixOS Linux, etc.)
      homeConfigurations = {
        "devbox" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.aarch64-linux;
          modules = [ ./hosts/devbox/default.nix ];
          extraSpecialArgs = {
            inherit nixvim;
            pkgsUnstable = import inputs.nixpkgs-unstable {
              system = "aarch64-linux";
              config = {
                allowUnfree = true;
                permittedInsecurePackages = [ "python-2.7.18.12" ];
              };
            };

            pkgsEdge = import inputs.nixpkgs-edge {
              system = "aarch64-linux";
              config = {
                allowUnfree = true;
                permittedInsecurePackages = [ "python-2.7.18.12" ];
              };
            };
          };
        };

        # devcell container — session user `dmitry` at /home/dmitry.
        # Mirrors devcell's convention: bare name = x86_64-linux, `-aarch64` = aarch64-linux.
        # Coexists with the devcell base flake (which owns /opt/devcell).
        "devcell" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          modules = [ ./hosts/devcell/default.nix ];
          extraSpecialArgs = {
            inherit nixvim;
            pkgsUnstable = import inputs.nixpkgs-unstable {
              system = "x86_64-linux";
              config = {
                allowUnfree = true;
                permittedInsecurePackages = [ "python-2.7.18.12" ];
              };
            };
            pkgsEdge = import inputs.nixpkgs-edge {
              system = "x86_64-linux";
              config = {
                allowUnfree = true;
                permittedInsecurePackages = [ "python-2.7.18.12" ];
              };
            };
          };
        };

        "devcell-aarch64" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.aarch64-linux;
          modules = [ ./hosts/devcell/default.nix ];
          extraSpecialArgs = {
            inherit nixvim;
            pkgsUnstable = import inputs.nixpkgs-unstable {
              system = "aarch64-linux";
              config = {
                allowUnfree = true;
                permittedInsecurePackages = [ "python-2.7.18.12" ];
              };
            };
            pkgsEdge = import inputs.nixpkgs-edge {
              system = "aarch64-linux";
              config = {
                allowUnfree = true;
                permittedInsecurePackages = [ "python-2.7.18.12" ];
              };
            };
          };
        };
      };

    };
}
