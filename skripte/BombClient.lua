-- BombClient: Zielmodus + Fadenkreuz, Wurf-Eingabe, Wurfanimation, Hitmarker, Explosions-Effekt
-- (nur Eingabe und Optik - Timer, Radius und Schaden entscheidet der Server)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("BombConfig"))
local Sounds = require(ReplicatedStorage:WaitForChild("SoundConfig"))
local Remotes = ReplicatedStorage:WaitForChild("BombRemotes")
local ThrowRemote = Remotes:WaitForChild("Throw")
local EffectRemote = Remotes:WaitForChild("ExplosionEffect")
local ThrowAnimRemote = Remotes:WaitForChild("ThrowAnim")
local HitMarkerRemote = Remotes:WaitForChild("HitMarker")
local AimRemote = Remotes:WaitForChild("Aim")

local ACTION = "BombeWerfen"
local SchaleRemote = ReplicatedStorage:WaitForChild("SchaleWerfen", 10)
-- Was wird gerade geworfen? "bombe", "schale" (Bananeninsel, nach dem Essen) oder nil
local function wurfModus()
	if player:GetAttribute("HasBomb") then return "bombe" end
	local c = player.Character
	if c and c:GetAttribute("HatSchale") and not c:GetAttribute("Gelaehmt") then return "schale" end
	return nil
end
local SCHULTER_OFFSET = Vector3.new(1.75, 0.4, 0) -- Kamera ueber der rechten Schulter
local letzterWurf = 0
local wurfTrack = nil

-- =====================================================================
-- WURFANIMATION (prozedural, wie ein Mensch einen Ball wirft)
-- Laeuft auf jedem Client lokal -> fluessig fuer alle sichtbar.
-- Winkel in Grad, jeweils im Koordinatensystem des uebergeordneten Koerperteils.
-- =====================================================================
local rad = math.rad
local function X(d) return CFrame.Angles(rad(d), 0, 0) end
local function Y(d) return CFrame.Angles(0, rad(d), 0) end
local function Z(d) return CFrame.Angles(0, 0, rad(d)) end
local I = CFrame.identity

-- Gelenknamen R15 / R6
local GELENKE = {
	Root = {"Root", "RootJoint"},
	Waist = {"Waist"},
	Neck = {"Neck"},
	RightShoulder = {"RightShoulder", "Right Shoulder"},
	RightElbow = {"RightElbow"},
	LeftShoulder = {"LeftShoulder", "Left Shoulder"},
	LeftElbow = {"LeftElbow"},
	RightHip = {"RightHip", "Right Hip"},
	LeftHip = {"LeftHip", "Left Hip"},
	RightKnee = {"RightKnee"},
	LeftKnee = {"LeftKnee"},
}

-- Schluesselposen: t = Zeit in Sekunden, stil = Easing ZU dieser Pose hin
-- Ablauf wie bei einem echten Wurf: kurz in die Knie (Schwung holen) -> weit ausholen (hier wird gehalten, solange gezielt wird)
-- -> Peitsche: Huefte, dann Schulter, dann Arm schnellen nach vorne -> Ueberschwung -> Nachschwingen -> zurueck
local POSEN = {
	{ t = 0, pose = {} },
	{ -- 0) Schwung holen: leicht in die Knie, Oberkoerper sammelt sich, Wurfarm geht runter/nach hinten
		t = 0.09, stil = Enum.EasingStyle.Quad, richtung = Enum.EasingDirection.Out,
		pose = {
			Root = CFrame.new(0, -0.28, 0) * Y(-14) * X(6),
			Waist = Y(-8) * X(4),
			Neck = Y(12),
			RightShoulder = Y(-20) * Z(35),
			RightElbow = X(55),
			LeftShoulder = X(35) * Z(-10),
			LeftElbow = X(35),
			LeftHip = X(12), LeftKnee = X(-22),
			RightHip = X(10), RightKnee = X(-22),
		},
	},
	{ -- 1) Ausholen: Koerper dreht die rechte Schulter weit nach hinten, Wurfarm hinten oben (Ellbogen ~90 Grad),
	  --    linker Arm zeigt aufs Ziel, linkes Bein macht einen grossen Schritt nach vorne, Gewicht auf dem hinteren Bein
		t = 0.27, stil = Enum.EasingStyle.Back, richtung = Enum.EasingDirection.Out,
		pose = {
			Root = CFrame.new(0, -0.18, 0) * Y(-52) * X(10),
			Waist = Y(-22) * X(5),
			Neck = Y(58),
			RightShoulder = Y(-15) * Z(112) * Y(-96),
			RightElbow = X(118),
			LeftShoulder = Y(55) * X(95),
			LeftElbow = X(12),
			LeftHip = X(30), LeftKnee = X(-12),
			RightHip = X(-12), RightKnee = X(-28),
		},
	},
	{ -- 2) Abwurf (Peitsche): Huefte schnellt nach vorne, Oberkoerper folgt, Arm peitscht ueber den Kopf
		t = 0.32, stil = Enum.EasingStyle.Quint, richtung = Enum.EasingDirection.In,
		pose = {
			Root = CFrame.new(0, -0.32, 0) * Y(30) * X(-12),
			Waist = Y(20) * X(-8),
			Neck = Y(-35),
			RightShoulder = X(152) * Z(10),
			RightElbow = X(6),
			LeftShoulder = Y(-15) * X(15) * Z(-32),
			LeftElbow = X(52),
			LeftHip = X(32), LeftKnee = X(-16),
			RightHip = X(-26), RightKnee = X(-22),
		},
	},
	{ -- 3) Ueberschwung: Wucht reisst den Oberkoerper weiter nach vorne, Arm schlaegt quer runter, hinteres Bein kommt hoch
		t = 0.39, stil = Enum.EasingStyle.Quad, richtung = Enum.EasingDirection.Out,
		pose = {
			Root = CFrame.new(0, -0.42, 0) * Y(50) * X(-20),
			Waist = Y(28) * X(-15),
			Neck = Y(-58) * X(8),
			RightShoulder = Y(42) * X(68) * Z(-32),
			RightElbow = X(26),
			LeftShoulder = Y(-28) * Z(-38) * X(-18),
			LeftElbow = X(42),
			LeftHip = X(26), LeftKnee = X(-22),
			RightHip = X(-38), RightKnee = X(-48),
		},
	},
	{ -- 4) Nachschwingen: Koerper faengt die Bewegung ab, Arm pendelt aus
		t = 0.6, stil = Enum.EasingStyle.Sine, richtung = Enum.EasingDirection.Out,
		pose = {
			Root = CFrame.new(0, -0.22, 0) * Y(36) * X(-9),
			Waist = Y(18) * X(-7),
			Neck = Y(-38),
			RightShoulder = Y(30) * X(42) * Z(-18),
			RightElbow = X(34),
			LeftShoulder = Y(-14) * Z(-18),
			LeftElbow = X(24),
			LeftHip = X(16), LeftKnee = X(-10),
			RightHip = X(-12), RightKnee = X(-16),
		},
	},
	{ -- 5) Zurueck in die normale Haltung (mit leichtem Nachfedern)
		t = 0.98, stil = Enum.EasingStyle.Back, richtung = Enum.EasingDirection.Out,
		pose = {},
	},
}

