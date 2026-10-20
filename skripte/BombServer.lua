-- erst warten, bis MapVerteiler die Maps an ihren Platz geschoben hat
if not workspace:GetAttribute("MapsVerteilt") then workspace:GetAttributeChangedSignal("MapsVerteilt"):Wait() end
-- BombServer: Aufheben, Countdown, Wurf, Explosion und Schaden (alles serverseitig)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("BombConfig"))
local Sounds = require(ReplicatedStorage:WaitForChild("SoundConfig"))
local Remotes = ReplicatedStorage:WaitForChild("BombRemotes")
local ThrowRemote = Remotes:WaitForChild("Throw")
local EffectRemote = Remotes:WaitForChild("ExplosionEffect")
local ThrowAnimRemote = Remotes:WaitForChild("ThrowAnim")
local HitMarkerRemote = Remotes:WaitForChild("HitMarker")
local AimRemote = Remotes:WaitForChild("Aim")

local BOMB_TAG = "Bomb"
local SchadenLog = require(game:GetService("ServerStorage"):WaitForChild("SchadenLog"))

local PhysicsService = game:GetService("PhysicsService")
pcall(function() PhysicsService:RegisterCollisionGroup("Bomben") end)
pcall(function() PhysicsService:RegisterCollisionGroup("Charaktere") end)
PhysicsService:CollisionGroupSetCollidable("Bomben", "Charaktere", false)

local bombState = {}   -- [Model] = Zustand
local heldBy = {}      -- [Player] = Model
local lastThrow = {}   -- [Player] = Zeit

local setupBomb -- vorwaerts deklariert

local function getBody(bomb)
	return bomb:FindFirstChild("Body")
end

local function setTimerText(bomb, n)
	bomb:SetAttribute("Countdown", n)
	local body = getBody(bomb)
	local gui = body and body:FindFirstChild("TimerGui")
	local bg = gui and gui:FindFirstChild("Hintergrund")
	local label = bg and bg:FindFirstChild("Zeit")
	if label then
		label.Text = tostring(n)
		local rot = n <= 3
		label.TextColor3 = rot and Color3.fromRGB(255, 70, 70) or Color3.new(1, 1, 1)
		local ring = bg:FindFirstChild("Ring")
		if ring then ring.Color = rot and Color3.fromRGB(255, 70, 70) or Color3.new(1, 1, 1) end
	end
end

-- held = true: am Spieler; false: frei/physikalisch
local function setPhysics(bomb, held)
	for _, p in bomb:GetDescendants() do
		if p:IsA("BasePart") then
			p.CollisionGroup = "Bomben"
			p.Anchored = false
			p.Massless = held or p.Name ~= "Body"
			p.CanCollide = (not held) and p.Name == "Body"
		end
	end
end

local function getHand(char)
	return char:FindFirstChild("RightHand"), char:FindFirstChild("Right Arm")
end

-- "Akteur" = echter Player ODER Bot (ObjectValue in ServerStorage.BotAkteure, Value = Charakter)
local function istSpieler(actor)
	return typeof(actor) == "Instance" and actor:IsA("Player")
end
local function charOf(actor)
	if typeof(actor) ~= "Instance" then return nil end
	if actor:IsA("Player") then return actor.Character end
	if actor:IsA("ObjectValue") then return actor.Value end
	return nil
end

-- Animationsphase ("aushol", "wurf", "voll", "abbruch") an alle ausser den Werfer senden
local function sendeAnim(player, char, phase)
	if Config.THROW_ANIMATION_ID ~= "" or not char then return end
	for _, anderer in Players:GetPlayers() do
		if anderer ~= player then ThrowAnimRemote:FireClient(anderer, char, phase) end
	end
end

-- Bombe aus der Hand loesen (Wurf, Tod, Verlassen, Explosion in der Hand)
local function release(bomb, geworfen)
	local state = bombState[bomb]
	if not state then return end
	if state.weld then state.weld:Destroy(); state.weld = nil end
	for _, c in state.conns do c:Disconnect() end
	table.clear(state.conns)
	local holder = state.holder
	if holder and state.aimStart and not geworfen then
		sendeAnim(holder, charOf(holder), "abbruch") -- Arm nicht in der Aushol-Pose haengen lassen
	end
	state.aimStart = nil
	if holder then
		if heldBy[holder] == bomb then heldBy[holder] = nil end
		holder:SetAttribute("HasBomb", false)
	end
	state.holder = nil
	if bomb.Parent then
		setPhysics(bomb, false)
		local body = getBody(bomb)
		if body and body:IsDescendantOf(workspace) then
			pcall(function() body:SetNetworkOwner(nil) end)
		end
	end
end

-- ============ Neue Bombe faellt vom Himmel ============
local RunService = game:GetService("RunService")
local FALL_HOEHE = 90     -- Studs ueber dem Startplatz
local FALL_ZEIT = 1.2     -- Sekunden bis zum Aufprall

local function landeEffekt(bodenPos)
	-- Staubring, der sich ausbreitet
	local ring = Instance.new("Part")
	ring.Name = "BombenLandung"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored, ring.CanCollide, ring.CanQuery, ring.CanTouch = true, false, false, false
	ring.Material = Enum.Material.SmoothPlastic
	ring.Color = Color3.fromRGB(235, 225, 205)
	ring.Transparency = 0.25
	ring.Size = Vector3.new(0.3, 2, 2)
	ring.CFrame = CFrame.new(bodenPos + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = workspace
	TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = Vector3.new(0.1, 17, 17), Transparency = 1}):Play()
	game:GetService("Debris"):AddItem(ring, 0.6)
	-- Staubwolke
	local a = Instance.new("Attachment")
	a.WorldPosition = bodenPos + Vector3.new(0, 0.5, 0)
	a.Parent = workspace.Terrain
	local staub = Instance.new("ParticleEmitter")
	staub.Texture = "rbxasset://textures/particles/smoke_main.dds"
	staub.Color = ColorSequence.new(Color3.fromRGB(225, 215, 195))
	staub.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1)})
	staub.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 4.5)})
	staub.Lifetime = NumberRange.new(0.5, 0.9)
	staub.Speed = NumberRange.new(10, 18)
	staub.SpreadAngle = Vector2.new(180, 8)
	staub.Drag = 5
	staub.EmissionDirection = Enum.NormalId.Top
	staub.Rate = 0
	staub.Parent = a
	staub:Emit(22)
	game:GetService("Debris"):AddItem(a, 1.5)
	-- dumpfer Aufprall-Sound
	local s = Instance.new("Sound")
	s.SoundId = (Sounds.LANDUNG and Sounds.LANDUNG.id) or ""
	s.Volume = 1.4
	s.PlaybackSpeed = 0.6
	s.RollOffMaxDistance = 150
	s.Parent = a
	s:Play()
end

