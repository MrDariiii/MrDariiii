-- UebungsServer: Uebungswelt mit 3 Modi
--   AUSWEICHEN  : Kanonen schiessen Bomben, Ueberlebenszeit + Rekord (Treffer = kein Tod, nur Rueckstoss)
--   ZIELWERFEN  : Noobs (teils laufend) + Zielscheiben am Boden -> Punkte
--   1 VS 1      : zwei Felder, Countdown, Kampf im eigenen Feld, Siege werden gezaehlt
-- Eingang: Portal in der Lobby oeffnet ein Menue, Wahl teleportiert direkt. Zurueck per Button.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Sounds = require(RS:WaitForChild("SoundConfig"))
local Remotes = RS:WaitForChild("UebungRemotes")
local MenueRemote, WahlRemote, ZurueckRemote = Remotes:WaitForChild("Menue"), Remotes:WaitForChild("Wahl"), Remotes:WaitForChild("Zurueck")
local blitz = RS:WaitForChild("PortalBlitz")
local EffectRemote = RS:WaitForChild("BombRemotes"):WaitForChild("ExplosionEffect")
local explodiert = SS:WaitForChild("BombeExplodiert")

local welt = workspace:WaitForChild("Uebungswelt")
local ZONEN = {
	ausweichen = welt:WaitForChild("Ausweichen"),
	werfen = welt:WaitForChild("Zielwerfen"),
	duell = welt:WaitForChild("Duell"),
}
local lobby = workspace:WaitForChild("Lobby")
local portal = lobby:FindFirstChild("UebungsPortal") or lobby:FindFirstChild("d")

local function jetzt() return workspace:GetServerTimeNow() end

-- ================= Helfer =================
local function inBox(teil, pos)
	local rel = teil.CFrame:PointToObjectSpace(pos)
	local h = teil.Size / 2
	return math.abs(rel.X) <= h.X and math.abs(rel.Y) <= h.Y and math.abs(rel.Z) <= h.Z
end

local function wurzel(p)
	local c = p.Character
	local r = c and c:FindFirstChild("HumanoidRootPart")
	local h = c and c:FindFirstChildOfClass("Humanoid")
	if r and h and h.Health > 0 then return r, h, c end
	return nil
end

local function zoneVon(pos)
	for name, m in ZONEN do
		local b = m:FindFirstChild("Bereich")
		if b and inBox(b, pos) then return name end
	end
	return nil
end

local function teleportiere(p, cf, mitBlitz)
	local r, h, c = wurzel(p)
	if not r then return end
	if mitBlitz ~= false then blitz:FireClient(p); task.wait(0.15) end
	if not r.Parent then return end
	r.AssemblyLinearVelocity = Vector3.zero
	c:PivotTo(cf + Vector3.new(0, h.HipHeight + r.Size.Y / 2 + 0.5, 0))
end

local function spawnVon(zone, name)
	local s = ZONEN[zone]:FindFirstChild(name or "Spawn")
	return s and s.CFrame
end

local function lobbyCF()
	local e = portal and portal:FindFirstChild("Energie")
	if not e then return CFrame.new(0, 167, 12) end
	local innen = Vector3.new(-e.Position.X, 0, -e.Position.Z).Unit
	local pos = Vector3.new(e.Position.X, 166, e.Position.Z) + innen * 12
	return CFrame.lookAt(pos, Vector3.new(0, pos.Y, 0))
end

