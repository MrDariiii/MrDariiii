-- SkinExplosionen: jeder Bomben-Skin hat eine KOMPLETT eigene, mehrstufige Explosion.
--   M.farben(skin)                -> Farbpalette (auch fuer die Shop-Vorschau)
--   M.explosion(skin, pos, radius) -> spielt die ganze Explosion (ohne Sound/Kamera, das macht BombClient)
-- Gemeinsam fuer alle: flackerndes Licht, Luft-Druckwelle, Bodenring + Staub in der Farbe des Untergrunds.
-- Je Skin eigenes "Rezept" (Feuerball, Schleim, Wasser, Eisstacheln, Runen, Mond, Schatten ...).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local Q = require(ReplicatedStorage:WaitForChild("QuestConfig"))

local M = {}

-- ============================================================
--  EINSTELLUNGEN: Pixel-Look + Staerke der Explosion
-- ============================================================
local PIXEL = true   -- true = alles aus eckigen Bloecken, Partikel als Pixel-Quadrate, keine weichen Leuchtspuren
local GROESSE = 0.7  -- Groesse der Explosions-Optik (1 = wie frueher, kleiner = kleiner). Schaden/Radius aendert das NICHT
local MENGE = 0.5    -- Anzahl Partikel + Splitter (1 = wie frueher)
local LICHT = 0.4    -- Helligkeit vom Lichtblitz (1 = wie frueher)

local RGB = Color3.fromRGB
local V1 = Vector3.one
local TEX_FUNKEN = "rbxasset://textures/particles/sparkles_main.dds"
local TEX_RAUCH = "rbxasset://textures/particles/smoke_main.dds"
local TEX_FEUER = "rbxasset://textures/particles/fire_main.dds"
local BALL, BLOCK, ZYL = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder
local NEON, GLAS, PLASTIK, EIS, METALL, FF = Enum.Material.Neon, Enum.Material.Glass, Enum.Material.SmoothPlastic, Enum.Material.Ice, Enum.Material.Metal, Enum.Material.ForceField

local STANDARD = {blitz = RGB(255, 250, 220), feuer = RGB(255, 140, 40), feuer2 = RGB(200, 60, 20), licht = RGB(255, 180, 90),
	funke1 = RGB(255, 230, 150), funke2 = RGB(255, 120, 30), flamme1 = RGB(255, 200, 80), flamme2 = RGB(230, 70, 20), rauch1 = RGB(60, 58, 56), rauch2 = RGB(150, 146, 140)}

local PALETTEN = {
	rot = {feuer = RGB(255, 90, 20), feuer2 = RGB(170, 20, 10), licht = RGB(255, 110, 40), flamme1 = RGB(255, 170, 40), flamme2 = RGB(200, 30, 10), rauch1 = RGB(40, 30, 28), rauch2 = RGB(110, 90, 80)},
	gruen = {blitz = RGB(220, 255, 200), feuer = RGB(110, 255, 70), feuer2 = RGB(30, 120, 20), licht = RGB(120, 255, 90), funke1 = RGB(200, 255, 150), funke2 = RGB(60, 200, 40), flamme1 = RGB(160, 255, 90), flamme2 = RGB(40, 150, 30), rauch1 = RGB(60, 120, 40), rauch2 = RGB(120, 190, 80)},
	blau = {blitz = RGB(220, 245, 255), feuer = RGB(60, 150, 255), feuer2 = RGB(20, 60, 160), licht = RGB(90, 170, 255), funke1 = RGB(200, 240, 255), funke2 = RGB(60, 140, 255), flamme1 = RGB(120, 200, 255), flamme2 = RGB(30, 90, 200), rauch1 = RGB(150, 190, 230), rauch2 = RGB(220, 240, 255)},
	lila = {blitz = RGB(245, 220, 255), feuer = RGB(180, 80, 255), feuer2 = RGB(80, 20, 150), licht = RGB(190, 110, 255), funke1 = RGB(255, 220, 255), funke2 = RGB(170, 70, 255), flamme1 = RGB(210, 140, 255), flamme2 = RGB(110, 40, 200), rauch1 = RGB(80, 50, 110), rauch2 = RGB(150, 110, 190)},
	pink = {blitz = RGB(255, 230, 245), feuer = RGB(255, 110, 190), feuer2 = RGB(200, 40, 130), licht = RGB(255, 130, 200), funke1 = RGB(255, 230, 250), funke2 = RGB(255, 100, 190), flamme1 = RGB(255, 170, 220), flamme2 = RGB(230, 70, 160), rauch1 = RGB(240, 170, 210), rauch2 = RGB(255, 220, 240)},
	weiss = {blitz = RGB(255, 255, 255), feuer = RGB(220, 240, 255), feuer2 = RGB(150, 190, 230), licht = RGB(200, 230, 255), funke1 = RGB(255, 255, 255), funke2 = RGB(170, 220, 255), flamme1 = RGB(230, 245, 255), flamme2 = RGB(160, 200, 240), rauch1 = RGB(220, 230, 240), rauch2 = RGB(255, 255, 255)},
	gold = {blitz = RGB(255, 250, 200), feuer = RGB(255, 210, 60), feuer2 = RGB(200, 140, 10), licht = RGB(255, 210, 80), funke1 = RGB(255, 250, 180), funke2 = RGB(255, 190, 30), flamme1 = RGB(255, 230, 110), flamme2 = RGB(220, 150, 20), rauch1 = RGB(150, 120, 60), rauch2 = RGB(220, 200, 140)},
	diamant = {blitz = RGB(230, 255, 255), feuer = RGB(110, 240, 255), feuer2 = RGB(30, 150, 200), licht = RGB(130, 240, 255), funke1 = RGB(255, 255, 255), funke2 = RGB(90, 230, 255), flamme1 = RGB(170, 250, 255), flamme2 = RGB(50, 180, 230), rauch1 = RGB(150, 210, 230), rauch2 = RGB(230, 250, 255)},
	kuerbis = {feuer = RGB(255, 130, 20), feuer2 = RGB(180, 50, 0), licht = RGB(255, 140, 30), funke1 = RGB(255, 220, 90), funke2 = RGB(255, 110, 10), rauch1 = RGB(60, 30, 70), rauch2 = RGB(110, 70, 120)},
	gruft = {blitz = RGB(230, 210, 255), feuer = RGB(150, 60, 230), feuer2 = RGB(40, 10, 70), licht = RGB(170, 80, 255), funke1 = RGB(220, 190, 255), funke2 = RGB(130, 50, 220), flamme1 = RGB(180, 110, 255), flamme2 = RGB(70, 20, 140), rauch1 = RGB(30, 20, 40), rauch2 = RGB(80, 60, 100)},
	blutmond = {blitz = RGB(255, 210, 200), feuer = RGB(220, 20, 40), feuer2 = RGB(90, 0, 10), licht = RGB(255, 40, 40), funke1 = RGB(255, 160, 140), funke2 = RGB(200, 10, 30), flamme1 = RGB(255, 60, 50), flamme2 = RGB(130, 0, 10), rauch1 = RGB(50, 10, 15), rauch2 = RGB(110, 30, 40)},
	geisterbombe = {blitz = RGB(230, 255, 240), feuer = RGB(170, 255, 210), feuer2 = RGB(60, 160, 120), licht = RGB(170, 255, 210), funke1 = RGB(240, 255, 250), funke2 = RGB(140, 255, 200), flamme1 = RGB(190, 255, 225), flamme2 = RGB(80, 200, 150), rauch1 = RGB(170, 220, 200), rauch2 = RGB(230, 255, 245)},
	hexenkessel = {feuer = RGB(80, 230, 60), feuer2 = RGB(20, 100, 20), licht = RGB(90, 255, 70), funke1 = RGB(200, 255, 120), funke2 = RGB(60, 210, 40), flamme1 = RGB(130, 255, 80), flamme2 = RGB(30, 140, 30), rauch1 = RGB(40, 80, 30), rauch2 = RGB(90, 150, 60)},
	nachtschatten = {blitz = RGB(200, 180, 255), feuer = RGB(60, 30, 110), feuer2 = RGB(10, 0, 25), licht = RGB(120, 70, 220), funke1 = RGB(180, 150, 255), funke2 = RGB(70, 30, 160), flamme1 = RGB(90, 50, 170), flamme2 = RGB(20, 5, 50), rauch1 = RGB(10, 5, 20), rauch2 = RGB(40, 25, 70)},
}

