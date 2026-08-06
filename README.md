# informix-user-migration-toolkit

Scripts para auditar y trasladar usuarios entre servidores Informix durante un
upgrade/migración, cubriendo **ambas capas de autenticación**: las cuentas del
motor de base de datos y las cuentas de sistema operativo (Linux) de las que
Informix puede depender para autenticar.

## Por qué existe este proyecto

En una migración hecha con `dbexport`/`dbimport`, Informix traslada los datos,
el esquema y los permisos (`GRANT`) **dentro** de cada base de datos. Lo que
**no** traslada nunca es el sistema operativo: las cuentas Linux y sus
contraseñas viven en `/etc/passwd` y `/etc/shadow`, fuera del alcance del
motor.

Como Informix puede delegar la autenticación al sistema operativo, un usuario
sin cuenta Linux en el servidor nuevo (aunque tenga sus `GRANT` migrados)
simplemente no podrá conectarse. Este toolkit existe para detectar esa brecha
antes de que se convierta en un incidente en producción, y para trasladar lo
que falta de forma controlada.

## Qué NO hace este proyecto

- No reemplaza el `dbexport`/`dbimport` ni ningún mecanismo de migración de
  datos de Informix.
- No crea ni modifica cuentas sin confirmación explícita (todo corre en modo
  *dry-run* por defecto, ver más abajo).
- No transmite contraseñas en texto plano en ningún punto del proceso.

## Requisitos

- Acceso a `dbaccess` y `dbschema` con `INFORMIXDIR` / `INFORMIXSERVER` /
  `ONCONFIG` configurados en el entorno.
- Acceso `root` en los pasos que leen `/etc/shadow` o crean cuentas de
  sistema operativo (scripts 2 y 3).
- Bash 4+ en Linux/Unix.

## Scripts incluidos

| Script | Dónde se ejecuta | Qué hace |
|---|---|---|
| `informix_user_audit.sh` | En cada servidor (antiguo y nuevo, por separado) | Levanta cuentas de S.O. (`/etc/passwd`) y permisos de Informix (`sysusers` + `dbschema -g`) en una carpeta `audit_<tag>/` |
| `01_generar_listado.sh` | Donde tengas ambos `audit_*` | Compara antiguo vs nuevo y genera el listado de cuentas de S.O. faltantes y los `GRANT` de base de datos faltantes por base |
| `02_extraer_desde_antiguo.sh` | En el servidor **antiguo**, como root | Con el listado del paso anterior, extrae línea de `/etc/passwd`, hash de `/etc/shadow` y grupos secundarios de cada usuario faltante |
| `03_aplicar_en_nuevo.sh` | En el servidor **nuevo**, como root | Crea las cuentas faltantes con el mismo UID/home/shell/hash/grupos, y aplica los `GRANT` pendientes. Corre en *dry-run* salvo que se indique `--apply` |

## Flujo de uso

```bash
# 1. Auditoría en cada servidor
./informix_user_audit.sh legadoprod_antes       # en el servidor antiguo
./informix_user_audit.sh legadoprod14_despues   # en el servidor nuevo

# 2. Generar el listado de lo que falta
./01_generar_listado.sh audit_legadoprod_antes audit_legadoprod14_despues
#   -> paquete_XXXX/listado_usuarios_so.txt
#   -> paquete_XXXX/grants_bd_faltantes/*.sql

# 3. En el servidor ANTIGUO, como root
./02_extraer_desde_antiguo.sh listado_usuarios_so.txt
#   -> paquete_extraccion_XXXX.txt (permisos 600, contiene hashes)
#   Transferir SOLO por scp/rsync sobre SSH al servidor nuevo

# 4. En el servidor NUEVO, como root
./03_aplicar_en_nuevo.sh paquete_extraccion_XXXX.txt grants_bd_faltantes/
#   revisa la salida (dry-run)...
./03_aplicar_en_nuevo.sh paquete_extraccion_XXXX.txt grants_bd_faltantes/ --apply
#   ...y aplica de verdad
```

## Consideraciones importantes al correr en producción

- **`03_aplicar_en_nuevo.sh` no sobrescribe una cuenta que ya existe** en el
  servidor nuevo, para no romper algo que ya está funcionando. Solo avisa
  para revisión manual.
- **Conflictos de UID entre servidores** (el mismo número usado por otra
  cuenta en el nuevo) se marcan para revisión manual en vez de forzarse,
  porque reasignar un UID después de creados los archivos puede desordenar
  permisos existentes.
- **Borra `paquete_extraccion_XXXX.txt` del servidor nuevo una vez aplicado.**
  Contiene hashes de contraseña de varias cuentas y no debe quedar
  almacenado más tiempo del necesario.

## Seguridad y manejo de datos sensibles

Este repositorio contiene únicamente **código**, no datos. Pero al usarlo vas
a generar archivos que sí son sensibles y **nunca deben subirse a este (ni
ningún otro) repositorio**:

- `audit_*/` (contiene listados de cuentas del cliente)
- `paquete_*/` y `paquete_extraccion_*.txt` (contiene **hashes de
  contraseña**)
- cualquier `.sql` con datos reales de producción

Se incluye un [`.gitignore`](./.gitignore) que excluye estos patrones por
defecto. Aun así, revisa siempre `git status` antes de un `commit`/`push`.

El traslado del paquete de extracción (paso 3) debe hacerse **solo por scp o
rsync sobre SSH**, nunca por correo, chat, ni almacenado en el propio
repositorio.

## Licencia / uso interno

Uso interno de Indexar para proyectos de migración Informix. Ajustar la
lista `EXCLUDE_REGEX` de `informix_user_audit.sh` según las cuentas de
sistema propias de cada distribución/versión de Linux antes de usarlo en un
cliente nuevo.
