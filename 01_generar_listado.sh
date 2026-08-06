#!/bin/bash
#
# 01_generar_listado.sh
#
# Compara los audits (generados con informix_user_audit.sh) del servidor
# ANTIGUO y del NUEVO, y arma:
#   - listado_usuarios_so.txt   -> solo nombres de usuario de S.O. que faltan
#                                   en el nuevo (para llevar al servidor antiguo)
#   - grants_bd_faltantes/*.sql  -> GRANT que existian en el antiguo y faltan
#                                   en el nuevo (listos para aplicar directo,
#                                   no contienen datos sensibles)
#   - resumen.txt
#
# Uso:
#   ./01_generar_listado.sh <audit_ANTIGUO_dir> <audit_NUEVO_dir>

set -euo pipefail

OLD="${1:?Indica la carpeta del audit del servidor ANTIGUO}"
NEW="${2:?Indica la carpeta del audit del servidor NUEVO}"

STAMP=$(date +%Y%m%d_%H%M%S)
OUT="./paquete_${STAMP}"
mkdir -p "${OUT}/grants_bd_faltantes"

echo "== Usuarios de S.O. faltantes en el nuevo servidor ==" | tee "${OUT}/resumen.txt"

cut -d, -f1 "${OLD}/os_users.csv" | sort -u > "${OUT}/.old_names"
cut -d, -f1 "${NEW}/os_users.csv" | sort -u > "${OUT}/.new_names"

comm -23 "${OUT}/.old_names" "${OUT}/.new_names" > "${OUT}/listado_usuarios_so.txt"
rm -f "${OUT}/.old_names" "${OUT}/.new_names"

TOTAL=$(wc -l < "${OUT}/listado_usuarios_so.txt")
echo "  Total a buscar en el servidor antiguo: ${TOTAL}" | tee -a "${OUT}/resumen.txt"
cat "${OUT}/listado_usuarios_so.txt" | tee -a "${OUT}/resumen.txt"

echo "" | tee -a "${OUT}/resumen.txt"
echo "== GRANT de base de datos faltantes por base ==" | tee -a "${OUT}/resumen.txt"

for OLDFILE in "${OLD}"/grants/*.sql; do
  DB=$(basename "${OLDFILE}" .sql)
  NEWFILE="${NEW}/grants/${DB}.sql"

  if [ ! -f "${NEWFILE}" ]; then
    echo "  [${DB}] base no encontrada en el nuevo servidor -> copiando todos los grants" | tee -a "${OUT}/resumen.txt"
    grep -i '^grant' "${OLDFILE}" > "${OUT}/grants_bd_faltantes/${DB}.sql" || true
    continue
  fi

  grep -i '^grant' "${OLDFILE}" | sed 's/[[:space:]]\+/ /g' | sort -u > "${OUT}/.g_old"
  grep -i '^grant' "${NEWFILE}" | sed 's/[[:space:]]\+/ /g' | sort -u > "${OUT}/.g_new"
  comm -23 "${OUT}/.g_old" "${OUT}/.g_new" > "${OUT}/grants_bd_faltantes/${DB}.sql" || true
  rm -f "${OUT}/.g_old" "${OUT}/.g_new"

  N=$(wc -l < "${OUT}/grants_bd_faltantes/${DB}.sql")
  if [ "${N}" -gt 0 ]; then
    echo "  [${DB}] faltan ${N} grant(s)" | tee -a "${OUT}/resumen.txt"
  else
    rm -f "${OUT}/grants_bd_faltantes/${DB}.sql"
    echo "  [${DB}] OK" | tee -a "${OUT}/resumen.txt"
  fi
done

echo ""
echo "Listo. Carpeta generada: ${OUT}/"
echo "  1) Lleva ${OUT}/listado_usuarios_so.txt al servidor ANTIGUO"
echo "     y corre alli: 02_extraer_desde_antiguo.sh ${OUT}/listado_usuarios_so.txt"
echo "  2) ${OUT}/grants_bd_faltantes/*.sql ya estan listos para aplicar en el nuevo"
echo "     con dbaccess (no contienen datos sensibles, son solo GRANT SQL)"
