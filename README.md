# Debian 13 como servidor y Windows 11 como cliente

![Debian](https://img.shields.io/badge/Debian-13%20trixie-A81D33?logo=debian&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-11-0078D4?logo=windows11&logoColor=white)
![Shell](https://img.shields.io/badge/Bash-5.x-4EAA25?logo=gnubash&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)
![Versión](https://img.shields.io/badge/versión-1.0.0-blue)
![Licencia](https://img.shields.io/badge/licencia-MIT-green)

Guía técnica y automatizable para desplegar un entorno cliente-servidor de laboratorio: **Debian 13 "trixie"** ofrece acceso remoto seguro (OpenSSH), compartición de archivos (Samba/SMB3), cortafuegos (nftables) y sincronización horaria (chrony); **Windows 11** consume esos servicios desde **PowerShell**.

> **Alcance.** Entorno de laboratorio sobre una red local aislada (por ejemplo, red solo-anfitrión de VirtualBox/Hyper-V o LAN doméstica). Los valores por defecto (`192.168.56.0/24`) deben adaptarse a su red.

---

## Tabla de contenidos

1. [Fundamentos y arquitectura](#1-fundamentos-y-arquitectura)
2. [Requisitos previos](#2-requisitos-previos)
3. [Obtención del proyecto](#3-obtención-del-proyecto)
4. [Variables de entorno](#4-variables-de-entorno)
5. [Configuración del servidor Debian 13](#5-configuración-del-servidor-debian-13)
   - 5.1 Instalación base y usuario administrador
   - 5.2 Actualización e instalación de paquetes
   - 5.3 Nombre de host y resolución local
   - 5.4 Red con IP estática
   - 5.5 OpenSSH (endurecimiento)
   - 5.6 Samba (SMB3)
   - 5.7 Cortafuegos nftables
   - 5.8 Sincronización horaria (chrony)
   - 5.9 Automatización con `setup-debian.sh`
6. [Configuración del cliente Windows 11](#6-configuración-del-cliente-windows-11)
   - 6.1 Cliente OpenSSH
   - 6.2 Llave ed25519 y copia al servidor
   - 6.3 Archivo `hosts` y `~/.ssh/config`
   - 6.4 Montaje de la unidad SMB
   - 6.5 Automatización con `Setup-Windows.ps1`
   - 6.6 Alternativa en CMD
7. [Verificación y pruebas](#7-verificación-y-pruebas)
8. [Endurecimiento posterior (desactivar contraseñas SSH)](#8-endurecimiento-posterior)
9. [Solución de problemas](#9-solución-de-problemas)
10. [Resumen de pasos](#10-resumen-de-pasos)
11. [Estructura del proyecto](#11-estructura-del-proyecto)
12. [Publicación en GitHub y GitLab](#12-publicación-en-github-y-gitlab)
13. [Conclusiones](#13-conclusiones)
14. [Referencias](#14-referencias)
15. [Autor y licencia](#15-autor-y-licencia)
16. [Anexo A. Políticas de restricción Debian → Windows 11](#anexo-a-políticas-de-restricción-debian--windows-11)

---

## 1. Fundamentos y arquitectura

Debian 13 ("trixie") es la versión estable del proyecto Debian y conserva `ifupdown`, `systemd` y `nftables` como piezas de administración de servidores, por lo que resulta una base predecible para un servidor de laboratorio [1], [2]. Su documentación oficial describe tanto la instalación como las rutas de actualización, y es la referencia primaria para cualquier divergencia entre versiones.

El acceso remoto se apoya en el protocolo SSH, cuya capa de transporte garantiza confidencialidad e integridad [3] y cuya capa de autenticación admite llaves públicas [4]. Windows 11 incluye el cliente OpenSSH como característica opcional, lo que elimina la necesidad de software de terceros [7].

La compartición de archivos emplea SMB. Samba implementa el servidor en Linux [5] y Windows 11 es cliente nativo del protocolo SMB2/SMB3 definido en la especificación pública de Microsoft [6]. Se fuerza SMB3 con firma obligatoria, coherente con las exigencias de seguridad actuales de los clientes Windows [5], [6].

```
┌────────────────────────────┐        LAN 192.168.56.0/24        ┌─────────────────────────────┐
│  Windows 11 (cliente)      │◄──────── SSH  (tcp/22) ──────────►│  Debian 13 (servidor)       │
│  192.168.56.20             │◄──────── SMB3 (tcp/445) ─────────►│  192.168.56.10              │
│  PowerShell / CMD          │                                    │  sshd · smbd · nftables     │
│  ssh.exe · New-SmbMapping  │                                    │  chrony · /srv/samba/...    │
└────────────────────────────┘                                    └─────────────────────────────┘
```

| Elemento | Servidor | Cliente |
|---|---|---|
| Sistema operativo | Debian 13 (trixie) | Windows 11 (23H2/24H2/25H2) |
| Nombre de host | `srv-debian13.lab.local` | cualquiera |
| IP (por defecto) | `192.168.56.10/24` | `192.168.56.20/24` |
| Servicios | `ssh`, `smbd`, `nftables`, `chrony` | `ssh.exe`, cliente SMB |
| Puertos | 22/tcp, 445/tcp | — |

## 2. Requisitos previos

- Debian 13 instalado (instalación mínima + "servidor SSH" + "utilidades estándar"), con un usuario no-root con `sudo`.
- Windows 11 con PowerShell 5.1 o superior; privilegios de **Administrador** solo para instalar OpenSSH.Client y editar `hosts`.
- Ambos equipos en la misma red y con conectividad ICMP.
- Acceso a Internet en el servidor para `apt`.
- Git (opcional) para clonar el repositorio.

## 3. Obtención del proyecto

**Debian:**

```bash
sudo apt update && sudo apt install -y git
git clone https://github.com/andres-gutierrezri/debian13-server-windows11-client.git
cd debian13-server-windows11-client
```

**Windows (PowerShell):**

```powershell
git clone https://github.com/andres-gutierrezri/debian13-server-windows11-client.git
Set-Location .\debian13-server-windows11-client
```

> También puede descomprimir el archivo `.zip` entregado junto con este proyecto.

## 4. Variables de entorno

```bash
cp .env.example .env
nano .env        # ajuste interfaz, IP, usuario, red, etc.
```

| Variable | Valor por defecto | Descripción |
|---|---|---|
| `SERVER_HOSTNAME` | `srv-debian13` | Nombre corto del servidor |
| `DOMAIN_SUFFIX` | `lab.local` | Sufijo de dominio local |
| `SERVER_IFACE` | autodetectada | Interfaz (`ip -br link`) |
| `SERVER_IP` / `PREFIX` | `192.168.56.10` / `24` | Dirección estática |
| `LAN_CIDR` | `192.168.56.0/24` | Red permitida en el firewall y Samba |
| `ADMIN_USER` | `sysadmin` | Usuario existente en Debian |
| `SMB_GROUP` | `smbusers` | Grupo con acceso al recurso |
| `SHARE_NAME` / `SHARE_PATH` | `compartido` / `/srv/samba/compartido` | Recurso SMB |
| `APPLY_NETWORK` | `false` | `true` escribe la IP estática (puede cortar la sesión) |
| `SSH_PASSWORD_AUTH` | `yes` | Cambiar a `no` tras instalar la llave pública |

## 5. Configuración del servidor Debian 13

Todos los comandos se ejecutan en la terminal de Debian. Las secciones 5.1 a 5.8 detallan el procedimiento manual; la 5.9 lo automatiza.

### 5.1 Instalación base y usuario administrador

```bash
cat /etc/os-release | grep -E 'PRETTY_NAME|VERSION_CODENAME'   # debe indicar trixie
sudo adduser sysadmin            # si aún no existe
sudo usermod -aG sudo sysadmin
```

### 5.2 Actualización e instalación de paquetes

```bash
sudo apt update && sudo apt full-upgrade -y
sudo apt install -y openssh-server samba nftables chrony sudo curl ca-certificates
```

### 5.3 Nombre de host y resolución local

```bash
sudo hostnamectl set-hostname srv-debian13
echo "192.168.56.10 srv-debian13.lab.local srv-debian13" | sudo tee -a /etc/hosts
hostnamectl
```

### 5.4 Red con IP estática

Debian conserva `ifupdown` como método clásico de configuración [13]. Identifique la interfaz y cree un fragmento dedicado:

```bash
ip -br link                                   # p. ej. enp0s8
sudo tee /etc/network/interfaces.d/lab-static <<'EOF'
auto enp0s8
iface enp0s8 inet static
    address 192.168.56.10/24
    gateway 192.168.56.1
    dns-nameservers 1.1.1.1
EOF
sudo systemctl restart networking
ip -br addr show enp0s8
```

> **Precaución:** si está conectado por SSH a esa misma interfaz, la sesión puede interrumpirse. En máquinas con NetworkManager use `nmcli con mod` en su lugar [2], [13].

### 5.5 OpenSSH (endurecimiento)

Los parámetros se documentan en `sshd_config(5)` [9]. Se usa un fragmento en `sshd_config.d/` para no alterar el archivo original:

```bash
sudo tee /etc/ssh/sshd_config.d/10-hardening.conf <<'EOF'
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication yes
KbdInteractiveAuthentication no
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
AllowUsers sysadmin
EOF
sudo sshd -t && sudo systemctl enable --now ssh && sudo systemctl reload ssh
```

`PasswordAuthentication` queda en `yes` solo mientras se instala la llave del cliente; se desactiva en la [sección 8](#8-endurecimiento-posterior) [3], [9].

### 5.6 Samba (SMB3)

```bash
sudo groupadd smbusers
sudo usermod -aG smbusers sysadmin
sudo mkdir -p /srv/samba/compartido
sudo chown root:smbusers /srv/samba/compartido
sudo chmod 2770 /srv/samba/compartido

sudo cp /etc/samba/smb.conf /etc/samba/smb.conf.bak
sudo tee /etc/samba/smb.conf <<'EOF'
[global]
   workgroup = WORKGROUP
   server role = standalone server
   security = user
   map to guest = never
   server min protocol = SMB3
   server signing = mandatory
   smb encrypt = desired
   hosts allow = 127.0.0.1 192.168.56.0/24
   hosts deny = ALL
   disable netbios = yes
   smb ports = 445

[compartido]
   path = /srv/samba/compartido
   read only = no
   valid users = @smbusers
   force group = smbusers
   create mask = 0660
   directory mask = 0770
EOF

testparm -s
sudo smbpasswd -a sysadmin          # contraseña SMB independiente de la de Linux
sudo systemctl enable --now smbd && sudo systemctl restart smbd
```

La base de contraseñas de Samba es distinta de `/etc/shadow`, por eso `smbpasswd` es obligatorio [5]. Windows 11 rechaza el acceso de invitado por defecto, razón por la cual se usa autenticación de usuario [6].

### 5.7 Cortafuegos nftables

Se adopta política de denegación por defecto y se abren únicamente SSH y SMB hacia la red local [8].

```bash
sudo tee /etc/nftables.conf <<'EOF'
#!/usr/sbin/nft -f
flush ruleset
table inet filter {
  chain input {
    type filter hook input priority 0; policy drop;
    iif "lo" accept
    ct state established,related accept
    ct state invalid drop
    ip protocol icmp accept
    ip6 nexthdr icmpv6 accept
    ip saddr 192.168.56.0/24 tcp dport 22  ct state new accept
    ip saddr 192.168.56.0/24 tcp dport 445 ct state new accept
  }
  chain forward { type filter hook forward priority 0; policy drop; }
  chain output  { type filter hook output  priority 0; policy accept; }
}
EOF
sudo nft -c -f /etc/nftables.conf && sudo systemctl enable --now nftables
sudo nft list ruleset
```

### 5.8 Sincronización horaria (chrony)

Kerberos, TLS y los registros dependen de relojes coherentes [10].

```bash
sudo systemctl enable --now chrony
chronyc tracking
chronyc sources -v
```

### 5.9 Automatización con `setup-debian.sh`

```bash
chmod +x src/server/setup-debian.sh tests/test-server.sh
sudo ./src/server/setup-debian.sh            # lee .env automáticamente
sudo ./tests/test-server.sh
```

El script crea respaldos `*.bak.<fecha>` de cada archivo que sobrescribe, valida `sshd -t`, `testparm` y `nft -c` antes de reiniciar servicios, y solo toca la red si `APPLY_NETWORK=true`.

## 6. Configuración del cliente Windows 11

Abra **PowerShell** (como Administrador para las secciones 6.1 y 6.3).

### 6.1 Cliente OpenSSH

```powershell
Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Client*'
Add-WindowsCapability -Online -Name 'OpenSSH.Client~~~~0.0.1.0'
ssh -V
```

El cliente OpenSSH es una característica opcional de Windows documentada oficialmente por Microsoft [7].

### 6.2 Llave ed25519 y copia al servidor

```powershell
ssh-keygen -t ed25519 -a 100 -C "$env:USERNAME@$env:COMPUTERNAME"

# Equivalente a ssh-copy-id (Windows no lo incluye):
Get-Content "$env:USERPROFILE\.ssh\id_ed25519.pub" |
  ssh sysadmin@192.168.56.10 "umask 077; mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"

ssh sysadmin@192.168.56.10          # ya no debe pedir contraseña
```

La autenticación por llave pública sigue el marco descrito en la RFC 4252 [4].

### 6.3 Archivo `hosts` y `~/.ssh/config`

```powershell
Add-Content "$env:SystemRoot\System32\drivers\etc\hosts" "192.168.56.10`tsrv-debian13.lab.local`tsrv-debian13"

Add-Content "$env:USERPROFILE\.ssh\config" @"
Host srv-debian13
    HostName 192.168.56.10
    User sysadmin
    IdentityFile ~/.ssh/id_ed25519
    ServerAliveInterval 60
"@
ssh srv-debian13
```

### 6.4 Montaje de la unidad SMB

```powershell
Test-NetConnection 192.168.56.10 -Port 445
$cred = Get-Credential -UserName sysadmin -Message 'Contraseña SMB'
New-SmbMapping -LocalPath 'Z:' -RemotePath '\\192.168.56.10\compartido' `
  -UserName sysadmin -Password $cred.GetNetworkCredential().Password -Persistent $true
Get-SmbMapping
Get-ChildItem Z:\
```

Para desmontar: `Remove-SmbMapping -LocalPath 'Z:' -Force -UpdateProfile`. Samba y Windows negocian dialecto y firma conforme a [MS-SMB2] [6]; la opción `server signing = mandatory` es compatible con los clientes actuales [5].

### 6.5 Automatización con `Setup-Windows.ps1`

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\src\client\Setup-Windows.ps1 -ServerIp 192.168.56.10 -User sysadmin -ShareName compartido -DriveLetter Z
.\tests\Test-Client.ps1
```

### 6.6 Alternativa en CMD

```bat
ssh sysadmin@192.168.56.10
net use Z: \\192.168.56.10\compartido /user:sysadmin * /persistent:yes
net use
net use Z: /delete
```

## 7. Verificación y pruebas

| Prueba | Equipo | Comando | Resultado esperado |
|---|---|---|---|
| Servicios activos | Debian | `systemctl is-active ssh smbd nftables chrony` | `active` ×4 |
| Puertos en escucha | Debian | `ss -ltn '( sport = :22 or sport = :445 )'` | 2 líneas LISTEN |
| Sintaxis SSH | Debian | `sudo sshd -t` | sin salida |
| Sintaxis Samba | Debian | `testparm -s` | sin errores |
| Reglas de firewall | Debian | `sudo nft list ruleset` | `policy drop` |
| Conectividad | Windows | `Test-NetConnection 192.168.56.10 -Port 22` | `TcpTestSucceeded : True` |
| SSH por llave | Windows | `ssh -o BatchMode=yes sysadmin@192.168.56.10 echo ok` | `ok` |
| SMB | Windows | `Test-Path Z:\` | `True` |

Ejecución integral: `sudo ./tests/test-server.sh` (Debian) y `.\tests\Test-Client.ps1` (Windows).

## 8. Endurecimiento posterior

Solo después de comprobar el acceso por llave:

```bash
sudo sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config.d/10-hardening.conf
sudo sshd -t && sudo systemctl reload ssh
```

Mantenga **otra sesión abierta** mientras prueba, para no quedar excluido. Si usa el script, establezca `SSH_PASSWORD_AUTH=no` en `.env` y vuelva a ejecutarlo [9].

## 9. Solución de problemas

| Síntoma | Causa probable | Acción |
|---|---|---|
| `Connection timed out` en SSH | Firewall o IP incorrecta | `sudo nft list ruleset`; verifique `LAN_CIDR` y la IP del cliente |
| `Permission denied (publickey)` | Llave no instalada o permisos | `chmod 700 ~/.ssh; chmod 600 ~/.ssh/authorized_keys` en Debian |
| `Error de red 53` / `System error 53` | Puerto 445 bloqueado o IP errónea | `Test-NetConnection IP -Port 445` |
| `Error 1219` (conexiones múltiples) | Sesión previa con otro usuario | `net use * /delete` y reintente |
| Windows exige firma y falla | Política de firma desalineada | Mantener `server signing = mandatory` en `smb.conf` |
| Acceso denegado al recurso | Usuario fuera de `smbusers` o sin `smbpasswd` | `id sysadmin`; `sudo pdbedit -L` |
| `REMOTE HOST IDENTIFICATION HAS CHANGED` | Servidor reinstalado | `ssh-keygen -R 192.168.56.10` |
| Hora desfasada | chrony sin fuentes | `chronyc sources -v`; revise salida a Internet |

Registros útiles: `journalctl -u ssh -u smbd --since "10 min ago"` y `/var/log/samba/`.

## 10. Resumen de pasos

1. Verificar Debian 13: `grep VERSION_CODENAME /etc/os-release`.
2. Instalar paquetes: `sudo apt install -y openssh-server samba nftables chrony`.
3. Fijar nombre de host: `sudo hostnamectl set-hostname srv-debian13`.
4. Asignar IP estática: `/etc/network/interfaces.d/lab-static` + `sudo systemctl restart networking`.
5. Configurar SSH: `/etc/ssh/sshd_config.d/10-hardening.conf` + `sudo sshd -t`.
6. Configurar Samba: `/etc/samba/smb.conf`, `sudo smbpasswd -a sysadmin`, `testparm -s`.
7. Aplicar el firewall: `/etc/nftables.conf` + `sudo nft -c -f /etc/nftables.conf`.
8. Activar chrony y validar: `chronyc tracking`.
9. En Windows: `Add-WindowsCapability`, `ssh-keygen -t ed25519` y copiar la llave con `ssh ... authorized_keys`.
10. Montar el recurso y probar: `New-SmbMapping -LocalPath Z:` y `.\tests\Test-Client.ps1`.
11. Endurecer: `PasswordAuthentication no` y `sudo systemctl reload ssh`.
12. Versionar: `git init`, `git commit`, `git push` (sección 12).

## 11. Estructura del proyecto

```
debian13-server-windows11-client/
├── src/
│   ├── server/
│   │   ├── setup-debian.sh          # Automatización del servidor
│   │   ├── policyctl.sh             # Definición de políticas de restricción
│   │   └── configs/                 # Plantillas sshd, samba, nftables, red
│   └── client/
│       ├── Setup-Windows.ps1        # Automatización del cliente
│       └── Apply-Policy.ps1         # Aplicación de políticas (exige contraseña de Debian)
├── tests/
│   ├── test-server.sh               # Verificación Debian
│   ├── test-policyctl.sh            # Pruebas de policyctl.sh
│   └── Test-Client.ps1              # Verificación Windows
├── docs/
│   ├── PUBLICACION-GIT.md           # GitHub/GitLab: SSH, PAT, doble remoto, Git Flow
│   └── POLITICAS-RESTRICCION.md     # Detalle, limitaciones y recuperación
├── .env.example
├── .gitignore
├── LICENSE
└── README.md
```

> Este proyecto está compuesto por scripts de shell y PowerShell, por lo que **no requiere `requirements.txt` ni `package.json`**; no existen dependencias de Python ni Node.

## 12. Publicación en GitHub y GitLab

Resumen de comandos (procedimiento detallado, doble remoto, SSH/PAT, Git Flow, Conventional Commits y SemVer en [`docs/PUBLICACION-GIT.md`](docs/PUBLICACION-GIT.md)) [11], [12]:

```bash
git init
git config user.name  "Andrés Felipe Gutiérrez Rivera"
git config user.email "felipe.gutierrezri@gmail.com"
git add .
git commit -m "feat: versión inicial del entorno Debian 13 servidor y Windows 11 cliente"
git branch -M main

# 1) Cree el repositorio vacío en la interfaz web de GitHub (sin README) y luego:
git remote add origin git@github.com:andres-gutierrezri/debian13-server-windows11-client.git
git push -u origin main

# 2) Repetir en GitLab: https://gitlab.com/andres.gutierrezri
git remote add gitlab git@gitlab.com:andres.gutierrezri/debian13-server-windows11-client.git
git push -u gitlab main

git tag -a v1.0.0 -m "Primera versión estable"
git push origin v1.0.0 && git push gitlab v1.0.0
```

## 13. Conclusiones

1. Separar el procedimiento manual de la automatización permite auditar cada decisión antes de ejecutar scripts con privilegios [2], [11].
2. Usar fragmentos en `sshd_config.d/` evita editar el archivo principal y facilita revertir cambios [9].
3. La autenticación por llave ed25519 elimina el riesgo de ataques de fuerza bruta contra contraseñas [3], [4].
4. Mantener `PasswordAuthentication yes` temporalmente reduce el riesgo de quedar excluido durante la configuración inicial.
5. Forzar SMB3 con firma obligatoria evita dialectos heredados y alinea el servidor con los clientes Windows 11 [5], [6].
6. Samba mantiene su propia base de credenciales; omitir `smbpasswd` es la causa más frecuente de acceso denegado [5].
7. Una política `drop` en nftables con reglas explícitas hacia la red local reduce la superficie de ataque del servidor [8].
8. Restringir `hosts allow` en Samba y `saddr` en nftables implementa defensa en profundidad con dos capas independientes [5], [8].
9. La sincronización con chrony es una dependencia transversal de registros, certificados y trazabilidad [10].
10. Validar con `sshd -t`, `testparm` y `nft -c` antes de reiniciar previene interrupciones del servicio [8], [9].
11. Windows 11 no incluye `ssh-copy-id`; la tubería de PowerShell hacia `authorized_keys` es un sustituto funcional [7].
12. Versionar plantillas con marcadores `@VAR@` y un `.env.example` separa configuración de secretos [11], [12].
13. La doble publicación en GitHub y GitLab aporta redundancia del código y resiliencia frente a la indisponibilidad de un proveedor [11].

## 14. Referencias

[1] Debian Project, "Debian 13 'trixie' Release Notes." [En línea]. Disponible: https://www.debian.org/releases/trixie/releasenotes

[2] R. Hertzog and R. Mas, *The Debian Administrator's Handbook*. [En línea]. Disponible: https://debian-handbook.info/

[3] T. Ylonen and C. Lonvick, Ed., "The Secure Shell (SSH) Transport Layer Protocol," IETF, RFC 4253, Jan. 2006. [En línea]. Disponible: https://www.rfc-editor.org/rfc/rfc4253

[4] T. Ylonen and C. Lonvick, Ed., "The Secure Shell (SSH) Authentication Protocol," IETF, RFC 4252, Jan. 2006. [En línea]. Disponible: https://www.rfc-editor.org/rfc/rfc4252

[5] Samba Team, "Samba Documentation." [En línea]. Disponible: https://www.samba.org/samba/docs/

[6] Microsoft, "[MS-SMB2]: Server Message Block (SMB) Protocol Versions 2 and 3." [En línea]. Disponible: https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-smb2/

[7] Microsoft, "OpenSSH for Windows overview." [En línea]. Disponible: https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh-overview

[8] The nftables Project, "Quick reference: nftables in 10 minutes." [En línea]. Disponible: https://wiki.nftables.org/wiki-nftables/index.php/Quick_reference-nftables_in_10_minutes

[9] OpenBSD Project, "sshd_config(5) — OpenSSH daemon configuration file." [En línea]. Disponible: https://man.openbsd.org/sshd_config

[10] chrony Project, "chrony Documentation." [En línea]. Disponible: https://chrony-project.org/documentation.html

[11] S. Chacon and B. Straub, *Pro Git*, 2nd ed., Apress, 2014. [En línea]. Disponible: https://git-scm.com/book

[12] T. Preston-Werner, "Semantic Versioning 2.0.0." [En línea]. Disponible: https://semver.org/

[13] Debian Wiki, "NetworkConfiguration." [En línea]. Disponible: https://wiki.debian.org/NetworkConfiguration

[14] Microsoft, "DisableMSI," Windows Installer. [En línea]. Disponible: https://learn.microsoft.com/en-us/windows/win32/msi/disablemsi

[15] Microsoft, "reg load," Windows commands. [En línea]. Disponible: https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/reg-load

[16] Microsoft, "Software Restriction Policies." [En línea]. Disponible: https://learn.microsoft.com/en-us/windows-server/identity/software-restriction-policies/software-restriction-policies

[17] Microsoft, "AppLocker overview." [En línea]. Disponible: https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/applocker/applocker-overview

[18] T. C. Miller, "sudo(8) manual (opciones -S, -k, -v)." [En línea]. Disponible: https://www.sudo.ws/docs/man/sudo.man/

> Las URL corresponden a documentación pública habitual de cada proyecto; verifique su vigencia antes de citarlas en un trabajo formal.

## 15. Autor y licencia

**Ingeniero Andrés Felipe Gutiérrez Rivera**

- GitHub: <https://github.com/andres-gutierrezri>
- GitLab: <https://gitlab.com/andres.gutierrezri>
- LinkedIn: <https://www.linkedin.com/in/felipe-gutierrezri>

Distribuido bajo licencia [MIT](LICENSE).

---

## Anexo A. Políticas de restricción Debian → Windows 11

Este módulo permite que el servidor Debian 13 defina **qué se restringe** y que el cliente Windows 11 lo aplique únicamente tras validar la **contraseña del servidor**. Las políticas se definen en `policy.conf` mediante `policyctl.sh` y se traducen a claves de registro de Windows con `Apply-Policy.ps1` [14], [15]. La validación de la contraseña se realiza con `sudo -S -k -v` en el servidor, por lo que la clave nunca se almacena en el cliente [18], [3].

| Política | Qué restringe |
|---|---|
| `BLOCK_INSTALL` | Instalación de programas MSI y Microsoft Store [14] |
| `BLOCK_CMD` | Símbolo del sistema (`cmd.exe`) |
| `BLOCK_POWERSHELL` | `powershell.exe`, ISE, `pwsh.exe` y Windows Terminal |
| `BLOCK_CONTROL_PANEL` | Panel de control y Configuración |
| `BLOCK_REGISTRY_TOOLS` | `regedit` y herramientas del registro |

**Servidor Debian:**

```bash
chmod +x src/server/policyctl.sh tests/test-policyctl.sh
sudo ./src/server/policyctl.sh init
sudo ./src/server/policyctl.sh enable BLOCK_CMD
sudo ./src/server/policyctl.sh preset aula          # activa las 5 políticas
./src/server/policyctl.sh show
./tests/test-policyctl.sh
```

**Cliente Windows 11 (PowerShell como Administrador; el usuario objetivo debe ser estándar):**

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\src\client\Apply-Policy.ps1 -Action Status -TargetUser estudiante
.\src\client\Apply-Policy.ps1 -Action Apply  -TargetUser estudiante   # solicita la contraseña de Debian
.\src\client\Apply-Policy.ps1 -Action Remove -TargetUser estudiante   # solicita la contraseña de Debian
```

**Limitaciones importantes:** un Administrador local de Windows puede editar el registro sin pasar por el script, y `DisableMSI` no bloquea instaladores `.exe` ni programas portables; para una aplicación obligatoria use cuentas estándar y AppLocker/Directiva de grupo [16], [17]. El detalle, la tabla de claves de registro, la auditoría y el procedimiento de recuperación están en [`docs/POLITICAS-RESTRICCION.md`](docs/POLITICAS-RESTRICCION.md).