-- Gelenke werden ueber .Transform gesteuert (nach dem Animator-Schritt gesetzt).
-- Funktioniert mit Motor6D (R6/R15) und den neuen AnimationConstraint-Rigs.
local function findeGelenke(char)
	local liste = {}
	for key, namen in GELENKE do
		for _, name in namen do
			local j = char:FindFirstChild(name, true)
			if j and (j:IsA("Motor6D") or j:IsA("AnimationConstraint")) then
				local basis
				if j:IsA("Motor6D") then
					basis = j.C0
				elseif j.Attachment0 then
					basis = j.Attachment0.CFrame
				end
				if basis then
					local rot = basis.Rotation
					liste[key] = {gelenk = j, rot = rot, rotInv = rot:Inverse()}
					break
				end
			end
		end
	end
	return liste
end

-- rot ist im Koordinatensystem des uebergeordneten Koerperteils angegeben
local function setzeGelenk(g, rot)
	g.gelenk.Transform = g.rotInv * rot * g.rot
end

-- Beine/Huefte: beim Laufen mischt sich die normale Lauf-Animation drunter
local UNTERKOERPER = {RightHip = true, LeftHip = true, RightKnee = true, LeftKnee = true}
local HALTE_ZEIT = POSEN[3].t          -- Zeitpunkt der Aushol-Pose
local ENDE_ZEIT = POSEN[#POSEN].t
local anims = setmetatable({}, {__mode = "k"}) -- [Character] = Zustand

local function beendeAnim(char)
	local a = anims[char]
	if not a then return end
	a.conn:Disconnect()
	for _, g in a.gelenke do
		if g.gelenk.Parent then g.gelenk.Transform = CFrame.identity end
	end
	anims[char] = nil
end

local function istCharacter(char)
	return typeof(char) == "Instance" and char:IsA("Model") and char:FindFirstChildOfClass("Humanoid") ~= nil
end

-- halten = true: laeuft bis zur Aushol-Pose und bleibt dort, bis losgelassen wird
local function starteAnim(char, halten)
	if not istCharacter(char) then return end
	beendeAnim(char)
	local a = {t = 0, halten = halten, gelenke = findeGelenke(char), letzte = os.clock(), bew = 0, schritt = 0}
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	-- PreSimulation: laeuft NACH dem Animator, sonst setzt dieser die Gelenke jeden Frame zurueck
	a.conn = RunService.PreSimulation:Connect(function()
		local jetzt = os.clock()
		local dt = jetzt - a.letzte
		a.t += dt
		a.letzte = jetzt
		if a.halten and a.t > HALTE_ZEIT then a.t = HALTE_ZEIT end
		if not char.Parent or a.t >= ENDE_ZEIT then
			beendeAnim(char)
			return
		end
		local i = 2
		while POSEN[i].t < a.t do i += 1 end
		local von, zu = POSEN[i - 1], POSEN[i]
		local alpha = TweenService:GetValue(math.clamp((a.t - von.t) / (zu.t - von.t), 0, 1), zu.stil, zu.richtung)

		-- ===== Bewegung beim Zielen: eigener, deutlicher "Aim-Walk" =====
		-- b = 0 steht, 1 laeuft (weich angeglichen); vor/seitwaerts relativ zur Blickrichtung
		local v = hrp and hrp.AssemblyLinearVelocity or Vector3.zero
		local flach = Vector3.new(v.X, 0, v.Z)
		local tempo = flach.Magnitude
		local laufTempo = math.max(hum and hum.WalkSpeed or 16, 1)
		local ziel = math.clamp(tempo / (laufTempo * 0.45), 0, 1)
		local inLuft = hum and hum.FloorMaterial == Enum.Material.Air
		if inLuft then ziel = 0 end
		a.bew += (ziel - a.bew) * math.min(1, dt * 10)
		local b = a.bew
		local vor, seit = 0, 0
		if hrp and tempo > 0.5 then
			vor = flach:Dot(hrp.CFrame.LookVector) / tempo     -- +1 vorwaerts, -1 rueckwaerts
			seit = flach:Dot(hrp.CFrame.RightVector) / tempo   -- +1 rechts, -1 links
		end
		a.vor = (a.vor or 0) + (vor - (a.vor or 0)) * math.min(1, dt * 8)
		a.seit = (a.seit or 0) + (seit - (a.seit or 0)) * math.min(1, dt * 8)
		vor, seit = a.vor, a.seit
		-- Schrittfrequenz passt zur Geschwindigkeit
		a.schritt += dt * (4 + tempo * 0.42)
		local p = a.schritt
		local sn, cs = math.sin(p), math.cos(p)
		local richtungX = (math.abs(vor) > 0.25 and math.sign(vor) or 0)
		local schwungX = 38 * (math.abs(vor) * 0.85 + 0.15)    -- Beinschwung nach vorne/hinten
		local schwungZ = 22 * math.abs(seit)                    -- Seitschritte
		local kniaR = 0.5 + 0.5 * math.sin(p - 0.9)               -- Knie beugt sich in der Schwungphase
		local kniaL = 0.5 + 0.5 * math.sin(p + math.pi - 0.9)
		local hoch = math.abs(sn)                                 -- Koerper geht pro Schritt kurz runter
		local LAUF = {
			RightHip = X(sn * schwungX * (richtungX ~= 0 and richtungX or 0.3)) * Z(-sn * schwungZ * math.sign(seit)),
			LeftHip = X(-sn * schwungX * (richtungX ~= 0 and richtungX or 0.3)) * Z(sn * schwungZ * math.sign(seit)),
			RightKnee = X(-(12 + kniaR * 48)),
			LeftKnee = X(-(12 + kniaL * 48)),
			-- leicht geduckt, nach vorne in die Laufrichtung gelehnt, seitlich ins Gewicht
			Root = CFrame.new(0, -0.32 - hoch * 0.18, 0) * X(-10 * vor - 4) * Z(7 * seit) * Y(sn * 6),
			-- Oberkoerper dreht gegen die Beine + traegt die Aushol-Drehung
			Waist = Y(-sn * 9) * X(4 + hoch * 3),
			-- Kopf bleibt ruhig aufs Ziel
			Neck = Y(sn * 9 - 0) * X(-hoch * 3),
			-- Zielarm pendelt gegen das rechte Bein, Wurfarm federt im Schritt
			LeftShoulder = X(sn * 14),
			LeftElbow = X(10 + hoch * 8),
			RightShoulder = X(-hoch * 6),
			RightElbow = X(hoch * 10),
		}

		local rootPose = (von.pose.Root or I):Lerp(zu.pose.Root or I, alpha)
		for key, g in a.gelenke do
			local rot = (von.pose[key] or I):Lerp(zu.pose[key] or I, alpha)
			local lauf = LAUF[key] or I
			if UNTERKOERPER[key] then
				-- Beine: im Stand Wurf-Schrittstellung, beim Laufen echte Schritte
				setzeGelenk(g, rot:Lerp(lauf, b))
			elseif key == "Root" then
				-- Huefte bleibt in Laufrichtung (nur ein Rest der Ausholdrehung), dazu ducken + lehnen
				setzeGelenk(g, I:Lerp(lauf, b) * I:Lerp(rot, 1 - 0.85 * b))
			elseif key == "Waist" then
				-- die Ausholdrehung wandert von der Huefte in den Oberkoerper
				local extra = I:Lerp(rootPose.Rotation, 0.85 * b)
				setzeGelenk(g, I:Lerp(lauf, b) * extra * rot)
			else
				setzeGelenk(g, I:Lerp(lauf, b) * rot)
			end
		end
	end)
	anims[char] = a
end

-- Loslassen: Animation laeuft von der Aushol-Pose weiter (Abwurf + Nachschwingen)
local function loslassen(char)
	local a = anims[char]
	if a then
		a.halten = false
	else
		starteAnim(char, false)
	end
end

ThrowAnimRemote.OnClientEvent:Connect(function(char, phase)
	if not istCharacter(char) then return end
	if phase == "aushol" then
		starteAnim(char, true)
	elseif phase == "wurf" then
		loslassen(char)
	elseif phase == "abbruch" then
		beendeAnim(char)
	else
		starteAnim(char, false) -- "voll"
	end
end)

-- Hochgeladene Animation (optional, statt der prozeduralen)
local function ladeAnimation(char)
	wurfTrack = nil
	if Config.THROW_ANIMATION_ID == "" then return end
	local hum = char:WaitForChild("Humanoid", 5)
	local animator = hum and hum:WaitForChild("Animator", 5)
	if not animator then return end
	local anim = Instance.new("Animation")
	anim.AnimationId = Config.THROW_ANIMATION_ID
	local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
	if ok and track then
		track.Priority = Enum.AnimationPriority.Action
		wurfTrack = track
	end
end

-- =====================================================================
-- FADENKREUZ + HITMARKER (skaliert mit der Bildschirmgroesse)
-- =====================================================================
local gui = Instance.new("ScreenGui")
gui.Name = "BombFadenkreuz"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 50
gui.Parent = player:WaitForChild("PlayerGui")

local mitte = Instance.new("Frame")
mitte.Name = "Mitte"
mitte.AnchorPoint = Vector2.new(0.5, 0.5)
mitte.Position = UDim2.fromScale(0.5, 0.5)
mitte.Size = UDim2.fromOffset(0, 0)
mitte.BackgroundTransparency = 1
mitte.Parent = gui

local punkt = Instance.new("Frame")
punkt.Name = "Punkt"
punkt.AnchorPoint = Vector2.new(0.5, 0.5)
punkt.BackgroundColor3 = Color3.new(1, 1, 1)
punkt.BorderSizePixel = 0
punkt.Visible = false
punkt.Parent = mitte
Instance.new("UICorner", punkt).CornerRadius = UDim.new(1, 0)
local punktRand = Instance.new("UIStroke", punkt)
punktRand.Color = Color3.new(0, 0, 0)
punktRand.Transparency = 0.4

local hitStriche = {}
for i = 0, 3 do
	local winkel = 45 + i * 90
	local s = Instance.new("Frame")
	s.Name = "Hit" .. i
	s.AnchorPoint = Vector2.new(0.5, 0.5)
	s.BackgroundColor3 = Color3.fromRGB(255, 45, 45)
	s.BorderSizePixel = 0
	s.Rotation = winkel
	s.BackgroundTransparency = 1
	s.Parent = mitte
	table.insert(hitStriche, {frame = s, winkel = rad(winkel)})
end

local skala = 1
local function aktualisiereGroesse()
	local vp = workspace.CurrentCamera.ViewportSize
	local kurz = math.min(vp.X, vp.Y)
	skala = math.clamp(kurz / 1000, 0.65, 1.4) -- Handy klein, PC normal, 4K/TV groesser
	local d = math.max(3, math.floor(6 * skala + 0.5))
	punkt.Size = UDim2.fromOffset(d, d)
	punktRand.Thickness = math.max(1, math.floor(skala + 0.5))
end

local function setzeHitStriche(abstand, laenge, dicke)
	for _, h in hitStriche do
		-- Strich zeigt diagonal nach aussen, Mittelpunkt auf der Diagonale
		local r = abstand + laenge / 2
		h.frame.Size = UDim2.fromOffset(laenge, dicke)
		h.frame.Position = UDim2.fromOffset(math.cos(h.winkel) * r, math.sin(h.winkel) * r)
	end
end

local hitId = 0
local function zeigeHitmarker(kill)
	hitId += 1
	local meineId = hitId
	local farbe = kill and Color3.fromRGB(200, 0, 0) or Color3.fromRGB(255, 45, 45)
	local laenge = (kill and 14 or 10) * skala
	local dicke = math.max(2, math.floor((kill and 3 or 2) * skala + 0.5))
	local abstandStart, abstandEnde = 4 * skala, 8 * skala
	for _, h in hitStriche do
		h.frame.BackgroundColor3 = farbe
		h.frame.BackgroundTransparency = 0
	end
	local start = os.clock()
	local dauer = kill and 0.45 or 0.3
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = (os.clock() - start) / dauer
		if meineId ~= hitId or t >= 1 then
			if meineId == hitId then
				for _, h in hitStriche do h.frame.BackgroundTransparency = 1 end
			end
			conn:Disconnect()
			return
		end
		local pop = TweenService:GetValue(math.min(t * 3, 1), Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		setzeHitStriche(abstandStart + (abstandEnde - abstandStart) * pop, laenge, dicke)
		local fade = math.clamp((t - 0.5) * 2, 0, 1)
		for _, h in hitStriche do h.frame.BackgroundTransparency = fade end
	end)
end

local letzterCash = 0
HitMarkerRemote.OnClientEvent:Connect(function(kill)
	zeigeHitmarker(kill == true)
	if kill == true and os.clock() - (letzterCash or 0) > 0.3 then
		letzterCash = os.clock() -- bei Doppel-Kills nur EIN Ka-Ching (nicht uebereinander)
		-- Kill-Sound (2D, nur fuer den Killer)
		local ks = Instance.new("Sound")
		ks.SoundId = Sounds.KILL.id
		ks.Volume = Sounds.KILL.volume
		ks.Parent = game:GetService("SoundService")
		ks:Play()
		ks.Ended:Once(function() ks:Destroy() end)
		-- Killing-Shot-Sound gleichzeitig dazu
		if Sounds.KILL_SHOT then
			local shot = Instance.new("Sound")
			shot.SoundId = Sounds.KILL_SHOT.id
			shot.Volume = Sounds.KILL_SHOT.volume
			shot.Parent = game:GetService("SoundService")
			shot:Play()
			shot.Ended:Once(function() shot:Destroy() end)
		end
	end
end)

workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(aktualisiereGroesse)
aktualisiereGroesse()

-- =====================================================================
-- ZIELMODUS (Schulterkamera, Figur dreht mit der Kamera) solange Bombe in der Hand
-- =====================================================================
local zielModus = false

-- Siegerfeier: die Kamera steht fest vor der Buehne. Dann wird dorthin geworfen, wo die Maus
-- (bzw. der Finger) auf dem Bildschirm zeigt - also auch nach vorne Richtung Kamera.
local function inFeier()
	local c = player.Character
	return c ~= nil and c:GetAttribute("Feier") == true
end
local function feierRichtung()
	local cam = workspace.CurrentCamera
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	local m = UserInputService:GetMouseLocation()
	local strahl = cam:ViewportPointToRay(m.X, m.Y)
	local hoehe = root.Position.Y - 2
	local treffer
	if strahl.Direction.Y < -0.02 then
		treffer = strahl.Origin + strahl.Direction * ((hoehe - strahl.Origin.Y) / strahl.Direction.Y)
	else
		treffer = strahl.Origin + strahl.Direction * 200
	end
	local flach = Vector3.new(treffer.X - root.Position.X, 0, treffer.Z - root.Position.Z)
	if flach.Magnitude < 1 then
		flach = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	end
	if flach.Magnitude < 0.01 then return nil end
	return flach.Unit, root
end

local function zielPunkt()
	if inFeier() then
		local flach, root = feierRichtung()
		if flach then
			local w = math.rad(28) -- schoener Bogen
			return root.Position + (flach * math.cos(w) + Vector3.yAxis * math.sin(w)) * 1000
		end
	end
	-- Wurfrichtung = Blickrichtung der Kamera (Maus / Wischen / rechter Stick lenkt),
	-- etwas nach oben gekippt, damit auch bei normaler Kamera ein schoener Bogen entsteht
	local cam = workspace.CurrentCamera
	local look = cam.CFrame.LookVector
	local flach = Vector3.new(look.X, 0, look.Z)
	if flach.Magnitude > 0.05 then
		local winkel = math.asin(math.clamp(look.Y, -1, 1)) + math.rad(Config.AIM_PITCH_OFFSET or 0)
		winkel = math.clamp(winkel, math.rad(-80), math.rad(80))
		look = flach.Unit * math.cos(winkel) + Vector3.yAxis * math.sin(winkel)
	end
	-- Weit entfernter Punkt, damit Server und Zielfaden dieselbe Richtung berechnen
	return cam.CFrame.Position + look * 1000
end

RunService:BindToRenderStep("BombZielen", Enum.RenderPriority.Camera.Value + 1, function()
	if not zielModus then return end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 then return end
	if inFeier() then
		-- feste Feier-Kamera: Maus frei, Figur dreht sich in Wurfrichtung (auch zur Kamera hin)
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		punkt.Visible = false
		local flach = feierRichtung()
		if flach then root.CFrame = CFrame.lookAt(root.Position, root.Position + flach) end
		return
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false
	punkt.Visible = true
	local look = workspace.CurrentCamera.CFrame.LookVector
	local flach = Vector3.new(look.X, 0, look.Z)
	if flach.Magnitude > 0.01 then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + flach)
	end
end)

