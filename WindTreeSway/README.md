# Wind Tree Sway (Build 42.19)

Mod Project Zomboid qui fait osciller légèrement les arbres proches du joueur,
à une vitesse/amplitude proportionnelle au vent en jeu.

## Structure du mod (important, Build 42)

Depuis le Build 42, PZ exige un sous-dossier versionné pour le `mod.info`,
sinon le mod n'apparaît pas du tout dans la liste en jeu. La structure est
donc :

```
WindTreeSway/
├── 42/
│   └── mod.info
└── common/
    └── media/
        └── lua/
            └── client/
                └── WindTreeSway_client.lua
```

Ne remets pas tout à plat dans `WindTreeSway/` directement : le `mod.info`
doit être dans `WindTreeSway/42/mod.info`, pas à la racine.

## Installation (test local)

1. Copie le dossier `WindTreeSway/` (avec sa structure `42/` + `common/`
   intacte) dans ton dossier de mods PZ :
   - Windows : `%USERPROFILE%\Zomboid\mods\WindTreeSway`
   - Linux/Steam Deck : `~/Zomboid/mods/WindTreeSway`
2. Lance le jeu, active le mod dans le menu Mods de l'écran d'accueil.
3. Charge une partie (idéalement en extérieur, près d'arbres).
4. Ouvre `~/Zomboid/console.txt` (ou la console debug en jeu) et cherche les
   lignes commençant par `[WindTreeSway]`.

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
`common/media/lua/client/WindTreeSway_client.lua` :

- `UPDATE_RADIUS` : rayon (en tuiles) autour du joueur où les arbres sont
  animés.
- `BASE_FREQ_HZ` / `MAX_FREQ_HZ` : vitesse d'oscillation par vent faible/fort.
- `BASE_AMPLITUDE` / `MAX_AMPLITUDE` : amplitude (pixels) par vent faible/fort.
- `WindTreeSway.debug` : passe à `false` pour couper les logs une fois que
  tout fonctionne.
