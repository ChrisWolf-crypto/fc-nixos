f: {
  system ? builtins.currentSystem
  , nixpkgs ? (import ../nixpkgs.nix {}).nixpkgs
  , pkgs ? import nixpkgs {}
  , minimal ? false
  , config ? {}
  , ...
} @ args:

with import "${nixpkgs}/nixos/lib/testing.nix" {
  inherit system minimal config;
};

makeTest (
  if pkgs.lib.isFunction f
  then f (args // { inherit pkgs; inherit (pkgs) lib; })
  else f
)