local function setzeZielModus(an)
	zielModus = an
	punkt.Visible = an
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.AutoRotate = not an
		hum.CameraOffset = an and SCHULTER_OFFSET or Vector3.zero
	end
	UserInputService.MouseIconEnabled = not an
	if not an then UserInputService.MouseBehavior = Enum.MouseBehavior.Default end
end

-- =====================================================================
-- WERFEN
-- =====================================================================
local holtAus = false -- Taste wird gerade gehalten
local ladeStart = 0   -- Zeitpunkt, ab dem aufgeladen wird

-- =====================================================================
-- ZIELFADEN (zeigt beim Aufladen ungefaehr die Flugbahn) + LADEBALKEN
-- =====================================================================
local CollectionService = game:GetService("CollectionService")

-- Gestrichelter Faden: einzelne weisse Striche entlang der Flugbahn (nur lokal sichtbar)
local STRICH_LAENGE = 2.4   -- Laenge eines Strichs (Studs)
local STRICH_LUECKE = 1.5   -- Abstand zwischen den Strichen
local STRICH_BREITE_MIN = 0.7  -- Breite ohne Aufladen
local STRICH_BREITE_MAX = 1.4  -- Breite bei voller Ladung
local STRICH_LAUF = 6       -- Striche wandern mit dieser Geschwindigkeit nach vorne
local MAX_STRICHE = 70

