---
title: TProxy on Linux with Xray
published: 2025-08-30
description: So GFW, Love you :)
tags: [Linux, Proxy, TProxy, Xray, Iptables]
category: Linux
draft: false
---

# What Is TProxy?

TProxy (Transparent Proxy) is a network proxy technique used to intercept and redirect network traffic without modifying the client’s configuration. It is often used to filter or redirect traffic, monitor network usage, or apply access controls. Essentially, the proxy operates in a way that’s transparent to the client, meaning the client doesn’t need to know it’s being proxied.

# Why Use TProxy?

By using TProxy, it is possible to proxy all traffic from a device, including traffic from other devices within the same LAN. This eliminates the need to configure a proxy for each program and allows all traffic to be managed with a single configuration file.

# Setting TProxy

## Policy-Based Routing

```sh
sudo ip route add local default dev lo table 100
```

This command adds a default local route to routing table 100, directing all local traffic (traffic destined for the local machine) to the loopback interface (lo). It essentially makes sure that local traffic is handled within the system itself, and not sent out to the network.

```sh
sudo ip rule add fwmark 1 table 100
```

This command adds a rule that directs all packets marked with fwmark 1 to use routing table 100. The fwmark is typically set by firewall rules or other mechanisms to tag packets, and this rule ensures that packets with the mark are routed according to the specific table (100) defined.

## Iptables

```sh
iptables -t mangle -N XRAY
iptables -t mangle -A XRAY -d 10.0.0.0/8 -j RETURN
iptables -t mangle -A XRAY -d 100.64.0.0/10 -j RETURN
iptables -t mangle -A XRAY -d 127.0.0.0/8 -j RETURN
iptables -t mangle -A XRAY -d 169.254.0.0/16 -j RETURN
iptables -t mangle -A XRAY -d 172.16.0.0/12 -j RETURN
iptables -t mangle -A XRAY -d 192.0.0.0/24 -j RETURN
iptables -t mangle -A XRAY -d 224.0.0.0/4 -j RETURN
iptables -t mangle -A XRAY -d 240.0.0.0/4 -j RETURN
iptables -t mangle -A XRAY -d 255.255.255.255/32 -j RETURN
iptables -t mangle -A XRAY -d 192.168.0.0/16 -p tcp ! --dport 53 -j RETURN
iptables -t mangle -A XRAY -d 192.168.0.0/16 -p udp ! --dport 53 -j RETURN
iptables -t mangle -A XRAY -p tcp -j TPROXY --on-port 12345 --tproxy-mark 1
iptables -t mangle -A XRAY -p udp -j TPROXY --on-port 12345 --tproxy-mark 1
iptables -t mangle -A PREROUTING -j XRAY

iptables -t mangle -N XRAY_SELF
iptables -t mangle -A XRAY_SELF -d 10.0.0.0/8 -j RETURN
iptables -t mangle -A XRAY_SELF -d 100.64.0.0/10 -j RETURN
iptables -t mangle -A XRAY_SELF -d 127.0.0.0/8 -j RETURN
iptables -t mangle -A XRAY_SELF -d 169.254.0.0/16 -j RETURN
iptables -t mangle -A XRAY_SELF -d 172.16.0.0/12 -j RETURN
iptables -t mangle -A XRAY_SELF -d 192.0.0.0/24 -j RETURN
iptables -t mangle -A XRAY_SELF -d 224.0.0.0/4 -j RETURN
iptables -t mangle -A XRAY_SELF -d 240.0.0.0/4 -j RETURN
iptables -t mangle -A XRAY_SELF -d 255.255.255.255/32 -j RETURN
iptables -t mangle -A XRAY_SELF -d 192.168.0.0/16 -p tcp ! --dport 53 -j RETURN
iptables -t mangle -A XRAY_SELF -d 192.168.0.0/16 -p udp ! --dport 53 -j RETURN
iptables -t mangle -A XRAY_SELF -m mark --mark 2 -j RETURN
iptables -t mangle -A XRAY_SELF -p tcp -j MARK --set-mark 1
iptables -t mangle -A XRAY_SELF -p udp -j MARK --set-mark 1
iptables -t mangle -A OUTPUT -j XRAY_SELF
```

This series of iptables commands is part of a configuration for routing and packet marking, particularly for handling transparent proxying (TPROXY) with specific traffic rules. The commands set up custom mangle tables for marking and modifying packets, as well as defining how to handle certain IP ranges and protocols (such as TCP/UDP). The goal here appears to be routing specific traffic through a proxy (on port 12345) while bypassing certain IPs and ports.

> [!NOTE]
> The addresses should be modified to match the actual network segments.
>
> ```sh
> iptables -t mangle -A XRAY -d 192.168.0.0/16 -p tcp ! --dport 53 -j RETURN
> iptables -t mangle -A XRAY -d 192.168.0.0/16 -p udp ! --dport 53 -j RETURN
> iptables -t mangle -A XRAY_SELF -d 192.168.0.0/16 -p tcp ! --dport 53 -j RETURN
> iptables -t mangle -A XRAY_SELF -d 192.168.0.0/16 -p udp ! --dport 53 -j RETURN
> ```

