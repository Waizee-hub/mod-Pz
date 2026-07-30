-- ModTemplate_server.lua
--
-- Charge en dernier, uniquement quand une partie demarre (solo ou serveur
-- dedie). A utiliser pour la logique cote serveur : spawns, evenements
-- meteo/agriculture, etc.

Events.OnServerStarted.Add(function()
    ModTemplate.log("server charge (OnServerStarted).")
end)
