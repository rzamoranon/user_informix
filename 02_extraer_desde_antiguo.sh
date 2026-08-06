#!/bin/bash
#
# 02_extraer_desde_antiguo.sh
#
# CORRE EN EL SERVIDOR ANTIGUO, COMO ROOT (necesita leer /etc/shadow).
#
# Toma el listado_usuarios_so.txt generado por 01_generar_listado.sh y arma
# un paquete con, para cada usuario:
#   - la linea exacta de /etc/passwd  (uid, gid, home, shell)
#   - el HASH de /etc/shadow           (nunca la clave en texto plano)
#   - sus grupos secundarios           (para no perder membresias como sudo/wheel)
#
# Uso:
#   ./02_extraer_desde_antiguo.sh listado_usuarios_so.txt
#
# IMPORTANTE:
#   El archivo de salida contiene HASHES de contrasena. Transferirlo al
#   servidor nuevo unicamente por un canal cifrado (scp/rsync sobre ssh).
#   Nunca por correo ni copiarlo a un repositorio.

set -euo pipefail

LISTADO="${1:?Indica el archivo listado_usuarios_so.txt}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Este script debe ejecutarse como root (necesita leer /etc/shadow)."
  exit 1
fi

STAMP=$(date +%Y%m%d_%H%M%S)
SALIDA="./paquete_extraccion_${STAMP}.txt"
: > "${SALIDA}"
chmod 600 "${SALIDA}"

TOTAL=0
ENCONTRADOS=0

while read -r USER; do
  [ -z "${USER}" ] && continue
  TOTAL=$((TOTAL+1))

  PASSWD_LINE=$(grep "^${USER}:" /etc/passwd || true)
  SHADOW_LINE=$(grep "^${USER}:" /etc/shadow || true)

  if [ -z "${PASSWD_LINE}" ]; then
    echo "  [AVISO] '${USER}' no existe en este servidor. Se omite." >&2
    continue
  fi

  # Grupos secundarios (sin el grupo primario)
  GRUPOS=$(id -Gn "${USER}" 2>/dev/null | tr ' ' ',' || echo "")

  {
    echo "### USUARIO: ${USER}"
    echo "PASSWD: ${PASSWD_LINE}"
    echo "SHADOW: ${SHADOW_LINE}"
    echo "GRUPOS: ${GRUPOS}"
    echo ""
  } >> "${SALIDA}"

  ENCONTRADOS=$((ENCONTRADOS+1))
done < "${LISTADO}"

echo ""
echo "Procesados: ${TOTAL}  |  Encontrados y extraidos: ${ENCONTRADOS}"
echo "Paquete generado: ${SALIDA}  (permisos 600, contiene hashes de clave)"
echo ""
echo "Siguiente paso: transferir este archivo al servidor NUEVO por scp/rsync"
echo "sobre SSH, y correr alli: 03_aplicar_en_nuevo.sh ${SALIDA} [grants_bd_faltantes/]"
