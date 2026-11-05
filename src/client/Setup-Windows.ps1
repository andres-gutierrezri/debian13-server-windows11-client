<#
.SYNOPSIS
    Configura Windows 11 como cliente del servidor Debian 13 (SSH + SMB).
.DESCRIPTION
    1) Verifica/instala el cliente OpenSSH. 2) Genera llave ed25519.
    3) Registra el host en el archivo hosts y en ~/.ssh/config.
    4) Instala la llave pública en el servidor. 5) Monta la unidad SMB.
.EXAMPLE
    PowerShell (como Administrador):
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
    .\Setup-Windows.ps1 -ServerIp 192.168.56.10 -User sysadmin
.NOTES
    Autor: Ingeniero Andrés Felipe Gutiérrez Rivera
#>
[CmdletBinding()]
param(
    [string]$ServerIp   = '192.168.56.10',
    [string]$ServerName = 'srv-debian13',
    [string]$Domain     = 'lab.local',
    [string]$User       = 'sysadmin',
    [string]$ShareName  = 'compartido',
    [ValidatePattern('^[A-Z]$')][string]$DriveLetter = 'Z'
)
$ErrorActionPreference = 'Stop'

function Escribir-Info($m) { Write-Host "[INFO]  $m" -ForegroundColor Cyan }
function Escribir-Aviso($m) { Write-Host "[AVISO] $m" -ForegroundColor Yellow }

# --- 1. Cliente OpenSSH ------------------------------------------------------
Escribir-Info '1/5 Verificando cliente OpenSSH'
if (-not (Get-Command ssh.exe -ErrorAction SilentlyContinue)) {
    $esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrator')
    if (-not $esAdmin) { throw 'Ejecute PowerShell como Administrador para instalar OpenSSH.Client.' }
    Add-WindowsCapability -Online -Name 'OpenSSH.Client~~~~0.0.1.0' | Out-Null
}
ssh -V

# --- 2. Llave ed25519 --------------------------------------------------------
Escribir-Info '2/5 Verificando llave SSH ed25519'
$dirSsh = Join-Path $env:USERPROFILE '.ssh'
$llave  = Join-Path $dirSsh 'id_ed25519'
if (-not (Test-Path $dirSsh)) { New-Item -ItemType Directory -Path $dirSsh | Out-Null }
if (-not (Test-Path $llave)) {
    ssh-keygen -t ed25519 -a 100 -f $llave -C "$env:USERNAME@$env:COMPUTERNAME"
}

# --- 3. hosts y ~/.ssh/config -----------------------------------------------
Escribir-Info '3/5 Registrando nombre del servidor'
$fqdn      = "$ServerName.$Domain"
$hostsFile = "$env:SystemRoot\System32\drivers\etc\hosts"
try {
    if (-not (Select-String -Path $hostsFile -Pattern ([regex]::Escape($fqdn)) -Quiet)) {
        Add-Content -Path $hostsFile -Value "$ServerIp`t$fqdn`t$ServerName"
    }
} catch { Escribir-Aviso 'No se pudo editar hosts (se requieren privilegios de Administrador).' }

$cfg = Join-Path $dirSsh 'config'
if (-not (Test-Path $cfg) -or -not (Select-String -Path $cfg -Pattern "Host $ServerName" -Quiet)) {
    Add-Content -Path $cfg -Value @"

Host $ServerName
    HostName $ServerIp
    User $User
    IdentityFile ~/.ssh/id_ed25519
    ServerAliveInterval 60
"@
}

# --- 4. Instalar llave pública en el servidor -------------------------------
Escribir-Info '4/5 Instalando la llave pública (solicitará la contraseña de Linux)'
Get-Content "$llave.pub" |
    ssh -o StrictHostKeyChecking=accept-new "$User@$ServerIp" `
        'umask 077; mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && sort -u -o ~/.ssh/authorized_keys ~/.ssh/authorized_keys'

# --- 5. Unidad SMB -----------------------------------------------------------
Escribir-Info "5/5 Montando \\$ServerIp\$ShareName en ${DriveLetter}:"
$cred = Get-Credential -UserName $User -Message 'Contraseña SMB (smbpasswd) del servidor'
$null = New-SmbMapping -LocalPath "${DriveLetter}:" -RemotePath "\\$ServerIp\$ShareName" `
        -UserName $User -Password $cred.GetNetworkCredential().Password -Persistent $true
Get-SmbMapping | Where-Object LocalPath -eq "${DriveLetter}:"

Escribir-Info 'Cliente configurado. Verifique con: .\tests\Test-Client.ps1'