function M.farben(skinId)
	local P = table.clone(STANDARD)
	if not skinId or skinId == "standard" then return P end
	local fest = PALETTEN[skinId]
	if not fest then
		local it = Q.item("skins", skinId)
		local ok, f = pcall(function() return Color3.fromHex(it.farbe) end)
		if ok and f then
			fest = {blitz = f:Lerp(Color3.new(1, 1, 1), 0.8), feuer = f:Lerp(Color3.new(1, 1, 1), 0.15), feuer2 = f:Lerp(Color3.new(), 0.5), licht = f,
				funke1 = f:Lerp(Color3.new(1, 1, 1), 0.6), funke2 = f, flamme1 = f:Lerp(Color3.new(1, 1, 1), 0.3), flamme2 = f:Lerp(Color3.new(), 0.35)}
		end
	end
	for k, v in fest or {} do P[k] = v end
	return P
end

-- =================== Bausteine ===================
local function teil(ordner, form, groesse, farbe, cf, material)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	if PIXEL then form = BLOCK end -- Kugeln/Zylinder werden zu Pixel-Bloecken
	p.Shape = form or BLOCK
	p.Size = groesse
	p.Color = farbe
	p.Material = material or NEON
	p.CFrame = cf
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = ordner
	return p
end
local function tw(o, t, ziel, stil, richtung)
	local x = TweenService:Create(o, TweenInfo.new(t, stil or Enum.EasingStyle.Quad, richtung or Enum.EasingDirection.Out), ziel)
	x:Play()
	return x
end
local function spaeter(t, f) task.delay(t, f) end
local function zufallsRichtung(hoch)
	local w = math.random() * math.pi * 2
	local y = math.random() * (hoch or 1)
	return Vector3.new(math.cos(w) * (1 - y * 0.5), y, math.sin(w) * (1 - y * 0.5)).Unit
end
local function nachhall(zeit) -- Effekte, die laenger leben duerfen als die Explosion selbst
	local m = Instance.new("Folder")
	m.Name = "SkinFX"
	m.Parent = workspace
	Debris:AddItem(m, zeit)
	return m
end
local function nk(t, v) return NumberSequenceKeypoint.new(t, v) end
local function partikel(ordner, pos, eig, anzahl, dauerRate)
	local h = teil(ordner, BLOCK, V1 * 0.2, Color3.new(), CFrame.new(pos))
	h.Transparency = 1
	local a = Instance.new("Attachment")
	a.Parent = h
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	for k, v in eig do e[k] = v end
	if PIXEL then -- ohne Textur = harte Quadrate, nicht gedreht -> Pixel
		e.Texture = ""
		e.Rotation = NumberRange.new(0)
		e.RotSpeed = NumberRange.new(0)
	end
	e.Parent = a
	if anzahl and anzahl > 0 then e:Emit(math.max(1, math.ceil(anzahl * MENGE))) end
	if dauerRate then -- {rate, sekunden}: eine Weile weiter ausstossen
		e.Rate = dauerRate[1] * MENGE
		e.Enabled = true
		spaeter(dauerRate[2], function() e.Enabled = false end)
	end
	return e, h
end
local function trail(p, farbe, laenge, breite)
	if PIXEL then return end -- weiche Leuchtspuren passen nicht zum Pixel-Look
	local a0 = Instance.new("Attachment") a0.Position = Vector3.new(0, (breite or 0.4) / 2, 0) a0.Parent = p
	local a1 = Instance.new("Attachment") a1.Position = Vector3.new(0, -(breite or 0.4) / 2, 0) a1.Parent = p
	local t = Instance.new("Trail")
	t.Attachment0, t.Attachment1 = a0, a1
	t.Lifetime = laenge or 0.3
	t.Color = ColorSequence.new(farbe)
	t.Transparency = NumberSequence.new(0.15, 1)
	t.LightEmission = 1
	t.FaceCamera = true
	t.WidthScale = NumberSequence.new(1, 0)
	t.Parent = p
end
-- Teile fliegen im Bogen nach aussen (Splitter), drehen sich, verblassen; optional mit Leuchtspur
local function truemmer(ordner, pos, anzahl, weite, dauer, bauen, spurFarbe, schwerkraft)
	anzahl = math.max(1, math.ceil(anzahl * MENGE))
	for i = 1, anzahl do
		local p = bauen(i)
		if spurFarbe then trail(p, spurFarbe, 0.25, math.min(p.Size.X, 0.6)) end
		local r = zufallsRichtung(0.95)
		local start = os.clock()
		local dreh = CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		local v = r * weite * (0.55 + math.random() * 0.6)
		local g = schwerkraft or 0.9
		local drehTempo = 4 + math.random() * 8
		task.spawn(function()
			while p.Parent do
				local t = (os.clock() - start) / dauer
				if t >= 1 then p:Destroy() break end
				local pp = pos + v * t + Vector3.new(0, -weite * g * t * t, 0)
				p.CFrame = CFrame.new(pp) * dreh * CFrame.Angles(t * drehTempo, t * drehTempo * 0.7, 0)
				p.Transparency = math.max(p:GetAttribute("T0") or 0, (t - 0.65) / 0.35)
				task.wait()
			end
		end)
	end
end
local function ring(ordner, pos, farbe, radius, dauer, material, dicke, cfOverride)
	local cf = cfOverride or (CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2))
	local r = teil(ordner, ZYL, Vector3.new(dicke or 0.3, 1, 1), farbe, cf, material)
	tw(r, dauer, {Size = Vector3.new((dicke or 0.3) * 0.5, radius * 2, radius * 2), Transparency = 1}, Enum.EasingStyle.Cubic)
	return r
end
-- Kamera-zugewandte Ausrichtung (fuer Scheiben/Gesichter)
local function zurKamera(pos)
	local cam = workspace.CurrentCamera
	if not cam then return CFrame.new(pos) end
	return CFrame.lookAt(pos, Vector3.new(cam.CFrame.Position.X, pos.Y, cam.CFrame.Position.Z))
end

-- =================== Boden ===================
local function bodenTreffer(pos)
	local ign = {}
	for _, pl in Players:GetPlayers() do if pl.Character then table.insert(ign, pl.Character) end end
	for _, c in workspace:GetChildren() do
		if c.Name == "BombExplosionFX" or c.Name == "SkinFX" or c:FindFirstChildOfClass("Humanoid") then table.insert(ign, c) end
	end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = ign
	rp.IgnoreWater = false
	return workspace:Raycast(pos + Vector3.new(0, 2, 0), Vector3.new(0, -40, 0), rp)
end
local function bodenFarbe(res)
	if not res then return RGB(140, 130, 115) end
	if res.Instance:IsA("Terrain") then
		local ok, c = pcall(function() return workspace.Terrain:GetMaterialColor(res.Material) end)
		return ok and c or RGB(140, 130, 115)
	end
	return res.Instance.Color
end
local function flachCF(p, n) -- Zylinder liegt flach auf einer Flaeche mit Normale n
	n = n or Vector3.yAxis
	local quer = n:Cross(Vector3.zAxis)
	if quer.Magnitude < 0.1 then quer = n:Cross(Vector3.xAxis) end
	return CFrame.fromMatrix(p, n, quer.Unit)
