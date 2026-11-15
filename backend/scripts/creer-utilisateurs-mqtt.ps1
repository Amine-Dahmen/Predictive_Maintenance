# Script PowerShell pour créer / réinitialiser les comptes MQTT sous Windows (sans Docker)
# Usage : powershell -ExecutionPolicy Bypass -File scripts/creer-utilisateurs-mqtt.ps1

$ErrorActionPreference = "Stop"

# Trouver l'exécutable mosquitto_passwd
$mosquittoPasswd = "C:\Program Files\Mosquitto\mosquitto_passwd.exe"
if (-not (Test-Path $mosquittoPasswd)) {
    $cmd = Get-Command mosquitto_passwd -ErrorAction SilentlyContinue
    if ($cmd) {
        $mosquittoPasswd = $cmd.Source
    } else {
        Write-Error "Impossible de trouver mosquitto_passwd.exe. Vérifiez que Mosquitto est bien installé dans 'C:\Program Files\Mosquitto'."
    }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$configDir = Join-Path $scriptDir "..\mosquitto\config"
$passwdFile = Join-Path $configDir "passwd"

Write-Host "Création / mise à jour du fichier de mots de passe : $passwdFile"

# 1. Compte du Backend
$backendPwd = if ($env:BACKEND_PWD) { $env:BACKEND_PWD } else { "backend_mqtt_pwd" }
& $mosquittoPasswd -c -b $passwdFile "backend" $backendPwd
Write-Host " -> Utilisateur créé : backend"

# 2. Compte de la machine de test M01
& $mosquittoPasswd -b $passwdFile "M01" "esp32_M01_pwd"
Write-Host " -> Utilisateur créé : M01"

# Ajoutez ici d'autres machines si besoin :
# & $mosquittoPasswd -b $passwdFile "M02" "esp32_M02_pwd"

Write-Host "`nTerminé avec succès !" -ForegroundColor Green
Write-Host "Pour lancer Mosquitto :"
Write-Host "  npm run mqtt"
