{ config, lib, pkgs, ... }:

# Our management agent keeping the system up to date, configuring it based on
# changes to our nixpkgs clone and data from our directory

with lib;

let
  cfg = config.flyingcircus;

  isStaging = !(attrByPath [ "parameters" "production" ] true cfg.enc);

  humanGid = toString config.ids.gids.users;
  serviceGid = toString config.ids.gids.service;
  log = "/var/log/fc-collect-garbage.log";

  script = ''
    # load dependent delay
    ncpu=$(awk '/^processor/ { ncpu+=1 }; END { print ncpu }' /proc/cpuinfo)
    load=""
    max_wait=0
    while [[ "$load" != "low" && $max_wait -lt 3600 ]]; do
      echo "load too high, waiting"
      sleep 10
      max_wait=$((max_wait + 10))
      load=$(awk "1 { if (\$1 / "$ncpu" < .5) print \"low\" }" /proc/loadavg)
    done
    started=$(date +%s)
    failed=0
    while read user home; do
      if [[ $home == /var/empty ]]; then
        continue
      fi
      echo "$(date -Is) Scanning $home as $user"
      sudo -u $user -H -- \
        fc-userscan -vrS -s 2 -c $home/.cache/fc-userscan.cache -L 10000000 \
        -z '*.egg' -E ${./userscan.exclude} \
        $home || failed=1
    done < <(getent passwd | awk -F: '$4 == ${humanGid} || $4 == ${serviceGid} \
              { print $1 " " $6 }') >> ${log}

    if (( failed )); then
      echo "ERROR: fc-userscan failed"
      exit 1
    else
      nice nix-collect-garbage --delete-older-than 3d --max-freed 10485760
    fi
    stopped=$(date +%s)
    echo "$(date -Is) time=$((stopped - started))s" >> ${log}
  '';

in {
  options = {
    flyingcircus.agent = {
      collect-garbage =
        mkEnableOption
        "automatic scanning for Nix store references and garbage collection";
    };
  };

  config = mkMerge [
    {
      systemd.tmpfiles.rules = [
        "f ${log}"
      ];
    }

    (mkIf cfg.agent.collect-garbage {

      flyingcircus.services.sensu-client.checks.fc-collect-garbage = {
        notification = "nix-collect-garbage stamp recent";
        command = ''
          ${pkgs.monitoring-plugins}/bin/check_file_age \
            -f ${log} -w 216000 -c 432000
        '';
      };

      systemd.services.fc-collect-garbage = {
        description = "Scan users for Nix store references and collect garbage";
        restartIfChanged = false;
        serviceConfig.Type = "oneshot";
        path = with pkgs; [ fc.userscan gawk nix glibc sudo ];
        environment = { LANG = "en_US.utf8"; };
        inherit script;
      };

      systemd.timers.fc-collect-garbage = {
        description = "Timer for fc-collect-garbage";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "00:00:00";
          RandomizedDelaySec = "24h";
        };
      };

    })
  ];
}
