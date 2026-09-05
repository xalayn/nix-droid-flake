{
  description = "Nix-on-Droid phone configuration";

  inputs = {
    discord-bot = {
      url = "github:xalayn/nix-discord-bot-test";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";

    nix-on-droid = {
      url = "github:nix-community/nix-on-droid/release-24.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { discord-bot, nixpkgs, nix-on-droid, ... }:
    let
      phone =
        nix-on-droid.lib.nixOnDroidConfiguration {
          pkgs = import nixpkgs {
            system = "aarch64-linux";
          };

          modules = [
            ./nix-on-droid.nix
            (import ./modules/discord-bot.nix { inherit discord-bot; })
          ];
        };
    in
    {
      nixOnDroidConfigurations = {
        inherit phone;
        default = phone;
      };
    };
}