end
-- Bodenring + Staubwolke in Untergrund-Farbe (+ optional Brandfleck/Pfuetze)
local function bodenEffekte(o, pos, R, ringFarbe, opts)
	opts = opts or {}
	local res = bodenTreffer(pos)
	if not res or (pos - res.Position).Magnitude > R * 1.5 then return nil end
	local bp, n = res.Position, res.Normal
	ring(o, nil, ringFarbe, R * 1.25, 0.45, NEON, 0.25, flachCF(bp + n * 0.15, n))
	ring(o, nil, ringFarbe:Lerp(Color3.new(1, 1, 1), 0.5), R * 0.8, 0.3, NEON, 0.15, flachCF(bp + n * 0.2, n))
	local staub = bodenFarbe(res):Lerp(RGB(200, 190, 170), 0.25)
	if opts.staub ~= false then
		partikel(o, bp + n * 0.6, {Texture = TEX_RAUCH, Color = ColorSequence.new(staub, staub:Lerp(Color3.new(1, 1, 1), 0.3)), Size = NumberSequence.new({nk(0, R * 0.15), nk(1, R * 0.55)}),
			Transparency = NumberSequence.new({nk(0, 0.35), nk(0.6, 0.6), nk(1, 1)}), Lifetime = NumberRange.new(1, 1.8), Speed = NumberRange.new(R * 1.3, R * 2),
			SpreadAngle = Vector2.new(84, 84), EmissionDirection = Enum.NormalId.Top, Drag = 4, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-60, 60), Acceleration = Vector3.new(0, 1.5, 0)}, 34)
		-- kleine Steinchen/Erdbrocken
		truemmer(o, bp + n * 0.5, 10, R * 0.7, 0.7, function()
			return teil(o, BLOCK, V1 * (0.25 + math.random() * 0.35), staub:Lerp(Color3.new(), 0.25), CFrame.new(bp), PLASTIK)
		end, nil, 1.3)
	end
	if opts.fleck then -- Brandfleck / Pfuetze bleibt ein paar Sekunden liegen
		local nh = nachhall(opts.fleckZeit or 9)
		local f = teil(nh, ZYL, Vector3.new(0.12, 1, 1), opts.fleck, flachCF(bp + n * 0.06, n), opts.fleckMaterial or PLASTIK)
		f.Transparency = opts.fleckT or 0.2
		local g = R * (opts.fleckGroesse or 1.1)
		tw(f, 0.25, {Size = Vector3.new(0.12, g * 2, g * 2)})
		spaeter((opts.fleckZeit or 9) - 3, function() if f.Parent then tw(f, 2.8, {Transparency = 1}) end end)
		if opts.fleckSchrumpft then spaeter(0.3, function() if f.Parent then tw(f, (opts.fleckZeit or 9) - 0.4, {Size = Vector3.new(0.12, 0.2, 0.2)}, Enum.EasingStyle.Sine) end end) end
		if opts.gluehen then -- gluehende Raender
			local gl = teil(nh, ZYL, Vector3.new(0.1, 1, 1), opts.gluehen, flachCF(bp + n * 0.09, n), NEON)
			gl.Transparency = 0.3
			tw(gl, 0.25, {Size = Vector3.new(0.1, g * 1.5, g * 1.5)})
			spaeter(0.4, function() if gl.Parent then tw(gl, 3, {Transparency = 1, Size = Vector3.new(0.1, g * 1.2, g * 1.2)}) end end)
		end
	end
	return res
end

-- =================== Kern-Bausteine ===================
local function lichtBlitz(o, pos, R, farbe, staerke, dauer)
	local h = teil(o, BLOCK, V1 * 0.1, Color3.new(), CFrame.new(pos))
	h.Transparency = 1
	local l = Instance.new("PointLight")
	l.Color = farbe
	staerke = (staerke or 12) * LICHT
	l.Range = math.min(R * 3.5, 60)
	l.Brightness = staerke
	l.Shadows = true
	l.Parent = h
	task.spawn(function() -- flackert beim Ausklingen
		local start, d = os.clock(), dauer or 0.8
		while l.Parent do
			local t = (os.clock() - start) / d
			if t >= 1 then l.Brightness = 0 break end
			l.Brightness = (staerke or 12) * (1 - t) ^ 1.6 * (0.75 + math.random() * 0.5)
			task.wait(0.03)
		end
	end)
end
local function luftwelle(o, pos, R, farbe)
	local w = teil(o, BALL, V1, farbe or Color3.new(1, 1, 1), CFrame.new(pos), FF)
	tw(w, 0.35, {Size = V1 * R * 2.2, Transparency = 1}, Enum.EasingStyle.Cubic)
end
local function blitzKugel(o, pos, R, farbe, f)
	local b = teil(o, BALL, V1 * R * 0.25, farbe, CFrame.new(pos))
	tw(b, 0.12, {Size = V1 * R * 1.3 * (f or 1), Transparency = 1})
end
-- Feuerball aus mehreren "Wolken"-Kugeln, die nacheinander aufquellen und zu Rauch werden
local function feuerball(o, pos, R, P, f, rauchHoch)
	f = f or 1
	blitzKugel(o, pos, R, P.blitz, f)
	local nh = nachhall(3)
	for i = 1, 8 do
		local off = (i == 1) and Vector3.zero or (zufallsRichtung(1) * R * 0.32 * f + Vector3.new(0, R * 0.1 * f, 0))
		local b = teil(o, BALL, V1 * R * 0.2, P.feuer:Lerp(P.blitz, i == 1 and 0.5 or 0), CFrame.new(pos + off * 0.3))
		local ziel = R * (0.65 + math.random() * 0.4) * f
		spaeter(i * 0.018, function()
			if not b.Parent then return end
			tw(b, 0.16, {Size = V1 * ziel, CFrame = CFrame.new(pos + off)})
			spaeter(0.16, function() if b.Parent then tw(b, 0.4, {Color = P.feuer2, Transparency = 1, Size = V1 * ziel * 1.2}) end end)
			spaeter(0.24, function()
				local r = teil(nh, BALL, V1 * ziel * 0.85, P.rauch1, CFrame.new(pos + off), PLASTIK)
				r.Transparency = 0.3
				tw(r, 1.8 + math.random() * 0.5, {Size = V1 * ziel * 1.6, Transparency = 1, Color = P.rauch2,
					CFrame = CFrame.new(pos + off + Vector3.new(0, R * (rauchHoch or 1) * (0.7 + math.random() * 0.5), 0))}, Enum.EasingStyle.Sine)
			end)
		end)
	end
	-- Flammenzungen + Funken
	partikel(o, pos, {Texture = TEX_FEUER, Color = ColorSequence.new(P.flamme1, P.flamme2), LightEmission = 0.9, Size = NumberSequence.new({nk(0, R * 0.25 * f), nk(1, R * 0.5 * f)}),
		Transparency = NumberSequence.new({nk(0, 0.05), nk(1, 1)}), Lifetime = NumberRange.new(0.35, 0.6), Speed = NumberRange.new(R * 1.3, R * 2), Drag = 4, SpreadAngle = Vector2.new(180, 180)}, 40)
	partikel(o, pos, {Texture = TEX_FUNKEN, Color = ColorSequence.new(P.funke1, P.funke2), LightEmission = 1, Size = NumberSequence.new({nk(0, 0.7), nk(1, 0)}),
		Lifetime = NumberRange.new(0.5, 1.1), Speed = NumberRange.new(R * 2.2, R * 3.8), Drag = 2.5, SpreadAngle = Vector2.new(180, 180), Acceleration = Vector3.new(0, -25, 0)}, 70)
end
-- Rauchpilz, der nach oben steigt
local function rauchpilz(o, pos, R, P, f)
	f = f or 1
	local nh = nachhall(4)
	partikel(nh, pos, {Texture = TEX_RAUCH, Color = ColorSequence.new(P.rauch1, P.rauch2), Size = NumberSequence.new({nk(0, R * 0.3 * f), nk(1, R * 0.85 * f)}),
		Transparency = NumberSequence.new({nk(0, 0.25), nk(0.7, 0.55), nk(1, 1)}), Lifetime = NumberRange.new(1.6, 2.4), Speed = NumberRange.new(R * 1.1, R * 1.7),
		SpreadAngle = Vector2.new(12, 12), EmissionDirection = Enum.NormalId.Top, Drag = 1.8, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-40, 40), Acceleration = Vector3.new(0, 2, 0)}, 18)
	spaeter(0.35, function()
		partikel(nh, pos + Vector3.new(0, R * 1.3 * f, 0), {Texture = TEX_RAUCH, Color = ColorSequence.new(P.rauch1, P.rauch2), Size = NumberSequence.new({nk(0, R * 0.4 * f), nk(1, R * 1 * f)}),
			Transparency = NumberSequence.new({nk(0, 0.35), nk(1, 1)}), Lifetime = NumberRange.new(1.4, 2), Speed = NumberRange.new(R * 0.4, R * 0.8), SpreadAngle = Vector2.new(180, 30),
			Drag = 2, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-30, 30)}, 14)
	end)
