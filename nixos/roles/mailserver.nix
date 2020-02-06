{ config, lib, pkgs, ... }:

with builtins;

let
  params = lib.attrByPath [ "parameters" ] {} config.flyingcircus.enc;
  fclib = config.fclib;
  roles = config.flyingcircus.roles;

  listenFe = fclib.listenAddresses "ethfe";

  # default domain should be changed to to fcio.net once #14970 is finished
  defaultFQDN =
    if (params ? location &&
        lib.hasAttrByPath [ "interfaces" "fe" ] params &&
        (length listenFe > 0))
    then "${config.networking.hostName}.fe.${params.location}.fcio.net"
    else "${config.networking.hostName}.fcio.net";

in
{
  imports = [
    ../services/mail
  ];

  options = {

    flyingcircus.roles.mailserver = with lib; {
      # The mailserver role was/is thought to implement an entire mailserver,
      # and would be billed as component.

      enable = mkEnableOption ''
        Flying Circus mailserver role with web UI.
        Mailout on all nodes in this RG/location.
      '';

      domains = mkOption {
        type = types.listOf types.str;
        example = [ "example.com" ];
        default = [];
        description = ''
          List of virtual domains that this mail server serves. The first value
          is the canonical domain used to construct internal addresses in
          various places.
        '';
      };

      mailHost = mkOption {
        type = types.str;
        description = "FQDN of the mail server's frontend address.";
        example = "mail.example.com";
      };

      webmailHost = mkOption {
        type = types.str;
        description = "(Virtual) host name of the webmail service.";
        example = "webmail.example.com";
      };

      redisDatabase = mkOption {
        type = types.int;
        description = "Redis db id to store spam-related data";
        default = 5;
      };

      rootAlias = mkOption {
        type = types.str;
        description = "Address to receive all mail to root@localhost.";
        default = "admin@flyingcircus.io";
      };
    };
  };
}
