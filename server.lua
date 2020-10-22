RegisterNetEvent('undead:newPlayer')
RegisterNetEvent('undead:playerKilledUndead')

local CurrentZone = (Config.DefaultZone and Config.Zones[Config.DefaultZone] or nil)

AddEventHandler('undead:newPlayer', function()
	TriggerClientEvent('undead:setZone', source, CurrentZone)
end)

AddEventHandler('undead:playerKilledUndead', function()
	--TriggerClientEvent('chat:addMessage', source, {args = {'Debug', 'Killed undead'}})
end)

function RandomZone()
	return Config.Zones[Config.ZoneRotation[math.random(#Config.ZoneRotation)]]
end

function SetZone(zone)
	if zone == 'random' then
		CurrentZone = RandomZone()
	elseif zone then
		CurrentZone = Config.Zones[zone]
	else
		CurrentZone = nil
	end

	TriggerClientEvent('undead:setZone', -1, CurrentZone)
end

function CreateZone(name, x, y, z, radius)
	Config.Zones[name] = {
		name = name,
		x = x,
		y = y,
		z = z,
		radius = radius
	}
	SetZone(name)
end

RegisterCommand('undeadzone', function(source, args, raw)
	if #args >= 5 then
		local name = args[1]
		local x = tonumber(args[2]) * 1.0
		local y = tonumber(args[3]) * 1.0
		local z = tonumber(args[4]) * 1.0
		local r = tonumber(args[5]) * 1.0
		CreateZone(name, x, y, z, r)
	else
		SetZone(args[1])
	end
end, true)

CreateThread(function()
	if Config.ZoneTimeout then
		local elapsed = Config.ZoneTimeout

		while true do
			Wait(1000)

			if elapsed >= Config.ZoneTimeout then
				SetZone('random')
				elapsed = 0
			else
				elapsed = elapsed + 1
			end
		end
	end
end)