local function schwebeText(pos, text, farbe, groesse)
	local anker = Instance.new("Part")
	anker.Anchored, anker.CanCollide, anker.CanQuery, anker.CanTouch = true, false, false, false
	anker.Transparency = 1
	anker.Size = Vector3.new(0.2, 0.2, 0.2)
	anker.CFrame = CFrame.new(pos)
	anker.Parent = workspace
	local g = Instance.new("BillboardGui")
	g.Size = UDim2.fromOffset(groesse or 180, (groesse or 180) * 0.4)
	g.AlwaysOnTop = true
	g.MaxDistance = 300
	g.Parent = anker
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.Text = text
	t.TextColor3 = farbe
	t.TextStrokeTransparency = 0.1
	t.Parent = g
	TweenService:Create(anker, TweenInfo.new(1.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {CFrame = anker.CFrame + Vector3.new(0, 5, 0)}):Play()
	TweenService:Create(t, TweenInfo.new(1.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {TextTransparency = 1, TextStrokeTransparency = 1}):Play()
	Debris:AddItem(anker, 1.4)
end

local KONFETTI = {Color3.fromRGB(255,80,80), Color3.fromRGB(255,210,50), Color3.fromRGB(80,200,255), Color3.fromRGB(120,255,120), Color3.fromRGB(200,110,255)}
local function konfetti(pos, menge)
	local a = Instance.new("Part")
	a.Anchored, a.CanCollide, a.CanQuery, a.CanTouch = true, false, false, false
	a.Transparency = 1
	a.Size = Vector3.new(1, 1, 1)
	a.CFrame = CFrame.new(pos)
	a.Parent = workspace
	for _, farbe in KONFETTI do
		local e = Instance.new("ParticleEmitter")
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Color = ColorSequence.new(farbe)
		e.Size = NumberSequence.new(0.6, 0.2)
		e.Lifetime = NumberRange.new(0.8, 1.5)
		e.Speed = NumberRange.new(18, 32)
		e.SpreadAngle = Vector2.new(60, 60)
		e.Acceleration = Vector3.new(0, -35, 0)
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-200, 200)
		e.EmissionDirection = Enum.NormalId.Top
		e.LightEmission = 0.5
		e.Enabled = false
		e.Parent = a
		e:Emit(menge or 12)
	end
	Debris:AddItem(a, 2)
end

local function spieleSound(eltern, info, lautstaerke)
	if not info then return end
	local s = Instance.new("Sound")
	s.SoundId = info.id or info
	s.Volume = lautstaerke or info.volume or 0.8
	s.RollOffMaxDistance = 120
	s.Parent = eltern
	s:Play()
	Debris:AddItem(s, 4)
end

-- ================= Eingang / Menue / Zurueck =================
-- Das Portal in der Lobby bringt jetzt direkt in die eigene Uebungsarena (UebungsArenaServer),
-- das Auswahlmenue wird darueber nicht mehr geoeffnet.
local menueZuletzt = {}

local rueckkehr = {} -- [Player] = Zone (nach dem Tod wieder dorthin)

WahlRemote.OnServerEvent:Connect(function(p, zone)
	if typeof(zone) ~= "string" or not ZONEN[zone] then return end
	local cf = spawnVon(zone)
	if not cf then return end
	if zone == "ausweichen" then p:SetAttribute("AusweichSeit", jetzt()) end
	if zone == "werfen" then p:SetAttribute("Punkte", 0) end
	teleportiere(p, cf)
end)

local verlasseDuell -- vorwaerts
ZurueckRemote.OnServerEvent:Connect(function(p)
	if p:GetAttribute("UebungZone") == "arena" then return end -- macht der UebungsArenaServer
	rueckkehr[p] = nil
	if verlasseDuell then verlasseDuell(p) end
	teleportiere(p, lobbyCF())
end)

-- Zone jedes Spielers mitverfolgen (fuer HUD auf dem Client)
task.spawn(function()
	while true do
		for _, p in Players:GetPlayers() do
			if p:GetAttribute("UebungZone") == "arena" then continue end -- Uebungsarena verwaltet UebungsArenaServer
			local r = wurzel(p)
			local z = r and zoneVon(r.Position) or nil
			if p:GetAttribute("UebungZone") ~= z then
				if z == "ausweichen" then p:SetAttribute("AusweichSeit", jetzt()) end
				p:SetAttribute("UebungZone", z)
			end
		end
		task.wait(0.3)
	end
end)

-- Wer in der Uebung stirbt (z.B. eigene Bombe), kommt dorthin zurueck
local function beobachte(p)
	p.CharacterAdded:Connect(function(char)
		local hum = char:WaitForChild("Humanoid")
		hum.Died:Connect(function()
			local z = p:GetAttribute("UebungZone")
			if z and ZONEN[z] then rueckkehr[p] = z end
		end)
		local z = rueckkehr[p]
		if z then
			rueckkehr[p] = nil
			task.wait(0.6)
			local cf = spawnVon(z)
			if cf then teleportiere(p, cf, false) end
		end
	end)
end
for _, p in Players:GetPlayers() do beobachte(p) end
Players.PlayerAdded:Connect(beobachte)
Players.PlayerRemoving:Connect(function(p) rueckkehr[p] = nil; menueZuletzt[p] = nil end)

-- ================= A: AUSWEICHEN =================
do
	local A = ZONEN.ausweichen
	local boden = A.Boden
	local AC = Vector3.new(boden.Position.X, boden.Position.Y + boden.Size.X / 2, boden.Position.Z)
	local kanonen = A.Kanonen:GetChildren()
	local vorlage = SS:WaitForChild("UebungsBombeVorlage")
	local RADIUS = 13
	local ZUENDER = 0.7 -- Sekunden nach der Landung
	local g = Vector3.new(0, -workspace.Gravity, 0)

	local function spielerDrin()
		local l = {}
		for _, p in Players:GetPlayers() do
			if p:GetAttribute("UebungZone") == "ausweichen" and wurzel(p) then table.insert(l, p) end
		end
		return l
	end

	local function richteKanone(k, ziel)
		local basis = k.Basis.Position
		local cf = CFrame.lookAt(basis, ziel) * CFrame.Angles(0, math.rad(90), 0)
		k.Lauf.CFrame = cf * CFrame.new(3, 0, 0)
		k.Muendung.CFrame = cf * CFrame.new(6.5, 0, 0)
		return cf
	end

	local function getroffen(p, pos)
		local r = wurzel(p)
		if not r then return end
		local weg = Vector3.new(r.Position.X - pos.X, 0, r.Position.Z - pos.Z)
		weg = weg.Magnitude > 0.1 and weg.Unit or Vector3.xAxis
		r.AssemblyLinearVelocity = weg * 45 + Vector3.new(0, 38, 0)
		local zeit = jetzt() - (p:GetAttribute("AusweichSeit") or jetzt())
		if zeit > (p:GetAttribute("AusweichRekord") or 0) then
			p:SetAttribute("AusweichRekord", zeit)
			schwebeText(r.Position + Vector3.new(0, 4, 0), "NEUER REKORD! " .. string.format("%.1fs", zeit), Color3.fromRGB(255, 220, 60), 260)
			konfetti(r.Position, 15)
		else
			schwebeText(r.Position + Vector3.new(0, 4, 0), "GETROFFEN! " .. string.format("%.1fs", zeit), Color3.fromRGB(255, 90, 60), 220)
		end
		p:SetAttribute("AusweichSeit", jetzt())
		p:SetAttribute("AusweichTreffer", (p:GetAttribute("AusweichTreffer") or 0) + 1)
	end

	local function setzeTimer(bombe, n)
		local body = bombe:FindFirstChild("Body")
		local gui = body and body:FindFirstChild("TimerGui")
		local bg = gui and gui:FindFirstChild("Hintergrund")
		local label = bg and bg:FindFirstChild("Zeit")
		if label then label.Text = tostring(n); label.TextColor3 = Color3.fromRGB(255, 90, 60) end
	end

	local function schiesse(k, p)
		local r = wurzel(p)
		if not r then return end
		local v = r.AssemblyLinearVelocity
		local flug = 1.05
		local streuung = Vector3.new(math.random(-30, 30) / 10, 0, math.random(-30, 30) / 10)
		local ziel = r.Position + Vector3.new(v.X, 0, v.Z) * flug * (math.random(40, 90) / 100) + streuung
		ziel = Vector3.new(ziel.X, AC.Y + 1.5, ziel.Z)
		-- im Kreis halten
		local rel = Vector3.new(ziel.X - AC.X, 0, ziel.Z - AC.Z)
		if rel.Magnitude > 30 then ziel = Vector3.new(AC.X, ziel.Y, AC.Z) + rel.Unit * 30 end
		local cf = richteKanone(k, ziel + Vector3.new(0, 12, 0))
		local start = (cf * CFrame.new(7, 0, 0)).Position
		local geschw = (ziel - start - 0.5 * g * flug * flug) / flug
		-- Rueckstoss + Muendungsblitz
		local lauf = k.Lauf
		local zurueck = lauf.CFrame * CFrame.new(-1.2, 0, 0)
		local vor = lauf.CFrame
		lauf.CFrame = zurueck
		TweenService:Create(lauf, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {CFrame = vor}):Play()
		local m = k.Muendung
		m.Color = Color3.fromRGB(255, 255, 200)
		TweenService:Create(m, TweenInfo.new(0.4), {Color = Color3.fromRGB(160, 165, 175)}):Play()
		spieleSound(k.Basis, Sounds.WURF, 0.9)

		local b = vorlage:Clone()
		b:PivotTo(CFrame.new(start))
		for _, t in b:GetDescendants() do
			if t:IsA("BasePart") then
				t.Anchored = false
				t.Massless = t.Name ~= "Body"
				t.CanCollide = t.Name == "Body"
				t.CanQuery = false
				t.CollisionGroup = "UebungKanonenBombe" -- fliegt durch Barriere/Wand, landet aber auf dem Boden
			end
		end
		b.Parent = A
		local body = b:FindFirstChild("Body")
		pcall(function() body:SetNetworkOwner(nil) end)
		body.AssemblyLinearVelocity = geschw
		local spur = body:FindFirstChild("Spur")
		if spur then spur.Enabled = true end
		setzeTimer(b, 1)
		-- Aufprall bremsen, dann kurz liegen lassen -> Zeit zum Wegrennen
		local gelandet = false
		body.Touched:Connect(function(t)
			if gelandet or t:IsDescendantOf(b) or t:IsDescendantOf(k) then return end
			if t.Parent and t.Parent:FindFirstChildOfClass("Humanoid") then return end
			gelandet = true
			local bv = body.AssemblyLinearVelocity
			body.AssemblyLinearVelocity = Vector3.new(bv.X * 0.2, math.min(bv.Y, 0) * 0.2, bv.Z * 0.2)
		end)
		local t0 = os.clock()
		while not gelandet and os.clock() - t0 < flug + 0.6 do task.wait() end
		setzeTimer(b, 0)
		task.wait(ZUENDER)
		if not body.Parent then return end
		local pos = body.Position
		b:Destroy()
		do local e = game:GetService("ServerStorage"):FindFirstChild("ExplosionPassiert") if e then e:Fire(pos, RADIUS) end end
		EffectRemote:FireAllClients(pos, RADIUS)
		for _, q in spielerDrin() do
			local rq = wurzel(q)
			if rq and (rq.Position - pos).Magnitude <= RADIUS then getroffen(q, pos) end
		end
	end

	-- Kanonen schauen im Leerlauf langsam herum
	task.spawn(function()
		local w = 0
		while true do
			local drin = #spielerDrin()
			if drin == 0 then
				w += 0.02
				for i, k in kanonen do
					richteKanone(k, AC + Vector3.new(math.cos(w + i) * 15, 8, math.sin(w + i) * 15))
				end
				task.wait(0.05)
			else
				task.wait(0.5)
			end
		end
	end)

	task.spawn(function()
		local i = 0
		while true do
			local ps = spielerDrin()
			if #ps == 0 then
				task.wait(0.4)
			else
				local laengste = 0
				for _, p in ps do laengste = math.max(laengste, jetzt() - (p:GetAttribute("AusweichSeit") or jetzt())) end
				-- wird schneller, je laenger jemand ueberlebt
				local pause = math.max(0.35, 1.5 - laengste * 0.035)
				i += 1
				task.spawn(schiesse, kanonen[(i - 1) % #kanonen + 1], ps[math.random(1, #ps)])
				task.wait(pause / math.clamp(#ps * 0.75, 1, 3))
			end
		end
	end)
end

-- ================= B: ZIELWERFEN =================
do
	local B = ZONEN.werfen
	local noobOrdner = B:FindFirstChild("Noobs") or Instance.new("Folder")
	noobOrdner.Name = "Noobs"
	noobOrdner.Parent = B
	local plaetze = B:WaitForChild("NoobPlaetze")

	local function punkte(p, n, pos, text, farbe)
		if not p or not p:IsA("Player") then return end
		local neu = (p:GetAttribute("Punkte") or 0) + n
		p:SetAttribute("Punkte", neu)
		if neu > (p:GetAttribute("PunkteRekord") or 0) then p:SetAttribute("PunkteRekord", neu) end
		schwebeText(pos, text or ("+" .. n), farbe or Color3.fromRGB(255, 220, 60), 200)
	end

	local function noobBeschreibung()
		local d = Instance.new("HumanoidDescription")
		local gelb = Color3.fromRGB(245, 205, 48)
		d.HeadColor, d.LeftArmColor, d.RightArmColor = gelb, gelb, gelb
		d.TorsoColor = Color3.fromRGB(13, 105, 172)
		d.LeftLegColor, d.RightLegColor = Color3.fromRGB(75, 151, 75), Color3.fromRGB(75, 151, 75)
		return d
	end

	local ANIM_IDLE, ANIM_LAUF = "rbxassetid://507766666", "rbxassetid://507777826"

	local function neuerNoob(startCF, schiene)
		local ok, m = pcall(function() return Players:CreateHumanoidModelFromDescription(noobBeschreibung(), Enum.HumanoidRigType.R15) end)
		if not ok or not m then return end
		m.Name = "Noob"
		local a = m:FindFirstChild("Animate")
		if a then a:Destroy() end
		local hum = m:FindFirstChildOfClass("Humanoid")
		hum.DisplayName = "Noob"
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOn
		hum.BreakJointsOnDeath = true
		local root = m:FindFirstChild("HumanoidRootPart")
		root.Anchored = true
		m:PivotTo(startCF + Vector3.new(0, hum.HipHeight + root.Size.Y / 2, 0))
		m.Parent = noobOrdner
		local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
		local anim = Instance.new("Animation")
		anim.AnimationId = schiene and ANIM_LAUF or ANIM_IDLE
		local track = animator:LoadAnimation(anim)
		track.Looped = true
		track:Play()

		-- Schaden -> Punkte fuer den Werfer, Kill-Bonus, neu spawnen
		local alt = hum.Health
		local zuletztGetroffen = 0
		hum.HealthChanged:Connect(function(neu)
			local diff = math.floor(alt - neu + 0.5)
			alt = neu
			if diff <= 0 then return end
			zuletztGetroffen = os.clock()
			local tag = hum:FindFirstChild("creator")
			local werfer = tag and tag.Value
			if neu <= 0 then
				punkte(werfer, diff + 50, root.Position + Vector3.new(0, 4, 0), "KILL! +" .. (diff + 50), Color3.fromRGB(255, 80, 80))
				konfetti(root.Position, 10)
			else
				punkte(werfer, diff, root.Position + Vector3.new(0, 4, 0), "+" .. diff)
			end
		end)
		task.spawn(function()
			while m.Parent and hum.Health > 0 do
				task.wait(0.5)
				if hum.Health < hum.MaxHealth and os.clock() - zuletztGetroffen > 2 then hum.Health = hum.MaxHealth; alt = hum.MaxHealth end
			end
		end)
		hum.Died:Connect(function()
			root.Anchored = false
			task.wait(2)
			m:Destroy()
			neuerNoob(startCF, schiene)
		end)

		-- laufende Noobs: auf der Schiene hin und her
		if schiene then
			local tempo = schiene:GetAttribute("Tempo") or 10
			local halb = schiene.Size.X / 2 - 2
			local x = 0
			local richtung = math.random() < 0.5 and -1 or 1
			local conn
			conn = RunService.Heartbeat:Connect(function(dt)
				if not m.Parent or hum.Health <= 0 then conn:Disconnect() return end
				x += richtung * tempo * dt
				if math.abs(x) > halb then x = math.clamp(x, -halb, halb); richtung = -richtung end
				local basis = schiene.Position + Vector3.new(x, hum.HipHeight + root.Size.Y / 2 - schiene.Size.Y / 2, 0)
				root.CFrame = CFrame.lookAt(basis, basis + Vector3.new(richtung, 0, 0))
			end)
		end
	end

	for _, s in plaetze:GetChildren() do
		if s.Name == "Schiene" then
			neuerNoob(CFrame.new(s.Position), s)
		elseif s.Name == "Platz" then
			local pos = Vector3.new(s.Position.X, s.Position.Y - s.Size.Y / 2, s.Position.Z)
			local wurfZ = B.Wurflinie.Position.Z
			neuerNoob(CFrame.lookAt(pos, Vector3.new(pos.X, pos.Y, wurfZ)), nil)
		end
	end

	-- Zielscheiben: Explosion in der Naehe = Punkte
	explodiert.Event:Connect(function(pos, besitzer)
		if not (typeof(besitzer) == "Instance" and besitzer:IsA("Player")) then return end
		if not inBox(B.Bereich, pos) then return end
		for _, z in B.Zielscheiben:GetChildren() do
			local mitte = z:FindFirstChild("Mitte")
			local r = z:GetAttribute("Radius") or 5
			if mitte then
				local d = Vector3.new(pos.X - mitte.Position.X, 0, pos.Z - mitte.Position.Z).Magnitude
				local n, text, farbe
				if d <= r * 0.22 + 1.2 then n, text, farbe = 100, "VOLLTREFFER! +100", Color3.fromRGB(255, 220, 60)
				elseif d <= r * 0.5 + 1 then n, text, farbe = 50, "+50", Color3.fromRGB(120, 255, 140)
				elseif d <= r + 1.5 then n, text, farbe = 25, "+25", Color3.fromRGB(150, 210, 255) end
				if n then
					punkte(besitzer, n, mitte.Position + Vector3.new(0, 4, 0), text, farbe)
					if n == 100 then konfetti(mitte.Position + Vector3.new(0, 1, 0), 18) end
					-- Scheibe blinkt
					local alt = mitte.Color
					mitte.Color = Color3.new(1, 1, 1)
					TweenService:Create(mitte, TweenInfo.new(0.6), {Color = alt}):Play()
				end
			end
		end
	end)
end

-- ================= C: 1 VS 1 =================
do
	local C = ZONEN.duell
	local felder = {C:WaitForChild("Feld1"), C:WaitForChild("Feld2")}
	local tafel = C:WaitForChild("Tafel"):FindFirstChildWhichIsA("SurfaceGui"):FindFirstChild("Text")
	local kampfbereich = C:WaitForChild("Kampfbereich")
	local STANDARD = "🟣 1 VS 1\nStellt euch auf die Felder!"
	local zustand = "frei"
	local kaempfer = {}

	local function aufFeld(feld)
		for _, p in Players:GetPlayers() do
			local r = wurzel(p)
			if r and not table.find(kaempfer, p) then
				local d = Vector3.new(r.Position.X - feld.Position.X, 0, r.Position.Z - feld.Position.Z).Magnitude
				if d < feld.Size.Y / 2 + 0.5 and math.abs(r.Position.Y - feld.Position.Y) < 6 then return p end
			end
		end
		return nil
	end

	local function feldText(i, p)
		local t = felder[i]:FindFirstChild("Anzeige") and felder[i].Anzeige:FindFirstChild("Text")
		if t then t.Text = "SPIELER " .. i .. "\n" .. (p and p.DisplayName or "frei") end
	end

	local function info(p, text) if p and p.Parent then p:SetAttribute("DuellInfo", text) end end

	local function beenden(sieger, verlierer, grund)
		if zustand ~= "kampf" then return end
		zustand = "ende"
		if sieger then
			sieger:SetAttribute("DuellSiege", (sieger:GetAttribute("DuellSiege") or 0) + 1)
			tafel.Text = "🏆 " .. sieger.DisplayName .. " GEWINNT!"
			local r = wurzel(sieger)
			if r then konfetti(r.Position, 25) end
			info(sieger, "🏆 GEWONNEN!")
			info(verlierer, "💥 Verloren – Revanche?")
		else
			tafel.Text = "⏱ UNENTSCHIEDEN"
			for _, p in kaempfer do info(p, "⏱ Unentschieden") end
		end
		local alle = kaempfer
		kaempfer = {}
		task.wait(3)
		for _, p in alle do
			if p.Parent and wurzel(p) and p:GetAttribute("UebungZone") == "duell" then teleportiere(p, spawnVon("duell"), false) end
			info(p, nil)
		end
		tafel.Text = STANDARD
		zustand = "frei"
	end

	verlasseDuell = function(p)
		local i = table.find(kaempfer, p)
		if i and zustand == "kampf" then
			local anderer = kaempfer[3 - i]
			task.spawn(beenden, anderer, p, "aufgegeben")
		end
	end

	task.spawn(function()
		while true do
			task.wait(0.2)
			local p1, p2 = aufFeld(felder[1]), aufFeld(felder[2])
			feldText(1, p1); feldText(2, p2)
			if zustand == "frei" and p1 and p2 and p1 ~= p2 then
				zustand = "countdown"
				local ok = true
				for n = 3, 1, -1 do
					tafel.Text = "⚔ " .. p1.DisplayName .. " vs " .. p2.DisplayName .. "\nStart in " .. n .. "…"
					info(p1, "Start in " .. n); info(p2, "Start in " .. n)
					task.wait(1)
					if aufFeld(felder[1]) ~= p1 or aufFeld(felder[2]) ~= p2 then ok = false break end
				end
				if not ok then
					tafel.Text = STANDARD
					info(p1, nil); info(p2, nil)
					zustand = "frei"
				else
					kaempfer = {p1, p2}
					teleportiere(p1, spawnVon("duell", "DuellSpawn1"))
					teleportiere(p2, spawnVon("duell", "DuellSpawn2"))
					tafel.Text = "⚔ KAMPF!\n" .. p1.DisplayName .. " vs " .. p2.DisplayName
					info(p1, "⚔ KAMPF! Schnapp dir eine Bombe!"); info(p2, "⚔ KAMPF! Schnapp dir eine Bombe!")
					zustand = "kampf"
					local start = os.clock()
					task.spawn(function()
						while zustand == "kampf" do
							task.wait(0.2)
							for i, p in kaempfer do
								local r = p.Parent and wurzel(p)
								if not r or not inBox(kampfbereich, r.Position) then
									beenden(kaempfer[3 - i], p)
									return
								end
							end
							if os.clock() - start > 120 then beenden(nil, nil) return end
						end
					end)
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(p) if verlasseDuell then verlasseDuell(p) end end)
end
