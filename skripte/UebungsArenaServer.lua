-- UebungsArenaServer: Wer durch das UEBUNGS-PORTAL in der Lobby laeuft, landet direkt in der
-- Arena-Map - aber ALLEIN: jeder Spieler bekommt seine eigene Kopie der Arena, weit weg von allem.
-- In der Kopie stehen Zielscheiben und Uebungspuppen rund um die Map verteilt, dazu liegen Bomben.
--   Zielscheibe: Bombe trifft die Scheibe -> Punkte je nach Ring (10 innen ... 1 aussen) x 10
--   Uebungspuppe: Schaden = Punkte, Puppe kaputt = +50, kommt nach ein paar Sekunden wieder
-- Zurueck in die Lobby: LOBBY-Knopf oben (UebungsArenaClient). Wer in der Uebung stirbt, kommt wieder in seine Arena.
-- Kills, Tode, Coins und Bestenliste zaehlen hier NICHT (Puppen sind keine Spieler/Bots).
if not workspace:GetAttribute("MapsVerteilt") then workspace:GetAttributeChangedSignal("MapsVerteilt"):Wait() end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- ============ EINSTELLUNGEN ============
local MAP_ID = "arena"        -- welche Map als Uebungsarena kopiert wird (Attribut MapId)
local ANZAHL_ZIELSCHEIBEN = 6
local ANZAHL_PUPPEN = 8
local ANZAHL_BOMBEN = 6       -- so viele Bomben liegen immer in der Uebungsarena
local PUPPE_LEBEN = 100
local PUPPE_KILL_BONUS = 50
local PUPPE_ZURUECK = 4       -- Sekunden, bis eine kaputte Puppe wieder steht
local PLATZ_ABSTAND = 1000    -- Abstand zwischen den Arena-Kopien der Spieler
local PLATZ_START = Vector3.new(0, 100, 30000) -- weit weg von Lobby (Mitte) und Maps (Kreis mit 10.000 Radius)

local SicherTeleport = require(SS:WaitForChild("SicherTeleport"))
local bombApi = SS:WaitForChild("BombBotAPI")
local explodiert = SS:WaitForChild("BombeExplodiert")
local blitz = RS:WaitForChild("PortalBlitz")

local remotes = Instance.new("Folder")
remotes.Name = "UebungsArena"
local betretenRemote = Instance.new("RemoteEvent")
betretenRemote.Name = "Betreten" -- Server -> Client: Einblendung "Du bist in der Uebungsarena"
betretenRemote.Parent = remotes
local verlassenRemote = Instance.new("RemoteEvent")
verlassenRemote.Name = "Verlassen" -- Client -> Server: zurueck in die Lobby
verlassenRemote.Parent = remotes
remotes.Parent = RS

local lobby = workspace:WaitForChild("Lobby")
local portal = lobby:WaitForChild("UebungsPortal")
local energie = portal:WaitForChild("Energie")

-- ============ Vorlage: saubere Kopie der Arena-Map ============
local function findeMap()
	for _, m in workspace:GetChildren() do
		if m:IsA("Model") and m:GetAttribute("MapId") == MAP_ID then return m end
	end
	return nil
end
local quelle = findeMap()
if not quelle then
	warn("[UebungsArena] Map mit MapId '" .. MAP_ID .. "' nicht gefunden - Uebungsportal ist aus.")
	return
end
local vorlage = quelle:Clone()
vorlage.Name = "UebungsArenaVorlage"
-- keine "echte" Map (sonst halten MapServer, Chaos-Modus usw. sie fuer eine Spielmap)
for _, a in {"MapId", "MapName", "VorschauRichtung", "VorschauMitte", "VorschauRadius"} do vorlage:SetAttribute(a, nil) end
-- Bomben der Map raus (die verwaltet der BombServer, hier legen wir eigene hin), keine Skripte
local bombenOrdnerVorlage = vorlage:FindFirstChild("Bomben")
if bombenOrdnerVorlage then bombenOrdnerVorlage:ClearAllChildren() end
for _, d in vorlage:GetDescendants() do
	if d:IsA("LuaSourceContainer") then d:Destroy() end
