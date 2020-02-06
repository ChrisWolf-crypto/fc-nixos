{ config, lib, pkgs, ... }:

with builtins;

let
  snm = fetchTarball {
    url = "https://github.com/flyingcircusio/nixos-mailserver/archive/d1bc7eb2b532bc0f65f52cfd4b99368a0e2bb3dc.tar.gz";
    sha256 = "1j0d2xcnlfsp3556n8xj5g000000000000000000000000000000";
  };

  fqdn = with config.networking; "${hostName}.${domain}";
  role = config.flyingcircus.roles.mailserver;
  vmailDir = "/srv/vmail";
  passwdFile = "/var/lib/dovecot/passwd";

  loginAccounts = {}; # XXX

  extraVirtualAliases = {}; # XXX

  genericVirtual = ''
    spam@${}
  '';

  genericVirtualPCRE = toFile "virtual.pcre" ''
  '';

in {
  imports = [
    snm
    # roundcube
    # rspamd
    # postgresql
    # redis
  ];

  config = lib.mkIf role.enable {
    mailserver = {
      enable = true;
      inherit (role) fqdn domains;
      inherit loginAccounts extraVirtualAliases;
      certificateScheme = 3;
      enableImapSsl = true;
      enableManageSieve = true;
      mailDirectory = vmailDir;
      mailboxes = [
        { name = "Trash"; auto = "create"; specialUse = "Trash"; }
        { name = "Junk"; auto = "create"; specialUse = "Junk"; }
        { name = "Drafts"; auto = "subscribe"; specialUse = "Drafts"; }
        { name = "Sent"; auto = "subscribe"; specialUse = "Sent"; }
        { name = "Archives"; auto = "subscribe"; specialUse = "Archive"; }
      ];
      policydSPFExtraConfig = ''
        skip_addresses = 127.0.0.0/8,::ffff:127.0.0.0/104,::/64
      '';
      vmailGroupName = "vmail";
      vmailUserName = "vmail";
    };

    security.acme.certs.${fqdn}.extraDomains = {
      ${role.mailHost} = null;
    };

    services.dovecot2.extraConfig = ''
      passdb {
        driver = passwd-file
        args = ${passwdFile}
      }

      plugin {
        mail_plugins = $mail_plugins expire
        expire = Trash
        expire2 = Trash/*
        expire3 = Junk
        expire_cache = yes
      }
    '';

    # TODO users from json
    # TODO submission port should circumvent some spam checks
    # XXX autoconfig?

    services.postfix = {
      destination = [
        role.mailHost
        config.networking.hostName
        fqdn
        "localhost"
      ];
      extraConfig = ''
        sender_canonical_maps = tcp:localhost:10001
        sender_canonical_classes = envelope_sender
        recipient_canonical_maps = tcp:localhost:10002
        recipient_canonical_classes = envelope_recipient, header_recipient
        smtpd_client_restrictions =
          reject_rbl_client ix.dnsbl.manitu.net,
          reject_unknown_client_hostname,
          permit
        empty_address_recipient = mail
      '';
      extraAliases = ''
        devnull: /dev/null
        mail: root
        abuse: root
      '';
      inherit (role) rootAlias;
      virtual = genericVirtual;
      config.virtual_alias_maps = [ "pcre:${genericVirtualPCRE}" ];
    };

    services.postsrsd = {
      enable = true;
      domain = head role.domains;
      excludeDomains = tail config.mailserver.domains;
    };

    systemd.services.dovecot2-expunge = {
      script = ''
        doveadm expunge -A mailbox Trash savedbefore 7d || true
        doveadm expunge -A mailbox Junk savedbefore 30d || true
      '';
      path = with pkgs; [ dovecot ];
      startAt = "04:39:47";
    };

    systemd.tmpfiles.rules = [
      "f ${passwdFile} 0600 nginx"
    ];
  };
}
