{ config, pkgs, ... }:

let
  bot = pkgs.callPackage ./package.nix { };
  stateDir = "${config.user.home}/.local/state/hello-discord-bot";
  tokenFile = "${stateDir}/token";
  identityFile = "${config.user.home}/.config/age/nix-droid-discord-bot.key";

  supervisor = pkgs.writeShellScript "hello-discord-bot-supervisor" ''
    set -u

    child_pid=""

    terminate() {
      trap - HUP INT TERM
      if [ -n "$child_pid" ] && kill -0 "$child_pid" 2>/dev/null; then
        kill "$child_pid" 2>/dev/null || true
        wait "$child_pid" 2>/dev/null || true
      fi
      exit 0
    }

    trap terminate HUP INT TERM
    delay=1

    while :; do
      echo "$(${pkgs.coreutils}/bin/date --iso-8601=seconds) starting Discord bot"
      DISCORD_TOKEN_FILE=${tokenFile} ${bot}/bin/hello-discord-bot &
      child_pid=$!
      wait "$child_pid"
      status=$?
      child_pid=""

      echo "$(${pkgs.coreutils}/bin/date --iso-8601=seconds) bot exited with status $status; restarting in $delay seconds"
      ${pkgs.coreutils}/bin/sleep "$delay" &
      child_pid=$!
      wait "$child_pid" 2>/dev/null || true
      child_pid=""

      if [ "$delay" -lt 60 ]; then
        delay=$((delay * 2))
        if [ "$delay" -gt 60 ]; then
          delay=60
        fi
      fi
    done
  '';

  serviceStart = pkgs.writeShellScriptBin "hello-discord-bot-start" ''
    set -eu

    pid_file=${stateDir}/supervisor.pid
    log_file=${stateDir}/service.log

    ${pkgs.coreutils}/bin/install -d -m 700 ${stateDir}

    if [ ! -r ${tokenFile} ]; then
      echo "hello-discord-bot-start: decrypted token not found at ${tokenFile}" >&2
      exit 1
    fi

    if [ -s "$pid_file" ]; then
      pid="$(${pkgs.coreutils}/bin/cat "$pid_file")"
      if kill -0 "$pid" 2>/dev/null; then
        echo "Discord bot supervisor is already running with PID $pid"
        exit 0
      fi
      ${pkgs.coreutils}/bin/rm -f "$pid_file"
    fi

    ${pkgs.coreutils}/bin/nohup ${supervisor} \
      >>"$log_file" 2>&1 </dev/null &
    pid=$!
    printf '%s\n' "$pid" >"$pid_file"
    ${pkgs.coreutils}/bin/sleep 1

    if ! kill -0 "$pid" 2>/dev/null; then
      echo "hello-discord-bot-start: supervisor failed to start" >&2
      ${pkgs.coreutils}/bin/tail -n 20 "$log_file" >&2 || true
      exit 1
    fi

    echo "Discord bot supervisor started with PID $pid"
  '';

  serviceStop = pkgs.writeShellScriptBin "hello-discord-bot-stop" ''
    set -eu

    pid_file=${stateDir}/supervisor.pid

    if [ ! -s "$pid_file" ]; then
      echo "Discord bot supervisor is not running"
      exit 0
    fi

    pid="$(${pkgs.coreutils}/bin/cat "$pid_file")"
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid"
      attempts=0
      while kill -0 "$pid" 2>/dev/null && [ "$attempts" -lt 50 ]; do
        ${pkgs.coreutils}/bin/sleep 0.1
        attempts=$((attempts + 1))
      done
    fi

    if kill -0 "$pid" 2>/dev/null; then
      echo "hello-discord-bot-stop: supervisor $pid did not stop" >&2
      exit 1
    fi

    ${pkgs.coreutils}/bin/rm -f "$pid_file"
    echo "Discord bot supervisor stopped"
  '';

  serviceStatus = pkgs.writeShellScriptBin "hello-discord-bot-status" ''
    set -eu

    pid_file=${stateDir}/supervisor.pid

    if [ -s "$pid_file" ]; then
      pid="$(${pkgs.coreutils}/bin/cat "$pid_file")"
      if kill -0 "$pid" 2>/dev/null; then
        echo "Discord bot supervisor is running with PID $pid"
        exit 0
      fi
    fi

    echo "Discord bot supervisor is not running"
    exit 1
  '';

  loginShell = pkgs.writeShellScript "nix-on-droid-bot-login-shell" ''
    ${serviceStart}/bin/hello-discord-bot-start >/dev/null 2>&1 || true
    exec -a -bash ${pkgs.bashInteractive}/bin/bash "$@"
  '';
in
{
  environment.packages = [
    bot
    pkgs.age
    serviceStart
    serviceStatus
    serviceStop
  ];

  user.shell = loginShell;

  build.activation.discordBotSecret = ''
    if [ -n "''${DRY_RUN:-}" ]; then
      echo "Would decrypt the Discord bot token into ${tokenFile}"
    else
      if [ ! -r ${identityFile} ]; then
        echo "Discord bot age identity missing: ${identityFile}" >&2
        exit 1
      fi

      ${pkgs.coreutils}/bin/install -d -m 700 ${stateDir}
      token_tmp="$(${pkgs.coreutils}/bin/mktemp ${stateDir}/.token.XXXXXX)"

      cleanup_token_tmp() {
        ${pkgs.coreutils}/bin/rm -f "$token_tmp"
      }
      trap cleanup_token_tmp EXIT HUP INT TERM

      ${pkgs.age}/bin/age \
        --decrypt \
        --identity ${identityFile} \
        --output "$token_tmp" \
        ${./secrets/token.age}

      ${pkgs.coreutils}/bin/chmod 400 "$token_tmp"
      ${pkgs.coreutils}/bin/mv "$token_tmp" ${tokenFile}
      trap - EXIT HUP INT TERM
    fi
  '';

  build.activationAfter.zzDiscordBotService = ''
    if [ -n "''${DRY_RUN:-}" ]; then
      echo "Would restart the Discord bot supervisor"
    else
      ${serviceStop}/bin/hello-discord-bot-stop || true
      ${serviceStart}/bin/hello-discord-bot-start
    fi
  '';
}