end
for _, d in vorlage:GetDescendants() do
	if d:IsA("Model") and d:FindFirstChildOfClass("Humanoid") then d:Destroy() end
end
local VORLAGE_PIVOT = vorlage:GetPivot() -- MapVerteiler hat den Drehpunkt in die Mitte auf Bodenhoehe gelegt
vorlage.Parent = SS

-- ============ Bausteine ============
local RGB = Color3.fromRGB
local function teil(eltern, name, groesse, cf, farbe, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = groesse
	p.CFrame = cf
	p.Color = farbe
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = eltern
	return p
end

-- Pixel-Kreise auf ein SurfaceGui malen: jede Scheibe = eine Reihe von Zeilen (1 Frame pro Zeile)
-- scheiben = {{radius in Pixeln, Farbe}, ...} von aussen nach innen
local function pixelScheibe(gui, n, scheiben)
	local m = n / 2
	for z, s in scheiben do
		local r, farbe = s[1], s[2]
		for y = 0, n - 1 do
			local py = y + 0.5 - m
			if math.abs(py) < r then
				local halb = math.sqrt(r * r - py * py)
				local x0, x1 = math.floor(m - halb + 0.5), math.floor(m + halb + 0.5)
				if x1 > x0 then
					local f = Instance.new("Frame")
					f.BorderSizePixel = 0
					f.BackgroundColor3 = farbe
					f.Position = UDim2.fromScale(x0 / n, y / n)
					f.Size = UDim2.fromScale((x1 - x0) / n, 1 / n)
					f.ZIndex = z
					f.Parent = gui
				end
			end
		end
	end
end
-- einzelne Pixel (z.B. Gesicht): muster = Zeilen aus Zeichen, farben = {Zeichen = Farbe}
local function pixelMuster(gui, muster, farben, z)
	local h, b = #muster, #muster[1]
	for y, zeile in muster do
		for x = 1, b do
			local farbe = farben[zeile:sub(x, x)]
			if farbe then
				local f = Instance.new("Frame")
				f.BorderSizePixel = 0
				f.BackgroundColor3 = farbe
				f.Position = UDim2.fromScale((x - 1) / b, (y - 1) / h)
				f.Size = UDim2.fromScale(1 / b, 1 / h)
				f.ZIndex = z or 1
				f.Parent = gui
			end
		end
	end
end
local function surfaceGui(p, seite)
	local g = Instance.new("SurfaceGui")
	g.Face = seite or Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	g.CanvasSize = Vector2.new(400, 400)
	g.LightInfluence = 1
	g.Parent = p
	return g
end

local function schwebeText(pos, text, farbe)
	local anker = Instance.new("Part")
	anker.Anchored, anker.CanCollide, anker.CanQuery, anker.CanTouch = true, false, false, false
	anker.Transparency = 1
	anker.Size = Vector3.one * 0.2
	anker.CFrame = CFrame.new(pos)
	anker.Parent = workspace
	local g = Instance.new("BillboardGui")
	g.Size = UDim2.fromOffset(220, 60)
	g.AlwaysOnTop = true
	g.MaxDistance = 250
	g.Parent = anker
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.TextScaled = true
	t.Text = text
	t.TextColor3 = farbe
	t.TextStrokeTransparency = 0
	t.Parent = g
	TweenService:Create(anker, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {CFrame = anker.CFrame + Vector3.new(0, 5, 0)}):Play()
	TweenService:Create(t, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {TextTransparency = 1, TextStrokeTransparency = 1}):Play()
	Debris:AddItem(anker, 1.3)
end

local function punkte(p, n, pos, text, farbe)
	if not (p and p.Parent) then return end
	local neu = (p:GetAttribute("UebungsPunkte") or 0) + n
	p:SetAttribute("UebungsPunkte", neu)
	if neu > (p:GetAttribute("UebungsRekord") or 0) then p:SetAttribute("UebungsRekord", neu) end
	schwebeText(pos, text or ("+" .. n), farbe or RGB(255, 220, 60))
end

-- ============ Zielscheibe (wie eine echte Bogen-Zielscheibe, in Pixeln) ============
-- 10 Ringe: weiss, weiss, schwarz, schwarz, blau, blau, rot, rot, gelb, gelb (aussen -> innen)
local SCHEIBE_RADIUS = 5 -- Studs
local RING_FARBEN = {
	{RGB(250, 250, 250), RGB(170, 170, 175)}, -- {Ringfarbe, Linie zwischen den zwei Ringen gleicher Farbe}
	{RGB(30, 30, 34), RGB(110, 110, 118)},
	{RGB(40, 170, 230), RGB(20, 100, 160)},
	{RGB(230, 40, 45), RGB(140, 15, 20)},
	{RGB(255, 220, 40), RGB(210, 150, 20)},
}
local function baueZielscheibe(eltern, cf)
	local m = Instance.new("Model")
	m.Name = "Zielscheibe"
	local holz, holzDunkel = RGB(150, 100, 55), RGB(105, 68, 38)
	-- Staffelei: zwei Beine vorne, eins hinten
	for _, x in {-3.2, 3.2} do
		teil(m, "Bein", Vector3.new(0.6, 10, 0.6), cf * CFrame.new(x, 5, 0.6) * CFrame.Angles(math.rad(6), 0, 0), holz, Enum.Material.Wood)
	end
	teil(m, "Bein", Vector3.new(0.6, 10, 0.6), cf * CFrame.new(0, 4.6, 3) * CFrame.Angles(math.rad(-22), 0, 0), holzDunkel, Enum.Material.Wood)
	teil(m, "Quer", Vector3.new(7.6, 0.6, 0.6), cf * CFrame.new(0, 1.2, 0.5), holzDunkel, Enum.Material.Wood)
	-- Strohplatte + Scheibe vorne drauf (oben leicht nach hinten gekippt)
	local brettCF = cf * CFrame.new(0, 7, 0) * CFrame.Angles(math.rad(8), 0, 0)
	local brett = teil(m, "Scheibe", Vector3.new(11, 11, 1.2), brettCF, RGB(215, 185, 110), Enum.Material.Fabric)
	brett:SetAttribute("ZielScheibe", true)
	local g = surfaceGui(brett, Enum.NormalId.Front)
	local n = 44 -- Pixel ueber die ganze Platte (11 Studs) -> Scheibe hat 20 Pixel Radius = 5 Studs
	local liste = {{20.6, RGB(60, 60, 64)}} -- duenner Aussenrand
	for i, f in RING_FARBEN do
		local aussen = 20 - (i - 1) * 4 -- jede Farbe = 4 Pixel = 2 Ringe
		table.insert(liste, {aussen, f[1]})
		table.insert(liste, {aussen - 2, f[2]}) -- Linie zwischen den beiden Ringen
		table.insert(liste, {aussen - 2.6, f[1]})
	end
	pixelScheibe(g, n, liste)
	-- kleines Kreuz in der Mitte
	local kreuz = Instance.new("Frame")
	kreuz.BackgroundTransparency = 1
	kreuz.AnchorPoint = Vector2.new(0.5, 0.5)
	kreuz.Position = UDim2.fromScale(0.5, 0.5)
	kreuz.Size = UDim2.fromScale(5 / n, 5 / n)
	kreuz.ZIndex = 50
	kreuz.Parent = g
	pixelMuster(kreuz, {".....", "..k..", ".kkk.", "..k..", "....."}, {k = RGB(30, 30, 34)}, 50)
	m.PrimaryPart = brett
	m.Parent = eltern
	return m, brett
end

-- Treffer-Ring (10 = Mitte ... 1 = ganz aussen, 0 = daneben)
local function ringVon(brett, pos)
	local rel = brett.CFrame:PointToObjectSpace(pos)
	local d = math.sqrt(rel.X * rel.X + rel.Y * rel.Y)
	if d > SCHEIBE_RADIUS + 0.4 then return 0 end
	return math.clamp(10 - math.floor(d / (SCHEIBE_RADIUS / 10)), 1, 10)
end

-- ============ Uebungspuppe (Strohpuppe auf einem Pfahl) ============
local function bauePuppe(eltern, cf)
	local m = Instance.new("Model")
	m.Name = "Uebungspuppe"
	local sack, sackHell = RGB(186, 146, 92), RGB(205, 170, 112)
	local stroh, strohDunkel = RGB(240, 205, 90), RGB(205, 160, 50)
	local holz, naht = RGB(110, 72, 40), RGB(80, 52, 30)
	local FABRIC, WOOD = Enum.Material.Fabric, Enum.Material.Wood

	local root = teil(m, "HumanoidRootPart", Vector3.new(2, 2, 1), cf * CFrame.new(0, 5.2, 0), sack)
	root.Transparency = 1
	root.CanCollide = false

	-- Pfahl (statt Beine)
	teil(m, "Left Leg", Vector3.new(0.7, 3.6, 0.7), cf * CFrame.new(0, 1.8, 0), holz, WOOD)
	-- Koerper: Jutesack mit Naht, Flicken und Stroh, das unten rausschaut
	local torso = teil(m, "Torso", Vector3.new(2.8, 3, 1.5), cf * CFrame.new(0, 5.1, 0), sack, FABRIC)
	teil(m, "Naht", Vector3.new(0.14, 3.02, 1.52), cf * CFrame.new(-1.05, 5.1, 0), naht, FABRIC)
	teil(m, "Flicken", Vector3.new(0.7, 0.7, 0.1), cf * CFrame.new(0.85, 6.2, -0.78), RGB(120, 150, 90), FABRIC)
	for i, x in {-1.1, -0.5, 0.15, 0.75, 1.2} do
		local h = (i % 2 == 0) and 0.7 or 0.5
		teil(m, "Stroh", Vector3.new(0.35, h, 0.35), cf * CFrame.new(x, 3.6 - h / 2 + 0.05, (i % 2 == 0) and -0.4 or 0.35), (i % 2 == 0) and stroh or strohDunkel, FABRIC)
	end
	-- Zielscheibe auf der Brust (rot/weiss, Pixel)
	local brust = surfaceGui(torso, Enum.NormalId.Front)
	brust.CanvasSize = Vector2.new(280, 300)
	local feld = Instance.new("Frame")
	feld.BackgroundTransparency = 1
	feld.AnchorPoint = Vector2.new(0.5, 0.5)
	feld.Position = UDim2.fromScale(0.5, 0.5)
	feld.Size = UDim2.fromScale(0.5, 0.466) -- 1.4 x 1.4 Studs auf der 2.8 x 3 Vorderseite
	feld.Parent = brust
	pixelScheibe(feld, 14, {{7, RGB(200, 30, 35)}, {5.5, RGB(250, 245, 235)}, {4, RGB(200, 30, 35)}, {2.5, RGB(250, 245, 235)}, {1.2, RGB(200, 30, 35)}})

	-- Arme: Querstange durch die Schultern, an den Enden Strohbuendel
	teil(m, "Left Arm", Vector3.new(1.8, 0.45, 0.45), cf * CFrame.new(-2.3, 6.1, 0), holz, WOOD)
	teil(m, "Right Arm", Vector3.new(1.8, 0.45, 0.45), cf * CFrame.new(2.3, 6.1, 0), holz, WOOD)
	teil(m, "Left Hand", Vector3.new(0.8, 0.8, 0.8), cf * CFrame.new(-3.35, 6.1, 0), stroh, FABRIC)
	teil(m, "Right Hand", Vector3.new(0.8, 0.8, 0.8), cf * CFrame.new(3.35, 6.1, 0), stroh, FABRIC)

	-- Kopf: kleiner Sack mit aufgenaehtem Gesicht + Strohhaare
	local kopf = teil(m, "Head", Vector3.new(1.7, 1.6, 1.4), cf * CFrame.new(0, 7.45, 0), sackHell, FABRIC)
	teil(m, "Kordel", Vector3.new(1.3, 0.25, 1.1), cf * CFrame.new(0, 6.7, 0), naht, FABRIC)
	local gesicht = surfaceGui(kopf, Enum.NormalId.Front)
	gesicht.CanvasSize = Vector2.new(340, 320)
	pixelMuster(gesicht, {
		"..........",
		"..........",
		".k.k..k.k.",
		"..k....k..",
		".k.k..k.k.",
		"..........",
		"..........",
		"..k.k.k.k.",
		"...k.k.k..",
		"..........",
	}, {k = RGB(45, 30, 20)}, 2)
	for i, x in {-0.6, -0.2, 0.2, 0.6} do
		teil(m, "Haar", Vector3.new(0.3, (i % 2 == 0) and 0.6 or 0.45, 0.9), cf * CFrame.new(x, 8.45, 0) * CFrame.Angles(0, 0, math.rad(x * -25)), (i % 2 == 0) and stroh or strohDunkel, FABRIC)
	end

	-- alles an den (verankerten) Wurzelteil schweissen
	for _, p in m:GetChildren() do
		if p:IsA("BasePart") and p ~= root then
			p.Anchored = false
			p.CanCollide = true
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = root, p
			w.Parent = p
		end
	end

	local hum = Instance.new("Humanoid")
	hum.RigType = Enum.HumanoidRigType.R6
	hum.RequiresNeck = false
	hum.BreakJointsOnDeath = false
	hum.MaxHealth = PUPPE_LEBEN
	hum.Health = PUPPE_LEBEN
	hum.DisplayName = "Übungspuppe"
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOn
	hum.NameDisplayDistance = 80
	hum.HealthDisplayDistance = 80
	hum.Parent = m
	m.PrimaryPart = root
	m.Parent = eltern
	return m, hum, root
end

-- Sockel bleibt stehen, wenn die Puppe wegfliegt
local function baueSockel(eltern, cf)
	local s = Instance.new("Model")
	s.Name = "PuppenSockel"
	teil(s, "Platte", Vector3.new(5, 0.5, 5), cf * CFrame.new(0, 0.25, 0), RGB(125, 85, 48), Enum.Material.WoodPlanks)
	teil(s, "Rand", Vector3.new(5.4, 0.3, 5.4), cf * CFrame.new(0, 0.05, 0), RGB(90, 60, 34), Enum.Material.Wood)
	teil(s, "Halter", Vector3.new(1.2, 0.5, 1.2), cf * CFrame.new(0, 0.75, 0), RGB(80, 80, 88), Enum.Material.Metal)
	s.Parent = eltern
	return s
end

-- ============ Arenen der Spieler ============
local aktiv = {} -- [Player] = {map, platz, puppen, zielscheiben, ...}
local belegt = {} -- [platz] = true

local function freierPlatz()
	local i = 0
	while belegt[i] do i += 1 end
	belegt[i] = true
	return i
end

-- Punkte gleichmaessig ueber die Map verteilen: immer den Punkt nehmen, der am weitesten von allen bisherigen weg ist
local function verteilen(kandidaten, anzahl, fern)
	local gewaehlt = {}
	local belegtePos = table.clone(fern)
	while #gewaehlt < anzahl and #kandidaten > 0 do
		local bester, besterAbstand, besterIndex = nil, -1, nil
		for i, p in kandidaten do
			local d = math.huge
			for _, q in belegtePos do d = math.min(d, (Vector3.new(p.X - q.X, 0, p.Z - q.Z)).Magnitude) end
			if d > besterAbstand then bester, besterAbstand, besterIndex = p, d, i end
		end
		if besterAbstand < 14 then break end -- kein Platz mehr
		table.insert(gewaehlt, bester)
		table.insert(belegtePos, bester)
		table.remove(kandidaten, besterIndex)
	end
	return gewaehlt
end

local function zurMitte(pos, mitte)
	local ziel = Vector3.new(mitte.X, pos.Y, mitte.Z)
	if (ziel - pos).Magnitude < 0.5 then return CFrame.new(pos) end
	return CFrame.lookAt(pos, ziel)
end

local function spawnCF(a)
	local ordner = a.map:FindFirstChild("ArenaSpawns")
	local liste = ordner and ordner:GetChildren() or {}
	if #liste == 0 then return CFrame.new(a.mitte + Vector3.new(0, 5, 0)) end
	local s = liste[math.random(1, #liste)]
	local pos = s.Position + Vector3.new(0, s.Size.Y / 2, 0)
	return zurMitte(pos, a.mitte)
end

local function teleportInArena(p, a, mitBlitz)
	local char = p.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 then return false end
	if mitBlitz then blitz:FireClient(p); task.wait(0.15) end
	if not root.Parent then return false end
	local cf = spawnCF(a)
	root.AssemblyLinearVelocity = Vector3.zero
	SicherTeleport.hin(p, char, cf + Vector3.new(0, hum.HipHeight + root.Size.Y / 2 + 0.5, 0))
	return true
end

local function puppeAufstellen(p, a, platzCF)
	local m, hum, root = bauePuppe(a.figuren, platzCF)
	local alt = hum.Health
	local zuletztGetroffen = 0
	hum.HealthChanged:Connect(function(neu)
		local diff = math.floor(alt - neu + 0.5)
		alt = neu
		if diff <= 0 then return end
		zuletztGetroffen = os.clock()
		local tag = hum:FindFirstChild("creator")
		if not tag or tag.Value ~= p then return end -- nur der Besitzer dieser Arena sammelt Punkte
		if neu <= 0 then
			punkte(p, diff + PUPPE_KILL_BONUS, root.Position + Vector3.new(0, 5, 0), "KAPUTT! +" .. (diff + PUPPE_KILL_BONUS), RGB(255, 90, 70))
		else
			punkte(p, diff, root.Position + Vector3.new(0, 5, 0), "+" .. diff)
		end
	end)
	-- heilt sich, wenn sie eine Weile nicht getroffen wurde
	task.spawn(function()
		while m.Parent and hum.Health > 0 do
			task.wait(0.5)
			if hum.Health > 0 and hum.Health < hum.MaxHealth and os.clock() - zuletztGetroffen > 3 then
				hum.Health = hum.MaxHealth
				alt = hum.MaxHealth
			end
		end
	end)
	hum.Died:Connect(function()
		task.wait(PUPPE_ZURUECK)
		if m.Parent then m:Destroy() end
		if aktiv[p] == a and a.map.Parent then puppeAufstellen(p, a, platzCF) end
	end)
end

-- Bomben nachlegen (immer ANZAHL_BOMBEN Stueck)
local function bombenNachlegen(p, a)
	local ordner = a.bomben
	local anzahl = #ordner:GetChildren() + ((p:GetAttribute("HasBomb") and 1) or 0)
	if anzahl >= ANZAHL_BOMBEN then return end
	local char = p.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local frei = {}
	for _, bp in a.bombenPunkte do
		local ok = true
		for _, q in a.figurenPos do if (bp - q).Magnitude < 7 then ok = false break end end
		if ok and root and (Vector3.new(bp.X - root.Position.X, 0, bp.Z - root.Position.Z)).Magnitude < 10 then ok = false end
		if ok then
			for _, b in ordner:GetChildren() do
				if b:IsA("Model") and (b:GetPivot().Position - bp).Magnitude < 15 then ok = false break end
			end
		end
		if ok then table.insert(frei, bp) end
	end
	if #frei == 0 then return end
	local pos = frei[math.random(1, #frei)]
	local ok, bombe = pcall(function() return bombApi:Invoke("spawnen", false, pos, ordner) end)
	if ok and bombe then
		-- Bomben-Timer sichtbar machen (die Vorlage kann von einer gerade inaktiven Map stammen)
		task.defer(function()
			for _, d in bombe:GetDescendants() do
				if d:IsA("BillboardGui") and d.Name == "TimerGui" then d.Enabled = true end
			end
		end)
	end
end

local function arenaBauen(p)
	local platz = freierPlatz()
	local map = vorlage:Clone()
	map.Name = "UebungsArena_" .. p.UserId
	local ziel = PLATZ_START + Vector3.new((platz % 2 == 0 and 1 or -1) * math.ceil(platz / 2) * PLATZ_ABSTAND, 0, 0)
	map:PivotTo(CFrame.new(ziel) * VORLAGE_PIVOT.Rotation)
	local a = {map = map, platz = platz, mitte = ziel, figurenPos = {}, bombenPunkte = {}}
	a.bomben = map:FindFirstChild("Bomben") or Instance.new("Folder")
	a.bomben.Name = "Bomben"
	a.bomben.Parent = map
	a.figuren = Instance.new("Folder")
	a.figuren.Name = "UebungsFiguren"
	a.figuren.Parent = map

	-- Plaetze: die "BombenPunkte" der Map sind erreichbare, flache Stellen
	local kandidaten = {}
	local punkteOrdner = map:FindFirstChild("BombenPunkte")
	for _, bp in punkteOrdner and punkteOrdner:GetChildren() or {} do
		if bp:IsA("BasePart") then
			table.insert(kandidaten, bp.Position)
			table.insert(a.bombenPunkte, bp.Position)
		end
	end
	local spawns = {}
	local spawnOrdner = map:FindFirstChild("ArenaSpawns")
	for _, s in spawnOrdner and spawnOrdner:GetChildren() or {} do
		if s:IsA("BasePart") then table.insert(spawns, s.Position) end
	end
	-- nicht direkt auf einen Startpunkt stellen
	for i = #kandidaten, 1, -1 do
		for _, s in spawns do
			if (Vector3.new(kandidaten[i].X - s.X, 0, kandidaten[i].Z - s.Z)).Magnitude < 12 then table.remove(kandidaten, i) break end
		end
	end
	-- erst die Zielscheiben, dann die Puppen in die Luecken - so weit wie moeglich auseinander
	local fuerZiele = verteilen(kandidaten, ANZAHL_ZIELSCHEIBEN, spawns)
	local fuerPuppen = verteilen(kandidaten, ANZAHL_PUPPEN, table.move(fuerZiele, 1, #fuerZiele, #spawns + 1, table.clone(spawns)))
	for _, pos in fuerZiele do
		local _, brett = baueZielscheibe(a.figuren, zurMitte(pos, ziel))
		table.insert(a.figurenPos, pos)
		brett.Touched:Connect(function(t)
			-- nur fliegende Bomben aus DIESER Arena zaehlen (gehaltene haengen an der Hand)
			if t.Name ~= "Body" or not t.Parent or t.Parent.Parent ~= a.bomben then return end
			local bombe = t.Parent
			if bombe:GetAttribute("ScheibeGetroffen") or bombApi:Invoke("haelt", p) == bombe then return end
			bombe:SetAttribute("ScheibeGetroffen", true)
			local ring = ringVon(brett, t.Position)
			if ring <= 0 then return end
			local text, farbe = "+" .. ring * 10, RGB(255, 255, 255)
			if ring == 10 then text, farbe = "VOLLTREFFER! +100", RGB(255, 220, 40)
			elseif ring >= 7 then farbe = RGB(255, 110, 90)
			elseif ring >= 5 then farbe = RGB(110, 200, 255) end
			punkte(p, ring * 10, brett.Position + brett.CFrame.LookVector * 1 + Vector3.new(0, 6.5, 0), text, farbe)
			-- Scheibe zuckt kurz
			local alt = brett.CFrame
			brett.CFrame = alt * CFrame.Angles(math.rad(-6), 0, 0)
			TweenService:Create(brett, TweenInfo.new(0.35, Enum.EasingStyle.Back), {CFrame = alt}):Play()
		end)
	end
	for _, pos in fuerPuppen do
		local cf = zurMitte(pos, ziel)
		baueSockel(a.figuren, cf)
		puppeAufstellen(p, a, cf * CFrame.new(0, 0.5, 0))
		table.insert(a.figurenPos, pos)
	end

	map.Parent = workspace
	return a
end

local function arenaWeg(p)
	local a = aktiv[p]
	if not a then return end
	aktiv[p] = nil
	belegt[a.platz] = nil
	if a.loop then task.cancel(a.loop) end
	-- gehaltene Bombe aus dieser Arena fallen lassen
	local gehalten = bombApi:Invoke("haelt", p)
	if gehalten and gehalten:IsDescendantOf(a.map) then pcall(function() bombApi:Invoke("loslassen", p) end) end
	a.map:Destroy()
	if p.Parent then
		p:SetAttribute("UebungsArena", nil)
	end
end

-- Lobby: direkt vor dem Uebungsportal, Blick in die Lobby
local function lobbyCF(hum, root)
	local n = energie.CFrame.LookVector
	local mitte = Vector3.new(0, energie.Position.Y, 0)
	local seite = ((mitte - energie.Position):Dot(n) >= 0) and 1 or -1
	local boden = energie.Position.Y - energie.Size.Y / 2
	local pos = Vector3.new(energie.Position.X, boden, energie.Position.Z) + n * seite * 10
	pos += Vector3.new(0, hum.HipHeight + root.Size.Y / 2 + 0.5, 0)
	return CFrame.lookAt(pos, Vector3.new(mitte.X, pos.Y, mitte.Z))
end

-- ============ Portal / Verlassen / Tod ============
local zuletzt = {}
local function betreten(p)
	if aktiv[p] then return end
	if zuletzt[p] and os.clock() - zuletzt[p] < 3 then return end
	zuletzt[p] = os.clock()
	local char = p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	local ok, a = pcall(arenaBauen, p)
	if not ok then warn("[UebungsArena] " .. tostring(a)) return end
	if not p.Parent then a.map:Destroy(); belegt[a.platz] = nil return end
	aktiv[p] = a
	p:SetAttribute("UebungsArena", true)
	p:SetAttribute("UebungsPunkte", 0)
	if not teleportInArena(p, a, true) then arenaWeg(p) return end
	betretenRemote:FireClient(p)
	a.loop = task.spawn(function()
		while aktiv[p] == a do
			pcall(bombenNachlegen, p, a)
			task.wait(1.5)
		end
	end)
	-- erste Bomben gleich hinlegen
	for _ = 1, ANZAHL_BOMBEN do pcall(bombenNachlegen, p, a) end
end

energie.Touched:Connect(function(t)
	local char = t:FindFirstAncestorOfClass("Model")
	local p = char and Players:GetPlayerFromCharacter(char)
	if p then task.spawn(betreten, p) end
end)

verlassenRemote.OnServerEvent:Connect(function(p)
	if not aktiv[p] then return end
	zuletzt[p] = os.clock() -- nicht sofort wieder ins Portal laufen
	local char = p.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	arenaWeg(p)
	if root and hum and hum.Health > 0 then
		blitz:FireClient(p)
		task.wait(0.15)
		if root.Parent then SicherTeleport.hin(p, char, lobbyCF(hum, root)) end
	end
end)

-- Wer in der Uebung stirbt (z.B. eigene Bombe), kommt nach dem Respawn wieder in seine Arena
local function beobachte(p)
	p.CharacterAdded:Connect(function(char)
		local a = aktiv[p]
		if not a then return end
		char:WaitForChild("HumanoidRootPart", 10)
		task.wait(0.5)
		if aktiv[p] == a and p.Character == char then
			zuletzt[p] = os.clock()
			teleportInArena(p, a, false)
		end
	end)
end
for _, p in Players:GetPlayers() do beobachte(p) end
Players.PlayerAdded:Connect(beobachte)
Players.PlayerRemoving:Connect(function(p)
	arenaWeg(p)
	zuletzt[p] = nil
end)

-- Explosion direkt an einer Zielscheibe (Bombe lag/rollte davor): kleine Trostpunkte
explodiert.Event:Connect(function(pos, besitzer)
	if typeof(besitzer) ~= "Instance" or not besitzer:IsA("Player") then return end
	local a = aktiv[besitzer]
	if not a then return end
	for _, z in a.figuren:GetChildren() do
		local brett = z.Name == "Zielscheibe" and z:FindFirstChild("Scheibe")
		if brett and (brett.Position - pos).Magnitude < SCHEIBE_RADIUS + 3 then
			punkte(besitzer, 5, brett.Position + Vector3.new(0, 7, 0), "+5", RGB(200, 200, 200))
		end
	end
end)
