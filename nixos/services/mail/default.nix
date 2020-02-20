{ config, lib, pkgs, ... }:

with builtins;

# TODO submission port should circumvent some spam checks
# TODO rspamd admin UI
# TODO autoconfig
# TODO test

# Explanation of various host names:
# - fqdn: "raw" machine name. Points to the srv address which is usually not
#   reachable from the outside but occasionally used for locally generated mail
#   (e.g., cron)
# - mailHost: HELO name
# - domains: list of mail domains for which regular mail accounts exist

let
  snm = fetchTarball {
    url = "https://github.com/flyingcircusio/nixos-mailserver/archive/d1bc7eb2b532bc0f65f52cfd4b99368a0e2bb3dc.tar.gz";
    sha256 = "1j6bfafng0309mp7r2bd02nlhfy1zyl6r8cbs03yrwz70y20q4ka";
  };

  role = config.flyingcircus.roles.mailserver;
  fclib = config.fclib;
  fqdn = with config.networking; "${hostName}.${domain}";
  primaryDomain = if role.domains != [] then elemAt role.domains 0 else fqdn;
  vmailDir = "/srv/mail";
  passwdFile = "/var/lib/dovecot/passwd";

# TODO load genericVirtual from /etc/local/mail/*.json
  genericVirtual = ''
    spam@${role.mailHost} devnull@${fqdn}
  '';
  genericVirtualPCRE = toFile "virtual.pcre" ''
  '';


in {
  imports = [
    # XXX conditional import?
    snm
    ./rspamd.nix
    # roundcube
    # postgresql
  ];

  options = {
    flyingcircus.services.mail.enable = lib.mkEnableOption ''
      Mail server (SNM) with postfix, dovecot, rspamd, dkim & spf
    '';
  };

  config = lib.mkIf config.flyingcircus.services.mail.enable {

    environment = {

      etc = {
        # refer to the source for a comprehensive list of options:
        # https://gitlab.com/simple-nixos-mailserver/nixos-mailserver/-/blob/master/default.nix
        "local/mail/users.json.example".text = (toJSON {
          "user@${primaryDomain}" = {
            # generate with `mkpasswd -m sha-256 PASSWD`
            hashedPassword = "$5$iCMCiTay$VXWuFJQqjEiK7FnRzaRD.y2/2Rq0PlHpnW11GsQFkOB";
            aliases = [ "user1@${primaryDomain}" ];
            quota = "4G";
            sieveScript = null;
          };
        });
        # these must use one of the configured domains as targets
        "local/mail/valiases.json.example".text = (toJSON {
          "postmaster@${primaryDomain}" = "user1@${primaryDomain}";
          "abuse@${primaryDomain}" = "user2@${primaryDomain}";
        });
      };

      systemPackages = with pkgs; [
        mkpasswd
      ];
    };

    mailserver = {
      enable = true;
      inherit (role) domains;
      fqdn = role.mailHost;
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

    # security.acme.certs.${fqdn}.extraDomains = {
    #   # autoconfig?
    # };

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
        smtp_bind_address = ${role.smtpBind4}
        smtp_bind_address6 = ${role.smtpBind6}
        smtpd_client_restrictions =
          permit_mynetworks
          reject_rbl_client ix.dnsbl.manitu.net,
          reject_unknown_client_hostname,
        smtpd_data_restrictions = reject_unauth_pipelining
        smtpd_helo_restrictions =
          permit_sasl_authenticated,
          reject_unknown_helo_hostname
      '';
      extraAliases = ''
        abuse: root
        devnull: /dev/null
        mail: root
      '';
      inherit (role) rootAlias;
      virtual = genericVirtual;
      config.virtual_alias_maps = [ "pcre:${genericVirtualPCRE}" ];
    };

    services.postsrsd = {
      enable = true;
      domain = primaryDomain;
      excludeDomains =
        if role.domains != []
        then tail config.mailserver.domains ++ [ role.mailHost fqdn ]
        else [];
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