local function bombeFallenLassen(neu, spawnCF, ordner, fertig)
	-- Unterwasser-Map: Bombe sinkt ganz langsam von der Wasseroberflaeche runter (mit Blubberblasen)
	local FALL_HOEHE, FALL_ZEIT = FALL_HOEHE, FALL_ZEIT
	local map = ordner and ordner.Parent
	local sinkt = false
	if map and map:GetAttribute("Unterwasser") and map:GetAttribute("WasserOberflaeche") then
		local h = map:GetAttribute("WasserOberflaeche") - spawnCF.Position.Y - 4
		if h > 10 then
			sinkt = true
			FALL_HOEHE = h
			FALL_ZEIT = h / (map:GetAttribute("BombenSinkTempo") or 11)
			neu:SetAttribute("Blubbern", true)
		end
	end
	-- waehrend des Falls: alles verankert, nicht aufhebbar, keine Kollision
	local vorher = {}
	for _, p in neu:GetDescendants() do
		if p:IsA("BasePart") then
			vorher[p] = {p.Anchored, p.CanCollide}
			p.Anchored, p.CanCollide = true, false
		end
	end
	local body = getBody(neu)
	local prompt = body and body:FindFirstChild("PickupPrompt")
	if prompt then prompt.Enabled = false end

	-- Boden unter dem Startplatz suchen (fuer Schatten + Staub)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {neu}
	params.RespectCanCollide = true
	local treffer = workspace:Raycast(spawnCF.Position + Vector3.new(0, 1, 0), Vector3.new(0, -20, 0), params)
	local bodenPos = treffer and treffer.Position or (spawnCF.Position - Vector3.new(0, 3.2, 0))

	-- Schatten auf dem Boden, der beim Fallen groesser und dunkler wird
	local schatten = Instance.new("Part")
	schatten.Name = "BombenSchatten"
	schatten.Shape = Enum.PartType.Cylinder
	schatten.Anchored, schatten.CanCollide, schatten.CanQuery, schatten.CanTouch = true, false, false, false
	schatten.Material = Enum.Material.SmoothPlastic
	schatten.Color = Color3.new(0, 0, 0)
	schatten.Transparency = 0.9
	schatten.Size = Vector3.new(0.1, 1.5, 1.5)
	schatten.CFrame = CFrame.new(bodenPos + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90))
	schatten.Parent = workspace

	neu:PivotTo(spawnCF * CFrame.new(0, FALL_HOEHE, 0))
	neu.Parent = ordner
	-- Unterwasser: Bombe ist schon beim Runtersinken aufhebbar (nicht erst nach der Landung)
	local schonFertig = false
	if sinkt then
		schonFertig = true
		fertig()
	end
	local function aufgehoben()
		local st = bombState[neu]
		return st ~= nil and (st.owner ~= nil or st.exploded)
	end

	local start = os.clock()
	local phase = "fall"
	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not neu.Parent then
			conn:Disconnect(); schatten:Destroy()
			return
		end
		if schonFertig and aufgehoben() then
			-- beim Sinken geschnappt: Fall-Animation sofort beenden
			conn:Disconnect(); schatten:Destroy()
			neu:SetAttribute("Blubbern", false)
			return
		end
		local t = os.clock() - start
		if phase == "fall" then
			local k = math.min(t / FALL_ZEIT, 1)
			local y, dreh
			if sinkt then
				-- gleichmaessig langsam sinken, leicht hin und her schaukeln
				local e = 1 - (1 - k) ^ 1.3
				y = FALL_HOEHE * (1 - e)
				local w = t * 1.6
				dreh = CFrame.new(math.sin(w) * 1.2 * (1 - k), 0, math.cos(w * 0.8) * 0.8 * (1 - k))
					* CFrame.Angles(math.sin(w * 1.3) * 0.18, t * 0.6, math.cos(w) * 0.18)
			else
				y = FALL_HOEHE * (1 - k * k) -- beschleunigt wie echte Schwerkraft
				dreh = CFrame.Angles(math.sin(k * 9) * 0.25 * (1 - k), (1 - k) * math.pi * 4, 0)
			end
			neu:PivotTo(spawnCF * CFrame.new(0, y, 0) * dreh)
			local d = 1.5 + 6 * k
			schatten.Size = Vector3.new(0.1, d, d)
			schatten.Transparency = 0.9 - 0.45 * k
			if k >= 1 then
				neu:SetAttribute("Blubbern", false)
				phase = "huepf"
				start = os.clock()
				landeEffekt(bodenPos)
			end
		else
			-- kleiner Doppel-Huepfer nach dem Aufprall
			local y
			if t < 0.2 then y = 2.4 * math.sin(math.pi * t / 0.2)
			elseif t < 0.34 then y = 0.8 * math.sin(math.pi * (t - 0.2) / 0.14)
			else y = 0 end
			local wackel = CFrame.Angles(0, 0, math.sin(t * 40) * 0.12 * math.max(0, 1 - t / 0.4))
			neu:PivotTo(spawnCF * CFrame.new(0, y, 0) * wackel)
			if t >= 0.4 then
				conn:Disconnect()
				neu:PivotTo(spawnCF)
				TweenService:Create(schatten, TweenInfo.new(0.3), {Transparency = 1}):Play()
				game:GetService("Debris"):AddItem(schatten, 0.35)
				for p, w in vorher do
					if p.Parent then p.Anchored, p.CanCollide = w[1], w[2] end
				end
				if not schonFertig then fertig() end
			end
		end
	end)
end

-- ---------- Zufaelliger Platz fuer eine Bombe ----------
-- Jede Map hat einen Ordner "BombenPunkte" mit erreichbaren, flachen Orten (im Editor berechnet).
-- Eine Bombe erscheint an einem zufaelligen davon, nicht zu nah an anderen Bomben oder Spielern.
local BOMBE_ABSTAND = 22
local SPIELER_ABSTAND = 12
local function zufallsCF(ordner, vorlage, ausser)
	local map = ordner and ordner.Parent
	local punkte = map and map:FindFirstChild("BombenPunkte")
	if not punkte then return nil end
	local liste = punkte:GetChildren()
	if #liste == 0 then return nil end
	-- Hoehe: Unterkante der Bombe auf den Boden
	local cf, size = vorlage:GetBoundingBox()
	local pivot = vorlage:GetPivot()
	local offY = pivot.Position.Y - (cf.Position.Y - size.Y / 2) + 0.05
	local andere = {}
	for _, b in ordner:GetChildren() do
		if b ~= ausser and b:IsA("Model") then table.insert(andere, b:GetPivot().Position) end
	end
	local leute = {}
	for _, h in workspace:GetDescendants() do
		if h:IsA("Humanoid") and h.Health > 0 and h.Parent:FindFirstChild("HumanoidRootPart") then
			table.insert(leute, h.Parent.HumanoidRootPart.Position)
		end
	end
	local function flach(a, b) return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude end
	-- zufaellige Reihenfolge, erster passender Punkt gewinnt
	for i = #liste, 2, -1 do
		local j = math.random(1, i)
		liste[i], liste[j] = liste[j], liste[i]
	end
	local notfall
	for _, p in liste do
		local ok = true
		for _, q in andere do if flach(p.Position, q) < BOMBE_ABSTAND then ok = false break end end
		if ok then
			notfall = notfall or p
			for _, q in leute do if flach(p.Position, q) < SPIELER_ABSTAND then ok = false break end end
		end
		if ok then return pivot.Rotation + (p.Position + Vector3.new(0, offY, 0)) end
	end
	local p = notfall or liste[1]
	return pivot.Rotation + (p.Position + Vector3.new(0, offY, 0))
end

local kuerbisDesign -- (weiter unten definiert)
-- Soll eine Bombe in diesem Ordner ein Kuerbis sein?
-- Ja waehrend der Kuerbis-Welle (ALLE Bomben) und immer auf Maps mit "KuerbisBomben" (Spukfriedhof),
-- aber NICHT im Modus Chaos-Bomben (da bleiben es Spezial-Bomben).
local function sollKuerbisIn(inst)
	local map = inst
	while map and map ~= workspace and not (map:IsA("Model") and map:GetAttribute("MapId")) do map = map.Parent end
	if map == workspace then map = nil end
	local rs = ReplicatedStorage:FindFirstChild("Runde")
	if map and rs and rs:GetAttribute("Modus") == "chaos" then return false end
	if map and map:GetAttribute("KuerbisBomben") then return true end
	local h = ReplicatedStorage:FindFirstChild("Halloween")
	return h ~= nil and h:GetAttribute("KuerbisZeit") == true
