# Wind Tree Sway (Build 42.19)

Mod Project Zomboid qui fait osciller légèrement les arbres proches du joueur,
à une vitesse/amplitude proportionnelle au vent en jeu.

## Structure du mod (important, Build 42)

Depuis le Build 42, PZ exige un sous-dossier versionné contenant `mod.info`
**et** le `media/` du mod, plus un dossier `common/` (qui peut être vide,
mais doit exister), sinon le mod n'apparaît pas du tout dans la liste en
jeu. La structure est donc :

```
WindTreeSway/
├── 42/
│   ├── mod.info
│   ├── poster.png
│   └── media/
│       └── lua/
│           └── client/
│               └── WindTreeSway_client.lua
└── common/          (vide, doit juste exister)
```

Ne remets pas tout à plat dans `WindTreeSway/` directement : le `mod.info`
et le `media/` doivent être dans `WindTreeSway/42/`, pas à la racine.
Note : cette convention n'est pas encore stabilisée/documentée
officiellement pour le Build 42 (retours contradictoires selon les
versions 42.x) — si ça ne marche toujours pas après ce changement, voir
la section "Si le mod n'apparaît toujours pas" plus bas.

## Installation (test local)

1. Copie le dossier `WindTreeSway/` (avec sa structure `42/` + `common/`
   intacte) dans ton dossier de mods PZ :
   - Windows : `%USERPROFILE%\Zomboid\mods\WindTreeSway`
   - Linux/Steam Deck : `~/Zomboid/mods/WindTreeSway`
2. Lance le jeu, active le mod dans le menu Mods de l'écran d'accueil.
3. Charge une partie (idéalement en extérieur, près d'arbres).
4. Ouvre `~/Zomboid/console.txt` (ou la console debug en jeu) et cherche les
   lignes commençant par `[WindTreeSway]`.

## Si le mod n'apparaît toujours pas

Le système de mods du Build 42 a eu plusieurs bugs connus selon la version
exacte (42.7, 42.12, 42.13...). Pistes à essayer dans l'ordre :

1. Vérifie qu'il n'y a pas de double dossier (ex. `mods\WindTreeSway\WindTreeSway\42\...`)
   suite à une copie/décompression.
2. Dans `~/Zomboid/mods/`, supprime un éventuel fichier `reset-mods_*` (ou
   similaire) puis relance le jeu — ça force le jeu à rescanner les mods.
3. Vérifie la console de lancement / les logs (`~/Zomboid/console.txt`) juste
   après le lancement du jeu pour une erreur de parsing sur `mod.info`.
4. Si rien ne marche, dis-le moi avec le contenu exact de
   `~/Zomboid/console.txt` après un lancement — ça contient normalement une
   erreur explicite sur le mod qui ne charge pas.

## Ce qui est fiable vs expérimental

- **Lecture du vent** : robuste. Le script essaie plusieurs noms de méthode
  connus sur `ClimateManager` (`getWindSpeed`, `getWindIntensity`,
  `getWindStrength`, `getWind`) et log celle qui fonctionne. Si aucune
  n'existe dans le build 42.19, il utilise un vent "procédural" de secours
  (rafales douces générées mathématiquement) pour que le reste du mod reste
  utilisable.

- **Oscillation visuelle des arbres** : expérimentale. Project Zomboid met en
  cache/rend le monde isométrique par blocs pour la performance, et il n'y a
  pas de documentation publique confirmant une méthode Lua permettant de
  décaler visuellement, image par image, un objet déjà posé sur la carte. Le
  script teste automatiquement 4 méthodes candidates sur le premier arbre
  trouvé et log clairement laquelle fonctionne (s'il y en a une).

## Si l'effet visuel ne se voit pas en jeu

C'est possible et anticipé. Dans `console.txt`, cherche une ligne du type :

```
[WindTreeSway] Aucune methode de decalage visuel disponible sur cette version du jeu.
```

Envoie-moi ces lignes de log (et si possible les 20-30 lignes autour), et je
corrigerai le point de rendu avec la vraie API au lieu de deviner. C'est
beaucoup plus rapide de corriger à partir d'une erreur réelle du jeu que de
deviner à l'aveugle depuis ici, où je n'ai pas d'installation de Project
Zomboid pour tester.

## Réglages

Tout se trouve en haut de
`42/media/lua/client/WindTreeSway_client.lua` :

- `UPDATE_RADIUS` : rayon (en tuiles) autour du joueur où les arbres sont
  animés.
- `BASE_FREQ_HZ` / `MAX_FREQ_HZ` : vitesse d'oscillation par vent faible/fort.
- `BASE_AMPLITUDE` / `MAX_AMPLITUDE` : amplitude (pixels) par vent faible/fort.
- `WindTreeSway.debug` : passe à `false` pour couper les logs une fois que
  tout fonctionne.
