-- UebungsArenaServer: Wer durch das Uebungs-Portal in der Lobby laeuft, landet direkt in einer
-- EIGENEN Kopie der Arena-Map (MapId "arena") - ganz alleine, weit weg von allen anderen.
-- In der Kopie stehen Uebungs-Dummies und Zielscheiben rund um die Map verteilt:
--   DUMMY      : Bomben-Schaden = Punkte, Dummy umhauen = +50 Bonus, steht nach kurzer Zeit wieder auf
--   ZIELSCHEIBE: Bombe gegen die Scheibe werfen -> zuendet sofort, Ring 1-10 = 10-100 Punkte
-- Zurueck geht es mit dem LOBBY-Knopf (UebungsClient). Wer in der Uebungsarena stirbt, kommt wieder dorthin.
-- Die Kopie wird beim Verlassen (oder wenn der Spieler das Spiel verlaesst) wieder abgebaut.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local ZONE = "arena"          -- Wert fuer das Spieler-Attribut "UebungZone"
local MAP_ID = "arena"        -- diese Map wird kopiert
local ANZAHL_DUMMIES = 8
local ANZAHL_SCHEIBEN = 8
local ABKLINGZEIT = 3         -- Sekunden, damit das Portal nicht mehrfach ausloest
local WEIT_WEG = 30000        -- X-Position der Uebungsarenen (die Maps liegen im Kreis mit 10.000 Studs)
local DUMMY_LEBEN = 250
local DUMMY_RESPAWN = 5       -- Sekunden, bis ein umgehauener Dummy wieder steht (Finisher dauern bis ~4.6s)
local SPAWN_ABSTAND = 16      -- so weit bleiben Dummies/Scheiben von den Startpunkten weg

local Remotes = RS:WaitForChild("UebungRemotes")
local ZurueckRemote = Remotes:WaitForChild("Zurueck")
local blitz = RS:WaitForChild("PortalBlitz")
local explodiert = SS:WaitForChild("BombeExplodiert")
local SicherTeleport = require(SS:WaitForChild("SicherTeleport"))
local lobby = workspace:WaitForChild("Lobby")
local portal = lobby:WaitForChild("UebungsPortal")
local energie = portal:WaitForChild("Energie")

-- ================= Vorlage: Kopie der Arena-Map =================
local original
for _, m in workspace:GetChildren() do
	if m:IsA("Model") and m:GetAttribute("MapId") == MAP_ID then original = m break end
end
if not original then
	warn("UebungsArenaServer: keine Map mit MapId '" .. MAP_ID .. "' gefunden")
	return
end

local vorlage = original:Clone()
vorlage.Name = "UebungsArenaVorlage"
-- keine echte Map mehr (sonst Map-Wahl, Vorschau, Bots usw.)
for _, a in {"MapId", "MapName", "Radius", "Boden", "VorschauMitte", "VorschauRadius", "VorschauRichtung"} do
	vorlage:SetAttribute(a, nil)
end
vorlage:SetAttribute("Uebungsarena", true)
for _, d in vorlage:GetDescendants() do
	if d:IsA("SpawnLocation") then
		d:Destroy()
	elseif d:IsA("Humanoid") and d.Parent and d.Parent:IsA("Model") and d.Parent ~= vorlage then
		d.Parent:Destroy() -- keine Bots o.ae. mitkopieren
	elseif d:IsA("BillboardGui") and d.Name == "TimerGui" then
		d.Enabled = true -- Bomben-Timer immer sichtbar (MapServer zeigt sie sonst nur auf der aktiven Map)
	end
end
vorlage.Parent = SS

local _, vorlageGroesse = vorlage:GetBoundingBox()
local SLOT_ABSTAND = math.max(vorlageGroesse.X, vorlageGroesse.Z) + 400

local arenen = {}   -- [Player] = {model, slot, mitte, scheiben = {}}
local belegt = {}   -- [slot] = Player
local zuletzt = {}  -- [Player] = os.clock() (Portal-Abklingzeit)

