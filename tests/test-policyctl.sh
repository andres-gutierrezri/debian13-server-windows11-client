#!/usr/bin/env bash
# Pruebas de policyctl.sh en un directorio temporal (no toca /srv).
# Uso: ./tests/test-policyctl.sh
set -uo pipefail
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export POLICY_DIR="$(mktemp -d)"
CTL="${RAIZ}/src/server/policyctl.sh"
fallos=0
chequear() { # descripción, comando...
  local d="$1"; shift
  if "$@" >/dev/null 2>&1; then printf '[OK]    %s\n' "$d"; else printf '[FALLO] %s\n' "$d"; fallos=$((fallos+1)); fi
}
valor() { grep "^$1=" "${POLICY_DIR}/policy.conf" | cut -d= -f2; }

chequear "init crea policy.conf"            bash "$CTL" init
chequear "5 políticas en off tras init"      test "$(grep -c '=off$' "${POLICY_DIR}/policy.conf")" -eq 5
chequear "enable BLOCK_CMD"                  bash "$CTL" enable BLOCK_CMD
chequear "BLOCK_CMD quedó en on"             test "$(valor BLOCK_CMD)" = on
chequear "las demás siguen en off"           test "$(grep -c '=off$' "${POLICY_DIR}/policy.conf")" -eq 4
chequear "disable BLOCK_CMD"                 bash "$CTL" disable BLOCK_CMD
chequear "preset aula activa las 5"          bash "$CTL" preset aula
chequear "5 políticas en on"                 test "$(grep -c '=on$' "${POLICY_DIR}/policy.conf")" -eq 5
chequear "preset libre desactiva las 5"      bash "$CTL" preset libre
chequear "rechaza política inexistente"      bash -c "! bash '$CTL' enable NO_EXISTE"
chequear "show imprime SHA-256"              bash -c "bash '$CTL' show | grep -Eq '^[0-9a-f]{64}'"
chequear "init no sobrescribe"               bash -c "bash '$CTL' enable BLOCK_CMD && bash '$CTL' init && test \"\$(grep '^BLOCK_CMD=' '${POLICY_DIR}/policy.conf')\" = BLOCK_CMD=on"

rm -rf "$POLICY_DIR"
echo; [[ $fallos -eq 0 ]] && echo "Todas las pruebas superadas." || { echo "Pruebas fallidas: ${fallos}"; exit 1; }
