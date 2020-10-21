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

function DelEnt(entity)
	SetEntityAsMissionEntity(entity, true, true)
	DeleteEntity(entity)
	SetEntityAsNoLongerNeeded(entity)
end

function ClearPeds()
	for ped in EnumeratePeds() do
		if not IsPedAPlayer(ped) then
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
	if IsPedAPlayer(ped) then
		return false
	end

	if IsPedInGroup(ped) then
		return false
	end

	if not IsPedHuman(ped) then
		return false
	end

	if IsUndead(ped) then
		return false
	end

	return true
end

function ShouldCleanUp(ped1)
	if IsPedAPlayer(ped1) then
		return false
	end

	if not IsUndead(ped1) then
		return false
	end

	local x1, y1, z1 = table.unpack(GetEntityCoords(ped1))

	for _, player in ipairs(GetActivePlayers()) do
		local ped2 = GetPlayerPed(player)
		local x2, y2, z2 = table.unpack(GetEntityCoords(ped2))

		if GetDistanceBetweenCoords(x1, y1, z1, x2, y2, z2, true) <= Config.DespawnDistance then
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

AddEventHandler('onResourceStop', function(resourceName)
	if GetCurrentResourceName() == resourceName then
		ClearPeds()
		RemoveRelationshipGroup('undead')
	end
end)

CreateThread(function()
	ClearPeds()

	AddRelationshipGroup('undead')
	SetRelationshipBetweenGroups(5, `undead`, `PLAYER`)
	SetRelationshipBetweenGroups(5, `PLAYER`, `undead`)

	while true do
		Wait(0)

		local spawns = {}

		for ped in EnumeratePeds() do
			Wait(0)

			if ShouldBecomeUndead(ped) then
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

				table.insert(spawns, {ped = ped, x = x, y = y, z = z, h = h, hasLos = hasLos})

				DelEnt(ped)
			elseif ShouldCleanUp(ped) then
				DelEnt(ped)
			elseif IsPedDeadOrDying(ped) then
				SetPedAsNoLongerNeeded(ped)
			end
		end

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
					BlipAddForEntity(Config.UndeadBlip, ped)
				end

				if IsPedMale(ped) then
					Citizen.InvokeNative(0x89F5E7ADECCCB49C, ped, 'very_drunk')
				else
					Citizen.InvokeNative(0x89F5E7ADECCCB49C, ped, 'injured_general')
				end

				SetEntityMaxHealth(ped, Config.UndeadHealth)
				SetEntityHealth(ped, Config.UndeadHealth, 0)

				SetPedRelationshipGroupHash(ped, `undead`)
				SetPedCombatAttributes(ped, 46, true)
				SetPedFleeAttributes(ped, 0, 0)
				SetPedAsCop(ped, true)
				SetPedCombatMovement(ped, 3)

				TaskWanderStandard(ped, 10.0, 10)
			else
				SetEntityHealth(ped, 0.0, 0)
			end
		end
	end
end)