end
local function glut(o, pos, R, farbe1, farbe2, anzahl, dauer)
	local nh = nachhall((dauer or 1.5) + 3)
	partikel(nh, pos, {Texture = TEX_FUNKEN, Color = ColorSequence.new(farbe1, farbe2), LightEmission = 1, Size = NumberSequence.new({nk(0, 0.35), nk(1, 0)}),
		Lifetime = NumberRange.new(1.2, 2.4), Speed = NumberRange.new(R * 0.2, R * 0.8), SpreadAngle = Vector2.new(180, 180), Drag = 1.2,
		Acceleration = Vector3.new(0, 4, 0), RotSpeed = NumberRange.new(-180, 180)}, anzahl or 25, {math.floor((anzahl or 25) / 2), dauer or 1.5})
end
-- Stacheln (Eis/Kristall), die aus dem Boden schiessen und zerspringen
local function stacheln(o, bp, n, R, anzahl, farbe, material, reflex, zerspringFarbe)
	local nh = nachhall(3)
	for i = 1, anzahl do
		local w = (i / anzahl) * math.pi * 2 + math.random() * 0.4
		local abst = R * (0.25 + math.random() * 0.55)
		local fuss = bp + Vector3.new(math.cos(w) * abst, 0, math.sin(w) * abst)
		local laenge = R * (0.6 + math.random() * 0.6)
		local dicke = R * (0.1 + math.random() * 0.08)
		local neig = CFrame.Angles(math.sin(w) * 0.5, 0, -math.cos(w) * 0.5)
		local basis = CFrame.new(fuss) * neig
		local s = teil(nh, BLOCK, Vector3.new(dicke, 0.2, dicke), farbe, basis * CFrame.Angles(0, w, 0), material)
		s.Reflectance = reflex or 0
		s.Transparency = 0.15
		spaeter(i * 0.012, function()
			tw(s, 0.14, {Size = Vector3.new(dicke, laenge, dicke), CFrame = basis * CFrame.new(0, laenge / 2, 0) * CFrame.Angles(0, w, 0)}, Enum.EasingStyle.Back)
		end)
		spaeter(1.1 + math.random() * 0.4, function()
			if not s.Parent then return end
			local mitte = s.Position
			s:Destroy()
			truemmer(nh, mitte, 4, R * 0.35, 0.6, function()
				local k = teil(nh, BLOCK, V1 * dicke * 0.5, zerspringFarbe or farbe, CFrame.new(mitte), material)
				k.Reflectance = reflex or 0
				return k
			end, nil, 1.4)
		end)
	end
