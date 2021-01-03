local ZoneBlip = nil
local CurrentZone = nil
local Undead = {}

RegisterNetEvent('undead:setZone')
RegisterNetEvent('undead:updateScoreboard')
RegisterNetEvent('undead:updateTotalUndeadKilled')

local entityEnumerator = {
	__gc = function(enum)
		if enum.destructor and enum.handle then
			enum.destructor(enum.handle)
		end
		enum.destructor = nil
		enum.handle = nil
	end
}

function EnumerateEntities(firstFunc, nextFunc, endFunc)
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

function EnumerateObjects()
	return EnumerateEntities(FindFirstObject, FindNextObject, EndFindObject)
end

function EnumeratePeds()
	return EnumerateEntities(FindFirstPed, FindNextPed, EndFindPed)
end

function EnumerateVehicles()
	return EnumerateEntities(FindFirstVehicle, FindNextVehicle, EndFindVehicle)
end

function CreatePed_2(modelHash, x, y, z, heading, isNetwork, thisScriptCheck, p7, p8)
	return Citizen.InvokeNative(0xD49F9B0955C367DE, modelHash, x, y, z, heading, isNetwork, thisScriptCheck, p7, p8)
end

function SetPedDefaultOutfit(ped, p1)
	Citizen.InvokeNative(0x283978A15512B2FE, ped, p1)
end

function SetRandomOutfitVariation(ped, p1)
	Citizen.InvokeNative(0x283978A15512B2FE, ped, p1)
end

function BlipAddForEntity(blip, entity)
	return Citizen.InvokeNative(0x23f74c2fda6e7c61, blip, entity)
end

function BlipAddForRadius(blipHash, x, y, z, radius)
	return Citizen.InvokeNative(0x45F13B7E0A15C880, blipHash, x, y, z, radius)
end

function SetBlipNameFromPlayerString(blip, playerString)
	return Citizen.InvokeNative(0x9CB1A1623062F402, blip, playerString)
end

function DelEnt(entity)
	SetEntityAsMissionEntity(entity, true, true)
	DeleteEntity(entity)
	SetEntityAsNoLongerNeeded(entity)
end

function IsInZone(ped, zone)
	if not zone then
		return false
	end

	if not zone.radius then
		return true
	end

	local coords = GetEntityCoords(ped)

	return #(coords - vector3(zone.x, zone.y, coords.z)) <= zone.radius
end

function ClearPedsInZone(zone)
	for ped in EnumeratePeds() do
		if not IsPedAPlayer(ped) and IsInZone(ped, zone) then
			DelEnt(ped)
		end
	end
end

function IsUndead(ped)
	local model = GetEntityModel(ped)

	for _, undead in ipairs(UndeadPeds) do
		if model == GetHashKey(undead.model) then
			return true
		end
	end

	return false
end

function ShouldBecomeUndead(ped)
	if IsPedInGroup(ped) then
		return false
	end

	if not IsPedHuman(ped) then
		return false
	end

	if not IsInZone(ped, CurrentZone) then
		return false
	end

	return true
end

function ShouldCleanUp(ped1)
	local ped1Coords = GetEntityCoords(ped1)

	for _, player in ipairs(GetActivePlayers()) do
		local ped2 = GetPlayerPed(player)
		local ped2Coords = GetEntityCoords(ped2)

		if #(ped1Coords - ped2Coords) <= Config.DespawnDistance then
			return false
		end

		if HasEntityClearLosToEntity(ped2, ped1, 1) then
			return false
		end
	end

	return true
end

function HasAnyPlayerLos(ped)
	for _, player in ipairs(GetActivePlayers()) do
		local playerPed = GetPlayerPed(player)

		if HasEntityClearLosToEntity(playerPed, ped, 1) then
			return true
		end
	end

	return false
end

AddEventHandler('undead:setZone', function(zone)
	if CurrentZone and zone and CurrentZone.name == zone.name then
		return
	end

	if ZoneBlip then
		RemoveBlip(ZoneBlip)
	end

	ClearPedsInZone(CurrentZone)
	ClearPedsInZone(zone)

	CurrentZone = zone

	if not zone then
		return
	end

	if zone.radius then
		ZoneBlip = BlipAddForRadius(Config.ZoneBlipSprite, zone.x, zone.y, zone.z, zone.radius)
		SetBlipNameFromPlayerString(ZoneBlip, CreateVarString(10, 'LITERAL_STRING', 'Undead Infestation'))
		exports.notifications:notify('An undead infestation has appeared in ' .. zone.name)
	end
end)

