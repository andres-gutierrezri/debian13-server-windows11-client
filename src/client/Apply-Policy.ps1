<#
.SYNOPSIS
    Aplica, retira o consulta las políticas de restricción definidas en el servidor Debian 13.
.DESCRIPTION
    Descarga policy.conf del servidor por SSH y traduce cada política a claves de registro de Windows 11.
    Apply y Remove EXIGEN la contraseña del usuario del servidor Debian: se valida ejecutando
    "sudo -S -k -v" en el servidor; la contraseña no se guarda ni se escribe en disco.
    Debe ejecutarse desde una cuenta de Administrador; la cuenta objetivo debe ser un usuario estándar.
.PARAMETER Action
    Apply  = aplica policy.conf (activa las "on" y retira las "off").
    Remove = retira todas las restricciones.
    Status = muestra el estado local (no requiere contraseña).
.EXAMPLE
    .\Apply-Policy.ps1 -Action Apply  -TargetUser estudiante
    .\Apply-Policy.ps1 -Action Remove -TargetUser estudiante
    .\Apply-Policy.ps1 -Action Status -TargetUser estudiante
.NOTES
    Autor: Ingeniero Andrés Felipe Gutiérrez Rivera
    Usar solo en equipos que usted administra y con conocimiento de sus usuarios.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Apply', 'Remove', 'Status')][string]$Action,
    [Parameter(Mandatory)][ValidatePattern('^[\w.\-]+$')][string]$TargetUser,
    [string]$ServerIp   = '192.168.56.10',
    [string]$ServerUser = 'sysadmin',
    [string]$PolicyPath = '/srv/policies/windows11/policy.conf',
    [ValidateRange(1, 5)][int]$MaxAttempts = 3
)
$ErrorActionPreference = 'Stop'
$DirAuditoria = Join-Path $env:ProgramData 'LabPolicy'
$Auditoria    = Join-Path $DirAuditoria 'audit.log'
$ExePS        = 'powershell.exe', 'powershell_ise.exe', 'pwsh.exe', 'wt.exe'

function Info($m)  { Write-Host "[INFO]  $m" -ForegroundColor Cyan }
function Aviso($m) { Write-Host "[AVISO] $m" -ForegroundColor Yellow }

$esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrator')
if (-not $esAdmin) { throw 'Ejecute PowerShell como Administrador.' }

# ------------------------------------------------------------------ Servidor --
function Get-ServerPolicy {
    $ErrorActionPreference = 'Continue'
    $raw = ssh -o BatchMode=yes -o ConnectTimeout=8 "$ServerUser@$ServerIp" "cat $PolicyPath" 2>$null
    if ($LASTEXITCODE -ne 0) { throw "No se pudo leer $PolicyPath en el servidor (¿llave SSH instalada?)." }
    $p = @{}
    foreach ($l in $raw) { if ($l -match '^\s*([A-Z_]+)\s*=\s*(on|off)\s*$') { $p[$Matches[1]] = ($Matches[2] -eq 'on') } }
    return $p
}

function Confirm-ServerPassword {
    $ErrorActionPreference = 'Continue'
    for ($i = 1; $i -le $MaxAttempts; $i++) {
        $sec  = Read-Host "Contraseña de '$ServerUser' en el servidor Debian (intento $i/$MaxAttempts)" -AsSecureString
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
        try {
            $plano = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            $plano | ssh -o BatchMode=yes -o ConnectTimeout=8 "$ServerUser@$ServerIp" "sudo -S -k -v -p ''" 2>$null | Out-Null
            $codigo = $LASTEXITCODE
        } finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            $plano = $null
        }
        if ($codigo -eq 0)   { return $true }
        if ($codigo -eq 255) { throw 'No hay conexión SSH con el servidor.' }
        Aviso 'Contraseña incorrecta.'
    }
    return $false
}

function Write-Audit($msg) {
    if (-not (Test-Path $DirAuditoria)) { New-Item -ItemType Directory -Path $DirAuditoria | Out-Null }
    Add-Content -Path $Auditoria -Value ("{0:s} {1} {2}" -f (Get-Date), $env:USERNAME, $msg)
    $ErrorActionPreference = 'Continue'
    ssh -o BatchMode=yes "$ServerUser@$ServerIp" "logger -t winpolicy $Action-$TargetUser-$env:COMPUTERNAME" 2>$null | Out-Null
}

# ------------------------------------------------------------------ Registro --
function Set-Reg($ruta, $nombre, $valor) {
    if (-not (Test-Path $ruta)) { New-Item -Path $ruta -Force | Out-Null }
    New-ItemProperty -Path $ruta -Name $nombre -PropertyType DWord -Value $valor -Force | Out-Null
}
function Remove-Reg($ruta, $nombre) {
    if (Test-Path $ruta) { Remove-ItemProperty -Path $ruta -Name $nombre -ErrorAction SilentlyContinue }
}
function Get-Reg($ruta, $nombre) {
    if (-not (Test-Path $ruta)) { return $null }
    (Get-ItemProperty -Path $ruta -Name $nombre -ErrorAction SilentlyContinue).$nombre
}

