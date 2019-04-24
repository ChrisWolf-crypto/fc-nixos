Flying Circus NixOS overlay
===========================

Development mode
----------------

For local development, sync the fc-nixos source tree to the target machine and
set up the `channels` directory and NIX_PATH:

    eval `./dev-setup`

Build packages
--------------

Run in development mode:

    nix-build -A $package

(Dry) system build
------------------

Run in development mode:

    nix-build '<nixpkgs/nixos>' -A system

Execute test
------------

Automatic test execution for a single test:

    nix-build tests/$test.nix

Interactive test execution (gives a Perl REPL capable to run the test script):

    nix-build test/$test.nix -A driver
    ./result/bin/nixos-test-driver
