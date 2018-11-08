#!/usr/bin/env bash
# Usage: export `./dev-setup.sh`
base=$PWD
nixpkgsBootstrap=$(realpath $HOME/.nix-defexpr/channels_root/nixpkgs)
if [[ -z nixpkgsBootstrap ]]; then
    echo "$0: need <nixpkgs> available in system channels" >&2
    exit 1
fi
export NIX_PATH="nixpkgs=$nixpkgsBootstrap"
channels=`nix-build -Q -o channels $base/nixpkgs.nix`
if [[ -z $channels ]]; then
    echo "$0: failed to build nixpkgs+overlay" >&2
    exit 1
fi
cat <<_EOT_
NIX_PATH=$base/channels:fc=$base:nixos-config=$base/nixos/configuration.nix
export NIX_PATH
_EOT_
