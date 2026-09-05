{
  description = "Hello-world Discord bot";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [
        "aarch64-linux"
        "x86_64-linux"
      ];

      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      packageFor = system:
        let
          pkgs = import nixpkgs { inherit system; };
          python = pkgs.python3.withPackages (pythonPackages: [
            (pythonPackages.discordpy.override { withVoice = false; })
          ]);
        in
        pkgs.writeShellScriptBin "hello-discord-bot" ''
          set -eu

          config_home="''${XDG_CONFIG_HOME:-$HOME/.config}"
          token_file="''${DISCORD_TOKEN_FILE:-$config_home/hello-discord-bot/token}"

          if [ -z "''${DISCORD_TOKEN:-}" ]; then
            if [ ! -r "$token_file" ]; then
              echo "hello-discord-bot: Discord token not found" >&2
              echo "set DISCORD_TOKEN or place it in $token_file with mode 600" >&2
              exit 1
            fi

            DISCORD_TOKEN="$(${pkgs.coreutils}/bin/cat "$token_file")"
            export DISCORD_TOKEN
          fi

          exec ${python}/bin/python ${./bot.py}
        '';
    in
    {
      packages = forAllSystems (system: {
        default = packageFor system;
        hello-discord-bot = self.packages.${system}.default;
      });

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/hello-discord-bot";
        };
      });
    };
}
