-- KillCamServer: Respawn selbst steuern + Kill-Cam
-- Wer in der ARENA stirbt, respawnt nicht automatisch, sondern schaut dem Killer zu
-- und waehlt dann selbst: "Lobby" oder "Respawn" (direkt zurueck in die Arena).
-- Wer woanders stirbt (Lobby, Uebung, Duell), respawnt wie bisher automatisch.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Koerper = require(game:GetService("ServerStorage"):WaitForChild("GleicherKoerper")) -- gleiche Hitbox fuer alle

local AUTO_RESPAWN = 3     -- Sekunden bis zum automatischen Respawn ausserhalb der Arena
local MAX_ZUSCHAUEN = 45   -- nach so vielen Sekunden ohne Wahl geht's automatisch in die Lobby
local MIN_ZUSCHAUEN = 1.2  -- so lange sieht man mindestens die Kill-Cam

Players.CharacterAutoLoads = false

-- Lobby-Spawn: nur dieser SpawnLocation ist erlaubt. Alle anderen (z.B. aus eingefuegten Maps)
-- werden beim Start ausgeschaltet, damit niemand zufaellig auf einer Map spawnt.
local lobbySpawn = workspace:WaitForChild("SpawnLocation", 10)
for _, d in workspace:GetDescendants() do
	if d:IsA("SpawnLocation") and d ~= lobbySpawn then d.Enabled = false end
end
workspace.DescendantAdded:Connect(function(d)
	if d:IsA("SpawnLocation") and d ~= lobbySpawn then d.Enabled = false end
end)

local remotes = Instance.new("Folder")
remotes.Name = "KillCamRemotes"
local zeigeRemote = Instance.new("RemoteEvent")
zeigeRemote.Name = "Zeigen"
zeigeRemote.Parent = remotes
local wahlRemote = Instance.new("RemoteEvent")
wahlRemote.Name = "Wahl"
wahlRemote.Parent = remotes
remotes.Parent = ReplicatedStorage
local blitz = ReplicatedStorage:FindFirstChild("PortalBlitz")

local wartet = {} -- [Player] = {seit = os.clock(), id = n}
local zaehler = 0

