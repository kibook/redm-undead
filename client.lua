local zoneBlip
local currentZone
local undead = {}
local maskIsTaken
local maskBlip

RegisterNetEvent("undead:setZone")
RegisterNetEvent("undead:updateScoreboard")
RegisterNetEvent("undead:updateTotalUndeadKilled")
RegisterNetEvent("undead:toggleScoreboard")
RegisterNetEvent("undead:setMaskIsTaken")
RegisterNetEvent("undead:morePlayersNeeded")
RegisterNetEvent("undead:ritualCooldownActive")

local entityEnumerator = {
	__gc = function(enum)
		if enum.destructor and enum.handle then
			enum.destructor(enum.handle)
		end
		enum.destructor = nil
		enum.handle = nil
	end
}

local function enumerateEntities(firstFunc, nextFunc, endFunc)
	return coroutine.wrap(function()
		local iter, id = firstFunc()

		if not id or id == 0 then
			endFunc(iter)
			return
		end

		local enum = {handle = iter, destructor = endFunc}
		setmetatable(enum, entityEnumerator)

		local next = true
		repeat
			coroutine.yield(id)
			next, id = nextFunc(iter)
		until not next

		enum.destructor, enum.handle = nil, nil
		endFunc(iter)
	end)
end

local function enumeratePeds()
	return enumerateEntities(FindFirstPed, FindNextPed, EndFindPed)
end

local function delEnt(entity)
	SetEntityAsMissionEntity(entity, true, true)
	DeleteEntity(entity)
	SetEntityAsNoLongerNeeded(entity)
end

local function isInZone(ped, zone)
	if not zone then
		return false
	end

	if not zone.radius then
		return true
	end

	local coords = GetEntityCoords(ped)

	return #(coords.xy - zone.coords.xy) <= zone.radius
end

local function isUndead(ped)
	local model = GetEntityModel(ped)

	for _, undead in ipairs(UndeadPeds) do
		if model == GetHashKey(undead.model) then
			return true
		end
	end

	return false
end

local function shouldBecomeUndead(ped)
	if not IsPedHuman(ped) then
		return false
	end

	if not isInZone(ped, currentZone) then
		return false
	end

	if GetEntityPopulationType(ped) == 8 then
		return false
	end

	if IsPedInAnyVehicle(ped, false) then
		local veh = GetVehiclePedIsIn(ped, false)
		local model = GetEntityModel(veh)

		if IsThisModelATrain(model) or IsThisModelABoat(model) then
			return false
		end
	end

	return true
end

local function shouldCleanUp(ped1)
	local ped1Coords = GetEntityCoords(ped1)

	for _, player in ipairs(GetActivePlayers()) do
		local ped2 = GetPlayerPed(player)
		local ped2Coords = GetEntityCoords(ped2)

		if #(ped1Coords - ped2Coords) <= Config.despawnDistance then
			return false
		end

		if HasEntityClearLosToEntity(ped2, ped1, 1) then
			return false
		end
	end

	return true
end

local function hasAnyPlayerLos(ped)
	for _, player in ipairs(GetActivePlayers()) do
		local playerPed = GetPlayerPed(player)

		if HasEntityClearLosToEntity(playerPed, ped, 1) then
			return true
		end
	end

	return false
end

local function updateUndead(ped)
	if IsPedDeadOrDying(ped) then
		if undead[ped] then
			if GetPedSourceOfDeath(ped) == PlayerPedId() then
				TriggerServerEvent("undead:playerKilledUndead")
			end

			undead[ped] = nil
		end

		SetPedAsNoLongerNeeded(ped)
	elseif not undead[ped] then
		undead[ped] = true
	end

	if shouldCleanUp(ped) then
		delEnt(ped)
		undead[ped] = nil
	end
end

local function addUndeadSpawn(spawns, ped)
	local coords = GetEntityCoords(ped)
	local heading = GetEntityHeading(ped)
	local hasLos = hasAnyPlayerLos(ped)

	if IsPedInAnyVehicle(ped, false) then
		delEnt(GetVehiclePedIsIn(ped, false))
	end

	if IsPedOnMount(ped) then
		delEnt(GetMount(ped))
	end

	table.insert(spawns, {ped = ped, coords = coords, heading = heading, hasLos = hasLos})

	delEnt(ped)
end

local function createUndeadSpawns()
	local spawns = {}

	for ped in enumeratePeds() do
		if not IsPedAPlayer(ped) then
			if isUndead(ped) then
				updateUndead(ped)
			elseif shouldBecomeUndead(ped) then
				addUndeadSpawn(spawns, ped)
			end
		end
		Citizen.Wait(0)
	end

	return spawns
end