end
-- Lichtstrahlen, die aus der Mitte schiessen
local function strahlen(o, pos, R, farben, anzahl, dauer)
	for i = 1, anzahl do
		local f = farben[(i - 1) % #farben + 1]
		local dir = zufallsRichtung(0.8)
		local cf = CFrame.lookAt(pos, pos + dir)
		local s = teil(o, BLOCK, Vector3.new(0.25, 0.25, 0.5), f, cf)
		s.Transparency = 0.1
		local l = R * (1.3 + math.random() * 0.7)
		tw(s, 0.15, {Size = Vector3.new(0.35, 0.35, l), CFrame = cf * CFrame.new(0, 0, -l / 2)})
		spaeter(0.15, function() if s.Parent then tw(s, dauer or 0.5, {Transparency = 1, Size = Vector3.new(0.05, 0.05, l * 1.2), CFrame = cf * CFrame.new(0, 0, -l * 0.6)}) end end)
	end
end
local function geisterAufsteigen(o, pos, R, farbe, anzahl)
	local nh = nachhall(3)
	for i = 1, anzahl do
		local g = teil(nh, BALL, Vector3.new(1.4, 2, 1.4), farbe, CFrame.new(pos + zufallsRichtung(0.2) * R * 0.3), NEON)
		g.Transparency = 0.3
		trail(g, farbe, 0.5, 1)
		local ziel = g.Position + Vector3.new((math.random() - 0.5) * R * 0.8, R * (0.8 + math.random() * 0.7), (math.random() - 0.5) * R * 0.8)
		tw(g, 1.4 + math.random() * 0.6, {Position = ziel, Transparency = 1, Size = Vector3.new(0.5, 3, 0.5)}, Enum.EasingStyle.Sine)
	end
end
-- Kugeln, die spiralfoermig aufsteigen (Wirbel)
local function spirale(o, pos, R, farbe, stroeme, dauer, hoehe)
	local nh = nachhall(dauer + 1)
	for s = 1, stroeme do
		local k = teil(nh, BALL, V1 * 0.9, farbe, CFrame.new(pos), NEON)
		trail(k, farbe, 0.45, 0.9)
		local start, phase = os.clock(), s / stroeme * math.pi * 2
		task.spawn(function()
			while k.Parent do
				local t = (os.clock() - start) / dauer
				if t >= 1 then k:Destroy() break end
				local w = phase + t * math.pi * 4
				local r = R * (0.25 + t * 0.7)
				k.CFrame = CFrame.new(pos + Vector3.new(math.cos(w) * r, t * R * (hoehe or 1.8), math.sin(w) * r))
				k.Transparency = math.max(0, (t - 0.7) / 0.3)
				task.wait()
			end
		end)
	end
end
local function blasen(o, pos, R, farbe, anzahl, material)
	for i = 1, anzahl do
		local b = teil(o, BALL, V1 * 0.4, farbe, CFrame.new(pos + zufallsRichtung(0.8) * R * (0.25 + math.random() * 0.45)), material or GLAS)
		b.Transparency = 0.25
		local g = R * (0.12 + math.random() * 0.2)
		spaeter(i * 0.03, function()
			if not b.Parent then return end
			tw(b, 0.3, {Size = V1 * g}, Enum.EasingStyle.Back)
			spaeter(0.35 + math.random() * 0.35, function()
				if b.Parent then tw(b, 0.07, {Size = V1 * g * 1.5, Transparency = 1}) end
			end)
		end)
	end
end
local function standardTruemmer(o, pos, R, P, anzahl)
	truemmer(o, pos, anzahl or 14, R * 0.95, 0.95, function()
		local p = teil(o, BLOCK, Vector3.new(0.5 + math.random() * 0.6, 0.3, 0.5 + math.random() * 0.5), math.random() < 0.5 and RGB(34, 34, 42) or RGB(70, 70, 84), CFrame.new(pos), METALL)
		return p
	end, P.funke2)
end

-- =================== Rezepte je Skin ===================
local REZEPT = {}

REZEPT.standard = function(o, pos, R, P) -- klassische Bombe: Feuerball, Rauchpilz, Metallsplitter mit Funkenspur, Brandfleck
	feuerball(o, pos, R, P, 1)
	rauchpilz(o, pos, R, P, 1)
	standardTruemmer(o, pos, R, P, 16)
	bodenEffekte(o, pos, R, P.funke2, {fleck = RGB(24, 20, 18), gluehen = RGB(255, 110, 30)})
	glut(o, pos, R, P.funke1, P.funke2, 20, 1.2)
end

REZEPT.rot = function(o, pos, R, P) -- Feuer: Riesen-Feuerball, Feuersaeule, brennender Boden
	feuerball(o, pos, R, P, 1.2, 1.3)
	local nh = nachhall(4)
	partikel(nh, pos, {Texture = TEX_FEUER, Color = ColorSequence.new(P.flamme1, P.flamme2), LightEmission = 1, Size = NumberSequence.new({nk(0, R * 0.45), nk(1, R * 0.1)}),
		Lifetime = NumberRange.new(0.6, 1), Speed = NumberRange.new(R * 2.2, R * 3.2), SpreadAngle = Vector2.new(9, 9), EmissionDirection = Enum.NormalId.Top, Drag = 1}, 40, {70, 0.6})
	local res = bodenEffekte(o, pos, R, P.feuer, {fleck = RGB(20, 12, 8), gluehen = RGB(255, 80, 10), fleckGroesse = 1.3})
	if res then -- Flammen brennen am Boden weiter
		for i = 1, 8 do
			local w = i / 8 * math.pi * 2
			local fp = res.Position + Vector3.new(math.cos(w), 0, math.sin(w)) * R * (0.4 + math.random() * 0.4) + Vector3.new(0, 0.5, 0)
			partikel(nh, fp, {Texture = TEX_FEUER, Color = ColorSequence.new(P.flamme1, P.flamme2), LightEmission = 0.9, Size = NumberSequence.new({nk(0, 1.6), nk(1, 0.3)}),
				Lifetime = NumberRange.new(0.4, 0.8), Speed = NumberRange.new(3, 6), SpreadAngle = Vector2.new(15, 15), EmissionDirection = Enum.NormalId.Top}, 0, {20, 2.6})
		end
	end
	truemmer(o, pos, 14, R, 1, function() return teil(o, BLOCK, V1 * (0.3 + math.random() * 0.3), P.flamme1, CFrame.new(pos), NEON) end, P.flamme2)
	glut(o, pos, R, P.funke1, P.feuer, 40, 2.2)
end

REZEPT.gruen = function(o, pos, R, P) -- Gift: Schleimblase platzt, Giftpfuetze, Giftwolke
	local blob = teil(o, BALL, V1 * R * 0.3, P.feuer, CFrame.new(pos), GLAS)
	blob.Transparency = 0.15
	tw(blob, 0.2, {Size = Vector3.new(R * 1.3, R * 1.05, R * 1.3)}, Enum.EasingStyle.Back)
	spaeter(0.2, function() if blob.Parent then tw(blob, 0.08, {Size = Vector3.new(R * 1.8, R * 0.4, R * 1.8), Transparency = 1}) end end)
	spaeter(0.2, function()
		truemmer(o, pos, 26, R * 1.05, 1, function()
			local g = 0.4 + math.random() * 0.6
			return teil(o, BALL, Vector3.new(g, g * 1.4, g), P.feuer:Lerp(P.feuer2, math.random() * 0.6), CFrame.new(pos), GLAS)
		end, P.funke2, 1.5)
		bodenEffekte(o, pos, R, P.feuer, {staub = false, fleck = P.feuer2, fleckMaterial = GLAS, fleckT = 0.15, fleckGroesse = 1.2, fleckZeit = 6, fleckSchrumpft = true, gluehen = P.feuer})
	end)
	local nh = nachhall(6)
	partikel(nh, pos, {Texture = TEX_RAUCH, Color = ColorSequence.new(P.rauch2, P.rauch1), LightEmission = 0.25, Size = NumberSequence.new({nk(0, R * 0.3), nk(1, R * 0.9)}),
		Transparency = NumberSequence.new({nk(0, 0.4), nk(1, 1)}), Lifetime = NumberRange.new(2.5, 3.8), Speed = NumberRange.new(2, 6), SpreadAngle = Vector2.new(180, 25),
		RotSpeed = NumberRange.new(-30, 30), Rotation = NumberRange.new(0, 360)}, 22, {6, 2.5})
	partikel(nh, pos, {Texture = TEX_FUNKEN, Color = ColorSequence.new(P.funke1), LightEmission = 1, Size = NumberSequence.new(0.45, 0), Lifetime = NumberRange.new(1, 2),
		Speed = NumberRange.new(1, 4), SpreadAngle = Vector2.new(180, 180), Acceleration = Vector3.new(0, 4, 0)}, 30, {15, 2})
	blasen(o, pos, R * 0.8, P.feuer, 8)
end

REZEPT.blau = function(o, pos, R, P) -- Ozean: Wasserkuppel, Fontaene, Tropfen, Wellenringe
	local kuppel = teil(o, BALL, V1 * R * 0.3, P.feuer:Lerp(Color3.new(1, 1, 1), 0.2), CFrame.new(pos), GLAS)
	kuppel.Transparency = 0.35
	tw(kuppel, 0.22, {Size = V1 * R * 1.5})
	spaeter(0.22, function() if kuppel.Parent then tw(kuppel, 0.3, {Transparency = 1, Size = V1 * R * 1.8}) end end)
	-- Fontaene schiesst hoch und faellt zusammen
	local h = R * 2.6
	local saeule = teil(o, ZYL, Vector3.new(0.5, R * 0.45, R * 0.45), RGB(200, 235, 255), CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2), GLAS)
	saeule.Transparency = 0.25
	tw(saeule, 0.28, {Size = Vector3.new(h, R * 0.35, R * 0.35), CFrame = CFrame.new(pos + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2)}, Enum.EasingStyle.Quart)
	spaeter(0.35, function() if saeule.Parent then tw(saeule, 0.55, {Size = Vector3.new(0.5, R * 0.8, R * 0.8), CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2), Transparency = 1}, Enum.EasingStyle.Quad, Enum.EasingDirection.In) end end)
	truemmer(o, pos, 30, R * 1.1, 1.1, function()
		local g = 0.3 + math.random() * 0.5
		return teil(o, BALL, V1 * g, P.feuer:Lerp(Color3.new(1, 1, 1), math.random() * 0.6), CFrame.new(pos), GLAS)
	end, RGB(200, 235, 255), 1.4)
	local res = bodenEffekte(o, pos, R, P.funke2, {staub = false, fleck = RGB(30, 70, 120), fleckMaterial = GLAS, fleckT = 0.45, fleckZeit = 5, fleckSchrumpft = true})
	local bp = res and res.Position or pos
	for i = 0, 2 do -- Wellenringe
		spaeter(i * 0.18, function() ring(o, nil, RGB(200, 240, 255), R * (1 + i * 0.3), 0.7, GLAS, 0.25, flachCF(bp + Vector3.new(0, 0.2, 0))) end)
	end
	partikel(o, pos, {Texture = TEX_RAUCH, Color = ColorSequence.new(RGB(220, 240, 255)), Size = NumberSequence.new({nk(0, R * 0.2), nk(1, R * 0.6)}),
		Transparency = NumberSequence.new({nk(0, 0.5), nk(1, 1)}), Lifetime = NumberRange.new(0.8, 1.4), Speed = NumberRange.new(R * 0.8, R * 1.4), SpreadAngle = Vector2.new(180, 180), Drag = 3}, 20)
end