local strichOrdner = Instance.new("Model")
strichOrdner.Name = "Zielfaden"
strichOrdner.Parent = workspace.CurrentCamera
-- dunkler Rand, damit die Striche auch auf der weissen Arena gut sichtbar sind
local strichRand = Instance.new("Highlight")
strichRand.FillTransparency = 1
strichRand.OutlineColor = Color3.fromRGB(20, 20, 25)
strichRand.OutlineTransparency = 0.15
strichRand.DepthMode = Enum.HighlightDepthMode.Occluded
strichRand.Adornee = strichOrdner
strichRand.Parent = strichOrdner
local striche = {}
for i = 1, MAX_STRICHE do
	local s = Instance.new("Part")
	s.Name = "Strich"
	s.Anchored = true
	s.CanCollide = false
	s.CanQuery = false
	s.CanTouch = false
	s.CastShadow = false
	s.Material = Enum.Material.SmoothPlastic
	s.Color = Color3.fromRGB(255, 200, 40)
	s.Size = Vector3.new(0.4, 0.05, STRICH_LAENGE)
	s.Transparency = 1
	s.Parent = strichOrdner
	striche[i] = s
end

local ladeRahmen = Instance.new("Frame")
ladeRahmen.Name = "Ladebalken"
ladeRahmen.AnchorPoint = Vector2.new(0.5, 0)
ladeRahmen.BackgroundColor3 = Color3.new(0, 0, 0)
ladeRahmen.BackgroundTransparency = 0.5
ladeRahmen.BorderSizePixel = 0
ladeRahmen.Visible = false
ladeRahmen.Parent = mitte
Instance.new("UICorner", ladeRahmen).CornerRadius = UDim.new(1, 0)
local ladeFuellung = Instance.new("Frame")
ladeFuellung.Name = "Fuellung"
ladeFuellung.BorderSizePixel = 0
ladeFuellung.BackgroundColor3 = Color3.new(1, 1, 1)
ladeFuellung.Size = UDim2.fromScale(0, 1)
ladeFuellung.Parent = ladeRahmen
Instance.new("UICorner", ladeFuellung).CornerRadius = UDim.new(1, 0)

