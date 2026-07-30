-- ModTemplate.lua
--
-- Charge en premier (avant client/ et server/), sur le client ET le serveur.
-- Sert a definir le namespace du mod et tout ce qui doit etre partage entre
-- les deux cotes (constantes, fonctions utilitaires, etc.).

ModTemplate = ModTemplate or {}
ModTemplate.VERSION = "1.0"
ModTemplate.debug = true

function ModTemplate.log(msg)
    if ModTemplate.debug then
        print("[ModTemplate] " .. tostring(msg))
    end
end

ModTemplate.log("shared charge (version " .. ModTemplate.VERSION .. ")")

-- Opt-in pour le mod dev "[Dev] Hot Reload Mods (local)" (HotReload.lua) :
-- s'il est actif a cote de ModTemplate, editer un fichier liste dans
-- reload.filelist puis lancer dev-reload.ps1 recharge le Lua en jeu sans
-- relancer PZ. Sans ce mod actif, ces 3 lignes ne font rien.
HotReload = HotReload or {}
HotReload.mods = HotReload.mods or {}
HotReload.mods["ModTemplate"] = { enabled = function() return ModTemplate.debug end }
