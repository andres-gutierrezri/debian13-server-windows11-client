#!/usr/bin/env bash
# Pruebas de verificación del servidor Debian 13. Uso: sudo ./tests/test-server.sh
set -uo pipefail
fallos=0
ok()   { printf '\033[1;32m[OK]\033[0m   %s\n' "$*"; }
fallo(){ printf '\033[1;31m[FALLO]\033[0m %s\n' "$*"; fallos=$((fallos+1)); }

for srv in ssh smbd nftables chrony; do
  systemctl is-active --quiet "$srv" && ok "Servicio ${srv} activo" || fallo "Servicio ${srv} inactivo"
done
for puerto in 22 445; do
  ss -ltn "sport = :${puerto}" | grep -q LISTEN && ok "Puerto ${puerto}/tcp en escucha" || fallo "Puerto ${puerto}/tcp cerrado"
done
sshd -t 2>/dev/null && ok "sshd -t sin errores" || fallo "sshd -t reporta errores"
testparm -s >/dev/null 2>&1 && ok "testparm sin errores" || fallo "testparm reporta errores"
nft list ruleset | grep -q 'policy drop' && ok "nftables con política drop" || fallo "nftables sin política drop"
chronyc tracking >/dev/null 2>&1 && ok "chronyc tracking responde" || fallo "chronyc no responde"

echo; [[ $fallos -eq 0 ]] && echo "Todas las pruebas superadas." || { echo "Pruebas fallidas: ${fallos}"; exit 1; }