## Full Script

```sh
#!/usr/bin/env bash
ip route add local default dev lo table 100
ip rule add fwmark 1 table 100

iptables -t mangle -N XRAY
iptables -t mangle -A XRAY -d 10.0.0.0/8 -j RETURN
iptables -t mangle -A XRAY -d 100.64.0.0/10 -j RETURN
iptables -t mangle -A XRAY -d 127.0.0.0/8 -j RETURN
iptables -t mangle -A XRAY -d 169.254.0.0/16 -j RETURN
iptables -t mangle -A XRAY -d 172.16.0.0/12 -j RETURN
iptables -t mangle -A XRAY -d 192.0.0.0/24 -j RETURN
iptables -t mangle -A XRAY -d 224.0.0.0/4 -j RETURN
iptables -t mangle -A XRAY -d 240.0.0.0/4 -j RETURN
iptables -t mangle -A XRAY -d 255.255.255.255/32 -j RETURN
iptables -t mangle -A XRAY -d 192.168.0.0/16 -p tcp ! --dport 53 -j RETURN
iptables -t mangle -A XRAY -d 192.168.0.0/16 -p udp ! --dport 53 -j RETURN
iptables -t mangle -A XRAY -p tcp -j TPROXY --on-port 52345 --tproxy-mark 1
iptables -t mangle -A XRAY -p udp -j TPROXY --on-port 52345 --tproxy-mark 1
iptables -t mangle -A PREROUTING -j XRAY

iptables -t mangle -N XRAY_SELF
iptables -t mangle -A XRAY_SELF -d 10.0.0.0/8 -j RETURN
iptables -t mangle -A XRAY_SELF -d 100.64.0.0/10 -j RETURN
iptables -t mangle -A XRAY_SELF -d 127.0.0.0/8 -j RETURN
iptables -t mangle -A XRAY_SELF -d 169.254.0.0/16 -j RETURN
iptables -t mangle -A XRAY_SELF -d 172.16.0.0/12 -j RETURN
iptables -t mangle -A XRAY_SELF -d 192.0.0.0/24 -j RETURN
iptables -t mangle -A XRAY_SELF -d 224.0.0.0/4 -j RETURN
iptables -t mangle -A XRAY_SELF -d 240.0.0.0/4 -j RETURN
iptables -t mangle -A XRAY_SELF -d 255.255.255.255/32 -j RETURN
iptables -t mangle -A XRAY_SELF -d 192.168.0.0/16 -p tcp ! --dport 53 -j RETURN
iptables -t mangle -A XRAY_SELF -d 192.168.0.0/16 -p udp ! --dport 53 -j RETURN
iptables -t mangle -A XRAY_SELF -m mark --mark 2 -j RETURN
iptables -t mangle -A XRAY_SELF -p tcp -j MARK --set-mark 1
iptables -t mangle -A XRAY_SELF -p udp -j MARK --set-mark 1
iptables -t mangle -A OUTPUT -j XRAY_SELF
```

# Xray Config

```json
{
  "log": {
    "loglevel": "warning",
    "error": "/var/log/xray/error.log",
    "access": "/var/log/xray/access.log"
  },
  "inbounds": [
    {
      "tag": "all-in",
      "port": 12345,
      "protocol": "dokodemo-door",
      "settings": {
        "network": "tcp,udp",
        "followRedirect": true
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      },
      "streamSettings": {
        "sockopt": {
          "tproxy": "tproxy"
        }
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "UseIPv4"
      },
      "streamSettings": {
        "sockopt": {
          "mark": 2
        }
      }
    },
    {
      "tag": "proxy",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "Server Domain Name",
            "port": 443,
            "users": [
              {
                "id": "UUID",
                "flow": "xtls-rprx-vision",
                "encryption": "none"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "xtls",
        "sockopt": {
          "mark": 2
        }
      }
    },
    {
      "tag": "block",
      "protocol": "blackhole",
      "settings": {
        "response": {
          "type": "http"
        }
      }
    },
    {
      "tag": "dns-out",
      "protocol": "dns",
      "settings": {
        "address": "8.8.8.8"
      },
      "proxySettings": {
        "tag": "proxy"
      },
      "streamSettings": {
        "sockopt": {
          "mark": 2
        }
      }
    }
  ],
  "dns": {
    "hosts": {
      "Server Domain Name": "Server IP"
    },
    "servers": [
      {
        "address": "119.29.29.29",
        "port": 53,
        "domains": ["geosite:cn"],
        "expectIPs": ["geoip:cn"]
      },
      {
        "address": "223.5.5.5",
        "port": 53,
        "domains": ["geosite:cn"],
        "expectIPs": ["geoip:cn"]
      },
      "8.8.8.8",
      "1.1.1.1",
      "https+local://doh.dns.sb/dns-query"
    ]
  },
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "inboundTag": ["all-in"],
        "port": 53,
        "outboundTag": "dns-out"
      },
      {
        "type": "field",
        "ip": ["8.8.8.8", "1.1.1.1"],
        "outboundTag": "proxy"
      },
      {
        "type": "field",
        "domain": ["geosite:category-ads-all"],
        "outboundTag": "block"
      },
      {
        "type": "field",
        "domain": ["geosite:geolocation-!cn"],
        "outboundTag": "proxy"
      },
      {
        "type": "field",
        "ip": ["geoip:telegram"],
        "outboundTag": "proxy"
      }
    ]
  }
}
```

