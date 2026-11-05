#!/usr/bin/env bash
# =============================================================================
# setup-debian.sh - Configuración del servidor Debian 13 (trixie)
# Servicios: OpenSSH, Samba (SMB3), nftables, chrony
# Autor: Ingeniero Andrés Felipe Gutiérrez Rivera
# Uso:   sudo ./setup-debian.sh [ruta/al/.env]
# =============================================================================
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLANTILLAS="${RAIZ}/src/server/configs"
ARCHIVO_ENV="${1:-${RAIZ}/.env}"

# --- Utilidades --------------------------------------------------------------
info()  { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
aviso() { printf '\033[1;33m[AVISO]\033[0m %s\n' "$*"; }
error() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || error "Ejecute este script como root (sudo)."
grep -q '^VERSION_CODENAME=trixie' /etc/os-release \
  || aviso "El sistema no parece ser Debian 13 (trixie); continúe bajo su criterio."

# --- Variables (valores por defecto + .env) ----------------------------------
SERVER_HOSTNAME=srv-debian13; DOMAIN_SUFFIX=lab.local
SERVER_IFACE=""; SERVER_IP=192.168.56.10; PREFIX=24
LAN_CIDR=192.168.56.0/24; GATEWAY=192.168.56.1; DNS=1.1.1.1
ADMIN_USER=sysadmin; SMB_GROUP=smbusers
SHARE_NAME=compartido; SHARE_PATH=/srv/samba/compartido
WORKGROUP=WORKGROUP; APPLY_NETWORK=false; SSH_PASSWORD_AUTH=yes

if [[ -f "$ARCHIVO_ENV" ]]; then
  info "Cargando variables desde ${ARCHIVO_ENV}"
  # shellcheck disable=SC1090
  set -a; source "$ARCHIVO_ENV"; set +a
fi

[[ -n "$SERVER_IFACE" ]] || SERVER_IFACE="$(ip -o -4 route show to default | awk '{print $5; exit}')"
[[ -n "$SERVER_IFACE" ]] || error "No se pudo detectar la interfaz de red; defina SERVER_IFACE."
id "$ADMIN_USER" &>/dev/null || error "El usuario ${ADMIN_USER} no existe (adduser ${ADMIN_USER})."
[[ "$SSH_PASSWORD_AUTH" =~ ^(yes|no)$ ]] || error "SSH_PASSWORD_AUTH debe ser yes o no."

# Sustituye marcadores @VAR@ de una plantilla y escribe el destino con respaldo
renderizar() {
  local origen="$1" destino="$2"
  [[ -f "$destino" ]] && cp -a "$destino" "${destino}.bak.$(date +%Y%m%d%H%M%S)"
  sed -e "s|@SERVER_IFACE@|${SERVER_IFACE}|g" -e "s|@SERVER_IP@|${SERVER_IP}|g" \
      -e "s|@PREFIX@|${PREFIX}|g"             -e "s|@LAN_CIDR@|${LAN_CIDR}|g" \
      -e "s|@GATEWAY@|${GATEWAY}|g"           -e "s|@DNS@|${DNS}|g" \
      -e "s|@ADMIN_USER@|${ADMIN_USER}|g"     -e "s|@SMB_GROUP@|${SMB_GROUP}|g" \
      -e "s|@SHARE_NAME@|${SHARE_NAME}|g"     -e "s|@SHARE_PATH@|${SHARE_PATH}|g" \
      -e "s|@WORKGROUP@|${WORKGROUP}|g"       -e "s|@SSH_PASSWORD_AUTH@|${SSH_PASSWORD_AUTH}|g" \
      "$origen" > "$destino"
}

# --- 1. Sistema base ---------------------------------------------------------
info "1/7 Actualizando índices e instalando paquetes"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y openssh-server samba nftables chrony sudo curl ca-certificates

# --- 2. Nombre de host -------------------------------------------------------
info "2/7 Configurando nombre de host: ${SERVER_HOSTNAME}"
hostnamectl set-hostname "$SERVER_HOSTNAME"
grep -q "${SERVER_HOSTNAME}.${DOMAIN_SUFFIX}" /etc/hosts \
  || echo "${SERVER_IP} ${SERVER_HOSTNAME}.${DOMAIN_SUFFIX} ${SERVER_HOSTNAME}" >> /etc/hosts

# --- 3. Red estática (opcional) ----------------------------------------------
if [[ "$APPLY_NETWORK" == "true" ]]; then
  info "3/7 Escribiendo IP estática en /etc/network/interfaces.d/lab-static"
  renderizar "${PLANTILLAS}/interfaces.tpl" /etc/network/interfaces.d/lab-static
  aviso "La IP se aplicará al reiniciar la red; puede perder la sesión actual."
else
  info "3/7 Red: omitida (APPLY_NETWORK=false)"
fi

# --- 4. OpenSSH --------------------------------------------------------------
info "4/7 Configurando OpenSSH"
mkdir -p /etc/ssh/sshd_config.d
renderizar "${PLANTILLAS}/sshd-hardening.conf.tpl" /etc/ssh/sshd_config.d/10-hardening.conf
sshd -t || error "Configuración sshd inválida; revise /etc/ssh/sshd_config.d/10-hardening.conf"
systemctl enable --now ssh
systemctl reload ssh

# --- 5. Samba ----------------------------------------------------------------
info "5/7 Configurando Samba (SMB3)"
getent group "$SMB_GROUP" >/dev/null || groupadd "$SMB_GROUP"
usermod -aG "$SMB_GROUP" "$ADMIN_USER"
mkdir -p "$SHARE_PATH"
chown root:"$SMB_GROUP" "$SHARE_PATH"
chmod 2770 "$SHARE_PATH"
renderizar "${PLANTILLAS}/smb.conf.tpl" /etc/samba/smb.conf
testparm -s /etc/samba/smb.conf >/dev/null || error "smb.conf inválido."
if ! pdbedit -L 2>/dev/null | grep -q "^${ADMIN_USER}:"; then
  info "Defina la contraseña SMB de ${ADMIN_USER} (independiente de la de Linux):"
  smbpasswd -a "$ADMIN_USER"
fi
systemctl enable --now smbd
systemctl restart smbd

# --- 6. Cortafuegos nftables -------------------------------------------------
info "6/7 Configurando nftables"
renderizar "${PLANTILLAS}/nftables.conf.tpl" /etc/nftables.conf
nft -c -f /etc/nftables.conf || error "nftables.conf inválido."
systemctl enable --now nftables
systemctl restart nftables

# --- 7. Sincronización horaria ----------------------------------------------
info "7/7 Habilitando chrony"
systemctl enable --now chrony

info "Servidor configurado. Verifique con: sudo ./tests/test-server.sh"
