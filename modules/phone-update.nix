{ pkgs, ... }:

let
  repository = "github:xalayn/nix-droid-flake";
  repositoryBranch = "master";
  repositoryGitUrl = "https://github.com/xalayn/nix-droid-flake.git";

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
  environment.packages = [
    pkgs.curl
    pkgs.git
    phoneUpdate
  ];
}
