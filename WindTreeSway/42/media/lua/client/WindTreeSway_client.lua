-- WindTreeSway_client.lua
--
-- Objectif : faire legerement osciller les arbres meme par vent calme, en
-- reutilisant le systeme NATIF de sway du jeu (celui qui fait deja bouger les
-- arbres pendant les tempetes) plutot que de deplacer les sprites nous-memes.
--
-- HISTORIQUE DES ECHECS :
--
-- 1) Ecrire directement x1/y1/x2/y2 sur l'objet ObjectRenderEffects partage
--    renvoye par IsoObject:getWindRenderEffects(). Teste en jeu (build
--    42.20.0) : plante a chaque tick avec
--      java.lang.RuntimeException: attempted index of non-table
--      at KahluaThread.tableSet
--    Les champs publics x1..y4 sont bien la (confirme par decompilation),
--    mais Kahlua ne permet pas d'ECRIRE un champ Java par simple assignation
--    "objet.champ = valeur" -- seule la LECTURE fonctionne. Abandonne.
--
-- 2) Declencher l'effet natif "Vegetation_Rustle" via
--    IsoObject:setRenderEffect(RenderEffectType.Vegetation_Rustle, true)
--    (IsoTree s'en sert en interne pour son effet de coupe). Teste en jeu :
--    plante immediatement des l'evaluation de l'argument avec
--      java.lang.RuntimeException: attempted index: Vegetation_Rustle of non-table: null
--    Cause confirmee en decompilant zombie.iso.objects.RenderEffectType.class :
--    cette enum n'a AUCUNE annotation @UsedFromLua (grep du constant pool,
--    zero reference a "UsedFromLua"). Le jeu ne l'expose donc pas comme
--    variable globale Lua -- "RenderEffectType" vaut nil cote Lua, impossible
--    d'obtenir une instance de cet enum depuis un script. Abandonne.
--
-- APPROCHE ACTUELLE (validee par decompilation de
-- zombie.iso.weather.ClimateManager.class, build 42.20.0) :
--
-- Plutot que de manipuler des ObjectRenderEffects par arbre, on agit
-- directement sur la valeur de vent AMBIANTE que le moteur utilise deja pour
-- animer TOUT le feuillage natif (arbres ET buissons) :
--   zombie.iso.weather.ClimateManager$ClimateFloat (annotee @UsedFromLua,
--   donc pleinement accessible -- champs prives mais methodes publiques
--   exposees) est la classe qui porte windIntensity. Chaque tick,
--   ClimateManager.updateWindTick() calcule :
--     windTickFinal = clamp01(windIntensity.finalValue + bruit)
--   et c'est CETTE valeur que ObjectRenderEffects.updateStatic() lit pour
--   faire osciller le pool partage d'effets de vent (WIND_EFFECTS /
--   WIND_EFFECTS_TREES) qui anime tous les arbres/buissons "moveWithWind".
--
--   ClimateFloat.calculate() :
--     finalValue = (isOverride et interpolate>0)
--                    ? lerp(interpolate, ..., override)
--                    : internalValue   -- valeur reelle simulee par la meteo
--
--   setOverride(cible, interpolate) met isOverride=true automatiquement et
--   force finalValue vers "cible" -- avec interpolate=1.0, le lerp donne
--   directement la cible, sans a-coup. C'est EXACTEMENT le mecanisme que le
--   jeu utilise en interne pour l'option sandbox "Endless Weather" (voir
--   ClimateManager.updateSandboxOverrides) -- donc un detour officiel et
--   deja eprouve, pas un hack.
--
--   PIEGE (rencontre et corrige en jeu) : NE PAS appeler setOverrideValue()
--   en plus de setOverride(). Sa vraie implementation est
--     isOverrideValue = v; isOverride = v;
--   donc setOverrideValue(false) desactive isOverride en meme temps --
--   annulait silencieusement le setOverride() precedent, chaque tick.
--   Diagnostic confirme par log : finalValue restait colle a internalValue
--   (le vent reel) au lieu de suivre le plancher, alors qu'aucune erreur
--   n'etait levee (les deux appels reussissaient individuellement, seul
--   leur effet combine annulait tout).
--
--   Des que le vent reel (getInternalValue(), la valeur simulee independante
--   de notre override) depasse le plancher, on desactive l'override
--   (setEnableOverride(false)) et finalValue revient instantanement a la
--   vraie valeur meteo -- comportement des tempetes inchange, transition
--   immediate sans le delai d'extinction qui affectait l'ancienne approche
--   par arbre.
--
--   Avantage supplementaire : plus besoin de scanner/suivre les arbres pres
--   du joueur -- un seul point d'ajustement global, beaucoup plus simple et
--   fiable.

