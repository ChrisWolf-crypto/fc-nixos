{ config, lib, pkgs, ... }:

with builtins;

# TODO submission port should circumvent some spam checks
# TODO autoconfig

let
  snm = fetchTarball {
    url = "https://github.com/flyingcircusio/nixos-mailserver/archive/d1bc7eb2b532bc0f65f52cfd4b99368a0e2bb3dc.tar.gz";
    sha256 = "1j6bfafng0309mp7r2bd02nlhfy1zyl6r8cbs03yrwz70y20q4ka";
  };

  role = config.flyingcircus.roles.mailserver;
  fclib = config.fclib;
  fqdn = with config.networking; "${hostName}.${domain}";
  vmailDir = "/srv/vmail";
  passwdFile = "/var/lib/dovecot/passwd";
  primaryDomain = if role.domains != [] then elemAt role.domains 0 else fqdn;

# TODO load genericVirtual from /etc/local/mail/*.json
  genericVirtual = ''
    spam@${fqdn} devnull@${fqdn}
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
    environment.etc = {
      # refer to the source for a comprehensive list of options:
      # https://gitlab.com/simple-nixos-mailserver/nixos-mailserver/-/blob/master/default.nix
      "local/mail/users.json.example".text = (toJSON {
        mbox = "user@${primaryDomain}";
        hashedPassword = "$5$vIcN8UjKhofUvKW9$ckVkr1c8IH9jvd48pdpGbL19vrzipvHtNG8t2f77Kv/";
        aliases = [ "user1@${primaryDomain}" ];
        quota = "4G";
        sieveScript = null;
      });

      "local/mail/valiases.json.example".text = (toJSON {
        "postmaster@${primaryDomain}" = "user1@${primaryDomain}";
        "abuse@${primaryDomain}" = "user2@${primaryDomain}";
      });
    };

    mailserver = {
      enable = true;
      inherit (role) domains;
      inherit fqdn;
      loginAccounts = fclib.jsonFromFile "/etc/local/mail/users.json" "{}";
      extraVirtualAliases =
        fclib.jsonFromFile "/etc/local/mail/valiases.json" "{}";
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
        skip_addresses = 127.0.0.0/8,::ffff:127.0.0.0/104,::/64,${
          concatStringsSep "," (fclib.listenAddresses "ethfe")}
        HELO_Whitelist = ${fqdn},${role.mailHost}
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

    services.postfix = {
      destination = [
        role.mailHost
        config.networking.hostName
        fqdn
        "localhost"
      ];
      extraConfig = ''
        empty_address_recipient = postmaster
        enable_long_queue_ids = yes
        sender_canonical_maps = tcp:localhost:10001
        sender_canonical_classes = envelope_sender
        recipient_canonical_maps = tcp:localhost:10002
        recipient_canonical_classes = envelope_recipient, header_recipient
        smtp_address_preference = ipv6
        smtp_bind_address = ${role.smtpBind4}
        smtp_bind_address6 = ${role.smtpBind6}
        smtpd_client_restrictions =
          reject_rbl_client ix.dnsbl.manitu.net,
          reject_unknown_client_hostname,
          permit
      '';
      extraAliases = ''
        abuse: root
        devnull: /dev/null
        mail: root
        postmaster: root
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
