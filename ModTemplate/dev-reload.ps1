# Synchronise ModTemplate vers ~/Zomboid/mods/ModTemplate puis declenche un
# hot reload en jeu (necessite le mod "[Dev] Hot Reload Mods (local)" actif
# a cote de Mod Template dans la partie en cours, jeu non en pause).
#
# Usage : edite tes .lua dans ce dossier repo, sauvegarde, puis lance ce
# script. Le rechargement se fait en jeu dans la seconde qui suit.

$ErrorActionPreference = "Stop"

$src = $PSScriptRoot
$dest = "$env:USERPROFILE\Zomboid\mods\ModTemplate"

robocopy $src $dest /MIR /XF "dev-reload.ps1" "README.md" /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) {
    Write-Error "robocopy a echoue (code $LASTEXITCODE)"
    exit 1
}

$triggerPath = Join-Path $dest "common\media\reload.trigger"
[System.DateTime]::UtcNow.Ticks | Set-Content -Path $triggerPath -NoNewline -Encoding ascii

Write-Output "OK - $dest synchronise, reload.trigger mis a jour."
exit 0
