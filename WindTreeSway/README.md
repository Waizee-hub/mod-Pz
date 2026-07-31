# Wind Tree Sway (Build 42.20)

Mod Project Zomboid qui fait osciller legerement les arbres proches du
joueur meme par temps calme, en reutilisant le systeme natif de sway du jeu
(celui qui anime deja les arbres pendant les tempetes) plutot qu'un hack
maison.

## Comment ca marche (et pourquoi ca ne marchait pas avant)

Le jeu a deja un systeme de sway des arbres/buissons, entierement natif
(`zombie.iso.objects.ObjectRenderEffects`) : chaque arbre "moveWithWind"
partage un des 45 objets d'effet du pool (15 slots x 3 types de vegetation),
qui expose 4 coins (`x1..y4`) lus directement par le rendu -- les coins 1&2
sont le sommet de l'arbre (celui qui bouge), les coins 3&4 la base (fixe).
Ce pool est anime chaque tick par `ObjectRenderEffects.updateStatic()`, qui
lit une seule valeur : `ClimateManager.getWindTickFinal()`.

Ce mecanisme est desactive par un seuil interne : des que cette valeur de
vent (0..1) est sous ~0.08 a 0.3 selon le type de vegetation, le code natif
force ces coins a 0 -- d'ou l'absence totale de sway par temps calme, alors
que le systeme est pret et fonctionnel, juste inactif. Ce n'est **pas**
documente publiquement ; identifie en decompilant `projectzomboid.jar` (voir
plus bas).