-- ---------- Arena-Spawn (wie beim Portal) ----------
local function arenaSpawn()
	local arena = workspace:FindFirstChild("Arena")
	local ordner = arena and arena:FindFirstChild("ArenaSpawns")
	local liste = ordner and ordner:GetChildren() or {}
	if #liste == 0 then return nil, arena end
	return liste[math.random(1, #liste)].Position, arena
end

local function inDieArena(p, char)
	local root = char:WaitForChild("HumanoidRootPart", 5)
	local hum = char:WaitForChild("Humanoid", 5)
	if not root or not hum then return end
	local pos, arena = arenaSpawn()
	if not pos then return end
	local ziel = pos + Vector3.new(0, hum.HipHeight + root.Size.Y / 2 + 0.5, 0)
	local mitte = arena:GetPivot().Position
	local blick = Vector3.new(mitte.X, ziel.Y, mitte.Z)
	if (blick - ziel).Magnitude < 0.1 then blick = ziel + Vector3.new(0, 0, -1) end
	require(game:GetService("ServerStorage"):WaitForChild("SicherTeleport")).hin(p, char, CFrame.lookAt(ziel, blick))
	root.AssemblyLinearVelocity = Vector3.zero
end

local function respawn(p, wohin)
	if not p.Parent then return end
	wartet[p] = nil
	p.ReplicationFocus = nil
	if wohin == "respawn" then
		local conn
		conn = p.CharacterAdded:Connect(function(char)
			conn:Disconnect()
			task.defer(function()
				if blitz then blitz:FireClient(p) end
				inDieArena(p, char)
			end)
		end)
		Koerper.laden(p)
	else
		Koerper.laden(p)
	end
end

-- ---------- Wer hat mich getoetet? ----------
local function killerVon(hum, opfer)
	local tag = hum:FindFirstChild("creator")
	local k = tag and tag.Value
	if typeof(k) ~= "Instance" or k == opfer then return nil end
	if k:IsA("Player") then
		local ls = k:FindFirstChild("leaderstats")
		local lv = ls and ls:FindFirstChild("Level")
		return {char = k.Character, name = k.DisplayName, userId = k.UserId, spieler = k, level = lv and lv.Value or 1}
	elseif k:IsA("ObjectValue") and k.Value then
		-- Bots tragen den Avatar eines echten Roblox-Spielers -> dessen Profilbild zeigen
		return {char = k.Value, name = k.Name, userId = k.Value:GetAttribute("AvatarUserId") or 0, spieler = nil, level = k.Value:GetAttribute("Level") or 1}
	end
	return nil
end

-- ---------- Tod ----------
local function beobachte(p)
	if lobbySpawn then p.RespawnLocation = lobbySpawn end
	local function neuerCharakter(char)
		p.ReplicationFocus = nil
		local hum = char:WaitForChild("Humanoid", 10)
		if not hum then return end
		hum.Died:Connect(function()
			local inArena = p:GetAttribute("InArena") == true and not p:GetAttribute("UebungZone")
			if not inArena then
				task.wait(AUTO_RESPAWN)
				if p.Parent and p.Character == char then respawn(p, "lobby") end
				return
			end
			-- Kill-Cam
			zaehler += 1
			local id = zaehler
			wartet[p] = {seit = os.clock(), id = id}
			local killer = killerVon(hum, p)
			local kRoot = killer and killer.char and killer.char:FindFirstChild("HumanoidRootPart")
			if kRoot then p.ReplicationFocus = kRoot end -- damit der Killer beim Zuschauer geladen bleibt
			zeigeRemote:FireClient(p, {
				char = killer and killer.char or nil,
				spieler = killer and killer.spieler or nil,
				name = killer and killer.name or nil,
				userId = killer and killer.userId or 0,
				level = killer and killer.level or nil,
			})
			-- Sicherheit: niemand bleibt ewig tot rumliegen
			task.delay(MAX_ZUSCHAUEN, function()
				if wartet[p] and wartet[p].id == id then respawn(p, "lobby") end
			end)
		end)
	end
	p.CharacterAdded:Connect(neuerCharakter)
	if p.Character then task.spawn(neuerCharakter, p.Character) end
	task.defer(function()
		if p.Parent and not p.Character then Koerper.laden(p) end
	end)
end

wahlRemote.OnServerEvent:Connect(function(p, wohin)
	local w = wartet[p]
	if not w then return end
	if wohin ~= "lobby" and wohin ~= "respawn" then return end
	if os.clock() - w.seit < MIN_ZUSCHAUEN then return end
	respawn(p, wohin)
end)

-- ---------- Alle zurueck in die Lobby (ruft der RundenServer nach der Abstimmung auf) ----------
local alleInLobby = Instance.new("BindableFunction")
alleInLobby.Name = "AlleInLobby"
alleInLobby.OnInvoke = function(alle)
	for _, p in Players:GetPlayers() do
		local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
		local schonInLobby = hum and hum.Health > 0 and not wartet[p]
			and not p:GetAttribute("InArena") and not p:GetAttribute("UebungZone")
			and not (p.Character and p.Character:GetAttribute("Feier"))
		-- wer alleine in seiner Uebungsarena trainiert, bleibt dort (Runden gehen ihn nichts an)
		local inUebungsArena = p:GetAttribute("UebungZone") == "arena"
		-- alle == true: wirklich JEDEN neu in der Lobby spawnen (z.B. nach der Siegerfeier)
		if not inUebungsArena and (alle == true or not schonInLobby) then
			task.spawn(respawn, p, "lobby")
		end
	end
end
alleInLobby.Parent = game:GetService("ServerStorage")

-- Siegerfeier: toten Spieler sofort wiederbeleben (Kill-Cam endet), damit er mit auf die Buehne kann
local wiederbeleben = Instance.new("BindableFunction")
wiederbeleben.Name = "SpielerWiederbeleben"
wiederbeleben.OnInvoke = function(p)
	if typeof(p) == "Instance" and p:IsA("Player") and p.Parent then
		respawn(p, "lobby")
	end
	return true
end
wiederbeleben.Parent = game:GetService("ServerStorage")

Players.PlayerAdded:Connect(beobachte)
for _, p in Players:GetPlayers() do beobachte(p) end
Players.PlayerRemoving:Connect(function(p) wartet[p] = nil end)
