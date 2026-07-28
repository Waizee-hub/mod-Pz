-- WindTreeSway_client.lua
--
-- Objectif : faire osciller légèrement les arbres proches du joueur, avec une
-- vitesse/amplitude qui suit l'intensité du vent (Build 42.19).
--
-- A LIRE AVANT DE JUGER LE RESULTAT :
-- La lecture du vent via ClimateManager est robuste (plusieurs noms de methode
-- candidats sont testes automatiquement, avec repli sur un vent "procedural"
-- si aucun n'est trouve). En revanche, Project Zomboid met en cache/rend par
-- blocs les objets du monde isometrique pour la performance, et il n'existe
-- pas de documentation publique confirmant une methode Lua pour decaler
-- visuellement, image par image, un IsoObject deja pose sur la carte.
--
-- Ce script teste donc, sur le premier arbre trouve, plusieurs methodes
-- candidates et log clairement dans console.txt laquelle fonctionne (le cas
-- echeant) sur cette version du jeu. Si aucune ne fonctionne, seule la
-- lecture du vent reste active, avec un log explicite -> il suffit de me
-- transmettre ces lignes de console.txt pour que je corrige precisement le
-- point de rendu au lieu de deviner.

local WindTreeSway = {}
WindTreeSway.debug = true

-- Reglages
local UPDATE_RADIUS   = 12      -- rayon (en tuiles) autour du joueur a surveiller
local RESCAN_MS       = 4000    -- intervalle (ms) entre deux re-scans des arbres proches
local BASE_FREQ_HZ    = 0.35    -- vitesse d'oscillation par vent faible
local MAX_FREQ_HZ     = 1.8     -- vitesse d'oscillation par vent fort
local BASE_AMPLITUDE  = 0.8     -- amplitude (px) par vent faible
local MAX_AMPLITUDE   = 3.2     -- amplitude (px) par vent fort
local WIND_SMOOTHING  = 0.03    -- lissage des rafales (plus petit = plus lisse)

local swayTargets = {}
local lastRescan = 0
local windSmoothed = 0.35
local capability = nil          -- nil = pas encore teste, false = aucune trouvee, sinon table candidate
local lastWindLog = 0

local function log(msg)
    if WindTreeSway.debug then
        print("[WindTreeSway] " .. tostring(msg))
    end
end

---------------------------------------------------------------------------
-- Lecture du vent
---------------------------------------------------------------------------

local WIND_METHOD_CANDIDATES = { "getWindSpeed", "getWindIntensity", "getWindStrength", "getWind" }
local resolvedWindMethod = nil
local windMethodResolved = false

local function tryReadRealWind()
    local ok, climate = pcall(getClimateManager)
    if not ok or not climate then return nil end

    if not windMethodResolved then
        windMethodResolved = true
        for _, name in ipairs(WIND_METHOD_CANDIDATES) do
            local fn = climate[name]
            if fn then
                local okCall, val = pcall(fn, climate)
                if okCall and type(val) == "number" then
                    resolvedWindMethod = name
                    log("Vent lu via ClimateManager:" .. name .. "() = " .. tostring(val))
                    break
                end
            end
        end
        if not resolvedWindMethod then
            log("Aucune methode de vent connue trouvee sur ClimateManager -> repli sur un vent procedural.")
        end
    end

    if not resolvedWindMethod then return nil end
    local fn = climate[resolvedWindMethod]
    local ok2, val = pcall(fn, climate)
    if not ok2 or type(val) ~= "number" then return nil end
    if val > 1.5 then val = val / 10.0 end -- au cas ou l'echelle reelle est 0..10 plutot que 0..1
    if val < 0 then val = 0 end
    if val > 1 then val = 1 end
    return val
end

local function proceduralWind()
    local t = getTimestampMs() / 1000.0
    local n = 0.5
        + 0.25 * math.sin(t * 0.11)
        + 0.15 * math.sin(t * 0.037 + 1.7)
        + 0.10 * math.sin(t * 0.021 + 4.2)
    if n < 0 then n = 0 end
    if n > 1 then n = 1 end
    return n
end

local function currentWind()
    local raw = tryReadRealWind()
    if raw == nil then raw = proceduralWind() end
    windSmoothed = windSmoothed + (raw - windSmoothed) * WIND_SMOOTHING

    local now = getTimestampMs()
    if WindTreeSway.debug and (now - lastWindLog) > 5000 then
        lastWindLog = now
        log(string.format("Vent actuel = %.2f (source: %s)", windSmoothed,
            resolvedWindMethod or "fallback procedural"))
    end
    return windSmoothed
end

---------------------------------------------------------------------------
-- Detection des arbres
---------------------------------------------------------------------------

local instanceofErrorLogged = false
local diagnosticDumpDone = false

-- NOTE: obj:getClass():getSimpleName() n'est PAS utilisable depuis Lua ici
-- (Kahlua ne supporte pas de chainer un appel sur l'objet Class Java
-- renvoye -> ca leve une RuntimeException a chaque appel). On reste donc
-- uniquement sur des methodes normalement exposees au Lua : instanceof et
-- le nom du sprite.

local function getSpriteName(obj)
    local ok, sprite = pcall(function() return obj:getSprite() end)
    if not ok or not sprite then return nil end
    local ok2, name = pcall(function() return sprite:getName() end)
    if ok2 then return name end
    return nil
end

local function isTree(obj)
    if not obj then return false end

    local ok, res = pcall(luautils.instanceof, obj, "IsoTree")
    if ok then
        if res then return true end
    elseif not instanceofErrorLogged then
        instanceofErrorLogged = true
        log("luautils.instanceof(obj, 'IsoTree') a echoue -> " .. tostring(res))
    end

    return false
end

local function dumpNearbyClassNames(square)
    if diagnosticDumpDone then return end
    diagnosticDumpDone = true

    local list = {}
    local objects = square:getObjects()
    if objects then
        for i = 0, objects:size() - 1 do
            local obj = objects:get(i)
            local name = getSpriteName(obj) or "?"
            if isTree(obj) then name = name .. "[IsoTree=true]" end
            table.insert(list, name)
        end
    end
    log("Diagnostic: sprites trouves sur la case du joueur -> " .. table.concat(list, ", "))
end

local function collectNearbyTrees()
    local player = getPlayer()
    if not player then
        log("collectNearbyTrees: getPlayer() est nil")
        return
    end
    local square = player:getSquare()
    if not square then
        log("collectNearbyTrees: player:getSquare() est nil")
        return
    end

    dumpNearbyClassNames(square)

    local cell = getCell()
    if not cell then
        log("collectNearbyTrees: getCell() est nil")
        return
    end

    local px, py, pz = square:getX(), square:getY(), square:getZ()
    local found = {}
    local squaresScanned, squaresWithObjects, objectsSeen, treesSeen = 0, 0, 0, 0

    for dx = -UPDATE_RADIUS, UPDATE_RADIUS do
        for dy = -UPDATE_RADIUS, UPDATE_RADIUS do
            local sq = cell:getGridSquare(px + dx, py + dy, pz)
            if sq then
                squaresScanned = squaresScanned + 1
                local objects = sq:getObjects()
                if objects and objects:size() > 0 then
                    squaresWithObjects = squaresWithObjects + 1
                    for i = 0, objects:size() - 1 do
                        local obj = objects:get(i)
                        objectsSeen = objectsSeen + 1
                        if isTree(obj) then
                            treesSeen = treesSeen + 1
                            local key = tostring(obj)
                            found[key] = swayTargets[key] or {
                                obj = obj,
                                phase = (math.abs((px + dx) * 92837 + (py + dy) * 1291) % 1000) / 1000.0 * math.pi * 2,
                            }
                        end
                    end
                end
            end
        end
    end

    swayTargets = found
    log(string.format(
        "Rescan: %d cases scannees, %d avec objets, %d objets vus, %d arbres detectes",
        squaresScanned, squaresWithObjects, objectsSeen, treesSeen))
end

---------------------------------------------------------------------------
-- Application de l'oscillation (experimental, voir note en tete de fichier)
---------------------------------------------------------------------------

local OFFSET_CANDIDATES = {
    { target = "sprite", method = "setOffsetPixelsX" },
    { target = "sprite", method = "setRenderOffsetX" },
    { target = "object", method = "setRenderOffsetX" },
    { target = "object", method = "setDrawOffsetX" },
}

local function resolveCapability(entry)
    local obj = entry.obj
    local sprite = (obj.getSprite and obj:getSprite()) or nil

    for _, candidate in ipairs(OFFSET_CANDIDATES) do
        local target = (candidate.target == "sprite") and sprite or obj
        if target and target[candidate.method] then
            local ok, err = pcall(target[candidate.method], target, 0)
            if ok then
                log("Methode de decalage visuel trouvee : " .. candidate.target .. ":" .. candidate.method .. "()")
                return candidate
            else
                log("Echec test " .. candidate.target .. ":" .. candidate.method .. "() -> " .. tostring(err))
            end
        end
    end

    log("Aucune methode de decalage visuel disponible sur cette version du jeu.")
    log("=> Seule la lecture du vent reste active. Merci de transmettre ces lignes de console.txt pour corriger le hook de rendu.")
    return false
end

local function applySway(entry, wind)
    if capability == nil then
        capability = resolveCapability(entry)
    end
    if capability == false then return end

    local obj = entry.obj
    local sprite = (obj.getSprite and obj:getSprite()) or nil
    local target = (capability.target == "sprite") and sprite or obj
    if not target then return end

    local freq = BASE_FREQ_HZ + (MAX_FREQ_HZ - BASE_FREQ_HZ) * wind
    local amplitude = BASE_AMPLITUDE + (MAX_AMPLITUDE - BASE_AMPLITUDE) * wind
    local t = getTimestampMs() / 1000.0
    local offset = math.sin(t * freq * math.pi * 2 + entry.phase) * amplitude

    pcall(target[capability.method], target, offset)
end

---------------------------------------------------------------------------
-- Boucle principale
---------------------------------------------------------------------------

local function onTick()
    local now = getTimestampMs()
    if now - lastRescan > RESCAN_MS then
        lastRescan = now
        collectNearbyTrees()
    end

    local wind = currentWind()
    for _, entry in pairs(swayTargets) do
        applySway(entry, wind)
    end
end

Events.OnTick.Add(onTick)

Events.OnGameStart.Add(function()
    log("Mod charge (cible Build 42.19). Debug=" .. tostring(WindTreeSway.debug))
end)

return WindTreeSway