REZEPT.lila = function(o, pos, R, P) -- Magie: Implosion -> Arkan-Explosion, Runenkreis, Lichtsaeule, Sternenwirbel
	local imp = teil(o, BALL, V1 * R * 1.3, P.feuer, CFrame.new(pos), FF)
	tw(imp, 0.14, {Size = V1 * 0.5}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	spaeter(0.14, function()
		if imp.Parent then imp:Destroy() end
		blitzKugel(o, pos, R, P.blitz, 1.1)
		local k = teil(o, BALL, V1 * R * 0.3, P.feuer, CFrame.new(pos), NEON)
		k.Transparency = 0.1
		tw(k, 0.35, {Size = V1 * R * 1.6, Transparency = 1, Color = P.feuer2})
		strahlen(o, pos, R, {P.funke1, P.feuer, P.flamme1}, 10, 0.5)
		local res = bodenTreffer(pos)
		local bp = res and res.Position or (pos - Vector3.new(0, 1, 0))
		local nh = nachhall(3)
		-- Runenkreis: zwei Ringe + Runen-Steine, die sich drehen
		local teile = {}
		for i = 1, 2 do
			local r = teil(nh, ZYL, Vector3.new(0.12, R * (0.9 + i * 0.5), R * (0.9 + i * 0.5)), P.feuer, flachCF(bp + Vector3.new(0, 0.12 * i, 0)), NEON)
			r.Transparency = 0.2
			local innen = teil(nh, ZYL, Vector3.new(0.14, R * (0.8 + i * 0.5), R * (0.8 + i * 0.5)), RGB(20, 0, 40), flachCF(bp + Vector3.new(0, 0.12 * i + 0.01, 0)), PLASTIK)
			innen.Transparency = 0.6
			table.insert(teile, r) table.insert(teile, innen)
		end
		local runen = {}
		for i = 1, 8 do
			local rn = teil(nh, BLOCK, Vector3.new(0.9, 0.12, 0.5), P.funke1, CFrame.new(bp), NEON)
			table.insert(runen, rn)
		end
		local start = os.clock()
		task.spawn(function()
			while nh.Parent do
				local t = (os.clock() - start) / 1.6
				if t >= 1 then break end
				local tr = math.max(0, (t - 0.55) / 0.45)
				for i, rn in runen do
					local w = i / #runen * math.pi * 2 + t * 3
					rn.CFrame = CFrame.new(bp + Vector3.new(math.cos(w) * R * 0.95, 0.3, math.sin(w) * R * 0.95)) * CFrame.Angles(0, -w, 0)
					rn.Transparency = tr
				end
				for _, tl in teile do tl.Transparency = math.max(tl.Transparency, tr) end
				task.wait()
			end
			nh:Destroy()
		end)
		-- Lichtsaeule
		local s = teil(o, ZYL, Vector3.new(0.5, R * 0.5, R * 0.5), P.funke1, CFrame.new(bp) * CFrame.Angles(0, 0, math.pi / 2), NEON)
		s.Transparency = 0.2
		tw(s, 0.25, {Size = Vector3.new(R * 4, R * 0.25, R * 0.25), CFrame = CFrame.new(bp + Vector3.new(0, R * 2, 0)) * CFrame.Angles(0, 0, math.pi / 2)})
		spaeter(0.25, function() if s.Parent then tw(s, 0.6, {Transparency = 1, Size = Vector3.new(R * 4.5, 0.1, 0.1)}) end end)
		partikel(o, pos, {Texture = TEX_FUNKEN, Color = ColorSequence.new(P.funke1, P.funke2), LightEmission = 1, Size = NumberSequence.new(1, 0), Lifetime = NumberRange.new(0.8, 1.4),
			Speed = NumberRange.new(R * 0.6, R), SpreadAngle = Vector2.new(180, 180), RotSpeed = NumberRange.new(-300, 300), Drag = 2, Acceleration = Vector3.new(0, 8, 0)}, 70)
	end)
	spirale(o, pos, R, P.funke2, 3, 1.1, 1.6)
end

REZEPT.pink = function(o, pos, R, P) -- Bubblegum: Riesen-Kaugummiblase waechst, wabbelt, platzt -> Konfetti
	local blase = teil(o, BALL, V1 * R * 0.3, P.feuer:Lerp(Color3.new(1, 1, 1), 0.25), CFrame.new(pos), GLAS)
	blase.Transparency = 0.2
	tw(blase, 0.3, {Size = V1 * R * 1.5}, Enum.EasingStyle.Back)
	task.spawn(function()
		local start = os.clock()
		task.wait(0.3)
		while blase.Parent and os.clock() - start < 0.55 do
			local t = os.clock() - start
			blase.Size = Vector3.new(R * 1.5 * (1 + math.sin(t * 40) * 0.06), R * 1.5 * (1 - math.sin(t * 40) * 0.06), R * 1.5 * (1 + math.sin(t * 40) * 0.06))
			task.wait()
		end
		if not blase.Parent then return end
		tw(blase, 0.07, {Size = V1 * R * 2, Transparency = 1})
		blitzKugel(o, pos, R, Color3.new(1, 1, 1), 0.9)
		local KONFETTI = {RGB(255, 110, 190), RGB(255, 255, 255), RGB(110, 230, 255), RGB(255, 230, 90), RGB(190, 120, 255)}
		truemmer(o, pos, 40, R * 1.2, 1.6, function()
			return teil(o, BLOCK, Vector3.new(0.6, 0.08, 0.35), KONFETTI[math.random(#KONFETTI)], CFrame.new(pos), PLASTIK)
		end, nil, 0.45)
		blasen(o, pos, R, P.feuer:Lerp(Color3.new(1, 1, 1), 0.3), 12)
		bodenEffekte(o, pos, R, P.feuer, {staub = false, fleck = P.feuer, fleckMaterial = PLASTIK, fleckT = 0.1, fleckGroesse = 0.6, fleckZeit = 6})
		luftwelle(o, pos, R, P.funke1)
	end)
end

REZEPT.weiss = function(o, pos, R, P) -- Schnee: Frost-Blitz, Eisstacheln aus dem Boden, Frostring, Schneegestoeber
	blitzKugel(o, pos, R, Color3.new(1, 1, 1), 1.2)
	local k = teil(o, BALL, V1 * R * 0.4, RGB(220, 245, 255), CFrame.new(pos), FF)
	tw(k, 0.4, {Size = V1 * R * 1.8, Transparency = 1})
	local res = bodenEffekte(o, pos, R, RGB(200, 235, 255), {staub = false, fleck = RGB(225, 245, 255), fleckMaterial = EIS, fleckT = 0.15, fleckGroesse = 1.3, fleckZeit = 6})
	stacheln(o, res and res.Position or (pos - Vector3.new(0, 1, 0)), res and res.Normal, R, 12, RGB(190, 230, 255), EIS, 0.1, RGB(230, 248, 255))
	truemmer(o, pos, 14, R * 0.9, 0.9, function() return teil(o, BLOCK, Vector3.new(0.35, 1.2, 0.35), RGB(215, 242, 255), CFrame.new(pos), EIS) end, RGB(220, 245, 255))
	local nh = nachhall(5)
	partikel(nh, pos + Vector3.new(0, 3, 0), {Texture = TEX_FUNKEN, Color = ColorSequence.new(Color3.new(1, 1, 1)), LightEmission = 0.4, Size = NumberSequence.new(0.5, 0.3), Lifetime = NumberRange.new(2, 3.2),
		Speed = NumberRange.new(R * 0.4, R * 0.9), SpreadAngle = Vector2.new(180, 180), Drag = 1.5, Acceleration = Vector3.new(0, -3, 0), RotSpeed = NumberRange.new(-90, 90)}, 90, {20, 1.5})
	partikel(o, pos, {Texture = TEX_RAUCH, Color = ColorSequence.new(RGB(235, 248, 255)), Size = NumberSequence.new({nk(0, R * 0.25), nk(1, R * 0.7)}),
		Transparency = NumberSequence.new({nk(0, 0.4), nk(1, 1)}), Lifetime = NumberRange.new(1, 1.6), Speed = NumberRange.new(R, R * 1.5), SpreadAngle = Vector2.new(180, 180), Drag = 3}, 24)
end

REZEPT.gold = function(o, pos, R, P) -- Gold: goldener Feuerball, Lichtstrahlen, Muenzfontaene, Glitzer
	feuerball(o, pos, R, P, 0.85, 0.6)
	strahlen(o, pos, R, {RGB(255, 250, 200), RGB(255, 215, 60)}, 12, 0.6)
	truemmer(o, pos, 30, R * 1.1, 1.3, function()
		return teil(o, ZYL, Vector3.new(0.2, 1.1, 1.1), RGB(255, 205, 50), CFrame.new(pos), METALL)
	end, RGB(255, 230, 120), 1.1)
	bodenEffekte(o, pos, R, P.feuer, {fleck = RGB(70, 55, 20), gluehen = RGB(255, 215, 60)})
	glut(o, pos, R, RGB(255, 250, 200), RGB(255, 200, 40), 60, 1.5)
end

REZEPT.diamant = function(o, pos, R, P) -- Diamant: Kristallstacheln, Prisma-Strahlen in Regenbogenfarben, Funkeln
	blitzKugel(o, pos, R, Color3.new(1, 1, 1), 1.2)
	local k = teil(o, BALL, V1 * R * 0.3, RGB(170, 250, 255), CFrame.new(pos), GLAS)
	k.Reflectance = 0.5
	tw(k, 0.3, {Size = V1 * R * 1.4, Transparency = 1})
	strahlen(o, pos, R, {RGB(255, 90, 90), RGB(255, 200, 70), RGB(120, 255, 120), RGB(90, 200, 255), RGB(180, 110, 255)}, 15, 0.55)
	local res = bodenEffekte(o, pos, R, RGB(200, 255, 255), {staub = false})
	stacheln(o, res and res.Position or (pos - Vector3.new(0, 1, 0)), res and res.Normal, R, 9, RGB(140, 240, 255), GLAS, 0.5)
	truemmer(o, pos, 20, R, 0.9, function()
		local s = teil(o, BLOCK, Vector3.new(0.6, 1, 0.6), RGB(160, 245, 255), CFrame.new(pos), GLAS)
		s.Reflectance = 0.5
		return s
	end, RGB(230, 255, 255))
	partikel(o, pos, {Texture = TEX_FUNKEN, Color = ColorSequence.new(Color3.new(1, 1, 1), RGB(120, 240, 255)), LightEmission = 1, Size = NumberSequence.new({nk(0, 0), nk(0.3, 1.5), nk(1, 0)}),
		Lifetime = NumberRange.new(0.6, 1.1), Speed = NumberRange.new(R * 0.5, R), SpreadAngle = Vector2.new(180, 180), Drag = 3}, 50)
end

REZEPT.kuerbis = function(o, pos, R, P) -- Kuerbis: Feuerball, Kuerbis-Fratze leuchtet auf, Kerne + Schalen, lila Rauch
	feuerball(o, pos, R, P, 1)
	rauchpilz(o, pos, R, P, 0.8)
	-- Fratze (zwei Dreieck-Augen + Zackenmund), schaut zur Kamera
	local mitte = zurKamera(pos + Vector3.new(0, R * 0.9, 0))
	local s = R * 0.22
	local gesicht = {}
	for _, d in {{-1}, {1}} do
		local a = teil(o, BLOCK, Vector3.new(s, s, 0.2), RGB(255, 200, 40), mitte * CFrame.new(d[1] * s * 1.1, s * 0.6, -0.2) * CFrame.Angles(0, 0, math.pi / 4))
		table.insert(gesicht, a)
	end
	for i = -2, 2 do
		local z = teil(o, BLOCK, Vector3.new(s * 0.55, s * (i % 2 == 0 and 0.7 or 0.45), 0.2), RGB(255, 200, 40), mitte * CFrame.new(i * s * 0.5, -s * 0.7, -0.2))
		table.insert(gesicht, z)
	end
	for _, g in gesicht do
		g.Transparency = 1
		tw(g, 0.15, {Transparency = 0})
		spaeter(0.6, function() if g.Parent then tw(g, 0.5, {Transparency = 1}) end end)
	end
	local schale = teil(o, BALL, V1 * R * 0.5, RGB(255, 120, 20), mitte * CFrame.new(0, 0, 0.3), PLASTIK)
	schale.Transparency = 1
	tw(schale, 0.15, {Transparency = 0.35, Size = V1 * R * 1})
	spaeter(0.6, function() if schale.Parent then tw(schale, 0.5, {Transparency = 1, Size = V1 * R * 1.3}) end end)
	truemmer(o, pos, 18, R * 0.85, 0.9, function() return teil(o, BALL, Vector3.new(0.5, 0.3, 0.4), RGB(255, 235, 170), CFrame.new(pos), PLASTIK) end)
	truemmer(o, pos, 12, R * 0.8, 0.9, function() return teil(o, BLOCK, Vector3.new(1.2, 1, 0.4), RGB(255, 120, 20), CFrame.new(pos), PLASTIK) end, RGB(255, 140, 30))
	bodenEffekte(o, pos, R, RGB(255, 140, 20), {fleck = RGB(30, 15, 30), gluehen = RGB(255, 120, 20)})
end

REZEPT.gruft = function(o, pos, R, P) -- Gruft: lila Seelenfeuer, Grabstein-Brocken, aufsteigende Seelen, Bodennebel
	feuerball(o, pos, R, P, 0.95, 0.8)
	geisterAufsteigen(o, pos, R, RGB(190, 120, 255), 7)
	truemmer(o, pos, 14, R * 0.85, 1, function()
		return teil(o, BLOCK, Vector3.new(0.8 + math.random() * 0.6, 0.9 + math.random() * 0.6, 0.35), RGB(110, 105, 120):Lerp(RGB(70, 66, 80), math.random()), CFrame.new(pos), Enum.Material.Slate)
	end, P.funke2)
	local res = bodenEffekte(o, pos, R, P.feuer, {fleck = RGB(20, 10, 28), gluehen = P.feuer})
	local nh = nachhall(6)
	partikel(nh, (res and res.Position or pos) + Vector3.new(0, 0.8, 0), {Texture = TEX_RAUCH, Color = ColorSequence.new(RGB(60, 40, 80), RGB(30, 20, 40)), Size = NumberSequence.new({nk(0, R * 0.3), nk(1, R * 0.8)}),
		Transparency = NumberSequence.new({nk(0, 0.45), nk(1, 1)}), Lifetime = NumberRange.new(2.5, 3.5), Speed = NumberRange.new(R * 0.3, R * 0.6), SpreadAngle = Vector2.new(88, 88),
		EmissionDirection = Enum.NormalId.Top, Drag = 1.5, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-20, 20)}, 18, {6, 2})
end

REZEPT.blutmond = function(o, pos, R, P) -- Blutmond: roter Blitz, Blutmond steigt auf, Doppel-Schockwelle, Blutspritzer
	blitzKugel(o, pos, R, RGB(255, 60, 60), 1.2)
	local k = teil(o, BALL, V1 * R * 0.3, P.feuer, CFrame.new(pos), NEON)
	tw(k, 0.3, {Size = V1 * R * 1.4, Transparency = 1, Color = P.feuer2})
	-- Mond-Scheibe (mit dunklem "Krater"-Schatten), schaut zur Kamera
	local mcf = zurKamera(pos + Vector3.new(0, R * 0.4, 0)) * CFrame.Angles(0, math.pi / 2, 0)
	local mond = teil(o, ZYL, Vector3.new(0.3, 0.5, 0.5), RGB(230, 30, 40), mcf, NEON)
	local schatten = teil(o, ZYL, Vector3.new(0.32, 0.4, 0.4), RGB(90, 0, 10), mcf * CFrame.new(-0.05, R * 0.12, R * 0.12), PLASTIK)
	local ziel = zurKamera(pos + Vector3.new(0, R * 1.7, 0)) * CFrame.Angles(0, math.pi / 2, 0)
	tw(mond, 0.6, {Size = Vector3.new(0.3, R * 1.3, R * 1.3), CFrame = ziel}, Enum.EasingStyle.Sine)
	tw(schatten, 0.6, {Size = Vector3.new(0.32, R * 1.05, R * 1.05), CFrame = ziel * CFrame.new(-0.05, R * 0.2, R * 0.2)}, Enum.EasingStyle.Sine)
	spaeter(0.75, function()
		if mond.Parent then tw(mond, 0.7, {Transparency = 1}) end
		if schatten.Parent then tw(schatten, 0.7, {Transparency = 1}) end
	end)
	ring(o, pos, RGB(220, 20, 40), R * 1.2, 0.7)
	spaeter(0.15, function() ring(o, pos + Vector3.new(0, 0.5, 0), RGB(120, 0, 10), R * 0.9, 0.9) end)
	truemmer(o, pos, 24, R * 0.95, 0.9, function() return teil(o, BALL, V1 * (0.3 + math.random() * 0.4), RGB(170, 0, 20), CFrame.new(pos), GLAS) end, RGB(150, 0, 20), 1.3)
	local res = bodenEffekte(o, pos, R, P.feuer, {staub = false, fleck = RGB(110, 0, 15), fleckMaterial = GLAS, fleckT = 0.15, fleckGroesse = 0.8, fleckZeit = 7})
	if res then -- einzelne Blutflecken
		local nh = nachhall(7)
		for i = 1, 7 do
			local w = math.random() * math.pi * 2
			local p = res.Position + Vector3.new(math.cos(w), 0, math.sin(w)) * R * (0.6 + math.random() * 0.7)
			local f = teil(nh, ZYL, Vector3.new(0.1, 0.2, 0.2), RGB(120, 0, 15), flachCF(p + Vector3.new(0, 0.07, 0)), GLAS)
			local g = 0.8 + math.random() * 1.6
			spaeter(0.35 + math.random() * 0.4, function() if f.Parent then tw(f, 0.1, {Size = Vector3.new(0.1, g, g)}) end end)
			spaeter(4.5, function() if f.Parent then tw(f, 2.4, {Transparency = 1}) end end)
		end
	end
	partikel(o, pos, {Texture = TEX_RAUCH, Color = ColorSequence.new(RGB(120, 10, 20), RGB(40, 0, 5)), Size = NumberSequence.new({nk(0, R * 0.3), nk(1, R * 0.8)}),
		Transparency = NumberSequence.new({nk(0, 0.4), nk(1, 1)}), Lifetime = NumberRange.new(1.2, 2), Speed = NumberRange.new(R * 0.6, R), SpreadAngle = Vector2.new(180, 180), Drag = 2.5}, 22)
end

REZEPT.geisterbombe = function(o, pos, R, P) -- Geisterhaft: Ektoplasma-Kugel, Geister fliegen, Seelen-Wirbel
	local k = teil(o, BALL, V1 * R * 0.3, RGB(190, 255, 225), CFrame.new(pos), FF)
	tw(k, 0.5, {Size = V1 * R * 2, Transparency = 1})
	local kern = teil(o, BALL, V1 * R * 0.3, RGB(200, 255, 230), CFrame.new(pos), NEON)
	kern.Transparency = 0.3
	tw(kern, 0.25, {Size = V1 * R * 1.1, Transparency = 1})
	geisterAufsteigen(o, pos, R, RGB(200, 255, 230), 10)
	spirale(o, pos, R, RGB(170, 255, 210), 5, 1.3, 1.4)
	bodenEffekte(o, pos, R, RGB(170, 255, 210), {staub = false, fleck = RGB(120, 220, 180), fleckMaterial = NEON, fleckT = 0.6, fleckGroesse = 0.9, fleckZeit = 4})
	partikel(o, pos, {Texture = TEX_RAUCH, Color = ColorSequence.new(RGB(200, 255, 230)), LightEmission = 0.5, Size = NumberSequence.new({nk(0, R * 0.2), nk(1, R * 0.6)}),
		Transparency = NumberSequence.new({nk(0, 0.5), nk(1, 1)}), Lifetime = NumberRange.new(1.2, 2), Speed = NumberRange.new(R * 0.5, R), SpreadAngle = Vector2.new(180, 180), Drag = 2, Acceleration = Vector3.new(0, 4, 0)}, 20)
end

REZEPT.hexenkessel = function(o, pos, R, P) -- Hexenkessel: gruenes Hexenfeuer, Flammen-Spirale, blubbernde Blasen, Zaubertrank-Pfuetze
	feuerball(o, pos, R, P, 0.85, 0.7)
	spirale(o, pos, R, P.feuer, 3, 1.1, 2)
	blasen(o, pos, R, RGB(110, 255, 90), 12)
	truemmer(o, pos, 20, R, 1, function() local g = 0.3 + math.random() * 0.4 return teil(o, BALL, V1 * g, RGB(120, 255, 90), CFrame.new(pos), GLAS) end, P.funke2, 1.4)
	bodenEffekte(o, pos, R, P.feuer, {staub = false, fleck = RGB(40, 140, 30), fleckMaterial = GLAS, fleckT = 0.2, fleckGroesse = 1, fleckZeit = 6, fleckSchrumpft = true, gluehen = P.feuer})
	glut(o, pos, R, RGB(200, 255, 120), P.feuer, 30, 1.5)
end

REZEPT.nachtschatten = function(o, pos, R, P) -- Nachtschatten: schwarzes Loch saugt alles ein, dann Schattententakel + dunkler Knall
	local loch = teil(o, BALL, V1 * R * 1.6, RGB(20, 5, 40), CFrame.new(pos), FF)
	tw(loch, 0.25, {Size = V1 * 1, Transparency = 0.1}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	partikel(o, pos, {Texture = TEX_FUNKEN, Color = ColorSequence.new(P.funke1, P.funke2), LightEmission = 1, Size = NumberSequence.new(0.6, 0), Lifetime = NumberRange.new(0.25, 0.25),
		Speed = NumberRange.new(-R * 4, -R * 4), SpreadAngle = Vector2.new(180, 180)}, 40) -- Funken fliegen nach innen
	spaeter(0.25, function()
		if loch.Parent then tw(loch, 0.45, {Size = V1 * R * 2.4, Transparency = 1}) end
		local k = teil(o, BALL, V1 * R * 0.3, RGB(40, 15, 80), CFrame.new(pos), NEON)
		tw(k, 0.3, {Size = V1 * R * 1.5, Transparency = 1, Color = RGB(5, 0, 15)})
		-- Schattententakel schiessen raus und ziehen sich zurueck
		for i = 1, 12 do
			local w = i / 12 * math.pi * 2 + math.random() * 0.3
			local dir = Vector3.new(math.cos(w), (math.random() - 0.3) * 0.5, math.sin(w)).Unit
			local cf = CFrame.lookAt(pos, pos + dir)
			local t = teil(o, BLOCK, Vector3.new(0.5, 0.5, 0.5), RGB(30, 10, 60), cf, NEON)
			local l = R * (1 + math.random() * 0.6)
			tw(t, 0.18, {Size = Vector3.new(0.6, 0.6, l), CFrame = cf * CFrame.new(0, 0, -l / 2)}, Enum.EasingStyle.Quart)
			spaeter(0.35, function() if t.Parent then tw(t, 0.3, {Size = Vector3.new(0.1, 0.1, 0.5), CFrame = cf, Transparency = 1}, Enum.EasingStyle.Quad, Enum.EasingDirection.In) end end)
		end
		geisterAufsteigen(o, pos, R, RGB(90, 50, 170), 5)
		bodenEffekte(o, pos, R, RGB(90, 50, 170), {fleck = RGB(8, 2, 16), gluehen = RGB(110, 60, 220), fleckGroesse = 1.2})
		partikel(o, pos, {Texture = TEX_RAUCH, Color = ColorSequence.new(RGB(10, 5, 20), RGB(40, 25, 70)), Size = NumberSequence.new({nk(0, R * 0.3), nk(1, R * 0.9)}),
			Transparency = NumberSequence.new({nk(0, 0.2), nk(1, 1)}), Lifetime = NumberRange.new(1.2, 2), Speed = NumberRange.new(R * 0.8, R * 1.3), SpreadAngle = Vector2.new(180, 180), Drag = 3}, 26)
	end)
end

-- Unbekannter (neuer) Skin: Feuerball + Splitter in Skin-Farbe
local function fallback(o, pos, R, P)
	feuerball(o, pos, R, P, 1)
	rauchpilz(o, pos, R, P, 0.8)
	truemmer(o, pos, 14, R * 0.9, 0.9, function() return teil(o, BLOCK, V1 * 0.7, P.feuer, CFrame.new(pos)) end, P.funke2)
	bodenEffekte(o, pos, R, P.feuer, {fleck = P.feuer2:Lerp(Color3.new(), 0.6)})
end

-- Spielt die komplette Explosion. Gibt den Effekt-Ordner zurueck.
function M.explosion(skinId, pos, radius)
	if not skinId or skinId == "" then skinId = "standard" end
	local R = math.clamp(radius, 1, 60) * GROESSE
	local P = M.farben(skinId)
	local o = Instance.new("Model")
	o.Name = "BombExplosionFX"
	o.Parent = workspace
	Debris:AddItem(o, 5)
	lichtBlitz(o, pos, R, P.licht, 14, 0.9)
	luftwelle(o, pos, R)
	local f = REZEPT[skinId] or fallback
	local ok, err = pcall(f, o, pos, R, P)
	if not ok then warn("[SkinExplosionen] " .. tostring(skinId) .. ": " .. tostring(err)) end
	return o
end

-- alte Schnittstelle (falls noch irgendwo benutzt): nur den skin-spezifischen Teil
function M.extra(skinId, ordner, pos, radius, P)
	local f = REZEPT[skinId or "standard"] or fallback
	pcall(f, ordner, pos, radius, P or M.farben(skinId))
end

return M