-- ================= Helfer =================
local function wurzel(p)
	local c = p.Character
	local r = c and c:FindFirstChild("HumanoidRootPart")
	local h = c and c:FindFirstChildOfClass("Humanoid")
	if r and h and h.Health > 0 then return r, h, c end
	return nil
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

local function punkte(p, n, pos, text, farbe)
	if not p.Parent then return end
	local neu = (p:GetAttribute("Punkte") or 0) + n
	p:SetAttribute("Punkte", neu)
	if neu > (p:GetAttribute("PunkteRekord") or 0) then p:SetAttribute("PunkteRekord", neu) end
	schwebeText(pos, text or ("+" .. n), farbe or Color3.fromRGB(255, 220, 60), 200)
end

-- Teil bauen (relativ zu einem Basis-CFrame)
local function teil(eltern, name, groesse, cf, farbe, material, props)
	local t = Instance.new("Part")
	t.Name = name
	t.Size = groesse
	t.CFrame = cf
	t.Color = farbe
	t.Material = material or Enum.Material.SmoothPlastic
	t.TopSurface, t.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	t.Anchored = true
	if props then for k, v in props do t[k] = v end end
	t.Parent = eltern
	return t
end
local function zylinder(eltern, name, dicke, durchmesser, cf, farbe, material, props)
	local t = teil(eltern, name, Vector3.new(dicke, durchmesser, durchmesser), cf, farbe, material, props)
	t.Shape = Enum.PartType.Cylinder
	return t
end
local FLACH = CFrame.Angles(0, 0, math.rad(90))   -- Zylinder liegt flach (Achse nach oben)
local NACH_VORN = CFrame.Angles(0, math.rad(90), 0) -- Zylinder-Achse zeigt nach vorne (-Z)

-- ================= DUMMY =================
-- Angelehnt an eine Trainingspuppe: Sack-Kopf mit genaehten X-Augen, rotes Stirnband mit Baendern,
-- Lederguertel + Schulterriemen, Zielscheibe auf der Brust, steht auf einem runden Holzsockel.
local S = 1.3 -- Groesse
local STOFF = Color3.fromRGB(221, 199, 158)
local STOFF_DUNKEL = Color3.fromRGB(186, 160, 116)
local NAHT = Color3.fromRGB(58, 40, 30)
local LEDER = Color3.fromRGB(78, 52, 34)
local ROT = Color3.fromRGB(196, 44, 44)

local function baueSockel(eltern, basis)
	local f = Instance.new("Model")
	f.Name = "DummySockel"
	zylinder(f, "Rand", 0.55, 7.2, basis * CFrame.new(0, 0.275, 0) * FLACH, Color3.fromRGB(92, 64, 42), Enum.Material.Wood)
	zylinder(f, "Platte", 0.8, 6.4, basis * CFrame.new(0, 0.4, 0) * FLACH, Color3.fromRGB(138, 100, 66), Enum.Material.WoodPlanks)
	f.Parent = eltern
	return f
end

