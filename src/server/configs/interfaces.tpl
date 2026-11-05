# /etc/network/interfaces.d/lab-static  (plantilla, solo si APPLY_NETWORK=true)
auto @SERVER_IFACE@
iface @SERVER_IFACE@ inet static
    address @SERVER_IP@/@PREFIX@
    gateway @GATEWAY@
    dns-nameservers @DNS@