end
local function scheduleRespawn(state)
	if Config.RESPAWN_TIME <= 0 or not state.template or state.keinRespawn then return end
	task.delay(Config.RESPAWN_TIME, function()
		-- Ordner gibt es nicht mehr (z.B. Uebungsarena wurde abgebaut) -> keine neue Bombe
		if state.ordner and state.ordner ~= workspace and not state.ordner:IsDescendantOf(game) then return end
		local neu = state.template:Clone()
		-- zurueck in denselben Ordner (z.B. Bomben-Ordner der Map), nicht lose in den Workspace
		local ordner = state.ordner
		ordner = (ordner and ordner:IsDescendantOf(workspace)) and ordner or workspace
		state.spawnCF = zufallsCF(ordner, state.template) or state.spawnCF -- jedes Mal ein neuer, zufaelliger Ort
		-- Kuerbis-Welle / Halloween-Map: schon beim Runterfallen ein Kuerbis
		if sollKuerbisIn(ordner) then
			neu:PivotTo(state.spawnCF)
			pcall(kuerbisDesign, neu, "kuerbis")
			neu:SetAttribute("EventKuerbis", true)
		end
		bombeFallenLassen(neu, state.spawnCF, ordner, function()
			setupBomb(neu, state.template, state.spawnCF)
		end)
	end)
end

local Todesflug = require(game:GetService("ServerStorage"):WaitForChild("Todesflug"))

-- Team Deathmatch: Teamkollegen verletzen sich nicht gegenseitig (sich selbst schon)
local function teamVonChar(model)
	if not model then return nil end
	local t = model:GetAttribute("Team")
	if t then return t end
	local p = Players:GetPlayerFromCharacter(model)
	if p then return p:GetAttribute("Team") end
	local ordner = game:GetService("ServerStorage"):FindFirstChild("BotAkteure")
	if ordner then
		for _, ak in ordner:GetChildren() do
			if ak:IsA("ObjectValue") and ak.Value == model then return ak:GetAttribute("Team") end
		end
	end
	return nil
end
local function teamKollege(attacker, model)
	local rs = game:GetService("ReplicatedStorage"):FindFirstChild("Runde")
	if not rs or rs:GetAttribute("Modus") ~= "tdm" then return false end
	local ac = attacker and charOf(attacker)
	if ac == model then return false end
	local t1 = (typeof(attacker) == "Instance" and attacker:GetAttribute("Team")) or teamVonChar(ac)
	local t2 = teamVonChar(model)
	return t1 ~= nil and t1 == t2
end

local function applyDamage(pos, attacker, bomb, radius, faktor)
	local R = radius or Config.EXPLOSION_RADIUS
	faktor = faktor or 1
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = bomb and {bomb} or {}
	local parts = workspace:GetPartBoundsInRadius(pos, R, params)
	local getroffen = {} -- jeder Humanoid nur einmal
	local gegner = {} -- getroffene Gegner (fuer Eis-Bombe usw.)
	local trefferAndere, kill = false, false
	for _, part in parts do
		local model = part:FindFirstAncestorOfClass("Model")
		local hum = model and model:FindFirstChildOfClass("Humanoid")
		if hum and not getroffen[hum] and hum.Health > 0 then
			getroffen[hum] = true
			local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or part
			local dist = (root.Position - pos).Magnitude
			if dist <= R and not teamKollege(attacker, model) then
				local t = math.clamp(dist / R, 0, 1)
				local schaden = (Config.MAX_DAMAGE + (Config.MIN_DAMAGE - Config.MAX_DAMAGE) * t) * faktor
				if model ~= charOf(attacker) then table.insert(gegner, model) end
				-- Kill-Credit (Standard "creator"-Tag)
				if attacker then
					local alt = hum:FindFirstChild("creator")
					if alt then alt:Destroy() end
					local tag = Instance.new("ObjectValue")
					tag.Name = "creator"
					tag.Value = attacker
					tag.Parent = hum
					game:GetService("Debris"):AddItem(tag, 2)
				end
				if attacker and model ~= charOf(attacker) then
					SchadenLog.eintragen(hum, attacker, math.min(schaden, hum.Health)) -- fuer Assists
				end
				local toedlich = schaden >= hum.Health
				if toedlich then Todesflug.vorbereiten(hum) end
				hum:TakeDamage(schaden)
				if toedlich and hum.Health <= 0 then
					-- Finisher des Killers (Troll-Shop) statt normalem Todesflug
					-- (Spieler UND Bots - bei Bots steht der Finisher am Bot-Akteur)
					local finisher = typeof(attacker) == "Instance" and (istSpieler(attacker) or attacker:IsA("ObjectValue"))
						and model ~= charOf(attacker) and attacker:GetAttribute("Finisher")
					local finEvent = game:GetService("ServerStorage"):FindFirstChild("FinisherStart")
					if finisher and finisher ~= "" and finEvent then
						finEvent:Fire(model, finisher, attacker, pos)
					else
						task.spawn(Todesflug.schleudern, model, pos)
					end
				end
				if attacker and model ~= charOf(attacker) then
					trefferAndere = true
					if hum.Health <= 0 then kill = true end
					-- Signal fuer Troll-Gadgets (GadgetServer): wer hat wen getroffen
					local treffer = game:GetService("ServerStorage"):FindFirstChild("BombenTreffer")
					if treffer then treffer:Fire(attacker, model, pos) end
				end
			end
		end
	end
	if trefferAndere and istSpieler(attacker) and attacker.Parent then
		HitMarkerRemote:FireClient(attacker, kill)
	end
	return gegner
end

-- =====================================================================
-- BOMBEN-TYPEN (Modus "CHAOS-BOMBEN": Spezial-Bomben liegen zufaellig auf der Map,
-- Attribut BombenTyp an der Bombe; wer sie aufhebt - Spieler oder Bot - wirft diesen Typ)
-- =====================================================================
local SpezialModelle = require(ReplicatedStorage:WaitForChild("SpezialBombenModelle"))
local chaosRng = Random.new()
local function chaosAktiv()
	local rs = ReplicatedStorage:FindFirstChild("Runde")
	return rs ~= nil and rs:GetAttribute("Modus") == "chaos"
end
-- liegt die Bombe auf einer Map (nicht Lobby / Uebungsbereich / Duell)?
local function aufMap(bomb)
	local x = bomb.Parent
	while x and x ~= workspace do
		if x:IsA("Model") and x:GetAttribute("MapId") then return true end
		x = x.Parent
	end
	return false
end
-- liegt die Bombe auf einer Map mit Kuerbis-Bomben (Attribut "KuerbisBomben")?
local function kuerbisMap(bomb)
	local x = bomb.Parent
	while x and x ~= workspace do
		if x:IsA("Model") and x:GetAttribute("MapId") then return x:GetAttribute("KuerbisBomben") == true end
		x = x.Parent
	end
	return false
end
local Debris = game:GetService("Debris")
local spezialRemote = Remotes:FindFirstChild("BombenSpezial") or Instance.new("RemoteEvent")
spezialRemote.Name = "BombenSpezial"
spezialRemote.Parent = Remotes