local function baueDummy(eltern, basis)
	local m = Instance.new("Model")
	m.Name = "Uebungsdummy"
	local y0 = 0.8 -- Oberkante Sockel
	local rumpfY = y0 + 3 * S
	local root = teil(m, "HumanoidRootPart", Vector3.new(2, 2, 1) * S, basis * CFrame.new(0, rumpfY, 0), STOFF, nil, {Transparency = 1, CanCollide = false})
	local B = function(x, y, z) return basis * CFrame.new(x, y, z) end
	local stoff = Enum.Material.Fabric
	local deko = {CanCollide = false, CanQuery = false}

	-- Koerper
	teil(m, "Torso", Vector3.new(2, 2, 1) * S, B(0, rumpfY, 0), STOFF, stoff)
	teil(m, "Left Leg", Vector3.new(0.95, 2, 1) * S, B(-0.5 * S, y0 + S, 0), STOFF, stoff)
	teil(m, "Right Leg", Vector3.new(0.95, 2, 1) * S, B(0.5 * S, y0 + S, 0), STOFF, stoff)
	-- Arme leicht nach aussen gestreckt
	local schulterY = y0 + 4 * S
	teil(m, "Left Arm", Vector3.new(1, 2, 1) * S, B(-1.5 * S, schulterY, 0) * CFrame.Angles(0, 0, math.rad(-16)) * CFrame.new(0, -S, 0), STOFF, stoff)
	teil(m, "Right Arm", Vector3.new(1, 2, 1) * S, B(1.5 * S, schulterY, 0) * CFrame.Angles(0, 0, math.rad(16)) * CFrame.new(0, -S, 0), STOFF, stoff)
	-- Sack-Kopf + Knoten oben
	local kopfY = y0 + 4 * S + 0.8 * S
	local kopf = teil(m, "Head", Vector3.new(1.7, 1.6, 1.5) * S, B(0, kopfY, 0), STOFF, stoff)
	teil(m, "Zipfel", Vector3.new(0.55, 0.45, 0.55) * S, B(0, kopfY + 1.0 * S, 0) * CFrame.Angles(0, math.rad(45), 0), STOFF_DUNKEL, stoff, deko)
	teil(m, "Zipfel", Vector3.new(0.3, 0.35, 0.3) * S, B(0, kopfY + 1.35 * S, 0) * CFrame.Angles(0, 0, math.rad(20)), STOFF_DUNKEL, stoff, deko)
	-- genaehte X-Augen + Mund
	local vorn = -0.75 * S - 0.03
	for _, ax in {-0.38 * S, 0.38 * S} do
		for _, w in {45, -45} do
			teil(m, "Naht", Vector3.new(0.12, 0.5, 0.06) * S, B(ax, kopfY + 0.12 * S, vorn) * CFrame.Angles(0, 0, math.rad(w)), NAHT, nil, deko)
		end
	end
	teil(m, "Naht", Vector3.new(0.85, 0.08, 0.06) * S, B(0, kopfY - 0.4 * S, vorn), NAHT, nil, deko)
	for i = -1, 1 do
		teil(m, "Naht", Vector3.new(0.07, 0.25, 0.06) * S, B(i * 0.28 * S, kopfY - 0.4 * S, vorn), NAHT, nil, deko)
	end
	-- rotes Stirnband mit zwei Baendern hinten
	teil(m, "Stirnband", Vector3.new(1.76, 0.3, 1.56) * S, B(0, kopfY + 0.45 * S, 0), ROT, stoff, deko)
	teil(m, "Band", Vector3.new(0.22, 0.75, 0.08) * S, B(-0.18 * S, kopfY + 0.15 * S, 0.8 * S) * CFrame.Angles(0, 0, math.rad(-18)), ROT, stoff, deko)
	teil(m, "Band", Vector3.new(0.22, 0.65, 0.08) * S, B(0.15 * S, kopfY + 0.18 * S, 0.8 * S) * CFrame.Angles(0, 0, math.rad(22)), ROT, stoff, deko)
	-- Lederguertel mit Schnalle + Schulterriemen
	teil(m, "Guertel", Vector3.new(2.06, 0.35, 1.06) * S, B(0, y0 + 2.2 * S, 0), LEDER, Enum.Material.Leather, deko)
	teil(m, "Schnalle", Vector3.new(0.45, 0.32, 0.06) * S, B(0, y0 + 2.2 * S, -0.53 * S - 0.02), Color3.fromRGB(214, 170, 60), Enum.Material.Metal, deko)
	teil(m, "Riemen", Vector3.new(0.32, 2.75, 1.04) * S, B(0, rumpfY, 0) * CFrame.Angles(0, 0, math.rad(-45)), LEDER, Enum.Material.Leather, deko)
	-- Flicken am Bein
	teil(m, "Flicken", Vector3.new(0.5, 0.5, 0.06) * S, B(-0.5 * S, y0 + 1.1 * S, -0.5 * S - 0.02) * CFrame.Angles(0, 0, math.rad(8)), STOFF_DUNKEL, stoff, deko)
	-- Zielscheibe auf der Brust (rot/weiss)
	local brust = B(0, rumpfY + 0.1 * S, -0.5 * S - 0.04) * NACH_VORN
	local ringe = {{0.9, ROT}, {0.66, Color3.fromRGB(245, 240, 230)}, {0.42, ROT}, {0.16, Color3.fromRGB(245, 240, 230)}}
	for i, r in ringe do
		zylinder(m, "Brustziel", 0.06, r[1] * 2 * S, brust * CFrame.new(i * 0.015, 0, 0), r[2], nil, deko)
	end

	-- alles am (verankerten) HumanoidRootPart festschweissen
	for _, p in m:GetChildren() do
		if p:IsA("BasePart") and p ~= root then
			p.Anchored = false
			local w = Instance.new("WeldConstraint")
			w.Part0 = root
			w.Part1 = p
			w.Parent = p
		end
	end
	m.PrimaryPart = root

	local hum = Instance.new("Humanoid")
	hum.RequiresNeck = false -- kein echtes Skelett, trotzdem nicht sofort "tot"
	hum.MaxHealth = DUMMY_LEBEN
	hum.Health = DUMMY_LEBEN
	hum.DisplayName = "Übungsdummy"
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOn
	hum.NameDisplayDistance = 80
	hum.HealthDisplayDistance = 80
	hum.Parent = m
	m:SetAttribute("KeinRagdoll", true) -- Todesflug (BombServer) uebernimmt das Umfallen
	m:SetAttribute("Uebungsdummy", true)
	m.Parent = eltern
	return m, hum, root, kopf
