#!/bin/bash
#
# informix_user_audit.sh
#
# Recorre las cuentas de sistema operativo (/etc/passwd) y las cuentas/permisos
# dentro de Informix (sysusers + dbschema -g), y cruza ambas listas.
#
# Uso:
#   ./informix_user_audit.sh <servidor_tag>
#
# Ejemplo:
#   ./informix_user_audit.sh legadoprod_antes
#   ./informix_user_audit.sh legadoprod_despues
#
# Genera una carpeta ./audit_<servidor_tag>/ con:
#   os_users.csv        -> cuentas reales del S.O.
#   db_users.csv         -> usuarios con nivel CONNECT/RESOURCE/DBA por base
#   grants/<db>.sql      -> volcado completo de GRANT por base (dbschema -g)
#   ambos.csv            -> existen en S.O. y en Informix
#   solo_so.csv           -> existen en S.O. pero sin permisos en Informix
#   solo_bd.csv           -> existen en Informix pero sin cuenta de S.O.
#
# Requiere: INFORMIXDIR / INFORMIXSERVER / ONCONFIG configurados en el entorno,
# y el usuario que ejecuta el script debe poder correr dbaccess y dbschema.

set -euo pipefail

TAG="${1:?Debes indicar un nombre para este levantamiento, ej: legadoprod_antes}"
OUTDIR="./audit_${TAG}"
mkdir -p "${OUTDIR}/grants"

echo "== 1. Cuentas de sistema operativo =="

# Cuentas de sistema que normalmente NO interesan para el cruce.
# Ajusta esta lista según lo que veas en cada servidor (varía entre RHEL 5 y RHEL 8).
EXCLUDE_REGEX='^(root|bin|daemon|adm|lp|sync|shutdown|halt|mail|operator|games|ftp|nobody|dbus|polkitd|sshd|chrony|systemd-.*|rpc|rpcuser|nfsnobody|tss|postfix|avahi.*|colord|geoclue|gnome-.*|pipewire|gdm|setroubleshoot)$'

awk -F: '{print $1","$3","$6","$7}' /etc/passwd \
  | awk -F, -v re="${EXCLUDE_REGEX}" '$1 !~ re' \
  > "${OUTDIR}/os_users.csv"

echo "  -> $(wc -l < "${OUTDIR}/os_users.csv") cuentas de S.O. relevantes"

echo "== 2. Bases de datos activas en la instancia =="

DBS=$(dbaccess sysmaster <<'SQL' 2>/dev/null | tail -n +3 | sed '/^$/d' | sed '/^(.*rows*)/d'
select trim(name) from sysdatabases where name not matches 'sys*';
SQL
)

echo "  -> Bases encontradas: $(echo "${DBS}" | wc -l)"

: > "${OUTDIR}/db_users.csv"

echo "== 3. Permisos por base de datos (sysusers + dbschema -g) =="

for DB in ${DBS}; do
  echo "  -- Procesando base: ${DB}"

  # 3a. Nivel de base de datos: CONNECT / RESOURCE / DBA
  dbaccess "${DB}" <<SQL 2>/dev/null | tail -n +3 | sed '/^$/d' | sed '/^(.*rows*)/d' \
    | awk -v db="${DB}" -F'|' '{gsub(/ /,"",$0); print $0","db}' >> "${OUTDIR}/db_users.csv"
select trim(username)||'|'||trim(usertype) from sysusers;
SQL

  # 3b. Volcado completo de GRANT (tablas, vistas, roles, columnas, procedimientos)
  dbschema -d "${DB}" -g > "${OUTDIR}/grants/${DB}.sql" 2>/dev/null || \
    echo "     (aviso: no se pudo generar dbschema -g para ${DB})"
done

echo "== 4. Cruce de ambas listas =="

# Usuarios únicos de S.O.
cut -d, -f1 "${OUTDIR}/os_users.csv" | sort -u > "${OUTDIR}/.os_names"

# Usuarios únicos con algún nivel dentro de Informix
cut -d, -f1 "${OUTDIR}/db_users.csv" | sort -u > "${OUTDIR}/.db_names"

comm -12 "${OUTDIR}/.os_names" "${OUTDIR}/.db_names" > "${OUTDIR}/ambos.csv"
comm -23 "${OUTDIR}/.os_names" "${OUTDIR}/.db_names" > "${OUTDIR}/solo_so.csv"
comm -13 "${OUTDIR}/.os_names" "${OUTDIR}/.db_names" > "${OUTDIR}/solo_bd.csv"

rm -f "${OUTDIR}/.os_names" "${OUTDIR}/.db_names"

echo ""
echo "Resumen para ${TAG}:"
echo "  Cuentas de S.O.......... $(wc -l < "${OUTDIR}/os_users.csv")"
echo "  Cuentas con permiso BD.. $(cut -d, -f1 "${OUTDIR}/db_users.csv" | sort -u | wc -l)"
echo "  En ambos................ $(wc -l < "${OUTDIR}/ambos.csv")"
echo "  Solo S.O. (sin GRANT)... $(wc -l < "${OUTDIR}/solo_so.csv")"
echo "  Solo BD (sin cuenta).... $(wc -l < "${OUTDIR}/solo_bd.csv")"
echo ""
echo "Resultados en: ${OUTDIR}/"