local function typVon(bomb)
	if typeof(bomb) ~= "Instance" then return nil end
	local id = bomb:GetAttribute("BombenTyp")
	return id and Config.spezial(id) or nil
end

-- alle lebenden Charaktere (Spieler + Bots)
local function alleCharaktere()
	local liste = {}
	for _, p in Players:GetPlayers() do if p.Character then table.insert(liste, p.Character) end end
	for _, c in CollectionService:GetTagged("BotCharakter") do table.insert(liste, c) end
	return liste
end
local function lebt(c)
	local h = c and c:FindFirstChildOfClass("Humanoid")
	return h and h.Health > 0 and c:FindFirstChild("HumanoidRootPart") and c:IsDescendantOf(workspace)
end

-- naechster Gegner fuer die Magnet-Bombe
local function naechsterGegner(pos, akteur, reichweite)
	local eigen = charOf(akteur)
	local best, bestD = nil, reichweite
	for _, c in alleCharaktere() do
		if c ~= eigen and lebt(c) and not teamKollege(akteur, c) and not c:GetAttribute("Feier") then
			local d = (c.HumanoidRootPart.Position - pos).Magnitude
			if d < bestD then best, bestD = c, d end
		end
	end
	return best
end

-- Bombe sieht aus wie ihr Typ (Farbe, Leuchten, Funken)
local function typOptik(bomb, typ)
	bomb:SetAttribute("BombenTyp", typ.id)
	local farbe = Color3.fromHex(typ.farbe)
	local body = getBody(bomb)
	if not body or body:FindFirstChild("TypLicht") then return end
	local licht = Instance.new("PointLight")
	licht.Name = "TypLicht"
	licht.Color = farbe
	licht.Range = 12
	licht.Brightness = 2.5
	licht.Parent = body
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "TypAura"
	pe.Texture = typ.sog and "rbxasset://textures/particles/smoke_main.dds" or "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(farbe, farbe:Lerp(Color3.new(1, 1, 1), 0.5))
	pe.LightEmission = typ.sog and 0 or 0.8
	pe.Size = NumberSequence.new(typ.sog and 1.2 or 0.5, 0)
	pe.Lifetime = NumberRange.new(0.4, 0.8)
	pe.Rate = 25
	pe.Speed = NumberRange.new(1, 3)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Parent = body
end

-- Bombe bekommt einen Spezial-Typ: Blender-Design + Leuchten + Aura
local function typGeben(bomb, typ)
	pcall(SpezialModelle.anwenden, bomb, typ.id)
	pcall(typOptik, bomb, typ)
end

-- Eis-Bombe: Getroffene kurz einfrieren
local function einfrieren(model, dauer)
	local root = model:FindFirstChild("HumanoidRootPart")
	if not lebt(model) or not root or model:GetAttribute("TrollFest") then return end
	model:SetAttribute("TrollFest", true)
	root.AssemblyLinearVelocity = Vector3.zero
	root.Anchored = true
	local effekt = ReplicatedStorage:FindFirstChild("TrollGadgets") and ReplicatedStorage.TrollGadgets:FindFirstChild("Effekt")
	if effekt then effekt:FireAllClients({art = "eisblock", char = model, dauer = dauer}) end
	task.delay(dauer, function()
		if root.Parent then root.Anchored = false end
		if model.Parent then model:SetAttribute("TrollFest", nil) end
	end)
end