end

local function dummyAufstellen(p, a, basis)
	if arenen[p] ~= a or not a.model.Parent then return end
	local m, hum, root, kopf = baueDummy(a.ordner, basis)
	local rootCF = root.CFrame
	local fuss = basis.Position + Vector3.new(0, 0.8, 0)
	local alt = hum.Health
	local zuletztGetroffen = 0
	local wackler

	-- Treffer: kurz nach hinten kippen (um die Fuesse)
	local function wackeln()
		if hum.Health <= 0 then return end
		if wackler then wackler:Cancel() end
		root.CFrame = rootCF
		-- um die eigene Querachse drehen, Drehpunkt = Fuesse
		local r = rootCF.Rotation
		local gekippt = CFrame.new(fuss) * r * CFrame.Angles(math.rad(14), 0, 0) * r:Inverse() * CFrame.new(-fuss) * rootCF
		wackler = TweenService:Create(root, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), {CFrame = gekippt})
		wackler:Play()
	end

	hum.HealthChanged:Connect(function(neu)
		local diff = math.floor(alt - neu + 0.5)
		alt = neu
		if diff <= 0 then return end
		zuletztGetroffen = os.clock()
		local tag = hum:FindFirstChild("creator")
		local werfer = tag and tag.Value
		local oben = kopf.Position + Vector3.new(0, 3, 0)
		if werfer == p then
			if neu <= 0 then
				punkte(p, diff + 50, oben, "K.O.! +" .. (diff + 50), Color3.fromRGB(255, 80, 80))
				konfetti(oben, 10)
			else
				punkte(p, diff, oben, "+" .. diff)
			end
		end
		if neu > 0 then wackeln() end
	end)

	-- nach ein paar Sekunden Ruhe wieder volle Leben
	task.spawn(function()
		while m.Parent and hum.Health > 0 do
			task.wait(0.5)
			if hum.Health > 0 and hum.Health < hum.MaxHealth and os.clock() - zuletztGetroffen > 2.5 then
				hum.Health = hum.MaxHealth
				alt = hum.MaxHealth
			end
		end
	end)

	hum.Died:Once(function()
		if wackler then wackler:Cancel() end
		task.wait(DUMMY_RESPAWN)
		m:Destroy()
		if arenen[p] == a and a.model.Parent then
			dummyAufstellen(p, a, basis)
			konfetti(basis.Position + Vector3.new(0, 3, 0), 6)
		end
	end)
