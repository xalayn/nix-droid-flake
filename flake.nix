{
  description = "Nix-on-Droid phone configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";

    nix-on-droid = {
      url = "github:nix-community/nix-on-droid/release-24.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, nix-on-droid, ... }:
    let
      phone =
        nix-on-droid.lib.nixOnDroidConfiguration {
          pkgs = import nixpkgs {
            system = "aarch64-linux";
          };

          modules = [ ./nix-on-droid.nix ];
        };
    in
    {
      nixOnDroidConfigurations = {
        inherit phone;
        default = phone;
      };
    };
}