# Start on Boot

```ini
[Unit]
Description=XRay TProxy Service
After=network.target

[Service]
ExecStartPre=/bin/bash /path/to/script.sh # TProxy initialization script
ExecStart=/path/to/xray run -c /path/to/config.json # Xray configuration
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

# Proxy Other Device

## 1.Enable IP Forwarding

```sh
sudo vi /etc/sysctl.conf

# Uncomment the following line to enable IP forwarding
net.ipv4.ip_forward=1

sudo sysctl -p
```

## 2.Set Up Other Device

set `Gateway` and `DNS servers` to tproxy device IP

# I use NixOS btw

```nix
{
  systemd.services.tproxy-routing = {
    enable = true;
    description = "Setup Transparent Proxy Routing";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      type = "oneshot";
      ExecStart = "/run/current-system/sw/bin/ip route add local default dev lo table 100";
      ExecStartPost = "/run/current-system/sw/bin/ip rule add fwmark 1 table 100";
      RemainAfterExit = true;
    };
  };
  networking.firewall.extraCommands = ''
    iptables -t mangle -N XRAY
    iptables -t mangle -A XRAY -d 10.0.0.0/8 -j RETURN
    iptables -t mangle -A XRAY -d 100.64.0.0/10 -j RETURN
    iptables -t mangle -A XRAY -d 127.0.0.0/8 -j RETURN
    iptables -t mangle -A XRAY -d 169.254.0.0/16 -j RETURN
    iptables -t mangle -A XRAY -d 172.16.0.0/12 -j RETURN
    iptables -t mangle -A XRAY -d 192.0.0.0/24 -j RETURN
    iptables -t mangle -A XRAY -d 224.0.0.0/4 -j RETURN
    iptables -t mangle -A XRAY -d 240.0.0.0/4 -j RETURN
    iptables -t mangle -A XRAY -d 255.255.255.255/32 -j RETURN
    iptables -t mangle -A XRAY -d 192.168.0.0/16 -p tcp ! --dport 53 -j RETURN
    iptables -t mangle -A XRAY -d 192.168.0.0/16 -p udp ! --dport 53 -j RETURN
    iptables -t mangle -A XRAY -p tcp -j TPROXY --on-port 52345 --tproxy-mark 1
    iptables -t mangle -A XRAY -p udp -j TPROXY --on-port 52345 --tproxy-mark 1
    iptables -t mangle -A PREROUTING -j XRAY

    iptables -t mangle -N XRAY_SELF
    iptables -t mangle -A XRAY_SELF -d 10.0.0.0/8 -j RETURN
    iptables -t mangle -A XRAY_SELF -d 100.64.0.0/10 -j RETURN
    iptables -t mangle -A XRAY_SELF -d 127.0.0.0/8 -j RETURN
    iptables -t mangle -A XRAY_SELF -d 169.254.0.0/16 -j RETURN
    iptables -t mangle -A XRAY_SELF -d 172.16.0.0/12 -j RETURN
    iptables -t mangle -A XRAY_SELF -d 192.0.0.0/24 -j RETURN
    iptables -t mangle -A XRAY_SELF -d 224.0.0.0/4 -j RETURN
    iptables -t mangle -A XRAY_SELF -d 240.0.0.0/4 -j RETURN
    iptables -t mangle -A XRAY_SELF -d 255.255.255.255/32 -j RETURN
    iptables -t mangle -A XRAY_SELF -d 192.168.0.0/16 -p tcp ! --dport 53 -j RETURN
    iptables -t mangle -A XRAY_SELF -d 192.168.0.0/16 -p udp ! --dport 53 -j RETURN
    iptables -t mangle -A XRAY_SELF -m mark --mark 2 -j RETURN
    iptables -t mangle -A XRAY_SELF -p tcp -j MARK --set-mark 1
    iptables -t mangle -A XRAY_SELF -p udp -j MARK --set-mark 1
    iptables -t mangle -A OUTPUT -j XRAY_SELF'';
  services.xray.enable = true;
  services.xray.settingsFile = /path/to/xray-config.json; # Xray configuration
}
```

Reference:

- [透明代理（TProxy）配置教程](https://xtls.github.io/en/document/level-2/tproxy.html)