end

-- ================= ZIELSCHEIBE =================
-- Klassische Bogen-Zielscheibe (weiss, schwarz, blau, rot, gelb - je 2 Ringe) auf Strohballen + Holzstaender.
local SCHEIBE_R = 4      -- Radius der Scheibe
local SCHEIBE_HOEHE = 6.4 -- Mitte der Scheibe ueber dem Boden
local SCHEIBE_KIPP = 8   -- Grad nach hinten geneigt
local BAND_FARBEN = {
	[5] = Color3.fromRGB(244, 244, 240), -- Ring 1-2  weiss
	[4] = Color3.fromRGB(28, 28, 32),    -- Ring 3-4  schwarz
	[3] = Color3.fromRGB(0, 166, 226),   -- Ring 5-6  blau
	[2] = Color3.fromRGB(228, 34, 46),   -- Ring 7-8  rot
	[1] = Color3.fromRGB(255, 222, 0),   -- Ring 9-10 gelb
}

local function baueScheibe(eltern, basis)
	local m = Instance.new("Model")
	m.Name = "Zielscheibe"
	local holz = Color3.fromRGB(120, 84, 54)
	local function balken(name, a, b, dicke)
		local mitte = (a + b) / 2
		teil(m, name, Vector3.new(dicke, dicke, (b - a).Magnitude), basis * CFrame.lookAt(mitte, b), holz, Enum.Material.Wood)
	end
	-- Staender: zwei schraege Vorderbeine, ein Stuetzbein hinten, Querlatte
	balken("Bein", Vector3.new(-2.4, 0, -0.6), Vector3.new(-1.9, SCHEIBE_HOEHE + 1.5, 0.5), 0.5)
	balken("Bein", Vector3.new(2.4, 0, -0.6), Vector3.new(1.9, SCHEIBE_HOEHE + 1.5, 0.5), 0.5)
	balken("Stuetze", Vector3.new(0, 0, 3.6), Vector3.new(0, SCHEIBE_HOEHE + 1.2, 0.9), 0.45)
	balken("Latte", Vector3.new(-2.3, 1.9, -0.2), Vector3.new(2.3, 1.9, -0.2), 0.4)

	local mitte = basis * CFrame.new(0, SCHEIBE_HOEHE, 0) * CFrame.Angles(math.rad(SCHEIBE_KIPP), 0, 0)
	-- Strohballen hinter der Scheibe
	teil(m, "Stroh", Vector3.new(SCHEIBE_R * 2 + 0.6, SCHEIBE_R * 2 + 0.6, 1.2), mitte * CFrame.new(0, 0, 0.62), Color3.fromRGB(212, 180, 96), Enum.Material.Fabric, {CanCollide = true})
	-- Ringe: von aussen nach innen, jeweils feine Trennlinie + Farbe
	local schritt = 0.012
	local n = 0
	for k = 10, 1, -1 do
		local band = math.ceil(k / 2)
		local r = SCHEIBE_R * k / 10
		local linie = band == 4 and Color3.fromRGB(205, 205, 205) or Color3.fromRGB(30, 30, 30)
		n += 1
		zylinder(m, "Ring", 0.05, r * 2, mitte * CFrame.new(0, 0, -n * schritt) * NACH_VORN, linie)
		n += 1
		zylinder(m, "Ring", 0.05, r * 2 - 0.07, mitte * CFrame.new(0, 0, -n * schritt) * NACH_VORN, BAND_FARBEN[band])
	end
	-- kleines Kreuz in der Mitte
	teil(m, "Kreuz", Vector3.new(0.3, 0.04, 0.04), mitte * CFrame.new(0, 0, -(n + 1) * schritt), Color3.fromRGB(30, 30, 30), nil, {CanCollide = false})
	teil(m, "Kreuz", Vector3.new(0.04, 0.3, 0.04), mitte * CFrame.new(0, 0, -(n + 1) * schritt), Color3.fromRGB(30, 30, 30), nil, {CanCollide = false})

	-- Scheibe + Stroh: Bombe zuendet beim Aufprall sofort (BombServer prueft "BombenZiel")
	for _, p in m:GetChildren() do
		if p.Name == "Ring" or p.Name == "Stroh" then p:SetAttribute("BombenZiel", true) end
	end
	m.Parent = eltern
	return {model = m, mitte = mitte}