-- Feuer-Bombe: brennender Boden, der Schaden macht
local function feuerZone(pos, akteur, dauer)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = alleCharaktere()
	params.RespectCanCollide = true
	local hit = workspace:Raycast(pos + Vector3.new(0, 2, 0), Vector3.new(0, -14, 0), params)
	local boden = hit and hit.Position or pos
	local R = 12
	local zone = Instance.new("Part")
	zone.Name = "FeuerZone"
	zone.Shape = Enum.PartType.Cylinder
	zone.Size = Vector3.new(0.25, R * 2, R * 2)
	zone.CFrame = CFrame.new(boden + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	zone.Color = Color3.fromRGB(255, 90, 20)
	zone.Material = Enum.Material.Neon
	zone.Transparency = 0.45
	zone.Anchored, zone.CanCollide, zone.CanTouch, zone.CanQuery = true, false, false, false
	zone.CastShadow = false
	zone.Parent = workspace
	for i = 1, 6 do
		local w = i / 6 * math.pi * 2
		local a = Instance.new("Attachment")
		a.WorldPosition = boden + Vector3.new(math.cos(w) * R * 0.55, 0.3, math.sin(w) * R * 0.55)
		a.Parent = workspace.Terrain
		local f = Instance.new("Fire")
		f.Size, f.Heat = 6, 9
		f.Parent = a
		Debris:AddItem(a, dauer)
	end
	local mitteA = Instance.new("Attachment")
	mitteA.WorldPosition = boden + Vector3.new(0, 0.3, 0)
	mitteA.Parent = workspace.Terrain
	local f = Instance.new("Fire"); f.Size, f.Heat = 10, 12; f.Parent = mitteA
	Debris:AddItem(mitteA, dauer)
	task.spawn(function()
		local ende = os.clock() + dauer
		while os.clock() < ende do
			task.wait(0.5)
			for _, c in alleCharaktere() do
				if lebt(c) and c ~= charOf(akteur) and not teamKollege(akteur, c) and not c:FindFirstChild("FeierSchutz") then
					local p = c.HumanoidRootPart.Position
					if Vector3.new(p.X - boden.X, 0, p.Z - boden.Z).Magnitude < R and math.abs(p.Y - boden.Y) < 6 then
						local hum = c:FindFirstChildOfClass("Humanoid")
						if akteur then
							local alt = hum:FindFirstChild("creator"); if alt then alt:Destroy() end
							local tag = Instance.new("ObjectValue"); tag.Name = "creator"; tag.Value = akteur; tag.Parent = hum
							Debris:AddItem(tag, 2)
						end
						hum:TakeDamage(6)
					end
				end
			end
		end
		TweenService:Create(zone, TweenInfo.new(0.5), {Transparency = 1}):Play()
		Debris:AddItem(zone, 0.6)
	end)
end

-- Schwarzes Loch: alle in der Naehe werden zur Bombe gezogen
local function ansaugen(pos, dauer)
	spezialRemote:FireAllClients({art = "loch", pos = pos, dauer = dauer})
	for _, c in alleCharaktere() do
		if lebt(c) and not c:FindFirstChild("FeierSchutz") then
			local root = c.HumanoidRootPart
			local weg = pos - root.Position
			if weg.Magnitude < 42 and weg.Magnitude > 2 then
				local att = Instance.new("Attachment")
				att.Parent = root
				local lv = Instance.new("LinearVelocity")
				lv.Attachment0 = att
				lv.MaxForce = 60000
				lv.RelativeTo = Enum.ActuatorRelativeTo.World
				lv.VectorVelocity = weg.Unit * math.clamp(weg.Magnitude * 1.6, 14, 42) + Vector3.new(0, 4, 0)
				lv.Parent = root
				Debris:AddItem(att, dauer)
				Debris:AddItem(lv, dauer)
			end
		end
	end
end

local function explode(bomb)
	local state = bombState[bomb]
	if not state or state.exploded then return end
	state.exploded = true
	local body = getBody(bomb)
	if body and bomb:IsDescendantOf(workspace) then
		local typ = state.typ
		local R = Config.EXPLOSION_RADIUS * (typ and typ.radius or 1)
		release(bomb)
		if typ and typ.sog then
			-- Schwarzes Loch: erst 1 Sekunde alles ansaugen, dann explodieren
			for _, p in bomb:GetDescendants() do if p:IsA("BasePart") then p.Anchored = true end end
			ansaugen(body.Position, 1)
			task.wait(1)
		end
		local pos = body.Position
		-- fuer RagdollServer: wo ist gerade etwas explodiert (Koerper werden davon weggeschleudert)
		local expEv = game:GetService("ServerStorage"):FindFirstChild("ExplosionPassiert")
		if expEv then expEv:Fire(pos, R) end
		local gegner = applyDamage(pos, state.owner, bomb, R, 1)
		EffectRemote:FireAllClients(pos, R, bomb:GetAttribute("SkinId"))
		if typ then
			spezialRemote:FireAllClients({art = typ.id, pos = pos, radius = R})
			if typ.eis then
				for _, m in gegner do einfrieren(m, typ.eis) end
			end
			if typ.feuer then feuerZone(pos, state.owner, typ.feuer) end
			if typ.cluster then
				local owner = state.owner
				task.delay(0.35, function()
					for i = 1, typ.cluster do
						local w = i / typ.cluster * math.pi * 2 + math.random() * 0.6
						local p2 = pos + Vector3.new(math.cos(w) * R * 0.75, 0, math.sin(w) * R * 0.75)
						applyDamage(p2, owner, nil, R * 0.45, 0.5)
						EffectRemote:FireAllClients(p2, R * 0.45)
						task.wait(0.12)
					end
				end)
			end
		end
		-- Signal fuer andere Server-Scripts (z.B. Zielscheiben im Uebungsbereich)
		local signal = game:GetService("ServerStorage"):FindFirstChild("BombeExplodiert")
		if signal then signal:Fire(pos, state.owner) end
	else
		release(bomb)
	end
	bombState[bomb] = nil
	bomb:Destroy()
	scheduleRespawn(state)
end

-- Zeit bis zur Explosion: Map kann eigene Zeit haben (Attribut "BombenZeit", z.B. Unterwasser = 6)
local function zuendZeit(bomb)
	local x = bomb.Parent
	while x and x ~= workspace do
		local z = x:GetAttribute("BombenZeit")
		if z then return z end
		x = x.Parent
	end
	return Config.FUSE_TIME
end

local function startCountdown(bomb)
	local FUSE = zuendZeit(bomb)
	bomb:SetAttribute("ZuendDauer", FUSE)
	bomb:SetAttribute("ZuendStart", workspace:GetServerTimeNow()) -- fuer die brennende Lunte (LunteClient)
	task.spawn(function()
		local start = os.clock()
		for n = FUSE, 0, -1 do
			local state = bombState[bomb]
			if not state or state.exploded then return end
			if not bomb:IsDescendantOf(workspace) or not getBody(bomb) then
				-- z.B. ins Void gefallen
				state.exploded = true
				release(bomb)
				bombState[bomb] = nil
				if bomb.Parent then bomb:Destroy() end
				scheduleRespawn(state)
				return
			end
			setTimerText(bomb, n)
			if n == 0 then
				explode(bomb)
				return
			end
			local ziel = start + (FUSE - n + 1)
			task.wait(math.max(0, ziel - os.clock()))
		end
	end)
end

-- ---------- Bomben-Skin + Wurf-Spur aus dem Geschaeft ----------
local QuestConfig = require(ReplicatedStorage:WaitForChild("QuestConfig"))
local HalloweenModelle = require(ReplicatedStorage:WaitForChild("HalloweenModelle"))
-- Halloween-Skins mit eigenem Blender-Modell (HalloweenModelle):
--   kuerbis = leuchtender Kuerbiskopf (Stiel = Lunte), gruft = dunkle Bombe mit Totenkopf + lila Rissen
local SKIN_DESIGNS = {
	kuerbis = {modell = "kuerbis", faktor = 1.75, mitteY = 6.5, spitze = Vector3.new(1.5, 16.2, 0.5), licht = Color3.fromRGB(255, 150, 40)},
	gruft = {modell = "gruftbombe", faktor = 2.4, mitteY = 5.5, spitze = Vector3.new(1.5, 14.2, 0.5), licht = Color3.fromRGB(180, 80, 255)},
}
kuerbisDesign = function(bomb, designId)
	local body = getBody(bomb)
	local pixel = bomb:FindFirstChild("Pixel")
	local d = SKIN_DESIGNS[designId or "kuerbis"]
	if not d or not body or not pixel or bomb:GetAttribute("Design") then return end
	local s = body.Size.Y / 3.74
	local faktor = d.faktor * s
	local v = HalloweenModelle.MODELLE[d.modell].voxel * faktor
	local m = HalloweenModelle.bauen(d.modell, faktor)
	if not m then return end
	pixel:ClearAllChildren()
	local basis = body.CFrame * CFrame.new(0, -d.mitteY * v, 0)
	for _, p in m:GetChildren() do
		if p:IsA("BasePart") and p.Name ~= "Mitte" then
			p.Name = "SkinVoxel"
			p.Anchored = false
			p.CanCollide, p.CanTouch, p.CanQuery = false, false, false
			p.Massless = true
			p.CFrame = basis * p.CFrame
			local w = Instance.new("WeldConstraint")
			w.Part0 = body
			w.Part1 = p
			w.Parent = p
			p.Parent = pixel
		end
	end
	m:Destroy()
	local funke = bomb:FindFirstChild("Funke")
	if funke and funke:IsA("BasePart") then
		for _, c in funke:GetChildren() do if c:IsA("WeldConstraint") or c:IsA("Weld") then c:Destroy() end end
		funke.CFrame = basis * CFrame.new(d.spitze * v)
		local w = Instance.new("WeldConstraint")
		w.Part0 = body
		w.Part1 = funke
		w.Parent = funke
	end
	local licht = Instance.new("PointLight")
	licht.Name = "KuerbisLicht"
	licht.Color = d.licht
	licht.Range = 10
	licht.Brightness = 2
	licht.Parent = body
	bomb:SetAttribute("Design", designId)
end
local function skinAnwenden(bomb, player)
	if not istSpieler(player) then return end
	local skin = QuestConfig.item("skins", player:GetAttribute("BombenSkin") or "standard")
	bomb:SetAttribute("SkinId", skin and skin.id or nil) -- fuer die eigene Explosions-Animation des Skins (SkinExplosionen)
	if skin and skin.design then pcall(kuerbisDesign, bomb, skin.design) end
	if skin and skin.id ~= "standard" and not skin.design then
		local basis = Color3.fromHex(skin.farbe)
		local pixel = bomb:FindFirstChild("Pixel")
		if pixel then
			for _, p in pixel:GetChildren() do
				if p:IsA("BasePart") and p.Name == "Voxel" then
					-- Helligkeit der alten Schattierung behalten (dunkel -> hell)
					local _, _, v = p.Color:ToHSV()
					local faktor = 0.45 + (v / 0.49) * 0.75
					p.Color = Color3.new(math.min(1, basis.R * faktor), math.min(1, basis.G * faktor), math.min(1, basis.B * faktor))
				end
			end
		end
	end
	local spur = QuestConfig.item("spuren", player:GetAttribute("BombenSpur") or "standard")
	bomb:SetAttribute("SpurDesign", spur and spur.design or nil) -- z.B. "geist": Blender-Geister fliegen hinterher (HalloweenClient)
	local body = getBody(bomb)
	local trail = body and body:FindFirstChild("Spur")
	if spur and trail then
		if spur.farbe == "regenbogen" then
			trail.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 60, 60)), ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 220, 60)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(60, 255, 90)), ColorSequenceKeypoint.new(0.75, Color3.fromRGB(60, 140, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 60, 255)),
			})
		else
			trail.Color = ColorSequence.new(Color3.fromHex(spur.farbe))
		end
	end
