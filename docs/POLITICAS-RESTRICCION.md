# Políticas de restricción: Debian 13 (servidor) → Windows 11 (cliente)

Autor: Ingeniero Andrés Felipe Gutiérrez Rivera. Uso previsto: equipos que usted administra (aulas, laboratorios, equipos familiares) y con conocimiento de sus usuarios.

## 1. Arquitectura

```
Debian 13                                              Windows 11 (Administrador)
─────────────────────                                  ───────────────────────────────
policyctl.sh  ──►  /srv/policies/windows11/policy.conf
                         ▲                              Apply-Policy.ps1
                         └──── ssh "cat policy.conf" ◄──  1) descarga policy.conf
                         ┌──── ssh "sudo -S -k -v"   ◄──  2) pide la contraseña del servidor
                         │       (valida contraseña)      3) si es válida → escribe el registro
                         └──── ssh "logger -t winpolicy"◄ 4) deja rastro en el journal de Debian
```

- **Definición** (servidor): `policy.conf` con pares `POLITICA=on|off`, editado solo con `sudo policyctl.sh`.
- **Aplicación** (cliente): `Apply-Policy.ps1` traduce cada política a claves de registro.
- **Control de cambios:** `Apply` y `Remove` exigen la **contraseña del usuario Debian**; se valida con `sudo -S -k -v` en el servidor. La contraseña no se escribe en disco ni en el registro de auditoría, y se admiten 3 intentos.
- **Consulta:** `Status` es de solo lectura y no pide contraseña.
- **Auditoría:** `C:\ProgramData\LabPolicy\audit.log` (cliente) y `journalctl -t winpolicy` (servidor).

## 2. Catálogo de políticas

| Política | Efecto | Claves de registro |
|---|---|---|
| `BLOCK_INSTALL` | Impide instalar programas MSI y quita Microsoft Store | `HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer`: `DisableMSI=2`, `DisableUserInstalls=1`; `HKLM\SOFTWARE\Policies\Microsoft\WindowsStore`: `RemoveWindowsStore=1` |
| `BLOCK_CMD` | Bloquea `cmd.exe` (y archivos por lotes) | `HKCU\Software\Policies\Microsoft\Windows\System`: `DisableCMD=1` |
| `BLOCK_POWERSHELL` | Bloquea `powershell.exe`, `powershell_ise.exe`, `pwsh.exe`, `wt.exe` | `HKCU\...\Policies\Explorer`: `DisallowRun=1` + subclave `DisallowRun` |
| `BLOCK_CONTROL_PANEL` | Bloquea Panel de control y Configuración | `HKCU\...\Policies\Explorer`: `NoControlPanel=1` |
| `BLOCK_REGISTRY_TOOLS` | Bloquea `regedit` y herramientas del registro | `HKCU\...\Policies\System`: `DisableRegistryTools=1` |

`HKCU` se refiere al **hive del usuario objetivo** (el script carga `NTUSER.DAT` si el usuario no tiene sesión abierta).

## 3. Uso

### 3.1 Servidor Debian

```bash
sudo ./src/server/policyctl.sh init               # crea policy.conf (todo en off)
./src/server/policyctl.sh list                    # catálogo
sudo ./src/server/policyctl.sh enable BLOCK_CMD
sudo ./src/server/policyctl.sh enable BLOCK_POWERSHELL
sudo ./src/server/policyctl.sh preset aula        # activa las 5 políticas
sudo ./src/server/policyctl.sh disable BLOCK_CONTROL_PANEL
./src/server/policyctl.sh show                    # estado + SHA-256
journalctl -t winpolicy --since today             # auditoría
```

### 3.2 Cliente Windows 11

