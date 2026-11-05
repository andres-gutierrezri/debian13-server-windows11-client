#!/usr/sbin/nft -f
# /etc/nftables.conf  (plantilla) - política de denegación por defecto
flush ruleset

table inet filter {
  chain input {
    type filter hook input priority 0; policy drop;

    iif "lo" accept
    ct state established,related accept
    ct state invalid drop

    ip protocol icmp accept
    ip6 nexthdr icmpv6 accept

    # SSH y SMB solo desde la red local del laboratorio
    ip saddr @LAN_CIDR@ tcp dport 22 ct state new accept
    ip saddr @LAN_CIDR@ tcp dport 445 ct state new accept
  }
  chain forward {
    type filter hook forward priority 0; policy drop;
  }
  chain output {
    type filter hook output priority 0; policy accept;
  }
}
