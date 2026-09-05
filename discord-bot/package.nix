{ pkgs }:

let
  python = pkgs.python3.withPackages (pythonPackages: [
    (pythonPackages.discordpy.override { withVoice = false; })
  ]);
in
pkgs.writeShellScriptBin "hello-discord-bot" ''
  set -eu

  state_home="''${XDG_STATE_HOME:-$HOME/.local/state}"
  token_file="''${DISCORD_TOKEN_FILE:-$state_home/hello-discord-bot/token}"

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
''
