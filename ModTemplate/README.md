# ModTemplate

Squelette de mod Project Zomboid (cible Build 42) pret a l'emploi : structure
de dossiers correcte, script Lua partage/client/serveur qui log au chargement
et ajoute une action testable en jeu, plus un objet personnalise d'exemple
(avec sa propre icone). Sert de point de depart pour un nouveau mod.

## Structure

```
ModTemplate/
├── common/
│   └── media/
│       ├── lua/
│       │   ├── shared/ModTemplate.lua          -> charge en 1er (client + serveur)
│       │   ├── client/ModTemplate_client.lua   -> charge en 2e (UI, menus contextuels)
│       │   └── server/ModTemplate_server.lua   -> charge seulement au demarrage d'une partie
│       ├── scripts/modtemplate_items.txt       -> definition de l'objet ExampleItem
│       └── textures/Item_ModTemplateExample.png -> icone de ExampleItem
└── 42/
    ├── mod.info
    ├── poster.png    (image d'apercu, a remplacer)
    └── icon.png      (icone du mod, a remplacer)
```

`common/` contient tout ce qui ne depend pas de la version du jeu (Lua,
scripts d'objets, textures...). Le dossier `42/` ne contient que ce qui est
specifique au Build 42 : `mod.info` et les images d'apercu. C'est cette
separation qu'exige le Build 42 pour que le mod apparaisse dans la liste en
jeu (voir le README de [WindTreeSway](../WindTreeSway/README.md) dans ce meme
repo pour le detail des soucis rencontres sur ce point).

## Pour en faire ton propre mod

1. Renomme le dossier `ModTemplate/` (et adapte le nom des fichiers `.lua` /
   `.txt` si tu veux, ce n'est pas obligatoire).
2. Dans `42/mod.info`, change au minimum `name` et **`id`** (l'id doit etre
   unique : ne publie jamais deux mods avec le meme id, meme dans des
   Workshop items differents).
3. Remplace `42/poster.png` et `42/icon.png` par tes propres images.
4. Remplace le namespace Lua `ModTemplate` (dans les 3 fichiers `.lua`) et le
   module `ModTemplate` (dans `modtemplate_items.txt`) par le nom de ton mod,
   et adapte `ExampleItem` / `Item_ModTemplateExample.png` a tes propres
   objets.

## Test en local

1. Copie (ou symlink) le dossier du mod tel quel dans ton dossier de mods PZ :
   - Windows : `%USERPROFILE%\Zomboid\mods\ModTemplate`
   - Linux/Steam Deck : `~/Zomboid/mods/ModTemplate`
2. Lance le jeu, active le mod dans le menu Mods de l'ecran d'accueil, charge
   une partie.
3. Ouvre `~/Zomboid/console.txt` (ou la console debug in-game) : tu dois voir
   `[ModTemplate] shared charge...`, `[ModTemplate] client charge...` puis
   `[ModTemplate] server charge...`.
4. Clic droit au sol -> l'option **"ModTemplate : dire bonjour"** doit
   apparaitre et faire parler le personnage.
5. Active le mode debug (`-debug` ou menu debug) et cherche **"Objet
   d'exemple"** dans le spawn d'objets pour verifier que le script d'item et
   son icone se chargent bien.

## Hot reload (dev)

Le mod embarque un opt-in pour [PZModReload](https://github.com/deckard93/PZModReload)
(MIT, par deckard93) : un mod-outil separe qui recharge le Lua a chaud en
jeu, sans relancer PZ.

1. Le mod watcher est installe en local (hors de ce repo, c'est un outil
   externe) dans `~/Zomboid/mods/ModHotReloadLocal`.
2. Dans le menu Mods, active **`[Dev] Hot Reload Mods (local)`** en plus de
   **`Mod Template`**, puis charge une partie.
3. Edite un `.lua` liste dans `common/media/reload.filelist` (shared/client
   uniquement — le serveur n'est pas rechargeable a chaud par ce mecanisme,
   il faut relancer pour ca), sauvegarde.
4. Lance `dev-reload.ps1` (dans ce dossier) : ca synchronise le mod vers
   `~/Zomboid/mods/ModTemplate` et met a jour `reload.trigger`. Le
   rechargement se fait en jeu dans la seconde qui suit (jeu non en pause),
   avec un message `[HotReload] ModTemplate: N file(s)` affiche et logge.
5. Pour ajouter un nouveau fichier au hot reload, liste-le dans
   `common/media/reload.filelist` (un chemin par ligne, `media/...`).

Limite : seul le Lua est recharge (pas les scripts d'objets, textures,
traductions) — pour ca, relance le jeu normalement.

## Sources

Structure et champs de `mod.info` bases sur la documentation PZwiki
(https://pzwiki.net/wiki/Modding, /wiki/Mod_structure, /wiki/Mod.info) et sur
le comportement observe/documente pour le Build 42 (dossier versionne +
`common/` obligatoire).