end

local function onPickup(bomb, player)
	local state = bombState[bomb]
	if not state or state.owner or state.exploded then return end -- gehoert schon jemandem
	if heldBy[player] then return end
	local char = charOf(player)
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local body = getBody(bomb)
	if not hum or hum.Health <= 0 or not root or not body then return end
	if (root.Position - body.Position).Magnitude > Config.PICKUP_DISTANCE + 5 then return end
	if char:GetAttribute("Gelaehmt") or char:GetAttribute("Isst") then return end -- ausgerutscht / isst gerade
	local r15Hand, r6Arm = getHand(char)
	local hand = r15Hand or r6Arm
	if not hand then return end

	state.owner = player
	state.holder = player
	heldBy[player] = bomb
	pcall(skinAnwenden, bomb, player)
	state.typ = typVon(bomb)
	if state.typ then
		local trail = body:FindFirstChild("Spur")
		if trail then trail.Color = ColorSequence.new(Color3.fromHex(state.typ.farbe)) end
	end
	local prompt = body:FindFirstChild("PickupPrompt")
	if prompt then prompt.Enabled = false end

	-- Abstand zur Hand passt sich der Bombengroesse an (Bomben sind kleiner geworden)
	local k = body.Size.Y / 6.43
	local offset = r15Hand and CFrame.new(0, -1.25 * k, 0) or CFrame.new(0, -2.1 * k, 0)
	bomb:PivotTo(hand.CFrame * offset)
	local weld = Instance.new("Weld")
	weld.Name = "HandWeld"
	weld.Part0 = hand
	weld.Part1 = body
	weld.C0 = offset
	weld.Parent = body
	state.weld = weld
	setPhysics(bomb, true)

	player:SetAttribute("HasBomb", true)
	table.insert(state.conns, hum.Died:Connect(function() release(bomb) end))
	if istSpieler(player) then
		table.insert(state.conns, player.CharacterRemoving:Connect(function() release(bomb) end))
	else
		table.insert(state.conns, char.AncestryChanged:Connect(function()
			if not char:IsDescendantOf(workspace) then release(bomb) end
		end))
	end

	startCountdown(bomb)
end

local function isValidVector(v)
	return typeof(v) == "Vector3" and v.X == v.X and v.Y == v.Y and v.Z == v.Z
		and math.abs(v.X) < 1e6 and math.abs(v.Y) < 1e6 and math.abs(v.Z) < 1e6
end