AddEventHandler('onResourceStop', function(resourceName)
	if GetCurrentResourceName() == resourceName then
		if ZoneBlip then
			RemoveBlip(ZoneBlip)
		end
		ClearPedsInZone(CurrentZone)
		RemoveRelationshipGroup('undead')
	end
end)

function UpdateUndead(ped)
	if IsPedDeadOrDying(ped) then
		if Undead[ped] then
			if GetPedSourceOfDeath(ped) == PlayerPedId() then
				TriggerServerEvent('undead:playerKilledUndead')
			end

			Undead[ped] = nil
		end

		SetPedAsNoLongerNeeded(ped)
	elseif not Undead[ped] then
		Undead[ped] = true
	end

	if ShouldCleanUp(ped) then
		DelEnt(ped)
		Undead[ped] = nil
	end
end

function AddUndeadSpawn(spawns, ped)
	local x, y, z = table.unpack(GetEntityCoords(ped))
	local h = GetEntityHeading(ped)
	local hasLos = HasAnyPlayerLos(ped)

	if IsPedInAnyVehicle(ped, false) then
		local veh = GetVehiclePedIsIn(ped, false)
		local model = GetEntityModel(veh)

		if not IsThisModelATrain(model) and not IsThisModelABoat(model) then
			DelEnt(veh)
		end
	end

	if IsPedOnMount(ped) then
		DelEnt(GetMount(ped))
	end

	Wait(0)

	table.insert(spawns, {ped = ped, x = x, y = y, z = z, h = h, hasLos = hasLos})

	DelEnt(ped)
end

function CreateUndeadSpawns()
	local spawns = {}

	for ped in EnumeratePeds() do
		Wait(0)
		if not IsPedAPlayer(ped) then
			if IsUndead(ped) then
				UpdateUndead(ped)
			elseif ShouldBecomeUndead(ped) then
				AddUndeadSpawn(spawns, ped)
			end
		end
	end

	return spawns
end

function SpawnUndead(spawns)
	for _, spawn in ipairs(spawns) do
		if not DoesEntityExist(spawn.ped) and not spawn.hasLos then
			local undead = UndeadPeds[math.random(#UndeadPeds)]
			local model = GetHashKey(undead.model)

			RequestModel(model)
			while not HasModelLoaded(model) do
				Wait(0)
			end

			local ped = CreatePed_2(model, spawn.x, spawn.y, spawn.z, spawn.h, true, false, false, false)
			SetModelAsNoLongerNeeded(model)

			SetPedOutfitPreset(ped, undead.outfit)

			if Config.ShowBlips then
				BlipAddForEntity(Config.UndeadBlipSprite, ped)
			end

			local walkingStyle = Config.WalkingStyles[math.random(#Config.WalkingStyles)]
			Citizen.InvokeNative(0x923583741DC87BCE, ped, walkingStyle[1])
			Citizen.InvokeNative(0x89F5E7ADECCCB49C, ped, walkingStyle[2])

			SetEntityMaxHealth(ped, Config.UndeadHealth)
			SetEntityHealth(ped, Config.UndeadHealth, 0)

			SetPedRelationshipGroupHash(ped, `undead`)
			SetPedCombatAttributes(ped, 46, true)
			SetPedFleeAttributes(ped, 0, 0)
			SetPedAsCop(ped, true)
			SetPedCombatMovement(ped, 3)

			TaskWanderStandard(ped, 10.0, 10)

			Undead[ped] = true
		end
	end
end

local ScoreboardIsOpen = false

RegisterCommand('undeadscore', function(source, args, raw)
	ScoreboardIsOpen = not ScoreboardIsOpen

	SendNUIMessage({
		type = 'toggleScoreboard'
	})
end, false)

AddEventHandler('undead:updateScoreboard', function(results)
	SendNUIMessage({
		type = 'updateScoreboard',
		scores = json.encode(results)
	})
end)

AddEventHandler('undead:updateTotalUndeadKilled', function(total)
	SendNUIMessage({
		type = 'updateTotalUndeadKilled',
		total = total
	})
end)

CreateThread(function()
	AddRelationshipGroup('undead')
	SetRelationshipBetweenGroups(5, `undead`, `PLAYER`)
	SetRelationshipBetweenGroups(5, `PLAYER`, `undead`)
	SetRelationshipBetweenGroups(5, `COP`, `COP`)

	TriggerServerEvent('undead:newPlayer')

	while true do
		Wait(0)

		if CurrentZone then
			local spawns = CreateUndeadSpawns()
			SpawnUndead(spawns)
		end
	end
end)