Cree antes una cuenta **estándar** para el usuario a restringir y ábrala una vez para generar su perfil. Ejecute PowerShell **como Administrador** con su cuenta administradora (que no se restringe):

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
New-LocalUser -Name estudiante -NoPassword -FullName "Usuario de aula"     # si aún no existe
.\src\client\Apply-Policy.ps1 -Action Status -TargetUser estudiante
.\src\client\Apply-Policy.ps1 -Action Apply  -TargetUser estudiante         # pide contraseña de Debian
.\src\client\Apply-Policy.ps1 -Action Remove -TargetUser estudiante         # pide contraseña de Debian
```

Parámetros útiles: `-ServerIp`, `-ServerUser`, `-PolicyPath`, `-MaxAttempts`. Cierre y abra sesión con la cuenta objetivo para que las políticas de usuario surtan efecto.

### 3.3 Pruebas

```bash
./tests/test-policyctl.sh          # Debian: lógica de policy.conf en un directorio temporal
```

En Windows verifique con `Apply-Policy.ps1 -Action Status` y, desde la cuenta restringida, intente abrir `cmd`, PowerShell, el Panel de control y `regedit` (deben mostrar un aviso de restricción).

## 4. Requisitos y prerrequisitos de seguridad

1. Llave SSH del administrador de Windows instalada en el servidor (sección 6.2 del README); el script usa `BatchMode`.
2. El usuario Debian (`ServerUser`) debe pertenecer a `sudo`: la validación usa `sudo -S -k -v`.
3. `policy.conf` es legible por el cliente (644) pero solo modificable con `sudo`.
4. Cuenta de trabajo del usuario final: **estándar**, nunca administradora. El script rechaza cuentas del grupo Administradores.

## 5. Alcance real y limitaciones (léase antes de desplegar)

- **No es una barrera frente a un administrador local.** Quien tenga privilegios de Administrador en Windows puede editar el registro o desinstalar el script directamente; la contraseña de Debian protege el *procedimiento*, no el registro de la máquina. Para aplicación obligatoria use cuentas estándar y, a escala, Active Directory/Directiva de grupo o Intune (control centralizado y no editable por el usuario).
- **`DisableMSI` solo cubre instaladores MSI.** Instaladores `.exe` y programas portables no se bloquean con esta política [14]. Para control real de ejecución use Software Restriction Policies, AppLocker o App Control for Business [16], [17].
- **`DisallowRun` aplica a programas lanzados desde el Explorador.** Un usuario con otros medios de ejecución podría eludirlo; combínelo con las otras políticas y con AppLocker.
- **Claves HKCU de política** pueden ser modificadas por el propio usuario si dispone de una herramienta de edición; por eso se bloquean `regedit`, CMD y PowerShell conjuntamente.
- **`BLOCK_INSTALL` es de ámbito máquina:** también impide instalaciones MSI hechas por administradores hasta que se ejecute `Remove` o se desactive y se reaplique.
- **Ediciones de Windows:** el comportamiento de algunas políticas (p. ej. `RemoveWindowsStore`) depende de la edición; se recomienda Pro, Enterprise o Education. Pruebe siempre en una máquina de laboratorio.
- **Ejecución de PowerShell por política de máquina:** no se usa `ExecutionPolicy` de directiva de grupo a propósito, porque prevalecería sobre `-ExecutionPolicy Bypass` y bloquearía sus propios scripts de administración.

## 6. Recuperación (si se bloqueó una cuenta)

```powershell
# Desde la cuenta Administrador:
.\src\client\Apply-Policy.ps1 -Action Remove -TargetUser estudiante
```

Si el servidor no está disponible, inicie sesión como Administrador y elimine manualmente los valores de la tabla de la sección 2 (con `reg delete` o `Remove-ItemProperty`) sobre el hive del usuario (`reg load HKU\tmp C:\Users\estudiante\NTUSER.DAT`).

## 7. Referencias

[14] Microsoft, "DisableMSI," Windows Installer. [En línea]. Disponible: https://learn.microsoft.com/en-us/windows/win32/msi/disablemsi
[15] Microsoft, "reg load," Windows commands. [En línea]. Disponible: https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/reg-load
[16] Microsoft, "Software Restriction Policies." [En línea]. Disponible: https://learn.microsoft.com/en-us/windows-server/identity/software-restriction-policies/software-restriction-policies
[17] Microsoft, "AppLocker overview." [En línea]. Disponible: https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/applocker/applocker-overview
[18] Todd C. Miller, "sudo(8) manual (opciones -S, -k, -v)." [En línea]. Disponible: https://www.sudo.ws/docs/man/sudo.man/

> Las URL se citan de memoria como documentación pública habitual; verifique su vigencia.
