#!/bin/bash
#
# 03_aplicar_en_nuevo.sh
#
# CORRE EN EL SERVIDOR NUEVO, COMO ROOT.
#
# Toma el paquete generado por 02_extraer_desde_antiguo.sh y:
#   - crea cada cuenta de S.O. que falte (mismo home/shell)
#   - le asigna el MISMO HASH de clave que tenia en el servidor antiguo
#     (usermod -p toma el hash ya cifrado, nunca se ve la clave en texto plano)
#   - la agrega a los mismos grupos secundarios (sudo/wheel, etc.)
# Opcionalmente aplica los GRANT de base de datos faltantes.
#
# Modo por defecto: SOLO MUESTRA lo que haria (dry-run), no cambia nada.
# Para ejecutar de verdad, agrega --apply al final.
#
# Uso:
#   ./03_aplicar_en_nuevo.sh paquete_extraccion_XXXX.txt [grants_bd_faltantes/] [--apply]

set -euo pipefail

PAQUETE="${1:?Indica el archivo paquete_extraccion_XXXX.txt}"
GRANTS_DIR="${2:-}"
APPLY="${3:-}"
[ "${GRANTS_DIR}" == "--apply" ] && { APPLY="--apply"; GRANTS_DIR=""; }

if [ "${APPLY}" == "--apply" ] && [ "$(id -u)" -ne 0 ]; then
  echo "Para aplicar cambios reales este script debe correr como root."
  exit 1
fi

echo "== Cuentas de sistema operativo =="

USER="" ; PASSWD_LINE="" ; SHADOW_LINE="" ; GRUPOS=""

aplicar_usuario() {
  [ -z "${USER}" ] && return
  local uid gid home shell hash grupos_csv

  uid=$(echo "${PASSWD_LINE}"  | cut -d: -f3)
  gid=$(echo "${PASSWD_LINE}"  | cut -d: -f4)
  home=$(echo "${PASSWD_LINE}" | cut -d: -f6)
  shell=$(echo "${PASSWD_LINE}"| cut -d: -f7)
  hash=$(echo "${SHADOW_LINE}" | cut -d: -f2)
  grupos_csv="${GRUPOS}"

  if id "${USER}" >/dev/null 2>&1; then
    echo "  [YA EXISTE] ${USER} -> se omite creacion, revisar manualmente si el hash difiere"
    return
  fi

  if getent passwd "${uid}" >/dev/null 2>&1; then
    echo "  [CONFLICTO UID] ${uid} ya esta en uso en este servidor. '${USER}' requiere revision manual (UID distinto)."
    return
  fi

  echo "  [CREAR] ${USER}  uid=${uid} home=${home} shell=${shell} grupos=${grupos_csv}"

  if [ "${APPLY}" == "--apply" ]; then
    useradd -u "${uid}" -g "${gid}" -d "${home}" -m -s "${shell}" "${USER}"
    usermod -p "${hash}" "${USER}"
    [ -n "${grupos_csv}" ] && usermod -G "${grupos_csv}" "${USER}"
    echo "    -> creado y clave/grupos aplicados"
  fi
}

while IFS= read -r LINEA; do
  case "${LINEA}" in
    "### USUARIO: "*) aplicar_usuario; USER="${LINEA#### USUARIO: }"; PASSWD_LINE=""; SHADOW_LINE=""; GRUPOS="" ;;
    "PASSWD: "*) PASSWD_LINE="${LINEA#PASSWD: }" ;;
    "SHADOW: "*) SHADOW_LINE="${LINEA#SHADOW: }" ;;
    "GRUPOS: "*) GRUPOS="${LINEA#GRUPOS: }" ;;
  esac
done < "${PAQUETE}"
aplicar_usuario

echo ""
echo "== GRANT de base de datos faltantes =="

if [ -z "${GRANTS_DIR}" ] || [ ! -d "${GRANTS_DIR}" ]; then
  echo "  (no se indico carpeta de grants_bd_faltantes, se omite este paso)"
else
  for SQLFILE in "${GRANTS_DIR}"/*.sql; do
    [ -s "${SQLFILE}" ] || continue
    DB=$(basename "${SQLFILE}" .sql)
    echo "  [${DB}] $(wc -l < "${SQLFILE}") grant(s) pendientes"
    if [ "${APPLY}" == "--apply" ]; then
      dbaccess "${DB}" "${SQLFILE}" || echo "    (aviso: alguna sentencia fallo, revisar)"
    fi
  done
fi

echo ""
if [ "${APPLY}" != "--apply" ]; then
  echo "Esto fue un DRY-RUN, no se modifico nada."
  echo "Para aplicar de verdad: $0 ${PAQUETE} ${GRANTS_DIR} --apply"
fi
