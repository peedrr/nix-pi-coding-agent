{
  description = "Pi coding agent wrapped with nix-wrapper-modules";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    wrappers = {
      url = "github:BirdeeHub/nix-wrapper-modules";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, wrappers }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      piModule = import ./wrapper-module.nix;
    in
    {
      wrappers.piModule = (wrappers.lib.evalModule piModule).config;

      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          piPkg = pkgs.callPackage ./packages/pi/package.nix { };
        in
        {
          pi = piPkg;

          default = self.wrappers.piModule.wrap {
            inherit pkgs;
            package = piPkg;
            # pi.codingAgentDir stays null: PI_CODING_AGENT_DIR is left unset so
            # both Pi and its extensions fall back to "$HOME/.pi/agent" at runtime.
          };
        }
      );

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/pi";
        };
      });

      nixosModules.pi =
        let
          installModule = wrappers.lib.getInstallModule {
            name = "pi";
            value = piModule;
          };
        in
        { config, lib, pkgs, ... }: {
          imports = [ installModule ];
          config.wrappers.pi.enable = lib.mkDefault true;
          config.wrappers.pi.package = lib.mkDefault self.packages.${pkgs.system}.pi;
        };
      nixosModules.default = self.nixosModules.pi;
    };
}