end

-- Wo hat die Explosion die Scheibe getroffen? -> Ring 1-10 (oder nil)
local function ringVon(scheibe, pos)
	local rel = scheibe.mitte:PointToObjectSpace(pos)
	if rel.Z < -6 or rel.Z > 2.5 then return nil end -- zu weit davor / dahinter
	local abstand = math.sqrt(rel.X * rel.X + rel.Y * rel.Y)
	if abstand > SCHEIBE_R + 0.6 then return nil end
	return math.clamp(10 - math.floor(abstand / SCHEIBE_R * 10), 1, 10)
end

explodiert.Event:Connect(function(pos, besitzer)
	if typeof(pos) ~= "Vector3" or typeof(besitzer) ~= "Instance" or not besitzer:IsA("Player") then return end
	local a = arenen[besitzer]
	if not a then return end
	local beste, besterRing
	for _, s in a.scheiben do
		local ring = ringVon(s, pos)
		if ring and (not besterRing or ring > besterRing) then beste, besterRing = s, ring end
	end
	if not beste then return end
	local n = besterRing * 10
	local ort = beste.mitte.Position + Vector3.new(0, SCHEIBE_R + 1.5, 0)
	if besterRing == 10 then
		punkte(besitzer, n, ort, "VOLLTREFFER! +" .. n, Color3.fromRGB(255, 220, 60))
		konfetti(beste.mitte.Position, 18)
	elseif besterRing >= 7 then
		punkte(besitzer, n, ort, "+" .. n, Color3.fromRGB(255, 120, 90))
	elseif besterRing >= 5 then
		punkte(besitzer, n, ort, "+" .. n, Color3.fromRGB(110, 200, 255))
	else
		punkte(besitzer, n, ort, "+" .. n, Color3.fromRGB(230, 230, 230))
	end
	-- Scheibe blitzt kurz auf
	local h = Instance.new("Highlight")
	h.FillColor = Color3.new(1, 1, 1)
	h.FillTransparency = 0.25
	h.OutlineTransparency = 1
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Parent = beste.model
	TweenService:Create(h, TweenInfo.new(0.5), {FillTransparency = 1}):Play()
	Debris:AddItem(h, 0.55)
end)

-- ================= Dummies + Zielscheiben verteilen =================
local function bodenUnter(m, pos)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {m}
	params.RespectCanCollide = true
	local r = workspace:Raycast(pos + Vector3.new(0, 3, 0), Vector3.new(0, -12, 0), params)
	return r and r.Position or pos
end

-- ist ueber diesem Bodenpunkt genug Platz (keine Waende, Kisten usw.)?
local PLATZ = Vector3.new(8.5, 11, 8.5)
local function platzFrei(m, boden)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {m}
	for _, t in workspace:GetPartBoundsInBox(CFrame.new(boden + Vector3.new(0, PLATZ.Y / 2 + 0.6, 0)), PLATZ, params) do
		if t.CanCollide and not t:FindFirstAncestor("Bomben") and not t:FindFirstAncestor("ArenaSpawns")
			and not t:FindFirstAncestor("BombenPunkte") then
			return false
		end
	end
	return true
end

