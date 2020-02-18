{ config, pkgs, lib, ... }:

let
  role = config.flyingcircus.roles.mailserver;

  # see also genericVirtual in default.nix
  spamtrapMap = builtins.toFile "spamtrap.map" ''
    /^spam@${role.mailHost}$/
  '';

in
{
  imports = [
    ../redis.nix
  ];

  config = {
    services.nginx = lib.mkIf (role.webmailHost != null) {
      upstreams."@rspamd".servers = {
        "unix:/run/rspamd/worker-controller.sock" = {};
      };

      virtualHosts.${role.webmailHost}.locations."/rspamd/" = {
        proxyPass = "http://@rspamd/";
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        '';
      };
    };

    services.rspamd.locals = {
      "greylist.conf".text = ''
        expire = 7d;
        ipv4_mask = 24;
        ipv6_mask = 56;
      '';

      "mx_check.conf".text = ''
        enabled = true;
      '';

      "rbl.conf".text = ''
        rbls {
          # abusech {
          #   disabled = true;
          # }
        }
      '';

      "redis.conf".text = ''
        server = "127.0.0.1";
        db = ${toString role.redisDatabase};
        password = "${config.services.redis.requirePass}";
        expand_keys = true;
      '';

      "replies.conf".text = ''
        action = "no action";
        expire = 3d;
      '';

      "spamtrap.conf".text = ''
        action = "reject";
        enabled = true;
        learn_spam = true;
        map = file://${spamtrapMap};
      '';

      "url_reputation.conf".text = ''
        enabled = true;
      '';

      # XXX generate passwd
      "worker-controller.inc".text = ''
        password = "$2$kj3b3hii3upfxzpf4y9y8ubxcgbcs3de$qf9qhdyu9ruzci4qa63w46dkdrttqcwq3mdqwe81kwngi35kz6ky";
        enable_password = "$2$ij98xwm31yu5qfbrfy61awbtdz83shft$ueftydb88b8ng3aexr1pfdyt3sxp187gmiczbs9gi8p9j6dcf16y";
        dynamic_conf = "/var/lib/rspamd/rspamd_dynamic";
        static_dir = "${pkgs.rspamd}/share/rspamd/www";
      '';
    };
  };
}