local WEISS = Color3.fromRGB(255, 255, 255)
local GELB = Color3.fromRGB(255, 205, 60)
local ROT = Color3.fromRGB(255, 60, 45)
local SCHALE_GELB = Color3.fromRGB(255, 225, 60)   -- Bananenschale: hellgelb ...
local SCHALE_BRAUN = Color3.fromRGB(120, 70, 25)   -- ... wird beim Aufladen braun
local function kraftFarbe(k)
	if k < 0.5 then return WEISS:Lerp(GELB, k * 2) end
	return GELB:Lerp(ROT, (k - 0.5) * 2)
end

-- X-Achse des Attachments zeigt in Flugrichtung (Beam-Kurven laufen entlang der X-Achse)
local function achsenCF(pos, x)
	local hoch = math.abs(x.Y) > 0.99 and Vector3.xAxis or Vector3.yAxis
	local z = x:Cross(hoch).Unit
	local y = z:Cross(x).Unit
	return CFrame.fromMatrix(pos, x, y, z)
end

local fadenParams = RaycastParams.new()
fadenParams.FilterType = Enum.RaycastFilterType.Exclude
fadenParams.RespectCanCollide = true

-- Zeit bis zum ersten Aufprall entlang der Flugbahn
local function flugzeitBisAufprall(p0, v0, g)
	local filter = CollectionService:GetTagged("Bomb")
	table.insert(filter, player.Character)
	fadenParams.FilterDescendantsInstances = filter
	local dt, t, p = 1 / 30, 0, p0
	while t < 3 do
		local t2 = t + dt
		local p2 = p0 + v0 * t2 + 0.5 * g * t2 * t2
		local hit = workspace:Raycast(p, p2 - p, fadenParams)
		if hit then
			return t + dt * ((hit.Position - p).Magnitude / math.max((p2 - p).Magnitude, 0.001))
		end
		t, p = t2, p2
	end
	return 3