local function verteileZiele(p, a)
	local m = a.model
	local punkteOrdner = m:FindFirstChild("BombenPunkte")
	local spawns = m:FindFirstChild("ArenaSpawns")
	local spawnPos = {}
	if spawns then
		for _, s in spawns:GetChildren() do
			if s:IsA("BasePart") then table.insert(spawnPos, s.Position) end
		end
	end
	local kandidaten = {}
	for _, pt in (punkteOrdner and punkteOrdner:GetChildren() or {}) do
		if pt:IsA("BasePart") then
			local ok = true
			for _, sp in spawnPos do
				if (pt.Position - sp).Magnitude < SPAWN_ABSTAND then ok = false break end
			end
			if ok then table.insert(kandidaten, pt) end
		end
	end

	-- moeglichst weit auseinander: immer den Punkt nehmen, der am weitesten von allen bisherigen weg ist
	local gewaehlt = {}
	local gesamt = ANZAHL_DUMMIES + ANZAHL_SCHEIBEN
	local naechster = #kandidaten > 0 and math.random(1, #kandidaten) or nil
	while naechster and #gewaehlt < gesamt do
		local pt = table.remove(kandidaten, naechster)
		local boden = bodenUnter(m, pt.Position)
		if platzFrei(m, boden) then table.insert(gewaehlt, boden) end
		naechster = nil
		local besterAbstand = -1
		for i, k in kandidaten do
			local d = math.huge
			for _, g in gewaehlt do d = math.min(d, (k.Position - g).Magnitude) end
			if d > besterAbstand then besterAbstand, naechster = d, i end
		end
	end

	for i, boden in gewaehlt do
		-- zur Mitte der Map schauen
		local blick = Vector3.new(a.mitte.X, boden.Y, a.mitte.Z)
		local basis
		if (blick - boden).Magnitude < 1 then
			basis = CFrame.new(boden) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
		else
			basis = CFrame.lookAt(boden, blick)
		end
		if i % 2 == 1 and i <= ANZAHL_DUMMIES * 2 then
			baueSockel(a.ordner, basis)
			dummyAufstellen(p, a, basis)
		else
			table.insert(a.scheiben, baueScheibe(a.ordner, basis))
		end
		-- keine Bomben mitten in Dummies/Scheiben fallen lassen
		if punkteOrdner then
			for _, pt in punkteOrdner:GetChildren() do
				if pt:IsA("BasePart") and (pt.Position - boden).Magnitude < 8 then pt:Destroy() end
			end
		end
	end
end

-- ================= Uebungsarena auf- und abbauen =================
local function baueArena(p)
	local slot = 1
	while belegt[slot] do slot += 1 end
	belegt[slot] = p
	local m = vorlage:Clone()
	m.Name = "UebungsArena_" .. p.UserId
	m:SetAttribute("Besitzer", p.UserId)
	local cf = m:GetBoundingBox()
	local ziel = Vector3.new(WEIT_WEG, cf.Position.Y, (slot - 1) * SLOT_ABSTAND)
	m:PivotTo(m:GetPivot() + (ziel - cf.Position))
	local ordner = Instance.new("Folder")
	ordner.Name = "Uebungsziele"
	ordner.Parent = m
	m.Parent = workspace
	local a = {model = m, slot = slot, ordner = ordner, mitte = ziel, scheiben = {}}
	arenen[p] = a
	verteileZiele(p, a)
	-- Bomben der Kopie aufhebbar machen
	local bomben = m:FindFirstChild("Bomben")
	local api = SS:FindFirstChild("BombBotAPI")
	if bomben and api then pcall(function() api:Invoke("einrichten", nil, bomben) end) end
	return a
end

local function abbauen(p)
	local a = arenen[p]
	if not a then return end
	arenen[p] = nil
	if belegt[a.slot] == p then belegt[a.slot] = nil end
	-- haelt er noch eine Bombe aus der Uebungsarena? loslassen, sie verschwindet mit der Arena
	local api = SS:FindFirstChild("BombBotAPI")
	if api then
		local ok, bombe = pcall(function() return api:Invoke("haelt", p) end)
		if ok and bombe and bombe:IsDescendantOf(a.model) then pcall(function() api:Invoke("loslassen", p) end) end
	end
	a.model:Destroy()
end

