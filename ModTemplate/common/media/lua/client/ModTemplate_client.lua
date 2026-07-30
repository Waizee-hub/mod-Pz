-- ModTemplate_client.lua
--
-- Charge apres shared/. Exemple minimal mais fonctionnel : ajoute une entree
-- dans le menu clic-droit (sol) qui fait dire une phrase au joueur. Sert a
-- verifier facilement en jeu que le mod est bien charge et actif.

local function onSayHello(player)
    player:Say("Hello depuis ModTemplate !")
    ModTemplate.log("Action 'Dire bonjour' declenchee par " .. player:getUsername())
end

local function onFillWorldObjectContextMenu(playerIndex, context, worldobjects)
    local player = getSpecificPlayer(playerIndex)
    if not player then return end

    context:addOption("ModTemplate : dire bonjour", player, onSayHello)
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)

Events.OnGameStart.Add(function()
    ModTemplate.log("client charge. Clic droit au sol -> 'ModTemplate : dire bonjour' pour tester.")
end)