end

local strichSichtbar = 0
local function versteckeFaden()
	for i = 1, strichSichtbar do striche[i].Transparency = 1 end
	strichSichtbar = 0
	ladeRahmen.Visible = false
end

-- Strich flach zur Kamera gedreht, Laengsachse entlang der Flugbahn
local function setzeStrich(s, a, b, breite, transparenz, camPos)
	local mitteP = (a + b) / 2
	local z = b - a
	if z.Magnitude < 0.01 then s.Transparency = 1 return end
	z = z.Unit
	local zurCam = camPos - mitteP
	local y = zurCam - z * zurCam:Dot(z)
	if y.Magnitude < 0.01 then y = Vector3.yAxis end
	y = y.Unit
	local x = y:Cross(z)
	s.Size = Vector3.new(breite, 0.12, (b - a).Magnitude)
	s.CFrame = CFrame.fromMatrix(mitteP, x, y, z)
	s.Transparency = transparenz
end

RunService:BindToRenderStep("BombZielfaden", Enum.RenderPriority.Camera.Value + 2, function()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local modus = wurfModus()
	if not root or not modus then
		versteckeFaden()
		player:SetAttribute("ZielfadenStriche", 0)
		return
	end
	-- Bombe in der Hand: kurzer Bogen; Taste halten: Bogen waechst mit der Kraft
	local kraft = holtAus and Config.kraftAusZeit(os.clock() - ladeStart) or 0
	local richtung = (zielPunkt() - (root.Position + Vector3.new(0, 2, 0))).Unit
	local p0 = Config.abwurfPunkt(root.CFrame, richtung)
	local v0 = Config.wurfGeschwindigkeit(richtung, kraft)
	local g = Vector3.new(0, -workspace.Gravity, 0)
	local T = math.max(flugzeitBisAufprall(p0, v0, g), 0.05)

	-- Bahn fein abtasten und nach Bogenlaenge in Striche aufteilen
	local punkte, laengen = {p0}, {0}
	local gesamt, schritte = 0, math.clamp(math.ceil(T * 90), 8, 400)
	for i = 1, schritte do
		local t = T * i / schritte
		local p = p0 + v0 * t + 0.5 * g * t * t
		gesamt += (p - punkte[i]).Magnitude
		punkte[i + 1] = p
		laengen[i + 1] = gesamt
	end
	local j = 1
	local function punktBei(d)
		while j < #laengen - 1 and laengen[j + 1] < d do j += 1 end
		local l0, l1 = laengen[j], laengen[j + 1]
		local a = (l1 > l0) and (d - l0) / (l1 - l0) or 0
		return punkte[j]:Lerp(punkte[j + 1], math.clamp(a, 0, 1))
	end

	local periode = STRICH_LAENGE + STRICH_LUECKE
	local versatz = (os.clock() * STRICH_LAUF) % periode
	local breite = STRICH_BREITE_MIN + (STRICH_BREITE_MAX - STRICH_BREITE_MIN) * kraft
	local camPos = workspace.CurrentCamera.CFrame.Position
	local strichFarbe = (modus == "schale") and SCHALE_GELB:Lerp(SCHALE_BRAUN, kraft) or GELB:Lerp(ROT, kraft)
	local n = 0
	local d = versatz - periode + 1.5 -- erste Striche etwas vor der Hand
	while d < gesamt and n < MAX_STRICHE do
		local von, bis = math.max(d, 1.5), math.min(d + STRICH_LAENGE, gesamt)
		if bis > von + 0.2 then
			n += 1
			-- zum Ende hin ausblenden -> Richtung klar, Einschlag nur ungefaehr
			local anteil = von / gesamt
			local transparenz = 0.08 + math.clamp((anteil - 0.55) / 0.45, 0, 1) * 0.85
			setzeStrich(striche[n], punktBei(von), punktBei(bis), breite, transparenz, camPos)
			striche[n].Color = strichFarbe
		end
		d += periode
	end
	for i = n + 1, strichSichtbar do striche[i].Transparency = 1 end
	strichSichtbar = n
	player:SetAttribute("ZielfadenStriche", n)

	-- Ladebalken unter dem Fadenkreuz (nur beim Aufladen)
	ladeRahmen.Visible = holtAus
	ladeRahmen.Size = UDim2.fromOffset(math.floor(64 * skala), math.max(4, math.floor(6 * skala)))
	ladeRahmen.Position = UDim2.fromOffset(0, math.floor(18 * skala))
	ladeFuellung.Size = UDim2.fromScale(kraft, 1)
	ladeFuellung.BackgroundColor3 = (modus == "schale") and SCHALE_GELB:Lerp(SCHALE_BRAUN, kraft) or kraftFarbe(kraft)
end)