local function startpunkt(a)
	local spawns = a.model:FindFirstChild("ArenaSpawns")
	local liste = {}
	for _, s in (spawns and spawns:GetChildren() or {}) do
		if s:IsA("BasePart") then table.insert(liste, s) end
	end
	if #liste == 0 then return a.mitte + Vector3.new(0, 5, 0) end
	return liste[math.random(1, #liste)].Position
end

local function inArenaSetzen(p, a)
	local r, h, c = wurzel(p)
	if not r then return end
	local ziel = startpunkt(a) + Vector3.new(0, h.HipHeight + r.Size.Y / 2 + 0.5, 0)
	local blick = Vector3.new(a.mitte.X, ziel.Y, a.mitte.Z)
	if (blick - ziel).Magnitude < 0.1 then blick = ziel + Vector3.new(0, 0, -1) end
	r.AssemblyLinearVelocity = Vector3.zero
	SicherTeleport.hin(p, c, CFrame.lookAt(ziel, blick))
end

-- Platz in der Lobby vor dem Uebungs-Portal (Richtung Lobby-Mitte), auf dem Boden
local function lobbyBoden()
	local innen = Vector3.new(-energie.Position.X, 0, -energie.Position.Z)
	innen = innen.Magnitude > 0.1 and innen.Unit or Vector3.new(0, 0, 1)
	local pos = energie.Position + innen * 12
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {lobby}
	params.RespectCanCollide = true
	local r = workspace:Raycast(pos + Vector3.new(0, 4, 0), Vector3.new(0, -60, 0), params)
	pos = r and r.Position or Vector3.new(pos.X, 166, pos.Z)
	return CFrame.lookAt(pos, Vector3.new(0, pos.Y, 0))
end

-- ================= Portal / Zurueck / Tod =================
local function betreten(p)
	if p:GetAttribute("UebungZone") then return end
	local jetzt = os.clock()
	if zuletzt[p] and jetzt - zuletzt[p] < ABKLINGZEIT then return end
	zuletzt[p] = jetzt
	if not wurzel(p) then return end
	local a = arenen[p] or baueArena(p)
	p:SetAttribute("Punkte", 0)
	p:SetAttribute("UebungZone", ZONE)
	blitz:FireClient(p) -- weisser Blitz + Sound
	task.wait(0.15)
	inArenaSetzen(p, a)
end

energie.Touched:Connect(function(t)
	local char = t:FindFirstAncestorOfClass("Model")
	local p = char and Players:GetPlayerFromCharacter(char)
	if p then task.spawn(betreten, p) end
end)

ZurueckRemote.OnServerEvent:Connect(function(p)
	if p:GetAttribute("UebungZone") ~= ZONE then return end
	zuletzt[p] = os.clock() -- nicht sofort wieder durchs Portal
	p:SetAttribute("UebungZone", nil)
	local r, h, c = wurzel(p)
	if r then
		blitz:FireClient(p)
		task.wait(0.15)
		if r.Parent then
			r.AssemblyLinearVelocity = Vector3.zero
			SicherTeleport.hin(p, c, lobbyBoden() + Vector3.new(0, h.HipHeight + r.Size.Y / 2 + 0.5, 0))
		end
	end
	task.delay(1, function()
		-- inzwischen wieder reingegangen? dann die Arena behalten
		if p:GetAttribute("UebungZone") ~= ZONE then abbauen(p) end
	end)
end)

-- Wer in der Uebungsarena stirbt, kommt nach dem Respawn (in der Lobby) wieder dorthin
local function beobachte(p)
	p.CharacterAdded:Connect(function(char)
		if p:GetAttribute("UebungZone") ~= ZONE then return end
		local a = arenen[p]
		if not a then
			p:SetAttribute("UebungZone", nil)
			return
		end
		char:WaitForChild("HumanoidRootPart", 10)
		task.wait(0.6)
		if p.Character == char and p:GetAttribute("UebungZone") == ZONE and arenen[p] == a then
			inArenaSetzen(p, a)
		end
	end)
end
for _, p in Players:GetPlayers() do beobachte(p) end
Players.PlayerAdded:Connect(beobachte)
Players.PlayerRemoving:Connect(function(p)
	abbauen(p)
	zuletzt[p] = nil
end)
