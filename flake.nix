{
  description = "Dmitry's multiplatform Nix configuration (macOS & NixOS)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-25.11-darwin";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs-edge.url = "github:NixOS/nixpkgs/master";


    nix-darwin = {
      url = "github:LnL7/nix-darwin/nix-darwin-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };


    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };


    #    _1password-shell-plugins.url = "github:1Password/shell-plugins";
    #    mac-app-util.url = "github:hraban/mac-app-util"; # Fixes home-manager symlinked apps

    nixvim = {
      #      url = "github:nix-community/nixvim";
      # If you are not running an unstable channel of nixpkgs, select the corresponding branch of nixvim.
      url = "github:nix-community/nixvim/nixos-25.11";

      inputs.nixpkgs.follows = "nixpkgs";
    };

    claude-code = {
      url = "github:roman/claude-code.nix";
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
      };

    };
}