local function werfen(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		local modus = wurfModus()
		if not modus then return Enum.ContextActionResult.Pass end
		if holtAus or os.clock() - letzterWurf < Config.THROW_COOLDOWN then return Enum.ContextActionResult.Sink end
		holtAus = true
		ladeStart = os.clock()
		player:SetAttribute("HoltAus", ladeStart) -- nur lokal: EmoteClient beendet damit ein laufendes Emote
		if not wurfTrack and player.Character then starteAnim(player.Character, true) end
		if modus == "bombe" then AimRemote:FireServer() end
		return Enum.ContextActionResult.Sink
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		if not holtAus then return Enum.ContextActionResult.Pass end
		holtAus = false
		local modus = wurfModus()
		if not modus then return Enum.ContextActionResult.Sink end
		letzterWurf = os.clock()
		if wurfTrack then
			wurfTrack:Play(0.05)
		elseif player.Character then
			loslassen(player.Character)
		end
		if modus == "schale" then
			if SchaleRemote then SchaleRemote:FireServer(zielPunkt(), Config.kraftAusZeit(os.clock() - ladeStart)) end
		else
			ThrowRemote:FireServer(zielPunkt(), Config.kraftAusZeit(os.clock() - ladeStart))
		end
		versteckeFaden()
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

local function aktualisiereSteuerung()
	local hatBombe = wurfModus() ~= nil
	if hatBombe then
		local inputs = {Config.THROW_KEY, Enum.KeyCode.ButtonR2} -- R2 / RT fuer PlayStation & Xbox
		if Config.THROW_WITH_LEFT_CLICK then table.insert(inputs, Enum.UserInputType.MouseButton1) end
		ContextActionService:BindAction(ACTION, werfen, false, table.unpack(inputs))
	else
		ContextActionService:UnbindAction(ACTION)
		if holtAus then
			holtAus = false
			if player.Character then beendeAnim(player.Character) end
		end
	end
	setzeZielModus(hatBombe)
end

-- ---------- Handy-Button zum Werfen (halten = ausholen, loslassen = werfen) ----------
do
	local gui = Instance.new("ScreenGui")
	gui.Name = "MobileWerfen"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local knopf = Instance.new("TextButton")
	knopf.Name = "WerfenButton"
	knopf.AnchorPoint = Vector2.new(0.5, 0.5)
	knopf.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
	knopf.BackgroundTransparency = 0.25
	knopf.AutoButtonColor = false
	knopf.Text = "WERFEN"
	knopf.Font = Enum.Font.GothamBlack
	knopf.TextColor3 = Color3.new(1, 1, 1)
	knopf.TextScaled = true
	knopf.Parent = gui
	Instance.new("UICorner", knopf).CornerRadius = UDim.new(1, 0)
	local rand = Instance.new("UIStroke", knopf)
	rand.Color = Color3.new(1, 1, 1)
	rand.Transparency = 0.2
	rand.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local pad = Instance.new("UIPadding", knopf)
	pad.PaddingLeft = UDim.new(0.16, 0); pad.PaddingRight = UDim.new(0.16, 0)

	local function layout()
		local vp = gui.AbsoluteSize
		local s = math.min(vp.X, vp.Y) <= 500 and 70 or 120 -- Groesse wie Roblox' Sprung-Button
		local g = math.floor(s * 0.95)
		knopf.Size = UDim2.fromOffset(g, g)
		rand.Thickness = math.max(2, math.floor(s / 35))
		-- ueber dem Sprung-Button
		knopf.Position = UDim2.new(1, -(s - 10), 1, -20 - s - 12 - g / 2)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	layout()

	local gedrueckt = nil
	knopf.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		if gedrueckt then return end
		gedrueckt = input
		knopf.BackgroundTransparency = 0.05
		werfen(ACTION, Enum.UserInputState.Begin)
	end)
	local function loslassen(input)
		if gedrueckt ~= input then return end
		gedrueckt = nil
		knopf.BackgroundTransparency = 0.25
		werfen(ACTION, Enum.UserInputState.End)
	end
	knopf.InputEnded:Connect(loslassen)
	-- Finger vom Knopf weggezogen und losgelassen: trotzdem werfen
	UserInputService.InputEnded:Connect(function(input)
		if gedrueckt and input == gedrueckt then loslassen(input) end
	end)

	local function sichtbarkeit()
		gui.Enabled = wurfModus() ~= nil and UserInputService.TouchEnabled
			and UserInputService:GetLastInputType() ~= Enum.UserInputType.Keyboard
	end
	player:GetAttributeChangedSignal("HasBomb"):Connect(sichtbarkeit)
	UserInputService.LastInputTypeChanged:Connect(sichtbarkeit)
	sichtbarkeit()
	task.spawn(function() while true do task.wait(0.3) sichtbarkeit() end end) -- auch fuer die Bananenschale
