import ./make-test.nix ({ pkgs, ... }:
{
  name = "haproxy";
  nodes = {
    haproxyVM =
      { lib, ... }:
      {
        imports = [ ../nixos ];
        flyingcircus.services.haproxy.enable = true;
        services.haproxy.config = lib.mkForce ''
          global
            daemon
            chroot /var/empty
            user haproxy
            group haproxy
            log localhost local2

          defaults
            mode http
            timeout connect 5s
            timeout client 5s
            timeout server 5s

          frontend http-in
            bind *:8888
            default_backend server

          backend server
            server python-http 127.0.0.1:7000
        '';
      };
  };
  testScript = ''
    $haproxyVM->execute(<<__SETUP__);
    echo 'Hello World!' > hello.txt
    ${pkgs.python3.interpreter} -m http.server 7000 &
    __SETUP__

    $haproxyVM->waitForUnit("haproxy.service");
    # request goes through haproxy
    my $curl = 'curl -s http://localhost:8888/hello.txt';
    $haproxyVM->succeed($curl) =~ /Hello World!/ or die "expected output missing";

    # check log file entry
    $haproxyVM->succeed('grep hello.txt /var/log/haproxy.log');
  '';
})
