# Synchronise WindTreeSway vers le dossier de staging Steam Workshop de PZ
# (Contents/mods/WindTreeSway sous l'installation du jeu), pour publier/mettre
# a jour l'item via le bouton Workshop du menu Mods en jeu.
#
# Contrairement a dev-reload.ps1 (qui copie tout, y compris les fichiers de
# dev, vers ~/Zomboid/mods pour le hot reload), ce script exclut les
# fichiers de dev qui n'ont rien a faire dans le mod publie : dev-reload.ps1,
# publish-workshop.ps1, README.md et les fichiers de hot reload
# (reload.trigger/reload.filelist).
#
# Usage : lance ce script apres chaque changement a publier, puis utilise le
# bouton Workshop en jeu (Mods > Workshop) pour envoyer la mise a jour --
# ce script ne touche jamais workshop.txt ni preview.png (a la racine du
# dossier Workshop/WindTreeSway, geres separement).

$ErrorActionPreference = "Stop"

$src = $PSScriptRoot
$gameDir = "C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid"
$dest = Join-Path $gameDir "Workshop\WindTreeSway\Contents\mods\WindTreeSway"

robocopy $src $dest /MIR `
    /XF "dev-reload.ps1" "publish-workshop.ps1" "README.md" "reload.trigger" "reload.filelist" `
    /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) {
    Write-Error "robocopy a echoue (code $LASTEXITCODE)"
    exit 1
}

# L'uploader Steam Workshop de PZ (SteamWorkshopItem.validateContents(), voir
# le message "UI_WorkshopError_MissingModDotInfo") exige mod.info (et son
# poster) A LA RACINE du dossier du mod dans Contents/mods/ -- contrairement
# au jeu, il ne va pas le chercher dans le sous-dossier versionne 42/. Confirme
# en comparant avec un vrai mod Build 42 deja publie sur le Workshop
# (DisableWelcomeMessage, present dans steamapps/workshop/content/108600/) :
# il duplique mod.info/poster a la racine ET dans 42/. Cette copie est
# PUREMENT pour satisfaire l'uploader -- le jeu continue a utiliser
# 42/mod.info comme version reelle en jeu.
Copy-Item (Join-Path $dest "42\mod.info") (Join-Path $dest "mod.info") -Force
Copy-Item (Join-Path $dest "42\poster.png") (Join-Path $dest "poster.png") -Force

Write-Output "OK - $dest synchronise (+ mod.info/poster.png dupliques a la racine pour l'uploader Workshop)."
