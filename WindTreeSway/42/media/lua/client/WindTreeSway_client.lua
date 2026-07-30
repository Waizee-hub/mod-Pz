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
--   (le vent reel) au lieu de suivre WIND_FLOOR, alors qu'aucune erreur
--   n'etait levee (les deux appels reussissaient individuellement, seul
--   leur effet combine annulait tout).
--
--   Des que le vent reel (getInternalValue(), la valeur simulee independante
--   de notre override) depasse WIND_FLOOR, on desactive l'override
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

-- Reglages
local WIND_FLOOR = 0.38  -- plancher de vent ambiant force par temps calme (0..1,
                          -- meme echelle que ClimateManager:getWindIntensity()).
                          -- Confirme par decompilation de ObjectRenderEffects.update() :
                          -- les 3 "windType" du pool partage ont des seuils
                          -- differents (0.08 / 0.15 / 0.3, comparaison stricte
                          -- <=) sous lesquels le sway reste a 0 -- 0.38 les
                          -- depasse tous les trois avec une marge confortable.
local CHECK_MS   = 1000  -- intervalle entre deux verifications/reapplications
local INTERP     = 1.0   -- vitesse de transition vers WIND_FLOOR (1.0 = immediat)

local WIND_INTENSITY_ID = 6  -- index de ClimateManager:getClimateFloat(), confirme
                              -- par decompilation (initClimateFloat(6, "WIND_INTENSITY"))

local function log(msg)
    if WindTreeSway.debug then
        print("[WindTreeSway] " .. tostring(msg))
    end
end

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

    ensureWindSpriteEffectsEnabled()

    local ok, climate = pcall(getClimateManager)
    if not ok or not climate then return end

    local ok2, windFloat = pcall(function() return climate:getClimateFloat(WIND_INTENSITY_ID) end)
    if not ok2 or not windFloat then return end

    local ok3, internal = pcall(function() return windFloat:getInternalValue() end)
    if not ok3 or type(internal) ~= "number" then return end

    if internal < WIND_FLOOR then
        -- IMPORTANT : ne PAS appeler setOverrideValue() ici. Sa vraie
        -- implementation (confirmee par decompilation) est
        --   isOverrideValue = v; isOverride = v;
        -- donc setOverrideValue(false) desactive isOverride en meme temps --
        -- exactement ce qui annulait silencieusement le setOverride()
        -- precedent (bug trouve via le diagnostic finalValue/windTickFinal :
        -- finalValue restait colle a internalValue au lieu de suivre
        -- WIND_FLOOR). setOverride() seul active deja isOverride=true, et
        -- isOverrideValue reste a son defaut (false, mis une fois par le jeu
        -- via updateSandboxOverrides en Vanilla), ce qui est le comportement
        -- voulu (blend depuis internalValue, pas overrideInternal).
        local okA, errA = pcall(function() windFloat:setOverride(WIND_FLOOR, INTERP) end)
        if not okA and not overrideErrorLogged then
            overrideErrorLogged = true
            log("setOverride a echoue -> " .. tostring(errA))
        end
        if not overriding then
            overriding = true
            log(string.format("vent reel=%.2f < plancher=%.2f -> plancher de vent applique", internal, WIND_FLOOR))
        end
    elseif overriding then
        overriding = false
        pcall(function() windFloat:setEnableOverride(false) end)
        log(string.format("vent reel=%.2f >= plancher=%.2f -> plancher de vent leve", internal, WIND_FLOOR))
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
            internal, WIND_FLOOR, tostring(overriding),
            okF and string.format("%.2f", finalVal) or ("ERR:" .. tostring(finalVal)),
            okT and string.format("%.2f", tickFinal) or ("ERR:" .. tostring(tickFinal)),
            okO and tostring(coreOpt) or ("ERR:" .. tostring(coreOpt))))
    end
end

Events.OnTick.Add(onTick)

Events.OnGameStart.Add(function()
    log("Mod charge (build 42.20.0). Plancher de vent ambiant = " .. tostring(WIND_FLOOR) .. ".")
end)

-- Opt-in pour le mod dev "[Dev] Hot Reload Mods (local)" (voir dev-reload.ps1
-- a la racine du mod) : permet d'iterer sur les reglages ci-dessus sans
-- relancer le jeu.
HotReload = HotReload or {}
HotReload.mods = HotReload.mods or {}
HotReload.mods["WindTreeSway"] = { enabled = function() return WindTreeSway.debug end }

return WindTreeSway
