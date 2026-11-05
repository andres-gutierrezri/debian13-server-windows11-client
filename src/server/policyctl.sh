#!/usr/bin/env bash
# =============================================================================
# policyctl.sh - Gestión centralizada de políticas de restricción para Windows 11
# La fuente de verdad es un archivo clave=valor (policy.conf) en el servidor
# Debian; el cliente Windows lo descarga por SSH (Apply-Policy.ps1).
# Autor: Ingeniero Andrés Felipe Gutiérrez Rivera
# Uso:   sudo ./policyctl.sh {init|list|show|enable|disable|preset} [argumentos]
# =============================================================================
set -euo pipefail

POLICY_DIR="${POLICY_DIR:-/srv/policies/windows11}"
POLICY_FILE="${POLICY_DIR}/policy.conf"
POLITICAS=(BLOCK_INSTALL BLOCK_CMD BLOCK_POWERSHELL BLOCK_CONTROL_PANEL BLOCK_REGISTRY_TOOLS)

declare -A DESCRIPCION=(
  [BLOCK_INSTALL]="Prohíbe la instalación de programas (Windows Installer y Microsoft Store)"
  [BLOCK_CMD]="Bloquea el Símbolo del sistema (cmd.exe)"
  [BLOCK_POWERSHELL]="Bloquea PowerShell, PowerShell ISE, pwsh y Windows Terminal"
  [BLOCK_CONTROL_PANEL]="Bloquea el Panel de control y la app Configuración"
  [BLOCK_REGISTRY_TOOLS]="Bloquea regedit y las herramientas de edición del registro"
)

error() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }
info()  { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
registrar() { logger -t winpolicy "$*" 2>/dev/null || true; }

uso() {
  cat <<EOF
Uso: sudo $0 <comando> [argumentos]

  init                    Crea ${POLICY_FILE} con todas las políticas en "off"
  list                    Lista las políticas disponibles
  show                    Muestra el estado actual y su huella SHA-256
  enable  <POLITICA>      Activa una política (p. ej. BLOCK_CMD)
  disable <POLITICA>      Desactiva una política
  preset  aula|libre      aula = todas en "on"; libre = todas en "off"

Variable opcional: POLICY_DIR (por defecto /srv/policies/windows11)
EOF
  exit 1
}

validar_nombre() {
  local n="$1" p
  for p in "${POLITICAS[@]}"; do [[ "$p" == "$n" ]] && return 0; done
  error "Política desconocida: '${n}'. Use '$0 list'."
}

requerir_archivo() { [[ -f "$POLICY_FILE" ]] || error "No existe ${POLICY_FILE}. Ejecute: sudo $0 init"; }

# Reemplaza el valor de forma atómica (archivo temporal + mv)
fijar_valor() {
  local nombre="$1" valor="$2" tmp
  requerir_archivo
  [[ -w "$POLICY_DIR" ]] || error "Sin permiso de escritura en ${POLICY_DIR}; use sudo."
  tmp="$(mktemp "${POLICY_DIR}/.policy.XXXXXX")"
  sed "s/^${nombre}=.*/${nombre}=${valor}/" "$POLICY_FILE" > "$tmp"
  chmod 644 "$tmp"
  mv -f "$tmp" "$POLICY_FILE"
  registrar "${nombre}=${valor} (usuario=${SUDO_USER:-${USER:-$(id -un)}})"
  info "${nombre} = ${valor}"
}

comando="${1:-}"; [[ -n "$comando" ]] || uso
case "$comando" in
  init)
    mkdir -p "$POLICY_DIR" || error "No se pudo crear ${POLICY_DIR}; use sudo."
    chmod 755 "$POLICY_DIR"
    if [[ -f "$POLICY_FILE" ]]; then
      info "Ya existe ${POLICY_FILE}; no se sobrescribe."
    else
      {
        echo "# Políticas de restricción para Windows 11 (on|off) - gestionado por policyctl.sh"
        for p in "${POLITICAS[@]}"; do echo "${p}=off"; done
      } > "$POLICY_FILE"
      chmod 644 "$POLICY_FILE"
      registrar "init ${POLICY_FILE}"
      info "Creado ${POLICY_FILE}"
    fi
    ;;
  list)
    for p in "${POLITICAS[@]}"; do printf '%-22s %s\n' "$p" "${DESCRIPCION[$p]}"; done
    ;;
  show)
    requerir_archivo
    cat "$POLICY_FILE"
    echo; sha256sum "$POLICY_FILE"
    ;;
  enable|disable)
    [[ $# -eq 2 ]] || uso
    validar_nombre "$2"
    [[ "$comando" == "enable" ]] && fijar_valor "$2" on || fijar_valor "$2" off
    ;;
  preset)
    [[ $# -eq 2 ]] || uso
    case "$2" in
      aula)  for p in "${POLITICAS[@]}"; do fijar_valor "$p" on;  done ;;
      libre) for p in "${POLITICAS[@]}"; do fijar_valor "$p" off; done ;;
      *) uso ;;
    esac
    ;;
  *) uso ;;
esac