local WindTreeSway = {}
WindTreeSway.debug = true

local function log(msg)
    if WindTreeSway.debug then
        print("[WindTreeSway] " .. tostring(msg))
    end
end

-- Reglages
local DEFAULT_TREE_AMPLITUDE  = 0.38  -- valeur par defaut historique (avant la
                          -- separation arbres/plantes) -- 0..1, meme echelle
                          -- que ClimateManager:getWindIntensity(). Confirme par
                          -- decompilation de ObjectRenderEffects.update() : le
                          -- pool "arbres" a un seuil (~0.3, comparaison stricte
                          -- <=) sous lequel le sway reste a 0 -- 0.38 le
                          -- depasse avec une marge confortable.
local DEFAULT_PLANT_AMPLITUDE = 0     -- desactive par defaut (nouvelle
                          -- categorie -- comportement inchange tant qu'on ne
                          -- monte pas ce slider).
local CHECK_MS   = 100   -- intervalle entre deux verifications/reapplications.
                          -- Reduit de 1000 a 100 ms : avec les sliders de
                          -- vitesse (voir plus bas), la cible n'est plus
                          -- constante -- l'echantillonner seulement 1x/s la
                          -- ferait ressortir en marches d'escalier plutot
                          -- qu'une oscillation fluide.
local INTERP     = 1.0   -- vitesse de transition vers le plancher (1.0 = immediat)

local WIND_INTENSITY_ID = 6  -- index de ClimateManager:getClimateFloat(), confirme
                              -- par decompilation (initClimateFloat(6, "WIND_INTENSITY"))

