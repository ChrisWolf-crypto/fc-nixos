{ config, lib, ... }:
let
  # Map list of roles to a list of attribute sets enabling each role.
  # Turn the list of role names (["a", "b"]) into an attribute set
  # ala { <role> = { enable = true;}; }
  roleSet = lib.listToAttrs (
    map (role: { name = role; value = { enable = true; }; })
      config.flyingcircus.active-roles);

in {
  imports = [
    ./external_net
    ./mailserver.nix
    ./memcached.nix
    ./mongodb
    ./mysql.nix
    ./nfs.nix
    ./postgresql.nix
    ./rabbitmq.nix
    ./redis.nix
    ./statshost
    ./webgateway.nix
    ./webproxy.nix
  ];

  flyingcircus.roles = roleSet;
}
