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

function BlipAddForCoord(blipHash, x, y, z)
	return Citizen.InvokeNative(0x554D9D53F696D002, blipHash, x, y, z)
end

function SetBlipNameFromPlayerString(blip, playerString)
	return Citizen.InvokeNative(0x9CB1A1623062F402, blip, playerString)
end
