<#
.SYNOPSIS  Pruebas de conectividad del cliente Windows 11 hacia Debian 13.
.EXAMPLE   .\tests\Test-Client.ps1 -ServerIp 192.168.56.10 -User sysadmin
#>
param(
    [string]$ServerIp = '192.168.56.10',
    [string]$User     = 'sysadmin',
    [string]$DriveLetter = 'Z'
)
$fallos = 0
function Resultado($ok, $msg) {
    if ($ok) { Write-Host "[OK]    $msg" -ForegroundColor Green }
    else { Write-Host "[FALLO] $msg" -ForegroundColor Red; $script:fallos++ }
}

Resultado (Test-Connection -ComputerName $ServerIp -Count 2 -Quiet) 'ICMP hacia el servidor'
foreach ($p in 22, 445) {
    $r = Test-NetConnection -ComputerName $ServerIp -Port $p -WarningAction SilentlyContinue
    Resultado $r.TcpTestSucceeded "TCP $p alcanzable"
}
$out = ssh -o BatchMode=yes -o ConnectTimeout=5 "$User@$ServerIp" 'echo conexion-ok' 2>$null
Resultado ($out -eq 'conexion-ok') 'Autenticación SSH por llave (BatchMode)'
Resultado (Test-Path "${DriveLetter}:\") "Unidad SMB ${DriveLetter}: accesible"

if ($fallos -eq 0) { 'Todas las pruebas superadas.' } else { "Pruebas fallidas: $fallos"; exit 1 }