-- 4 sliders en jeu (Options > Mods > Wind Tree Sway), 2 categories x
-- (Amplitude, Vitesse) :
--
-- POURQUOI 2 CATEGORIES MAIS UN SEUL SIGNAL MOTEUR -- confirme par
-- decompilation de ObjectRenderEffects.update() : il n'existe PAS deux
-- valeurs de vent separees pour les arbres et les plantes/herbes cote moteur
-- -- un seul ClimateFloat global (WIND_INTENSITY_ID=6) alimente les DEUX
-- pools de rendu (WIND_EFFECTS pour les plantes/buissons, WIND_EFFECTS_TREES
-- pour les arbres), qui ne different que par leur SEUIL d'activation fixe
-- (~0.08 pour les plantes, ~0.3 pour les arbres -- les arbres ont besoin de
-- plus de vent pour bouger). Consequence physique incontournable : on peut
-- faire osciller les plantes SANS les arbres (rester sous ~0.3), mais on ne
-- peut PAS faire osciller les arbres sans que les plantes suivent aussi
-- (des qu'on depasse ~0.3, on a deja largement depasse ~0.08). Ce mod calcule
-- donc une cible par categorie (chacune avec sa propre amplitude/vitesse) et
-- les ADDITIONNE (voir getTargetWindFloor()) -- au plus proche d'un controle
-- independant que le moteur permet. Testee en jeu : un MAX plutot qu'une
-- somme masque completement la categorie dont la cible instantanee est la
-- plus petite (son amplitude ET sa vitesse deviennent invisibles tant que
-- l'autre categorie domine) -- la somme garde toujours les deux
-- contributions perceptibles, au prix de ne jamais isoler parfaitement
-- "arbres actifs, plantes immobiles" (cf. plus haut).
--
-- AMPLITUDE (par categorie) -- meme role que l'ancien slider unique : la
-- force du plancher de vent force par temps calme pour cette categorie. Les
-- deux curseurs vont volontairement AU-DELA de 1.0, l'intensite de vent
-- "maximale" actuelle du moteur -- ClimateManager.updateWindTick() calcule
-- windTickFinal = clamp01(finalValue + bruit), donc au-dela de ~1.0 le rendu
-- du sway lui-meme ne peut plus s'intensifier davantage (clamp01 le recolle
-- a 1.0). Ce que ca apporte quand meme : le bruit ajoute par le moteur peut
-- faire redescendre finalValue sous 1.0 par intermittence, meme pendant la
-- pire tempete ; en poussant l'amplitude nettement au-dessus de 1.0, on
-- absorbe cette marge de bruit et on obtient un sway COLLE au maximum natif
-- en permanence, sans aucun creux -- un resultat qu'aucune meteo reelle ne
-- peut garantir. D'ou AMPLITUDE_MAX = 3.0.
--
-- VITESSE (par categorie) -- le moteur ne nous laisse controler qu'UNE SEULE
-- valeur (windIntensity), jamais une frequence d'oscillation separee (rien
-- d'equivalent n'est expose a Lua, voir l'historique des echecs en tete de
-- fichier) -- donc pour obtenir une vraie vitesse reglable, ce mod fait
-- lui-meme varier chaque cible de categorie dans le temps (rafales) plutot
-- que de forcer un plancher constant.
--
-- PREMIERE VERSION (abandonnee) : cible = amplitude*(1 + 35% * sin(phase)),
-- une sinusoide SYMETRIQUE autour de l'amplitude. Probleme constate en jeu
-- par l'utilisateur : au-dela d'une amplitude d'environ 1.5, MEME LE CREUX
-- de la sinusoide (amplitude*0.65) depasse deja 1.0 -- or le moteur calcule
-- windTickFinal = clamp01(...), donc toute la sinusoide se retrouve
-- ecrasee a 1.0 en permanence, quelle que soit la phase. Vitesse=0 ou
-- vitesse=20 rendaient alors EXACTEMENT le meme resultat visuel -- confirme
-- par les logs (plancher variant de 1.2 a 6.9 selon les lignes, mais
-- windTickFinal fige a 1.00 partout).
--
-- VERSION ACTUELLE : cible = amplitude * (0.5 - 0.5*cos(phase)), une
-- "rafale" qui part de 0 (phase=0), monte jusqu'a l'amplitude (phase=pi),
-- puis redescend a 0 (phase=2pi) -- PAS une sinusoide symetrique. Comme le
-- creux vaut TOUJOURS 0 quelle que soit l'amplitude, le plancher repasse a
-- chaque cycle sous la meteo reelle (le mod desactive alors l'override,
-- cf. onTick -- la vraie meteo, calme, s'affiche un instant) avant de
-- remonter vers le pic. La vitesse reste donc TOUJOURS visible (le rythme
-- calme/rafale change avec elle), quelle que soit l'amplitude choisie pour
-- le pic -- au prix de perdre, quand vitesse>0, la garantie "toujours au
-- maximum sans le moindre creux" (qui ne s'applique plus qu'a vitesse=0,
-- ou la cible reste bien une constante -- voir oscillate()).
--
-- ATTENTION (les 4 sliders) : windIntensity est une valeur GLOBALE
-- reutilisee par d'autres systemes que le sway (son ambiant, particules...)
-- -- decompilation non exhaustive sur ces autres usages, donc des valeurs
-- tres au-dela de 1.0 (amplitude) pourraient avoir des effets de bord
-- inattendus ailleurs. A tester en jeu.
local AMPLITUDE_MIN  = 0
local AMPLITUDE_MAX  = 3.0
local AMPLITUDE_STEP = 0.05