**Tentative 1 (abandonnee) :** ecrire directement `x1/y1/x2/y2` sur l'objet
d'effet partage, chaque tick, avec notre propre oscillation. Teste en jeu :
ca plante systematiquement avec `java.lang.RuntimeException: attempted index
of non-table` (Kahlua refuse l'assignation `objet.champ = valeur` sur cette
classe Java -- la lecture des champs publics marche, pas l'ecriture).

**Tentative 2 (abandonnee) :** declencher l'effet natif `Vegetation_Rustle`
par arbre via `IsoObject:setRenderEffect(RenderEffectType.Vegetation_Rustle,
true)` (`IsoTree` s'en sert en interne pour son effet de coupe). Teste en
jeu : plante immediatement avec `attempted index: Vegetation_Rustle of
non-table: null`. Cause confirmee en decompilant
`zombie.iso.objects.RenderEffectType.class` : cette enum n'a **aucune**
annotation `@UsedFromLua` (verifie dans le constant-pool du bytecode) -- le
jeu ne l'expose donc pas du tout comme variable Lua, impossible d'obtenir une
instance de cet enum depuis un script cote mod.

**Approche actuelle :** au lieu de manipuler des `ObjectRenderEffects` par
arbre, on agit directement sur la valeur de vent AMBIANTE qui alimente tout
le systeme natif. `ClimateManager.getWindTickFinal()` est calculee chaque
tick a partir de `windIntensity.finalValue` (voir `updateWindTick()`), et
`windIntensity` est une instance de
`ClimateManager$ClimateFloat` -- une classe **bien annotee `@UsedFromLua`**
cette fois (confirme par decompilation), avec des methodes publiques
`setOverride(cible, interpolation)` / `setOverrideValue(bool)` /
`setEnableOverride(bool)`. C'est **exactement** le mecanisme que le jeu
utilise en interne pour l'option sandbox "Endless Weather"
(`ClimateManager.updateSandboxOverrides`) -- donc un detour officiel et deja
eprouve par le moteur, pas un hack.

Chaque seconde, le mod lit `windIntensity:getInternalValue()` (la valeur
reelle simulee par la meteo, independante de notre override) :
- si elle est sous le plancher regle par le slider (voir "Reglages" plus
  bas), on force `finalValue` vers ce plancher via `setOverride(plancher,
  1.0)` (interpolation=1.0 -> effet immediat, sans a-coup) ;
- des qu'elle depasse ce plancher (debut de tempete), on desactive
  l'override (`setEnableOverride(false)`) et `finalValue` revient
  instantanement a la vraie valeur meteo -- comportement des tempetes
  inchange, transition immediate.

Cette valeur etant globale (lue par tout le systeme de vent ambiant), plus
besoin de scanner/suivre les arbres pres du joueur : un seul point
d'ajustement, beaucoup plus simple et fiable que les deux tentatives
precedentes, et sans le delai d'extinction qui affectait l'approche par
arbre.

**Piege supplementaire (corrige) :** meme avec `windTickFinal` correctement
force au-dessus du seuil, rien ne bougeait -- cause trouvee en decompilant
`zombie.core.Core.class` : l'option graphique `doWindSpriteEffects` (menu
Options > Affichage > "Wind Sprite Effects") est **desactivee par defaut**
(`false`). Sans elle, `ObjectRenderEffects.update()` remet systematiquement
tous les offsets a 0, quel que soit le vent. Le mod force donc cette option a
`true` au demarrage via `getCore():setOptionDoWindSpriteEffects(true)`
(reverifie toutes les `CHECK_MS`), pour ne pas dependre d'une configuration
manuelle du joueur.

Autre point confirme par decompilation de `ObjectRenderEffects.update(float,
float)` : le pool partage utilise 3 "windType" avec des seuils differents
(0.08 / 0.15 / 0.3, comparaison stricte `<=`) sous lesquels le sway reste a
0 -- d'ou la valeur par defaut de 0.38, qui depasse les trois avec une marge
confortable (0.30 pile sur le seuil le plus haut aurait laisse un tiers du
feuillage immobile).

## Structure du mod (Build 42)

```
WindTreeSway/
├── 42/
│   ├── mod.info
│   ├── poster.png
│   └── media/
│       ├── reload.trigger      (dev, hot reload)
│       ├── reload.filelist     (dev, hot reload)
│       └── lua/
│           └── client/
│               └── WindTreeSway_client.lua
├── dev-reload.ps1              (dev, hot reload)
├── publish-workshop.ps1        (dev, publication Steam Workshop)
└── common/                     (vide, doit exister -- exige par le Build 42)
```

## Installation (test local)

1. Copie le dossier `WindTreeSway/` (avec sa structure `42/` + `common/`
   intacte) dans ton dossier de mods PZ :
   - Windows : `%USERPROFILE%\Zomboid\mods\WindTreeSway`
   - Linux/Steam Deck : `~/Zomboid/mods/WindTreeSway`
2. Lance le jeu, active le mod dans le menu Mods de l'ecran d'accueil.
3. Charge une partie (idealement en exterieur, pres d'arbres, par temps
   calme -- c'est justement le cas que ce mod cible).
4. Ouvre `~/Zomboid/console.txt` (ou la console debug en jeu) et cherche les
   lignes commencant par `[WindTreeSway]`.

## Hot reload (dev)

Comme pour `ModTemplate`, le mod embarque un opt-in pour
[PZModReload](https://github.com/deckard93/PZModReload) (MIT, deckard93),
installe localement dans `~/Zomboid/mods/ModHotReloadLocal`.

1. Active `[Dev] Hot Reload Mods (local)` en plus de `Wind Tree Sway` dans le
   menu Mods.
2. Edite `42/media/lua/client/WindTreeSway_client.lua`, sauvegarde.
3. Lance `dev-reload.ps1` (racine du mod) : ca synchronise vers
   `~/Zomboid/mods/WindTreeSway` et declenche le rechargement en jeu (dans la
   seconde qui suit, jeu non en pause).

## Publication Steam Workshop

L'uploader Workshop de PZ (bouton "Workshop" du menu Mods en jeu) attend une
structure precise sous `<install PZ>/Workshop/WindTreeSway/` :

```
Workshop/WindTreeSway/
├── workshop.txt                 (titre, description, tags, visibilite)
├── preview.png                  (miniature affichee sur la page Workshop)
└── Contents/
    └── mods/
        └── WindTreeSway/        (copie du mod, sans les fichiers de dev)
            ├── 42/
            │   ├── mod.info
            │   ├── poster.png
            │   └── media/lua/client/WindTreeSway_client.lua
            └── common/
```

(confirme en comparant avec `Workshop/ModTemplate/`, deja publie avec cette
structure).

1. Edite `workshop.txt` et `preview.png` directement sous
   `Workshop/WindTreeSway/` (pas dans ce depot -- ce sont des fichiers de
   publication, geres a la main cote installation du jeu, jamais synchronises
   par un script).
2. Lance `publish-workshop.ps1` (racine du mod) apres chaque changement a
   publier : ca synchronise vers `Workshop/WindTreeSway/Contents/mods/
   WindTreeSway/`, en excluant les fichiers de dev (`dev-reload.ps1`,
   `publish-workshop.ps1`, `README.md`, `reload.trigger`, `reload.filelist`).
3. Utilise le bouton Workshop en jeu (Mods > Workshop) pour envoyer/mettre a
   jour l'item.

## Reglages

### Sliders en jeu (Options > Mods > Wind Tree Sway)

4 curseurs, 2 categories (Arbres / Herbes et plantes) x (Amplitude, Vitesse),
accessibles depuis le menu Options (menu principal ou en pause), pas besoin
d'editer le code pour en changer.

**Pourquoi 2 categories alors qu'il n'y a qu'un seul signal de vent cote
moteur ?** Confirme par decompilation de `ObjectRenderEffects.update()` : il
n'existe qu'**un seul** `ClimateFloat` global (`windIntensity`) qui alimente
les deux pools de rendu -- `WIND_EFFECTS` (plantes/buissons) et
`WIND_EFFECTS_TREES` (arbres) -- qui ne different que par leur **seuil
d'activation fixe** : ~0.08 pour les plantes, ~0.3 pour les arbres (il faut
plus de vent pour faire bouger un arbre qu'un brin d'herbe). Consequence
physique incontournable : on peut faire osciller les plantes **sans** les
arbres (en restant sous ~0.3), mais **pas l'inverse** -- des qu'on force
assez de vent pour faire bouger un arbre, on a deja largement depasse le
seuil des plantes, qui bougent donc aussi. Le mod calcule une cible par
categorie puis les **additionne** (pas un maximum -- teste en jeu : avec un
maximum, la categorie dont la cible est la plus petite est entierement
masquee, amplitude ET vitesse, tant qu'elle reste sous l'autre) -- la somme
garde les 4 curseurs perceptibles independamment, au prix de ne jamais
isoler parfaitement "arbres actifs, plantes immobiles".

- **Amplitude (arbres / herbes-plantes)** (0 a **3.0**, defaut 0.38 pour les
  arbres, 0 -- desactive -- pour les plantes) : le pic du plancher de vent
  ambiant pour cette categorie (l'ancien `WIND_FLOOR`, seul reglage de la
  toute premiere version). A vitesse=0, c'est un plancher **constant** a
  cette valeur -- l'echelle naturelle du vent (`ClimateManager:
  getWindIntensity()`) va de 0 a 1, et aller au-dela est volontaire : le
  moteur clampe `windTickFinal` a 1.0 (voir `updateWindTick()`), donc le
  rendu du sway ne s'intensifie plus au-dela de 1.0, mais ca absorbe la
  marge de bruit que le moteur ajoute meme en pleine tempete, garantissant
  un sway colle au maximum natif EN PERMANENCE, sans les creux intermittents
  qu'aucune meteo reelle ne peut eviter. A vitesse>0, cette valeur devient le
  pic de chaque rafale (voir Vitesse ci-dessous) plutot qu'un plancher fixe.
- **Vitesse (arbres / herbes-plantes)** (0 a 20 cycles/minute, defaut 0) : a
  0, le plancher de cette categorie reste parfaitement constant (voir
  Amplitude). Au-dela, le mod fait des **rafales** : le plancher part de 0
  (calme), monte jusqu'a l'amplitude, puis redescend a 0, en boucle a la
  frequence choisie -- le moteur n'expose aucune frequence de sway reglable
  a Lua (voir l'historique des echecs en tete du fichier lua), donc c'est le
  mod qui la simule. Premiere version testee : une onde sinusoidale
  symetrique autour de l'amplitude (+/-35%) -- abandonnee car au-dela d'une
  amplitude d'environ 1.5, meme le creux de la sinusoide restait au-dessus
  de 1.0, et le clamp du moteur ecrasait alors toute la courbe a 1.0 en
  permanence : vitesse=0 et vitesse=20 donnaient EXACTEMENT le meme resultat
  visuel (constate en jeu, confirme par les logs : le plancher variait mais
  `windTickFinal` restait fige a 1.00). Les rafales (0 -> amplitude -> 0)
  passent toujours par un vrai creux, donc la vitesse reste visible quelle
  que soit l'amplitude choisie pour le pic.

Avec les valeurs par defaut (plantes desactivees), le comportement est
identique a la toute premiere version du mod (arbres seulement, plancher
constant a 0.38).

Attention (les 4 curseurs) : `windIntensity` est une valeur globale
potentiellement lue par d'autres systemes que le sway (son ambiant,
particules...) -- decompilation non exhaustive sur ces usages annexes, donc
des valeurs tres au-dela de 1.0 (amplitude) pourraient avoir des effets de
bord ailleurs. A surveiller en jeu si un curseur est pousse tres haut.

### Constantes dans `42/media/lua/client/WindTreeSway_client.lua`

- `DEFAULT_TREE_AMPLITUDE` / `DEFAULT_PLANT_AMPLITUDE` / `DEFAULT_SPEED` :
  valeurs par defaut des sliders ci-dessus (voir `AMPLITUDE_MIN`/`MAX`/`STEP`
  et `SPEED_MIN`/`MAX`/`STEP` juste apres pour ajuster les bornes des
  curseurs, partagees par les deux categories).
- `CHECK_MS` : intervalle entre deux verifications/reapplications du
  plancher (reduit a 100ms pour que l'oscillation controlee par les sliders
  Vitesse paraisse fluide plutot qu'en marches d'escalier).
- `INTERP` : vitesse de transition vers le plancher (1.0 = immediat, sans
  a-coup ; une valeur plus basse donnerait une transition plus progressive).
- `WindTreeSway.debug` : passe a `false` pour couper les logs une fois que
  tout fonctionne (coupe aussi le hot reload, qui est branche sur ce flag).

## Limite connue / a surveiller

Le mod agit sur une valeur globale (`windIntensity` de `ClimateManager`),
donc l'effet touche **toute la carte**, pas seulement les environs du
joueur -- en pratique difficile a distinguer d'une brise legere ambiante
reelle, mais a garder en tete.

Si le sandbox est configure sur un mode "Endless Weather" (option
`ClimateCycle` != Vanilla), le jeu utilise ce meme mecanisme d'override en
interne pour forcer un vent constant -- notre plancher pourrait alors se
superposer a ce reglage. Non teste explicitement ; a surveiller si l'effet
semble incoherent avec ce sandbox option actif.

**Effet de bord confirme et NON separable : les vagues de l'eau accelerent
aussi.** Signale par l'utilisateur, verifie par decompilation de
`zombie.iso.IsoWater.class` (build 42.20.0) : cette classe importe
directement `ClimateManager` et appelle `getWindIntensity()` pour calculer
la vitesse/l'angle des vagues (`waterWindSpeed`, `waterWindAngle`,
`waterWindIntensity`) -- exactement la meme valeur globale que ce mod force
pour les arbres/plantes, sans seuil d'activation separe comme pour la
vegetation. `IsoWater.class` n'a par ailleurs **aucune** methode annotee
`@UsedFromLua` (verifie dans son constant pool) -- rien n'est expose a Lua
pour lui donner une valeur de vent independante. Consequence : monter
l'amplitude des sliders accelere systematiquement aussi l'animation de
l'eau, et **rien dans l'API de modding Lua ne permet de decoupler les
deux** -- seul un patch du `.class` Java lui-meme (hors du perimetre d'un
mod Lua standard) le permettrait.
