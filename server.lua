RegisterNetEvent("undead:newPlayer")
RegisterNetEvent("undead:playerKilledUndead")
RegisterNetEvent("undead:setZone")
RegisterNetEvent("undead:takeOrReturnMask")

local currentZone = Config.defaultZone and Config.zones[Config.defaultZone]
local zoneTimeElapsed = Config.zoneTimeout
local maskIsTaken = false
local ritualCooldownActive = false
local dbReady = false

local function getIdentifier(id, kind)
	local prefix = kind .. ":"

	for _, identifier in ipairs(GetPlayerIdentifiers(id)) do
		if string.sub(identifier, 1, #prefix) == prefix then
			return identifier
		end
	end

	return nil
end

local logColors = {
	["default"] = "\x1B[0m",
	["error"] = "\x1B[31m",
	["success"] = "\x1B[32m"
}

local function log(label, message)
	local color = logColors[label]

	if not color then
		color = logColors.default
	end

	print(string.format("%s[%s]%s %s", color, label, logColors.default, message))
end

local function initPlayer(player, name)
	local identifier = getIdentifier(player, Config.dbIdentifier)

	exports.ghmattimysql:scalar(
		"SELECT id FROM undead WHERE identifier = @identifier",
		{
			["identifier"] = identifier
		},
		function(id)
			if id then
				exports.ghmattimysql:execute(
					"UPDATE undead SET name = @name WHERE id = @id",
					{
						["name"] = name,
						["id"] = id
					},
					function(results)
						if results.affectedRows < 1 then
							log("error", "failed to update " .. identifier)
						end
					end)
			else
				exports.ghmattimysql:execute(
					"INSERT INTO undead (identifier, name) VALUES (@identifier, @name)",
					{
						["identifier"] = identifier,
						["name"] = name
					},
					function(results)
						if results.affectedRows > 0 then
							log("success", name .. " " .. identifier .. " was created")
						else
							log("error", "failed to initialize " .. name .. " " .. identifier)
						end
					end)
			end
		end)
end

local function randomZone()
	return Config.zones[Config.zoneRotation[math.random(#Config.zoneRotation)]]
end

local function setZone(zone)
	if currentZone and zone == currentZone.name then
		return
	end

	if zone == "random" then
		currentZone = randomZone()
	elseif zone then
		currentZone = Config.zones[zone]
	else
		currentZone = nil
	end

	zoneTimeElapsed = 0

	TriggerClientEvent("undead:setZone", -1, currentZone)
end

local function createZone(name, coords, radius)
	Config.zones[name] = {
		name = name,
		coords = coords,
		radius = radius
	}

	setZone(name)
end

local function updateScoreboard()
	exports.ghmattimysql:execute(
		"SELECT name, killed FROM undead WHERE name <> '' AND killed <> 0 ORDER BY killed DESC LIMIT 10",
		{},
		function(results)
			TriggerClientEvent("undead:updateScoreboard", -1, results)
		end)
	exports.ghmattimysql:scalar(
		"SELECT SUM(killed) FROM undead",
		{},
		function(total)
			TriggerClientEvent("undead:updateTotalUndeadKilled", -1, total)
		end)
end

AddEventHandler("undead:newPlayer", function()
	TriggerClientEvent("undead:setZone", source, currentZone)

	if Config.enableRitual then
		TriggerClientEvent("undead:setMaskIsTaken", source, maskIsTaken)
	end
end)

AddEventHandler("undead:playerKilledUndead", function()
	local source = source

	if not dbReady then
		return
	end

	local identifier = getIdentifier(source, Config.dbIdentifier)

	exports.ghmattimysql:execute(
		"UPDATE undead SET killed = killed + 1 WHERE identifier = @identifier",
		{
			["identifier"] = identifier
		},
		function (results)
			if results.affectedRows < 1 then
				log("error", "failed to update kill count for " .. identifier)
			end
		end)
end)

AddEventHandler("undead:setZone", function(zoneName)
	setZone(zoneName)
end)

AddEventHandler("undead:takeOrReturnMask", function(numPlayers)
	if ritualCooldownActive then
		TriggerClientEvent("undead:ritualCooldownActive", source)
		return
	end

	local totalPlayers = #GetPlayers()
	local majority = math.ceil(totalPlayers / 2) + (totalPlayers % 2 == 0 and 1 or 0)
	local numPlayersNeeded = majority - numPlayers

	if numPlayersNeeded < 1 then
		maskIsTaken = not maskIsTaken

		TriggerClientEvent("undead:setMaskIsTaken", -1, maskIsTaken)

		if maskIsTaken then
			setZone("world")
		else
			setZone()
		end
	else
		TriggerClientEvent("undead:morePlayersNeeded", source, numPlayersNeeded)
	end

	ritualCooldownActive = true

	Citizen.SetTimeout(5000, function()
		ritualCooldownActive = false
	end)
end)

AddEventHandler("playerConnecting", function(name, setKickReason, deferrals)
	if not dbReady then
		return
	end

	initPlayer(source, name)
end)

RegisterCommand("undeadzone", function(source, args, raw)
	if #args >= 5 then
		local name = args[1]
		local x = tonumber(args[2]) + 0.0
		local y = tonumber(args[3]) + 0.0
		local z = tonumber(args[4]) + 0.0
		local r = tonumber(args[5]) + 0.0
		createZone(name, vector3(x, y, z), r)
	else
		setZone(args[1])
	end
end, true)

RegisterCommand("undeadscore", function(source, args, raw)
	TriggerClientEvent("undead:toggleScoreboard", source)
end, true)

if Config.zoneTimeout then
	Citizen.CreateThread(function()
			while true do
				local t1 = os.time()
				Citizen.Wait(1000)
				local t2 = os.time()

				if zoneTimeElapsed >= Config.zoneTimeout then
					setZone("random")
					zoneTimeElapsed = 0
				else
					zoneTimeElapsed = zoneTimeElapsed + (t2 - t1)
				end
			end
	end)
end

if Config.enableDb then
	exports.ghmattimysql:transaction(
		{
			[[
			CREATE TABLE IF NOT EXISTS undead (
				id INT NOT NULL AUTO_INCREMENT,
				identifier VARCHAR(255) NOT NULL,
				name VARCHAR(255) NOT NULL,
				killed INT UNSIGNED NOT NULL DEFAULT 0,
				PRIMARY KEY (id)
			)
			]]
		},
		{},
		function(success)
			if success then
				dbReady = true

				log("success", "Connected to database")

				for _, playerId in ipairs(GetPlayers()) do
					initPlayer(playerId, GetPlayerName(playerId))
				end

				Citizen.CreateThread(function()
					while true do
						updateScoreboard()
						Citizen.Wait(1000)
					end
				end)
			else
				log("error", "Failed to connect to database")
			end
		end)
end
