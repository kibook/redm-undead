RegisterNetEvent('undead:newPlayer')
RegisterNetEvent('undead:playerKilledUndead')

local CurrentZone = (Config.DefaultZone and Config.Zones[Config.DefaultZone] or nil)

function GetIdentifier(id, kind)
	local identifiers = {}

	for _, identifier in ipairs(GetPlayerIdentifiers(id)) do
		local prefix = kind .. ':'
		local len = string.len(prefix)
		if string.sub(identifier, 1, len) == prefix then
			return string.sub(identifier, len + 1)
		end
	end

	return nil
end

local LogColors = {
	['name'] = '\x1B[31m',
	['default'] = '\x1B[0m',
	['error'] = '\x1B[31m',
	['success'] = '\x1B[32m'
}

function Log(label, message)
	local color = LogColors[label]

	if not color then
		color = LogColors.default
	end

	print(string.format('%s[Undead] %s[%s]%s %s', LogColors.name, color, label, LogColors.default, message))
end

function InitPlayer(player, name)
	local license = GetIdentifier(player, 'license')

	MySQL.Async.fetchScalar(
		'SELECT id FROM undead WHERE id = @id',
		{
			['id'] = license
		},
		function(id)
			if id then
				MySQL.Async.execute(
					'UPDATE undead SET name = @name WHERE id = @id',
					{
						['name'] = name,
						['id'] = license
					},
					function(affectedRows)
						if affectedRows < 1 then
							Log('error', 'failed to update ' .. license)
						end
					end)
			else
				MySQL.Async.execute(
					'INSERT INTO undead (id, name, killed) VALUES (@id, @name, 0)',
					{
						['id'] = license,
						['name'] = name
					},
					function(affectedRows)
						if affectedRows > 0 then
							Log('success', name .. ' ' .. license .. ' was created')
						else
							Log('error', 'failed to initialize ' .. name .. ' ' .. license)
						end
					end)
			end
		end)
end

AddEventHandler('undead:newPlayer', function()
	TriggerClientEvent('undead:setZone', source, CurrentZone)
end)

AddEventHandler('undead:playerKilledUndead', function()
	if not Config.EnableSql then
		return
	end

	local player = source
	local license = GetIdentifier(player, 'license')

	MySQL.ready(function()
		MySQL.Async.execute(
			'UPDATE undead SET killed = killed + 1 WHERE id = @id',
			{
				['id'] = license
			},
			function (affectedRows)
				if affectedRows < 1 then
					Log('error', 'failed to update kill count for ' .. license)
				end
			end)
	end)
end)

AddEventHandler('playerConnecting', function(name, setKickReason, deferrals)
	if not Config.EnableSql then
		return
	end

	local player = source
	MySQL.ready(function()
		InitPlayer(player, name)
	end)
end)

AddEventHandler('onResourceStart', function()
	if not Config.EnableSql then
		return
	end

	MySQL.ready(function()
		for _, playerId in ipairs(GetPlayers()) do
			InitPlayer(playerId, GetPlayerName(playerId))
		end
	end)
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

function UpdateScoreboards()
	MySQL.ready(function()
		MySQL.Async.fetchAll(
			"SELECT name, killed FROM undead WHERE name <> '' AND killed <> 0 ORDER BY killed DESC LIMIT 10",
			{},
			function(results)
				TriggerClientEvent('undead:updateScoreboard', -1, results)
			end)
		MySQL.Async.fetchScalar(
			"SELECT SUM(killed) FROM undead",
			{},
			function(total)
				TriggerClientEvent("undead:updateTotalUndeadKilled", -1, total)
			end)
	end)
end

if Config.ZoneTimeout then
	CreateThread(function()
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
	end)
end

if Config.EnableSql then
	CreateThread(function()
		while true do
			Wait(1000)
			UpdateScoreboards()
		end
	end)
end
