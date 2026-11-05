# /etc/samba/smb.conf  (plantilla)
[global]
   workgroup = @WORKGROUP@
   server string = Servidor Debian 13 (%h)
   server role = standalone server
   security = user
   map to guest = never
   # Solo SMB3 (cifrado y firmado) para clientes Windows 11
   server min protocol = SMB3
   server signing = mandatory
   smb encrypt = desired
   interfaces = lo @SERVER_IFACE@
   bind interfaces only = yes
   hosts allow = 127.0.0.1 @LAN_CIDR@
   hosts deny = ALL
   log file = /var/log/samba/log.%m
   max log size = 1000
   disable netbios = yes
   smb ports = 445

[@SHARE_NAME@]
   comment = Recurso compartido del laboratorio
   path = @SHARE_PATH@
   browseable = yes
   read only = no
   valid users = @@SMB_GROUP@
   force group = @SMB_GROUP@
   create mask = 0660
   directory mask = 0770
