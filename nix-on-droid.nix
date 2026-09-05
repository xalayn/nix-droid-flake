{ config, pkgs, ... }:

let
  port = 8022;
  repository = "github:xalayn/nix-droid-flake";
  repositoryBranch = "master";
  repositoryGitUrl = "https://github.com/xalayn/nix-droid-flake.git";
  stateDir = "${config.user.home}/.local/state/sshd";

  sshdConfig = pkgs.writeText "sshd_config" ''
    Port ${toString port}

    HostKey ${stateDir}/ssh_host_ed25519_key
    PidFile ${stateDir}/sshd.pid
    AuthorizedKeysFile ${config.user.home}/.ssh/authorized_keys

    AllowUsers ${config.user.userName}
    PubkeyAuthentication yes
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    ChallengeResponseAuthentication no
    PermitEmptyPasswords no
    PermitRootLogin no
    UsePAM no

    X11Forwarding no
    Subsystem sftp internal-sftp
  '';

  sshdStart = pkgs.writeShellScriptBin "sshd-start" ''
    set -eu

    pid_file=${stateDir}/sshd.pid

    if [ -s "$pid_file" ]; then
      pid="$(${pkgs.coreutils}/bin/cat "$pid_file")"
      if kill -0 "$pid" 2>/dev/null; then
        echo "sshd is already running with PID $pid"
        exit 0
      fi
      ${pkgs.coreutils}/bin/rm -f "$pid_file"
    fi

    ${pkgs.openssh}/bin/sshd -t -f ${sshdConfig}
    ${pkgs.openssh}/bin/sshd -f ${sshdConfig}
    echo "sshd started on port ${toString port}"
  '';

  sshdForeground = pkgs.writeShellScriptBin "sshd-foreground" ''
    set -eu
    exec ${pkgs.openssh}/bin/sshd -D -e -f ${sshdConfig}
  '';

  phoneUpdate = pkgs.writeShellScriptBin "phone-update" ''
    set -eu

    if [ "$#" -ne 0 ]; then
      echo "usage: phone-update" >&2
      exit 2
    fi

    if ! remote_ref="$(${pkgs.git}/bin/git ls-remote --exit-code \
      ${repositoryGitUrl} \
      refs/heads/${repositoryBranch})"; then
      echo "phone-update: could not contact ${repositoryGitUrl}" >&2
      exit 1
    fi

    revision="''${remote_ref%%[[:space:]]*}"

    if [ -z "$revision" ]; then
      echo "phone-update: could not resolve ${repositoryBranch}" >&2
      exit 1
    fi

    echo "Activating ${repository} at $revision"
    exec nix-on-droid switch --flake "${repository}/$revision#phone"
  '';
in
{
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  environment.packages = [
    pkgs.curl
    pkgs.git
    pkgs.openssh
    phoneUpdate
    sshdStart
    sshdForeground
  ];

  build.activation.sshd = ''
    $VERBOSE_ECHO "Installing SSH authorized keys"
    $DRY_RUN_CMD ${pkgs.coreutils}/bin/install \
      -d -m 700 \
      "${config.user.home}/.ssh" \
      "${stateDir}"

    $DRY_RUN_CMD ${pkgs.coreutils}/bin/install \
      -m 600 \
      ${./authorized_keys} \
      "${config.user.home}/.ssh/authorized_keys"

    if [ ! -e "${stateDir}/ssh_host_ed25519_key" ]; then
      $VERBOSE_ECHO "Generating persistent SSH host key"
      $DRY_RUN_CMD ${pkgs.openssh}/bin/ssh-keygen \
        -q -t ed25519 -N "" \
        -f "${stateDir}/ssh_host_ed25519_key"
    fi
  '';

  system.stateVersion = "24.05";
}
