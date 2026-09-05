{ discord-bot }:
{ config, lib, pkgs, ... }:

let
  bot = discord-bot.packages.${pkgs.system}.default;
  stateDir = "${config.user.home}/.local/state/hello-discord-bot";
  servicesDir = "${stateDir}/services";
  serviceDir = "${servicesDir}/hello-discord-bot";
  logDir = "${stateDir}/log";
  supervisorPidFile = "${stateDir}/runsvdir.pid";
  supervisorLogFile = "${stateDir}/runsvdir.log";
  legacySupervisorPidFile = "${stateDir}/supervisor.pid";
  tokenFile = "${stateDir}/token";
  identityFile = "${config.user.home}/.config/age/nix-droid-discord-bot.key";

  runitPath = lib.makeBinPath [
    pkgs.coreutils
    pkgs.runit
  ];

  serviceRun = pkgs.writeShellScript "hello-discord-bot-run" ''
    if [ ! -r ${lib.escapeShellArg tokenFile} ]; then
      echo "Discord token is not readable at ${tokenFile}" >&2
      exit 111
    fi

    DISCORD_TOKEN="$(${pkgs.coreutils}/bin/cat ${lib.escapeShellArg tokenFile})"
    export DISCORD_TOKEN
    exec ${bot}/bin/hello-discord-bot
  '';

  logRun = pkgs.writeShellScript "hello-discord-bot-log-run" ''
    exec ${pkgs.runit}/bin/svlogd -tt ${lib.escapeShellArg logDir}
  '';

  runsvdir = pkgs.writeShellScript "nix-on-droid-runsvdir" ''
    export PATH=${lib.escapeShellArg runitPath}
    exec ${pkgs.runit}/bin/runsvdir -P ${lib.escapeShellArg servicesDir}
  '';

  serviceStart = pkgs.writeShellScriptBin "hello-discord-bot-start" ''
    set -eu

    pid_file=${lib.escapeShellArg supervisorPidFile}
    service_dir=${lib.escapeShellArg serviceDir}

    if [ ! -r ${lib.escapeShellArg tokenFile} ]; then
      echo "hello-discord-bot-start: decrypted token not found at ${tokenFile}" >&2
      exit 1
    fi

    if [ -s "$pid_file" ]; then
      pid="$(${pkgs.coreutils}/bin/cat "$pid_file")"
      if kill -0 "$pid" 2>/dev/null; then
        exec ${pkgs.runit}/bin/sv up "$service_dir"
      fi
      ${pkgs.coreutils}/bin/rm -f "$pid_file"
    fi

    ${pkgs.coreutils}/bin/nohup ${runsvdir} \
      >>${lib.escapeShellArg supervisorLogFile} 2>&1 </dev/null &
    pid=$!
    printf '%s\n' "$pid" >"$pid_file"
    ${pkgs.coreutils}/bin/sleep 1

    if ! kill -0 "$pid" 2>/dev/null; then
      echo "hello-discord-bot-start: runsvdir failed to start" >&2
      exit 1
    fi

    exec ${pkgs.runit}/bin/sv up "$service_dir"
  '';

  serviceStop = pkgs.writeShellScriptBin "hello-discord-bot-stop" ''
    set -eu
    exec ${pkgs.runit}/bin/sv down ${lib.escapeShellArg serviceDir}
  '';

  serviceRestart = pkgs.writeShellScriptBin "hello-discord-bot-restart" ''
    set -eu
    ${serviceStart}/bin/hello-discord-bot-start >/dev/null
    exec ${pkgs.runit}/bin/sv restart ${lib.escapeShellArg serviceDir}
  '';

  serviceStatus = pkgs.writeShellScriptBin "hello-discord-bot-status" ''
    set -eu

    if [ ! -s ${lib.escapeShellArg supervisorPidFile} ]; then
      echo "Discord bot supervisor is not running"
      exit 1
    fi

    pid="$(${pkgs.coreutils}/bin/cat ${lib.escapeShellArg supervisorPidFile})"
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "Discord bot supervisor is not running"
      exit 1
    fi

    exec ${pkgs.runit}/bin/sv status ${lib.escapeShellArg serviceDir}
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
    pkgs.runit
    serviceStart
    serviceStop
    serviceRestart
    serviceStatus
  ];

  user.shell = loginShell;

  build.activation.discordBotSecret = ''
    if [ -n "''${DRY_RUN:-}" ]; then
      echo "Would decrypt the Discord bot token into ${tokenFile}"
    else
      if [ -s ${lib.escapeShellArg legacySupervisorPidFile} ]; then
        legacy_pid="$(${pkgs.coreutils}/bin/cat ${lib.escapeShellArg legacySupervisorPidFile})"
        if kill -0 "$legacy_pid" 2>/dev/null; then
          kill "$legacy_pid"
          attempts=0
          while kill -0 "$legacy_pid" 2>/dev/null && [ "$attempts" -lt 50 ]; do
            ${pkgs.coreutils}/bin/sleep 0.1
            attempts=$((attempts + 1))
          done

          if kill -0 "$legacy_pid" 2>/dev/null; then
            echo "Legacy Discord bot supervisor $legacy_pid did not stop" >&2
            exit 1
          fi
        fi
        ${pkgs.coreutils}/bin/rm -f ${lib.escapeShellArg legacySupervisorPidFile}
      fi

      if [ ! -r ${lib.escapeShellArg identityFile} ]; then
        echo "Discord bot age identity missing: ${identityFile}" >&2
        exit 1
      fi

      ${pkgs.coreutils}/bin/install -d -m 700 \
        ${lib.escapeShellArg stateDir} \
        ${lib.escapeShellArg servicesDir} \
        ${lib.escapeShellArg serviceDir} \
        ${lib.escapeShellArg "${serviceDir}/log"} \
        ${lib.escapeShellArg logDir}

      ${pkgs.coreutils}/bin/ln -sfn ${serviceRun} ${lib.escapeShellArg "${serviceDir}/run"}
      ${pkgs.coreutils}/bin/ln -sfn ${logRun} ${lib.escapeShellArg "${serviceDir}/log/run"}

      token_tmp="$(${pkgs.coreutils}/bin/mktemp ${lib.escapeShellArg "${stateDir}/.token.XXXXXX"})"

      cleanup_token_tmp() {
        ${pkgs.coreutils}/bin/rm -f "$token_tmp"
      }
      trap cleanup_token_tmp EXIT HUP INT TERM

      ${pkgs.age}/bin/age \
        --decrypt \
        --identity ${lib.escapeShellArg identityFile} \
        --output "$token_tmp" \
        ${../secrets/discord-bot-token.age}

      ${pkgs.coreutils}/bin/chmod 400 "$token_tmp"
      ${pkgs.coreutils}/bin/mv "$token_tmp" ${lib.escapeShellArg tokenFile}
      trap - EXIT HUP INT TERM
    fi
  '';

  build.activationAfter.zzDiscordBotService = ''
    if [ -n "''${DRY_RUN:-}" ]; then
      echo "Would restart the Discord bot through runit"
    else
      ${serviceRestart}/bin/hello-discord-bot-restart
    fi
  '';
}