# Cada política: ámbito (M=máquina, U=usuario) y acciones de activación/retirada/consulta.
function Set-PolicyState([string]$nombre, [bool]$activar, [string]$raizUsuario) {
    $explorer = "$raizUsuario\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"
    switch ($nombre) {
        'BLOCK_INSTALL' {
            $inst = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer'
            $tienda = 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore'
            if ($activar) {
                Set-Reg $inst 'DisableMSI' 2
                Set-Reg $inst 'DisableUserInstalls' 1
                Set-Reg $tienda 'RemoveWindowsStore' 1
            } else {
                Remove-Reg $inst 'DisableMSI'; Remove-Reg $inst 'DisableUserInstalls'; Remove-Reg $tienda 'RemoveWindowsStore'
            }
        }
        'BLOCK_CMD' {
            $r = "$raizUsuario\Software\Policies\Microsoft\Windows\System"
            if ($activar) { Set-Reg $r 'DisableCMD' 1 } else { Remove-Reg $r 'DisableCMD' }
        }
        'BLOCK_POWERSHELL' {
            $sub = "$explorer\DisallowRun"
            if ($activar) {
                Set-Reg $explorer 'DisallowRun' 1
                if (-not (Test-Path $sub)) { New-Item -Path $sub -Force | Out-Null }
                for ($i = 0; $i -lt $ExePS.Count; $i++) {
                    New-ItemProperty -Path $sub -Name ([string]($i + 1)) -PropertyType String -Value $ExePS[$i] -Force | Out-Null
                }
            } else {
                Remove-Reg $explorer 'DisallowRun'
                if (Test-Path $sub) { Remove-Item -Path $sub -Recurse -Force }
            }
        }
        'BLOCK_CONTROL_PANEL' {
            if ($activar) { Set-Reg $explorer 'NoControlPanel' 1 } else { Remove-Reg $explorer 'NoControlPanel' }
        }
        'BLOCK_REGISTRY_TOOLS' {
            $r = "$raizUsuario\Software\Microsoft\Windows\CurrentVersion\Policies\System"
            if ($activar) { Set-Reg $r 'DisableRegistryTools' 1 } else { Remove-Reg $r 'DisableRegistryTools' }
        }
    }
}

function Get-PolicyState([string]$nombre, [string]$raizUsuario) {
    $explorer = "$raizUsuario\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"
    switch ($nombre) {
        'BLOCK_INSTALL'        { return ((Get-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer' 'DisableMSI') -eq 2) }
        'BLOCK_CMD'            { return ((Get-Reg "$raizUsuario\Software\Policies\Microsoft\Windows\System" 'DisableCMD') -eq 1) }
        'BLOCK_POWERSHELL'     { return ((Get-Reg $explorer 'DisallowRun') -eq 1) }
        'BLOCK_CONTROL_PANEL'  { return ((Get-Reg $explorer 'NoControlPanel') -eq 1) }
        'BLOCK_REGISTRY_TOOLS' { return ((Get-Reg "$raizUsuario\Software\Microsoft\Windows\CurrentVersion\Policies\System" 'DisableRegistryTools') -eq 1) }
    }
}
$Nombres = 'BLOCK_INSTALL', 'BLOCK_CMD', 'BLOCK_POWERSHELL', 'BLOCK_CONTROL_PANEL', 'BLOCK_REGISTRY_TOOLS'

# ------------------------------------------------------------ Usuario objetivo --
$usuario = Get-LocalUser -Name $TargetUser -ErrorAction Stop
$sid = $usuario.SID.Value
if ((Get-LocalGroupMember -Group 'Administrators').SID.Value -contains $sid) {
    throw "'$TargetUser' es Administrador. Las restricciones solo se aplican a usuarios estándar."
}

$montaje = $null
$raiz = "Registry::HKEY_USERS\$sid"
try {
    if (-not (Test-Path $raiz)) {                                   # perfil no cargado: se monta NTUSER.DAT
        $perfil = Get-CimInstance Win32_UserProfile | Where-Object SID -eq $sid
        if (-not $perfil) { throw "'$TargetUser' no tiene perfil; inicie sesión una vez con esa cuenta." }
        $montaje = "LabPolicy_$($sid -replace '-', '_')"
        reg load "HKU\$montaje" "$($perfil.LocalPath)\NTUSER.DAT" | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'No se pudo cargar NTUSER.DAT (¿sesión abierta con otro proceso?).' }
        $raiz = "Registry::HKEY_USERS\$montaje"
    }

    if ($Action -eq 'Status') {
        Info "Estado local para '$TargetUser' en $env:COMPUTERNAME"
        $Nombres | ForEach-Object { [pscustomobject]@{ Politica = $_; Activa = (Get-PolicyState $_ $raiz) } } | Format-Table -AutoSize
        return
    }

    $politica = if ($Action -eq 'Apply') { Get-ServerPolicy } else { @{} }
    if (-not (Confirm-ServerPassword)) { Write-Audit "DENEGADO $Action $TargetUser"; throw 'Autenticación fallida: no se realizaron cambios.' }

    foreach ($n in $Nombres) {
        $activar = ($Action -eq 'Apply') -and ($politica[$n] -eq $true)
        Set-PolicyState $n $activar $raiz
        Info ("{0,-22} -> {1}" -f $n, $(if ($activar) { 'ACTIVA' } else { 'retirada' }))
    }
    Write-Audit "OK $Action $TargetUser"
    Aviso "Las políticas de usuario se aplican al próximo inicio de sesión de '$TargetUser'; las de instalación son inmediatas."
}
finally {
    if ($montaje) {
        [gc]::Collect(); [gc]::WaitForPendingFinalizers()
        reg unload "HKU\$montaje" | Out-Null
    }
}