local function werfenAusfuehren(player, zielPunkt, kraftClient)
	if not isValidVector(zielPunkt) then return end
	if typeof(kraftClient) ~= "number" or kraftClient ~= kraftClient then kraftClient = 1 end
	local bomb = heldBy[player]
	if not bomb then return end
	local state = bombState[bomb]
	if not state or state.holder ~= player or state.throwing or state.exploded then return end
	local jetzt = os.clock()
	if lastThrow[player] and jetzt - lastThrow[player] < Config.THROW_COOLDOWN then return end
	lastThrow[player] = jetzt

	local char = charOf(player)
	if not char then return end
	state.throwing = true
	local ausgeholt = state.aimStart and (jetzt - state.aimStart) or 0
	-- Kraft: Client-Wert, aber nie mehr als die echte Haltezeit hergibt (+ Ping-Toleranz)
	local kraft = math.clamp(kraftClient, 0, Config.kraftAusZeit(ausgeholt + 0.25))
	local verzoegerung = math.max(Config.RELEASE_DELAY - ausgeholt, Config.RELEASE_DELAY_MIN)
	sendeAnim(player, char, state.aimStart and "wurf" or "voll")

	task.delay(verzoegerung, function()
		state.throwing = false
		if state.exploded or state.holder ~= player or not bomb.Parent then return end
		local root = char:FindFirstChild("HumanoidRootPart")
		local body = getBody(bomb)
		if not root or not body then return end

		local origin = root.Position + Vector3.new(0, 2, 0)
		local dir = zielPunkt - origin
		if dir.Magnitude < 0.5 then dir = root.CFrame.LookVector end
		dir = dir.Unit

		-- Startpunkt = Hand beim Abwurf (vorne oben, leicht rechts)
		local startPos = Config.abwurfPunkt(root.CFrame, dir)
		local velocity
		if Config.wurfGeschwindigkeit then
			-- Aufgeladener Wurf (gleiche Formel wie der Zielfaden beim Client)
			velocity = Config.wurfGeschwindigkeit(dir, kraft)
		elseif Config.AIM_AT_CROSSHAIR then
			-- Ziel = dort, wo das Fadenkreuz hinzeigt (auf maximale Reichweite begrenzt)
			local weg = zielPunkt - startPos
			if weg.Magnitude > Config.MAX_RANGE then
				weg = weg.Unit * Config.MAX_RANGE
			end
			-- Ballistische Flugbahn: Geschwindigkeit so, dass die Bombe genau im Ziel ankommt
			local g = Vector3.new(0, -workspace.Gravity, 0)
			local flugzeit = math.clamp(weg.Magnitude / Config.THROW_SPEED, Config.MIN_FLIGHT_TIME, Config.MAX_FLIGHT_TIME)
			velocity = (weg - 0.5 * g * flugzeit * flugzeit) / flugzeit
		else
			velocity = dir * Config.THROW_SPEED + Vector3.new(0, Config.THROW_UPWARD, 0)
		end

		release(bomb, true)
		bomb:PivotTo(CFrame.new(startPos))
		-- Schneller fliegen + landen: Tempo hoch UND Schwerkraft fuer die Bombe entsprechend staerker
		-- -> die Flugbahn bleibt genau gleich (Zielfaden stimmt weiter), nur schneller.
		local tempo = (Config.WURF_TEMPO or 1) * (state.typ and state.typ.tempo or 1) -- Turbo-Bombe: schneller, gleiche Bahn
		body.AssemblyLinearVelocity = velocity * tempo
		if tempo ~= 1 then
			local att = body:FindFirstChild("SchwerkraftAtt") or Instance.new("Attachment")
			att.Name = "SchwerkraftAtt"
			att.Parent = body
			local kraft = body:FindFirstChild("ExtraSchwerkraft") or Instance.new("VectorForce")
			kraft.Name = "ExtraSchwerkraft"
			kraft.Attachment0 = att
			kraft.RelativeTo = Enum.ActuatorRelativeTo.World
			kraft.ApplyAtCenterOfMass = true
			kraft.Force = Vector3.new(0, -workspace.Gravity * body.AssemblyMass * (tempo * tempo - 1), 0)
			kraft.Parent = body
		end

		-- Aufprall: Direkttreffer auf einen Avatar -> sofort explodieren (Timer egal).
		-- Sonst (Boden/Wand): kaum weiterrollen, danach zaehlt nur noch der Timer.
		body.CanTouch = true
		-- Sobald eine geworfene Bombe irgendeinen lebenden Avatar beruehrt -> sofort explodieren.
		-- Gilt im Flug UND wenn sie schon liegt; auch fuer den Werfer selbst (ausser direkt beim Abwurf).
		local wurfZeit = os.clock()
		local function avatarTreffer(teil)
			if state.exploded then return true end
			-- Zielscheiben in der Uebungsarena (Attribut "BombenZiel"): Treffer zuendet sofort
			if teil:GetAttribute("BombenZiel") then
				bomb:SetAttribute("GetroffenVon", "Zielscheibe/" .. teil.Name)
				task.defer(explode, bomb)
				return true
			end
			local model = teil:FindFirstAncestorOfClass("Model")
			local hum = model and model:FindFirstChildOfClass("Humanoid")
			if not hum or hum.Health <= 0 then return false end
			if model == char and os.clock() - wurfZeit < 0.6 then return false end
			bomb:SetAttribute("GetroffenVon", model.Name .. "/" .. teil.Name)
			task.defer(explode, bomb)
			return true
		end
		local gebremst = false
		local aufprallConn
		aufprallConn = body.Touched:Connect(function(teil)
			if avatarTreffer(teil) then return end
			if gebremst or not teil.CanCollide then return end
			if teil:IsA("Terrain") and state.ordner and state.ordner.Parent and state.ordner.Parent:GetAttribute("Unterwasser") then return end -- Wasser ist kein Aufprall
			local m = teil:FindFirstAncestorOfClass("Model")
			if m and m:FindFirstChildOfClass("Humanoid") then return end -- Avatar (z.B. Werfer) bremst nicht
			if os.clock() - wurfZeit < 0.08 then return end -- direkt beim Abwurf nichts bremsen
			-- erster Boden-/Wandkontakt: kaum weiterrollen
			gebremst = true
			local v = body.AssemblyLinearVelocity
			body.AssemblyLinearVelocity = Vector3.new(v.X * 0.25, v.Y * 0.3, v.Z * 0.25)
			body.AssemblyAngularVelocity = body.AssemblyAngularVelocity * 0.2
		end)
		table.insert(state.conns, aufprallConn)
		-- Unterwasser: kein Bogen wie an Land, sondern ein kraeftiger, fast gerader Stoss
		-- in Blickrichtung, den das Wasser langsam abbremst; danach sinkt die Bombe langsam.
		local wMap = state.ordner and state.ordner.Parent
		if wMap and wMap:GetAttribute("Unterwasser") and wMap:GetAttribute("WasserOberflaeche") then
			local W = Config.WASSER or {}
			local speedMin, speedMax = Config.THROW_SPEED_MIN or 55, Config.THROW_SPEED_MAX or 190
			local k = math.clamp(tonumber(kraft) or 1, 0, 1)
			local tempo0 = (speedMin + (speedMax - speedMin) * k) * (W.TEMPO or 0.42)
			local richtung = (dir.Unit + Vector3.new(0, W.HOCH or 0.06, 0)).Unit
			local bremse = W.BREMSE or 1.0     -- wie stark das Wasser bremst (pro Sekunde)
			local sinken = W.SINKEN or 6       -- wie schnell sie nach unten zieht
			local kraftFeld = body:FindFirstChild("ExtraSchwerkraft")
			if kraftFeld then kraftFeld.Enabled = false end
			local flugStart = os.clock()
			local letztePos = body.Position
			local sweep = RaycastParams.new()
			sweep.FilterType = Enum.RaycastFilterType.Exclude
			local flugConn
			flugConn = RunService.Heartbeat:Connect(function()
				local t = os.clock() - flugStart
				local v = richtung * tempo0 * math.exp(-bremse * t) + Vector3.new(0, -sinken * t, 0)
				if gebremst or state.exploded or not body.Parent or state.holder or t > 4 or v.Magnitude < 5 then
					flugConn:Disconnect()
					return
				end
				-- sehr schnell -> Weg seit dem letzten Frame absuchen, damit nichts "durchtunnelt"
				local weg = body.Position - letztePos
				if weg.Magnitude > 0.5 then
					local filter = {bomb}
					if os.clock() - wurfZeit < 0.6 then table.insert(filter, char) end
					sweep.FilterDescendantsInstances = filter
					local treffer = workspace:Spherecast(letztePos, 2.2, weg, sweep)
					if treffer and not (treffer.Instance:IsA("Terrain") and treffer.Material == Enum.Material.Water) then
						if avatarTreffer(treffer.Instance) then flugConn:Disconnect() return end
						if treffer.Instance.CanCollide then
							-- Wand/Boden: dort stehen bleiben
							gebremst = true
							body.CFrame = CFrame.new(treffer.Position + treffer.Normal * 3)
							body.AssemblyLinearVelocity = Vector3.new(0, -3, 0)
							flugConn:Disconnect()
							return
						end
					end
				end
				letztePos = body.Position
				body.AssemblyLinearVelocity = v
				body.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
			end)
			table.insert(state.conns, flugConn)
		end
		-- Magnet-Bombe: lenkt im Flug zum naechsten Gegner (bis sie den Boden beruehrt)
		if state.typ and state.typ.magnet then
			local magStart = os.clock()
			local magConn
			magConn = RunService.Heartbeat:Connect(function(dt)
				local t = os.clock() - magStart
				if state.exploded or not body.Parent or state.holder or t > 3.5 or (gebremst and t > 0.4) then magConn:Disconnect() return end
				if t < 0.12 then return end
				local ziel = naechsterGegner(body.Position, player, 60)
				if ziel then
					local v = body.AssemblyLinearVelocity
					local tempoM = math.max(v.Magnitude, 85)
					local zielPos = ziel.HumanoidRootPart.Position
					body.AssemblyLinearVelocity = v:Lerp((zielPos - body.Position).Unit * tempoM, math.clamp(dt * 5, 0, 1))
					body:SetAttribute("MagnetZiel", ziel.Name)
				end
			end)
			table.insert(state.conns, magConn)
		end
		-- Touched verpasst schnelle Treffer manchmal -> zusaetzlich jede Physik-Runde nachschauen
		local suche = OverlapParams.new()
		suche.FilterType = Enum.RaycastFilterType.Exclude
		suche.FilterDescendantsInstances = {bomb}
		local radius = math.max(body.Size.X, body.Size.Y, body.Size.Z) / 2 + 0.6
		local pruefConn
		pruefConn = RunService.Heartbeat:Connect(function()
			if state.exploded or not body.Parent then pruefConn:Disconnect() return end
			for _, teil in workspace:GetPartBoundsInRadius(body.Position, radius, suche) do
				if avatarTreffer(teil) then pruefConn:Disconnect() return end
			end
		end)
		table.insert(state.conns, pruefConn)
		body.AssemblyAngularVelocity = Vector3.zero
		state.thrown = true
		if istSpieler(player) then
			local qf = game:GetService("ServerStorage"):FindFirstChild("QuestFortschritt")
			if qf then qf:Fire(player, "wuerfe", 1) end
		end

		-- Wurfsound
		local wurfSound = Instance.new("Sound")
		wurfSound.Name = "WurfSound"
		wurfSound.SoundId = Sounds.WURF.id
		wurfSound.Volume = Sounds.WURF.volume
		wurfSound.RollOffMaxDistance = 120
		wurfSound.Parent = root
		wurfSound:Play()
		game:GetService("Debris"):AddItem(wurfSound, 2)

		local spur = body:FindFirstChild("Spur")
		if spur then
			spur:Clear()
			spur.Enabled = true
		end
	end)
end
ThrowRemote.OnServerEvent:Connect(werfenAusfuehren)

local function ausholen(player)
	local bomb = heldBy[player]
	local state = bomb and bombState[bomb]
	if not state or state.holder ~= player or state.throwing or state.exploded or state.aimStart then return end
	state.aimStart = os.clock()
	sendeAnim(player, charOf(player), "aushol")