local SPEED_MIN     = 0     -- cycles par minute. 0 = statique (pas d'oscillation).
local SPEED_MAX     = 20    -- 20 cycles/min = periode de 3s (rapide).
local SPEED_STEP    = 0.5
local DEFAULT_SPEED = 0

local swayModOptions = nil
local swayTreeAmplitudeSlider = nil
local swayTreeSpeedSlider = nil
local swayPlantAmplitudeSlider = nil
local swayPlantSpeedSlider = nil

-- Recupere le slider "id" sur le groupe d'options "opts" s'il existe deja
-- (cas normal d'un hot reload sans changement d'id), sinon le cree. Sans ca,
-- renommer/ajouter un id d'un hot reload a l'autre (ce qui arrive souvent en
-- cours d'iteration -- vecu en pratique en passant de 2 a 4 sliders) laisse
-- le nouveau slider bloque a nil pour de bon : PZAPI.ModOptions.Dict survit
-- au reload, donc l'entree "WindTreeSway" existe deja, mais elle ne contient
-- que les anciens id -- getOption(nouvelId) renvoie nil, et sans repli sur
-- addSlider(), rien ne le cree jamais.
local function ensureSlider(opts, id, name, min, max, step, default, tooltip)
    local slider = opts:getOption(id)
    if slider ~= nil then return slider end
    return opts:addSlider(id, name, min, max, step, default, tooltip)
end

local function initModOptions()
    if swayTreeAmplitudeSlider ~= nil and swayTreeSpeedSlider ~= nil
        and swayPlantAmplitudeSlider ~= nil and swayPlantSpeedSlider ~= nil then
        return
    end
    if PZAPI == nil or PZAPI.ModOptions == nil then return end

    local ok, err = pcall(function()
        -- PZAPI.ModOptions.Dict/.Data survivent a un hot reload (seul CE
        -- chunk est reexecute, pas l'etat global de PZAPI) -- si l'entree
        -- existe deja (reload en cours d'iteration), la reutiliser plutot
        -- que de rappeler create(), qui n'a pas de dedup et dupliquerait la
        -- section "Wind Tree Sway" dans le menu Options a chaque reload. Ca
        -- a aussi l'avantage de preserver la position des curseurs choisie
        -- par le joueur pendant qu'on itere sur le code. Chaque slider passe
        -- ensuite par ensureSlider() (voir ci-dessus) pour etre cree s'il
        -- manque encore (nouvel id jamais vu par ce groupe d'options).
        local opts = PZAPI.ModOptions:getOptions("WindTreeSway")
        local isNew = (opts == nil)
        if isNew then
            opts = PZAPI.ModOptions:create("WindTreeSway", "Wind Tree Sway")
            opts:addDescription(
                "Fait osciller arbres et/ou plantes par temps calme en forcant "
                .. "un plancher de vent ambiant. Un seul signal de vent existe "
                .. "cote moteur : les deux categories S'ADDITIONNENT dans ce "
                .. "signal (ce n'est jamais l'une OU l'autre) -- monter "
                .. "l'amplitude des arbres au-dela du seuil natif (~0.3) fait "
                .. "aussi bouger les plantes (seuil natif plus bas, ~0.08), mais "
                .. "l'inverse n'est pas vrai : on peut garder les arbres "
                .. "immobiles et faire osciller les plantes seules. A "
                .. "vitesse=0, le plancher d'une categorie reste constant (son "
                .. "amplitude peut depasser 1.0, le maximum de vent naturel, "
                .. "pour garantir un sway au maximum en permanence). Des que "
                .. "vitesse>0, cette categorie fait plutot des rafales : le "
                .. "plancher part de calme, monte jusqu'a l'amplitude, "
                .. "redescend a calme, en boucle a la frequence choisie -- "
                .. "ainsi la vitesse reste toujours visible, quelle que soit "
                .. "l'amplitude choisie pour le pic -- voir les tooltips des "
                .. "curseurs.")
            opts:addTitle("Arbres")
        end
        swayModOptions = opts

        swayTreeAmplitudeSlider = ensureSlider(opts,
            "TreeAmplitude", "Amplitude (arbres)",
            AMPLITUDE_MIN, AMPLITUDE_MAX, AMPLITUDE_STEP, DEFAULT_TREE_AMPLITUDE,
            "Pic du plancher de vent pour le seuil de sway des arbres (~0.3 "
            .. "cote moteur). A vitesse=0, plancher constant a cette valeur -- "
            .. "au-dela de 1.0, le sway reste au maximum visuel sans jamais "
            .. "redescendre. A vitesse>0, c'est le pic de chaque rafale (le "
            .. "plancher revient a calme entre deux). Fait aussi osciller les "
            .. "plantes (seuil plus bas) -- impossible a eviter cote moteur.")
        swayTreeSpeedSlider = ensureSlider(opts,
            "TreeSpeed", "Vitesse (arbres)",
            SPEED_MIN, SPEED_MAX, SPEED_STEP, DEFAULT_SPEED,
            "A 0 (defaut), le plancher des arbres reste constant a son "
            .. "amplitude. Au-dela, il fait des rafales dans le temps (calme "
            .. "-> amplitude -> calme, en boucle) a cette frequence, en cycles "
            .. "par minute -- reste visible meme a forte amplitude.")

        if isNew then
            opts:addSeparator()
            opts:addTitle("Herbes et plantes")
        end
        swayPlantAmplitudeSlider = ensureSlider(opts,
            "PlantAmplitude", "Amplitude (herbes/plantes)",
            AMPLITUDE_MIN, AMPLITUDE_MAX, AMPLITUDE_STEP, DEFAULT_PLANT_AMPLITUDE,
            "Pic du plancher de vent pour le seuil de sway des plantes/herbes "
            .. "(~0.08 cote moteur, plus bas que celui des arbres). Reste sous "
            .. "~0.3 pour faire bouger les plantes SANS les arbres. A "
            .. "vitesse>0, c'est le pic de chaque rafale (le plancher revient "
            .. "a calme entre deux).")
        swayPlantSpeedSlider = ensureSlider(opts,
            "PlantSpeed", "Vitesse (herbes/plantes)",
            SPEED_MIN, SPEED_MAX, SPEED_STEP, DEFAULT_SPEED,
            "A 0 (defaut), le plancher des plantes reste constant a son "
            .. "amplitude. Au-dela, il fait des rafales dans le temps (calme "
            .. "-> amplitude -> calme, en boucle) a cette frequence, en cycles "
            .. "par minute -- reste visible meme a forte amplitude.")
    end)
    if not ok then
        log("initModOptions a echoue -> " .. tostring(err))
        swayModOptions = nil
        swayTreeAmplitudeSlider = nil
        swayTreeSpeedSlider = nil
        swayPlantAmplitudeSlider = nil
        swayPlantSpeedSlider = nil
    end
end

local function readSlider(slider, default)
    if slider ~= nil then
        local ok, value = pcall(function() return slider:getValue() end)
        if ok and type(value) == "number" then
            return value
        end
    end
    return default
end

-- Cible "rafale" pour une categorie donnee, a l'instant nowMs (ms horloge
-- murale). A vitesse=0, cible = amplitude, constante (voir le gros
-- commentaire plus haut sur les 2 versions testees). Sinon, part de 0,
-- monte jusqu'a amplitude, puis redescend a 0 -- le creux vaut TOUJOURS 0,
-- quelle que soit l'amplitude, donc la vitesse reste visible meme a forte
-- amplitude (contrairement a l'ancienne sinusoide symetrique).
local function oscillate(amplitude, speedCpm, nowMs)
    if speedCpm <= 0 then
        return amplitude
    end
    local phase = (nowMs / 60000) * speedCpm * (2 * math.pi)
    return amplitude * (0.5 - 0.5 * math.cos(phase))
end

-- Combine les 2 categories en UNE cible pour le plancher de vent unique du
-- moteur : SOMME des deux (pas MAX). Teste en jeu : avec un MAX, la
-- categorie dont la cible instantanee est la plus petite est entierement
-- masquee -- monter/baisser son amplitude ne change RIEN tant qu'elle reste
-- en-dessous de l'autre, et sa vitesse ne devient "visible" que si l'autre
-- categorie retombe en-dessous par coincidence (constate par le joueur : les
-- sliders plantes semblaient inertes, et la vitesse des deux categories
-- paraissait liee). Avec une somme, chaque categorie ajoute TOUJOURS sa
-- propre contribution (son propre battement, a sa propre vitesse) par-dessus
-- l'autre, donc les 4 sliders restent perceptibles independamment. Avec les
-- defauts (plantes desactivees = amplitude 0), la somme redonne exactement
-- le comportement d'avant la separation en categories (0.38 + 0 = 0.38).
-- Limite qui reste incontournable (voir le gros commentaire plus haut) :
-- une fois la somme au-dela du seuil de sway des arbres (~0.3), les arbres
-- suivent forcement les deux contributions cumulees -- on ne peut toujours
-- pas isoler "arbres actifs, plantes immobiles".
local function getTargetWindFloor(nowMs)
    local treeTarget = oscillate(
        readSlider(swayTreeAmplitudeSlider, DEFAULT_TREE_AMPLITUDE),
        readSlider(swayTreeSpeedSlider, DEFAULT_SPEED),
        nowMs)
    local plantTarget = oscillate(
        readSlider(swayPlantAmplitudeSlider, DEFAULT_PLANT_AMPLITUDE),
        readSlider(swayPlantSpeedSlider, DEFAULT_SPEED),
        nowMs)
    return treeTarget + plantTarget
end

-- Enregistre le slider des le chargement du script (pas seulement a
-- OnGameStart) : Options > Mods est accessible depuis le menu principal,
-- avant meme de charger une partie, donc PZAPI.ModOptions:create() doit
-- avoir ete appele des ce moment-la pour que le slider y apparaisse deja.
initModOptions()

-- L'option graphique "doWindSpriteEffects" (menu Options > Affichage > "Wind
-- Sprite Effects") est DESACTIVEE PAR DEFAUT dans PZ (confirme par
-- decompilation de zombie.core.Core.class : valeur par defaut = false). Sans
-- elle, ObjectRenderEffects.update() remet tous les offsets a 0 quel que soit
-- le vent -- donc sans cette option, aucun sway n'est jamais visible, meme
-- avec notre plancher de vent applique. On la force ici pour que le mod
-- fonctionne sans configuration manuelle.
-- Flags "log une seule fois" pour ne pas spammer si un appel echoue en boucle.
local windSpriteEffectsErrorLogged = false
local overrideErrorLogged = false

local function ensureWindSpriteEffectsEnabled()
    local ok, core = pcall(getCore)
    if not ok or not core then
        if not windSpriteEffectsErrorLogged then
            windSpriteEffectsErrorLogged = true
            log("getCore() indisponible -> " .. tostring(core))
        end
        return
    end
    local ok2, enabled = pcall(function() return core:getOptionDoWindSpriteEffects() end)
    if not ok2 then
        if not windSpriteEffectsErrorLogged then
            windSpriteEffectsErrorLogged = true
            log("getOptionDoWindSpriteEffects() a echoue -> " .. tostring(enabled))
        end
        return
    end
    if enabled == false then
        local ok3, err3 = pcall(function() core:setOptionDoWindSpriteEffects(true) end)
        if not ok3 and not windSpriteEffectsErrorLogged then
            windSpriteEffectsErrorLogged = true
            log("setOptionDoWindSpriteEffects(true) a echoue -> " .. tostring(err3))
        elseif ok3 then
            log("Option 'Wind Sprite Effects' etait desactivee -> activee automatiquement.")
        end
    end
end

local overriding = false
local lastCheck = 0
local lastLog = 0

local function onTick()
    local now = getTimestampMs()
    if now - lastCheck < CHECK_MS then return end
    lastCheck = now

    initModOptions()
    ensureWindSpriteEffectsEnabled()

    local ok, climate = pcall(getClimateManager)
    if not ok or not climate then return end

    local ok2, windFloat = pcall(function() return climate:getClimateFloat(WIND_INTENSITY_ID) end)
    if not ok2 or not windFloat then return end

    local ok3, internal = pcall(function() return windFloat:getInternalValue() end)
    if not ok3 or type(internal) ~= "number" then return end

    local windFloor = getTargetWindFloor(now)

    if internal < windFloor then
        -- IMPORTANT : ne PAS appeler setOverrideValue() ici. Sa vraie
        -- implementation (confirmee par decompilation) est
        --   isOverrideValue = v; isOverride = v;
        -- donc setOverrideValue(false) desactive isOverride en meme temps --
        -- exactement ce qui annulait silencieusement le setOverride()
        -- precedent (bug trouve via le diagnostic finalValue/windTickFinal :
        -- finalValue restait colle a internalValue au lieu de suivre
        -- le plancher). setOverride() seul active deja isOverride=true, et
        -- isOverrideValue reste a son defaut (false, mis une fois par le jeu
        -- via updateSandboxOverrides en Vanilla), ce qui est le comportement
        -- voulu (blend depuis internalValue, pas overrideInternal).
        local okA, errA = pcall(function() windFloat:setOverride(windFloor, INTERP) end)
        if not okA and not overrideErrorLogged then
            overrideErrorLogged = true
            log("setOverride a echoue -> " .. tostring(errA))
        end
        if not overriding then
            overriding = true
            log(string.format("vent reel=%.2f < plancher=%.2f -> plancher de vent applique", internal, windFloor))
        end
    elseif overriding then
        overriding = false
        pcall(function() windFloat:setEnableOverride(false) end)
        log(string.format("vent reel=%.2f >= plancher=%.2f -> plancher de vent leve", internal, windFloor))
    end

    if WindTreeSway.debug and now - lastLog > 5000 then
        lastLog = now
        -- Diagnostic complet : on relit finalValue APRES avoir applique
        -- l'override, pour verifier que le mecanisme agit vraiment (et pas
        -- seulement que l'appel n'a pas plante).
        local okF, finalVal = pcall(function() return windFloat:getFinalValue() end)
        local okT, tickFinal = pcall(function() return ClimateManager.getWindTickFinal() end)
        local okO, coreOpt = pcall(function() return getCore():getOptionDoWindSpriteEffects() end)
        log(string.format(
            "vent reel=%.2f (plancher=%.2f) -> override actif=%s | finalValue=%s | windTickFinal=%s | doWindSpriteEffects=%s",
            internal, windFloor, tostring(overriding),
            okF and string.format("%.2f", finalVal) or ("ERR:" .. tostring(finalVal)),
            okT and string.format("%.2f", tickFinal) or ("ERR:" .. tostring(tickFinal)),
            okO and tostring(coreOpt) or ("ERR:" .. tostring(coreOpt))))
    end
end

Events.OnTick.Add(onTick)

Events.OnGameStart.Add(function()
    initModOptions()
    log(string.format(
        "Mod charge (build 42.20.0). Arbres: amplitude=%.2f vitesse=%.1f cpm | "
        .. "Plantes: amplitude=%.2f vitesse=%.1f cpm.",
        readSlider(swayTreeAmplitudeSlider, DEFAULT_TREE_AMPLITUDE),
        readSlider(swayTreeSpeedSlider, DEFAULT_SPEED),
        readSlider(swayPlantAmplitudeSlider, DEFAULT_PLANT_AMPLITUDE),
        readSlider(swayPlantSpeedSlider, DEFAULT_SPEED)))
end)

-- Opt-in pour le mod dev "[Dev] Hot Reload Mods (local)" (voir dev-reload.ps1
-- a la racine du mod) : permet d'iterer sur les reglages ci-dessus sans
-- relancer le jeu.
HotReload = HotReload or {}
HotReload.mods = HotReload.mods or {}
HotReload.mods["WindTreeSway"] = { enabled = function() return WindTreeSway.debug end }

return WindTreeSway
