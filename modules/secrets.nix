{ config, lib, pkgs, ... }:

let
  cfg = config.age;

  secretType = lib.types.submodule ({ name, ... }: {
    options = {
      file = lib.mkOption {
        type = lib.types.path;
        description = "Age-encrypted source file.";
      };

      path = lib.mkOption {
        type = lib.types.str;
        default = "${cfg.secretsDir}/${name}";
        description = "Path where the decrypted secret is installed.";
      };

      mode = lib.mkOption {
        type = lib.types.strMatching "0[0-7]{3}";
        default = "0400";
        description = "Permissions applied to the decrypted secret.";
      };
    };
  });

  secrets = lib.mapAttrsToList (name: secret: {
    inherit name secret;
    stagingName = builtins.hashString "sha256" name;
  }) cfg.secrets;

  destinationPaths = map ({ secret, ... }: secret.path) secrets;

  identityChecks = lib.concatMapStringsSep "\n" (identityPath: ''
    if [ ! -r ${lib.escapeShellArg identityPath} ]; then
      echo "Age identity missing or unreadable: ${identityPath}" >&2
      exit 1
    fi
  '') cfg.identityPaths;

  identityArguments = lib.concatMapStringsSep " "
    (identityPath: "--identity ${lib.escapeShellArg identityPath}")
    cfg.identityPaths;

  destinationSetup = lib.concatMapStringsSep "\n" ({ secret, ... }: ''
    ${pkgs.coreutils}/bin/install -d -m 700 ${lib.escapeShellArg (builtins.dirOf secret.path)} || exit 1
  '') secrets;

  decryptCommands = lib.concatMapStringsSep "\n" ({ name, secret, stagingName }: ''
    echo "Decrypting age secret ${lib.escapeShellArg name}"
    if ! ${pkgs.age}/bin/age \
        --decrypt \
        ${identityArguments} \
        --output "$staging_dir/${stagingName}" \
        ${lib.escapeShellArg (toString secret.file)}; then
      echo "Failed to decrypt age secret ${lib.escapeShellArg name}; no live secrets were changed" >&2
      exit 1
    fi
    ${pkgs.coreutils}/bin/chmod ${lib.escapeShellArg secret.mode} "$staging_dir/${stagingName}" || exit 1
  '') secrets;

  publishCommands = lib.concatMapStringsSep "\n" ({ secret, stagingName, ... }: ''
    ${pkgs.coreutils}/bin/mv --force \
      "$staging_dir/${stagingName}" \
      ${lib.escapeShellArg secret.path} || exit 1
  '') secrets;

  cleanupCommands = lib.concatMapStringsSep "\n" ({ stagingName, ... }: ''
    ${pkgs.coreutils}/bin/rm -f "$staging_dir/${stagingName}"
  '') secrets;

  dryRunMessages = lib.concatMapStringsSep "\n" ({ name, secret, ... }: ''
    echo "Would decrypt age secret ${lib.escapeShellArg name} into ${lib.escapeShellArg secret.path}"
  '') secrets;
in
{
  options.age = {
    identityPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "${config.user.home}/.config/age/nix-droid-discord-bot.key" ];
      description = ''
        Age identities used to decrypt every declared secret. The default keeps
        the identity path used by the original Discord bot configuration.
      '';
    };

    secretsDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.user.home}/.local/state/nix-on-droid-secrets";
      description = "Default destination and staging directory for age secrets.";
    };

    secrets = lib.mkOption {
      type = lib.types.attrsOf secretType;
      default = { };
      description = "Age-encrypted secrets decrypted together during activation.";
    };
  };

  config = lib.mkIf (cfg.secrets != { }) {
    assertions = [
      {
        assertion = cfg.identityPaths != [ ];
        message = "age.identityPaths must contain at least one identity when age.secrets are declared";
      }
      {
        assertion = lib.all (path: lib.hasPrefix "/" path) destinationPaths;
        message = "Every age secret destination path must be absolute";
      }
      {
        assertion = builtins.length (lib.unique destinationPaths) == builtins.length destinationPaths;
        message = "Every age secret must have a unique destination path";
      }
    ];

    environment.packages = [ pkgs.age ];

    build.activation.ageSecrets = ''
      if [ -n "''${DRY_RUN:-}" ]; then
        ${dryRunMessages}
      else
        ${identityChecks}

        ${pkgs.coreutils}/bin/install -d -m 700 ${lib.escapeShellArg cfg.secretsDir} || exit 1
        ${destinationSetup}

        staging_dir="$(${pkgs.coreutils}/bin/mktemp -d ${lib.escapeShellArg "${cfg.secretsDir}/.staging.XXXXXX"})" || exit 1
        ${pkgs.coreutils}/bin/chmod 700 "$staging_dir" || exit 1

        cleanup_age_secrets() {
          ${cleanupCommands}
          ${pkgs.coreutils}/bin/rmdir "$staging_dir" 2>/dev/null || true
        }
        trap cleanup_age_secrets EXIT HUP INT TERM

        # Do not change any live secret until every ciphertext decrypts cleanly.
        ${decryptCommands}

        ${publishCommands}

        trap - EXIT HUP INT TERM
        ${pkgs.coreutils}/bin/rmdir "$staging_dir"
      fi
    '';
  };
}