end

player:GetAttributeChangedSignal("HasBomb"):Connect(aktualisiereSteuerung)
local function schaleBeobachten(char)
	char:GetAttributeChangedSignal("HatSchale"):Connect(aktualisiereSteuerung)
	char:GetAttributeChangedSignal("Gelaehmt"):Connect(aktualisiereSteuerung)
end
player.CharacterAdded:Connect(function(char)
	ladeAnimation(char)
	schaleBeobachten(char)
	task.defer(aktualisiereSteuerung)
end)
if player.Character then schaleBeobachten(player.Character) end
if player.Character then task.spawn(ladeAnimation, player.Character) end

-- ============ Explosions-Effekt ============
local SkinFX = require(ReplicatedStorage:WaitForChild("SkinExplosionen"))
local function effektPart(name, groesse, farbe, material, transparenz, pos, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.one * groesse
	p.Color = farbe
	p.Material = material
	p.Transparency = transparenz
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.CFrame = CFrame.new(pos)
	p.Parent = parent
	return p
end

local function tween(obj, zeit, ziel, stil)
	local t = TweenService:Create(obj, TweenInfo.new(zeit, stil or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), ziel)
	t:Play()
	return t
end

-- Kamera bei Explosion: 1 = wie frueher, 0 = gar nicht
local WACKELN = 0.35       -- wie stark die Kamera wackelt
local SICHT_ZUCKEN = 0.3   -- wie stark das Sichtfeld kurz "zuckt"

local function kameraWackeln(pos, radius)
	local cam = workspace.CurrentCamera
	local dist = (cam.CFrame.Position - pos).Magnitude
	local staerke = math.clamp(1 - dist / (radius * 3), 0, 1)
	if staerke <= 0 or WACKELN <= 0 then return end
	task.spawn(function()
		local dauer = 0.3
		local ende = os.clock() + dauer
		local fov0 = cam.FieldOfView
		-- kurzer "Punch" (Sichtfeld zuckt) + Wackeln, das abklingt
		cam.FieldOfView = fov0 + 6 * staerke * SICHT_ZUCKEN
		while os.clock() < ende do
			local r = staerke * WACKELN * ((ende - os.clock()) / dauer) ^ 1.5
			local t = os.clock() * 40
			cam.CFrame = cam.CFrame * CFrame.Angles(math.rad(math.noise(t, 0) * 5 * r), math.rad(math.noise(0, t) * 5 * r), math.rad(math.noise(t, t) * 2.5 * r))
			cam.FieldOfView = fov0 + 6 * staerke * SICHT_ZUCKEN * ((ende - os.clock()) / dauer) ^ 3
			task.wait()
		end
		cam.FieldOfView = fov0
	end)
end

EffectRemote.OnClientEvent:Connect(function(pos, radius, skinId)
	if typeof(pos) ~= "Vector3" or typeof(radius) ~= "number" then return end
	radius = math.clamp(radius, 1, 60)
	-- komplette Explosion je Bomben-Skin (Feuerball, Schleim, Wasser, Eis, Runen, ... siehe SkinExplosionen)
	local ordner = SkinFX.explosion(skinId, pos, radius)

	-- Explosions-Sound (3D an der Explosionsstelle)
	local halter = Instance.new("Part")
	halter.Anchored, halter.CanCollide, halter.CanQuery, halter.CanTouch = true, false, false, false
	halter.Transparency = 1
	halter.Size = Vector3.one * 0.1
	halter.CFrame = CFrame.new(pos)
	halter.Parent = ordner
	local knall = Instance.new("Sound")
	knall.SoundId = Sounds.EXPLOSION.id
	knall.Volume = Sounds.EXPLOSION.volume
	knall.RollOffMinDistance = 15
	knall.RollOffMaxDistance = 300
	knall.PlaybackSpeed = 0.92 + math.random() * 0.16 -- jede Explosion klingt etwas anders
	knall.Parent = halter
	knall:Play()

	kameraWackeln(pos, radius)
end)