local function spawnUndead(spawns)
	for _, spawn in ipairs(spawns) do
		if not DoesEntityExist(spawn.ped) and not spawn.hasLos then
			local undead = UndeadPeds[math.random(#UndeadPeds)]
			local model = GetHashKey(undead.model)

			RequestModel(model)
			while not HasModelLoaded(model) do
				Citizen.Wait(0)
			end

			local ped = CreatePed_2(model, spawn.coords, spawn.heading, true, false, false, false)
			SetModelAsNoLongerNeeded(model)

			SetPedOutfitPreset(ped, undead.outfit)

			if Config.showBlips then
				BlipAddForEntity(Config.undeadBlipSprite, ped)
			end

			local walkingStyle = Config.walkingStyles[math.random(#Config.walkingStyles)]
			Citizen.InvokeNative(0x923583741DC87BCE, ped, walkingStyle[1])
			Citizen.InvokeNative(0x89F5E7ADECCCB49C, ped, walkingStyle[2])

			SetEntityMaxHealth(ped, Config.undeadHealth)
			SetEntityHealth(ped, Config.undeadHealth, 0)

			SetPedRelationshipGroupHash(ped, `undead`)
			SetPedCombatAttributes(ped, 46, true)
			SetPedFleeAttributes(ped, 0, 0)
			SetPedAsCop(ped, true)
			SetPedCombatMovement(ped, 3)

			TaskWanderStandard(ped, 10.0, 10)

			undead[ped] = true
		end
	end
end

local function getNumberOfPlayersInCircle()
	local numPlayers = 0

	for _, playerId in ipairs(GetActivePlayers()) do
		local playerCoords = GetEntityCoords(GetPlayerPed(playerId))

		if #(playerCoords - Config.maskCoords) < 4.0 then
			numPlayers = numPlayers + 1
		end
	end

	return numPlayers
end

AddEventHandler("undead:setZone", function(zone)
	if currentZone and zone and currentZone.name == zone.name then
		return
	end

	if zoneBlip then
		RemoveBlip(zoneBlip)
	end

	currentZone = zone

	if not zone then
		return
	end

	if zone.radius then
		zoneBlip = BlipAddForRadius(Config.zoneBlipSprite, zone.coords, zone.radius)

		SetBlipNameFromPlayerString(zoneBlip, CreateVarString(10, "LITERAL_STRING", "Undead Infestation"))

		exports.uifeed:showSimpleRightText("An undead infestation has appeared in " .. zone.name, 5000)
	end
end)

AddEventHandler("onResourceStop", function(resourceName)
	if GetCurrentResourceName() == resourceName then
		if zoneBlip then
			RemoveBlip(zoneBlip)
		end

		RemoveRelationshipGroup("undead")

		if Config.enableRitual then
			RemoveBlip(maskBlip)
			RemoveImap(`undead_ritual_circle`)
			RemoveImap(`undead_ritual_mask`)
		end
	end
end)

AddEventHandler("undead:updateScoreboard", function(results)
	SendNUIMessage({
		type = "updateScoreboard",
		scores = json.encode(results)
	})
end)

AddEventHandler("undead:updateTotalUndeadKilled", function(total)
	SendNUIMessage({
		type = "updateTotalUndeadKilled",
		total = total
	})
end)

AddEventHandler("undead:toggleScoreboard", function()
	SendNUIMessage({
		type = "toggleScoreboard"
	})
end)

local maskPrompt = Uiprompt:new(`INPUT_DYNAMIC_SCENARIO`, "Take Mask", nil, false)
maskPrompt:setHoldMode(true)
maskPrompt:setOnHoldModeJustCompleted(function()
	TriggerServerEvent("undead:takeOrReturnMask", getNumberOfPlayersInCircle())
end)

AddEventHandler("undead:setMaskIsTaken", function(isTaken)
	if maskIsTaken ~= nil then
		local subtitle = "The ~COLOR_RED~undead~COLOR_WHITE~ "

		if isTaken then
			subtitle = subtitle .. "walk the earth"
		else
			subtitle = subtitle .. "have returned to rest"
		end

		exports.uifeed:showTopNotification("~COLOR_GREEN~The ritual~COLOR_WHITE~ has been performed", subtitle, 5000)
	end

	maskIsTaken = isTaken

	if maskIsTaken then
		RemoveImap(`undead_ritual_mask`)
		maskPrompt:setText("Return Mask")
	else
		RequestImap(`undead_ritual_mask`)
		maskPrompt:setText("Take Mask")
	end
end)

AddEventHandler("undead:morePlayersNeeded", function(numPlayersNeeded)
	exports.uifeed:showObjective("~COLOR_RED~" .. numPlayersNeeded .. " more " .. (numPlayersNeeded == 1 and "player" or "players") .. "~COLOR_WHITE~ must stand in the circle to perform ~COLOR_GREEN~the ritual~COLOR_WHITE~.", 5000)
end)

AddEventHandler("undead:ritualCooldownActive", function()
	exports.uifeed:showObjective("Someone is already performing ~COLOR_GREEN~the ritual~COLOR_WHITE~.", 5000)
end)

Citizen.CreateThread(function()
	AddRelationshipGroup("undead")
	SetRelationshipBetweenGroups(5, `undead`, `PLAYER`)
	SetRelationshipBetweenGroups(5, `PLAYER`, `undead`)
	SetRelationshipBetweenGroups(5, `COP`, `COP`)

	TriggerServerEvent("undead:newPlayer")

	while true do
		if currentZone and isInZone(PlayerPedId(), currentZone) then
			local spawns = createUndeadSpawns()
			spawnUndead(spawns)

			Citizen.Wait(0)
		else
			Citizen.Wait(2000)
		end
	end
end)

Citizen.CreateThread(function()
	if Config.enableRitual then
		RequestImap(`undead_ritual_circle`)
		RequestImap(`undead_ritual_mask`)

		maskBlip = BlipAddForCoord(1664425300, Config.maskBlipCoords)
		SetBlipSprite(maskBlip, Config.maskBlipSprite)
		SetBlipNameFromPlayerString(maskBlip, CreateVarString(10, "LITERAL_STRING", Config.maskBlipName))

		while true do
			local coords = GetEntityCoords(PlayerPedId())

			if #(coords - Config.maskCoords) < 1.5 then
				if not maskPrompt:isEnabled() then
					maskPrompt:setEnabledAndVisible(true)
				end

				maskPrompt:handleEvents()

				Citizen.Wait(0)
			else
				if maskPrompt:isEnabled() then
					maskPrompt:setEnabledAndVisible(false)
				end

				Citizen.Wait(1000)
			end
		end
	end
end)