end
AimRemote.OnServerEvent:Connect(ausholen)

Players.PlayerRemoving:Connect(function(player)
	local bomb = heldBy[player]
	if bomb then release(bomb) end
	lastThrow[player] = nil
end)

ersteVorlage = nil -- irgendeine Bomben-Vorlage (fuer Extra-Bomben, z.B. auf der Siegerbuehne)
setupBomb = function(bomb, template, spawnCF)
	if bombState[bomb] or not bomb:IsA("Model") then return end
	local body = getBody(bomb)
	if not body then return end
	if not template then
		-- Erste Bombe: Vorlage + Startplatz merken fuer den Respawn
		template = bomb:Clone()
		ersteVorlage = ersteVorlage or template
		-- Rundenstart: an einen zufaelligen, erreichbaren Ort der Map
		local zufall = zufallsCF(bomb.Parent, bomb, bomb)
		if zufall then bomb:PivotTo(zufall) end
		spawnCF = bomb:GetPivot()
	end
	bombState[bomb] = {
		owner = nil, holder = nil, weld = nil,
		thrown = false, throwing = false, exploded = false,
		conns = {}, template = template, spawnCF = spawnCF,
		ordner = bomb.Parent,
	}
	setTimerText(bomb, zuendZeit(bomb))
	local prompt = body:FindFirstChild("PickupPrompt")
	if prompt then
		prompt.MaxActivationDistance = Config.PICKUP_DISTANCE
		prompt.Enabled = true
		prompt.Triggered:Connect(function(player) onPickup(bomb, player) end)
	end
	-- CHAOS-BOMBEN: jede Bombe auf der Map ist eine zufaellige Spezial-Bombe
	if chaosAktiv() and aufMap(bomb) and not bomb:GetAttribute("BombenTyp") then
		typGeben(bomb, Config.zufallsSpezial(chaosRng))
	elseif not bomb:GetAttribute("BombenTyp") and sollKuerbisIn(bomb.Parent) then
		-- Kuerbis-Welle (alle Bomben) / Spukfriedhof: leuchtende Kuerbisse
		if not bomb:GetAttribute("Design") then pcall(kuerbisDesign, bomb, "kuerbis") end
		bomb:SetAttribute("EventKuerbis", true)
	end
end

-- Modus-Wechsel: liegende Bomben passend machen (Chaos -> Spezial, sonst wieder normal)
local function bombenAnModusAnpassen()
	local chaos = chaosAktiv()
	local liste = {}
	for bomb, state in bombState do
		if not state.owner and not state.thrown and not state.exploded and bomb:IsDescendantOf(workspace) then
			table.insert(liste, {bomb, state})
		end
	end
	for _, e in liste do
		local bomb, state = e[1], e[2]
		if chaos and aufMap(bomb) and not bomb:GetAttribute("BombenTyp") and bomb:GetAttribute("Design") and state.template then
			-- Kuerbis-Bombe -> frische Bombe, die dann eine Spezial-Bombe wird
			local cf = bomb:GetPivot()
			local ordner = bomb.Parent
			bombState[bomb] = nil
			bomb:Destroy()
			local neu = state.template:Clone()
			neu:PivotTo(cf)
			neu.Parent = ordner
			setupBomb(neu, state.template, state.spawnCF)
			if bombState[neu] then bombState[neu].keinRespawn = state.keinRespawn end
		elseif chaos and aufMap(bomb) and not bomb:GetAttribute("BombenTyp") then
			typGeben(bomb, Config.zufallsSpezial(chaosRng))
		elseif (not chaos and bomb:GetAttribute("BombenTyp") and state.template)
			or (bomb:GetAttribute("EventKuerbis") and not sollKuerbisIn(bomb.Parent) and state.template) then
			-- frische, normale Bombe an dieselbe Stelle (Chaos vorbei / Kuerbis-Welle vorbei)
			local cf = bomb:GetPivot()
			local ordner = bomb.Parent
			bombState[bomb] = nil
			bomb:Destroy()
			local neu = state.template:Clone()
			neu:PivotTo(cf)
			neu.Parent = ordner
			setupBomb(neu, state.template, state.spawnCF)
			if bombState[neu] then bombState[neu].keinRespawn = state.keinRespawn end
		elseif not bomb:GetAttribute("BombenTyp") and not bomb:GetAttribute("Design") and sollKuerbisIn(bomb.Parent) then
			-- Kuerbis-Welle beginnt: liegende Bomben werden Kuerbisse
			pcall(kuerbisDesign, bomb, "kuerbis")
			bomb:SetAttribute("EventKuerbis", true)
		end
	end
end
task.spawn(function()
	local rs = ReplicatedStorage:WaitForChild("Runde")
	rs:GetAttributeChangedSignal("Modus"):Connect(bombenAnModusAnpassen)
end)
-- Kuerbis-Welle an/aus: alle liegenden Bomben umbauen
task.spawn(function()
	local h = ReplicatedStorage:WaitForChild("Halloween")
	h:GetAttributeChangedSignal("KuerbisZeit"):Connect(bombenAnModusAnpassen)
end)

for _, b in CollectionService:GetTagged(BOMB_TAG) do
	if b:IsDescendantOf(workspace) then setupBomb(b) end
end


-- =====================================================================
-- SCHNITTSTELLE FUER BOTS (BotServer ruft das auf)
-- =====================================================================
do
	local ServerStorage = game:GetService("ServerStorage")
	local api = ServerStorage:FindFirstChild("BombBotAPI") or Instance.new("BindableFunction")
	api.Name = "BombBotAPI"
	api.Parent = ServerStorage
	api.OnInvoke = function(aktion, actor, a, b)
		if aktion == "aufheben" then
			onPickup(a, actor)
			return heldBy[actor] == a
		elseif aktion == "ausholen" then
			ausholen(actor)
		elseif aktion == "werfen" then
			werfenAusfuehren(actor, a, b)
		elseif aktion == "frei" then
			local st = bombState[a]
			return st ~= nil and st.owner == nil and not st.exploded
		elseif aktion == "gefaehrlich" then
			-- geworfen/liegt mit laufendem Timer und wird von niemandem gehalten
			local st = bombState[a]
			return st ~= nil and st.owner ~= nil and st.holder == nil and not st.exploded
		elseif aktion == "haelt" then
			return heldBy[actor]
		elseif aktion == "loslassen" then
			local bomb = heldBy[actor]
			if bomb then release(bomb) end
		elseif aktion == "spawnen" then
			-- Extra-Bombe ohne Respawn: a = Bodenpunkt (Vector3), b = Ordner
			if not ersteVorlage or typeof(a) ~= "Vector3" then return nil end
			local neu = ersteVorlage:Clone()
			neu:PivotTo(CFrame.new(a))
			local cf, size = neu:GetBoundingBox()
			neu:PivotTo(neu:GetPivot() + Vector3.new(0, a.Y - (cf.Position.Y - size.Y / 2) + 0.05, 0))
			neu.Parent = b or workspace
			setupBomb(neu, ersteVorlage, neu:GetPivot())
			if bombState[neu] then bombState[neu].keinRespawn = true end
			return neu
		elseif aktion == "einrichten" then
			-- a = Ordner mit Bomben (z.B. in einer frisch kopierten Uebungsarena): alle aufhebbar machen
			if typeof(a) ~= "Instance" then return nil end
			for _, b in a:GetChildren() do
				if CollectionService:HasTag(b, BOMB_TAG) and b:IsDescendantOf(workspace) then setupBomb(b) end
			end
		end
		return nil
	end
end
