-- UebungsClient: Auswahlmenue (oeffnet sich am Uebungs-Portal) + Anzeige in den Uebungsmodi
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local Remotes = RS:WaitForChild("UebungRemotes")

local MODI = {
	{id = "ausweichen", emoji = "💣", titel = "AUSWEICHEN", text = "Kanonen feuern auf dich.\nWie lange überlebst du?", farbe = Color3.fromRGB(255, 140, 40)},
	{id = "werfen", emoji = "🎯", titel = "ZIELWERFEN", text = "Triff Noobs & Zielscheiben.\nSammle Punkte!", farbe = Color3.fromRGB(50, 160, 255)},
	{id = "duell", emoji = "⚔️", titel = "1 VS 1", text = "Fordere einen anderen\nSpieler heraus!", farbe = Color3.fromRGB(165, 90, 255)},
}

local gui = Instance.new("ScreenGui")
gui.Name = "UebungsGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local skala = Instance.new("UIScale")
skala.Parent = gui
local function passeAn()
	local vp = workspace.CurrentCamera.ViewportSize
	skala.Scale = math.clamp(math.min(vp.X / 1100, vp.Y / 700), 0.55, 1.15)
end
passeAn()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(passeAn)

local function ecken(o, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 16); c.Parent = o; return c end
local function rand(o, farbe, dicke) local s = Instance.new("UIStroke"); s.Color = farbe; s.Thickness = dicke or 3; s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Parent = o; return s end
local function text(eltern, t, groesse, farbe, font)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = t
	l.Font = font or Enum.Font.FredokaOne
	l.TextColor3 = farbe or Color3.new(1, 1, 1)
	l.TextScaled = true
	l.Size = groesse
	l.Parent = eltern
	return l
end

-- ================= MENUE =================
local abdunkeln = Instance.new("Frame")
abdunkeln.Size = UDim2.fromScale(1, 1)
abdunkeln.BackgroundColor3 = Color3.new(0, 0, 0)
abdunkeln.BackgroundTransparency = 1
abdunkeln.Visible = false
abdunkeln.Parent = gui

local menue = Instance.new("Frame")
menue.AnchorPoint = Vector2.new(0.5, 0.5)
menue.Position = UDim2.fromScale(0.5, 0.5)
menue.Size = UDim2.fromOffset(820, 440)
menue.BackgroundColor3 = Color3.fromRGB(28, 30, 42)
menue.Visible = false
menue.Parent = gui
ecken(menue, 26)
rand(menue, Color3.fromRGB(0, 220, 200), 4)
local grad = Instance.new("UIGradient")
grad.Color = ColorSequence.new(Color3.fromRGB(40, 44, 64), Color3.fromRGB(24, 26, 36))
grad.Rotation = 90
grad.Parent = menue
local menueSkala = Instance.new("UIScale")
menueSkala.Parent = menue

local titel = text(menue, "🏋️ ÜBUNGSBEREICH", UDim2.new(1, -120, 0, 56), Color3.fromRGB(0, 240, 220))
titel.Position = UDim2.fromOffset(60, 18)
local unter = text(menue, "Wähle deinen Modus!", UDim2.new(1, -120, 0, 26), Color3.fromRGB(190, 195, 215), Enum.Font.GothamMedium)
unter.Position = UDim2.fromOffset(60, 74)

local zu = Instance.new("TextButton")
zu.Size = UDim2.fromOffset(46, 46)
zu.Position = UDim2.new(1, -62, 0, 16)
zu.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
zu.Text = "✕"
zu.Font = Enum.Font.FredokaOne
zu.TextScaled = true
zu.TextColor3 = Color3.new(1, 1, 1)
zu.Parent = menue
ecken(zu, 23)

local karten = Instance.new("Frame")
karten.BackgroundTransparency = 1
karten.Position = UDim2.fromOffset(30, 118)
karten.Size = UDim2.new(1, -60, 1, -140)
karten.Parent = menue
local liste = Instance.new("UIListLayout")
liste.FillDirection = Enum.FillDirection.Horizontal
liste.HorizontalAlignment = Enum.HorizontalAlignment.Center
liste.Padding = UDim.new(0, 20)
liste.Parent = karten

local offen = false
local function schliessen()
	if not offen then return end
	offen = false
	TweenService:Create(menueSkala, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Scale = 0.6}):Play()
	TweenService:Create(abdunkeln, TweenInfo.new(0.15), {BackgroundTransparency = 1}):Play()
	task.wait(0.15)
	if not offen then menue.Visible = false; abdunkeln.Visible = false end
end

local wahl = Remotes:WaitForChild("Wahl")
for _, m in MODI do
	local k = Instance.new("TextButton")
	k.AutoButtonColor = false
	k.Text = ""
	k.Size = UDim2.fromOffset(236, 280)
	k.BackgroundColor3 = m.farbe
	k.Parent = karten
	ecken(k, 22)
	rand(k, Color3.new(1, 1, 1), 0).Transparency = 0.5
	local kg = Instance.new("UIGradient")
	kg.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170))
	kg.Rotation = 90
	kg.Parent = k
	local ks = Instance.new("UIScale"); ks.Parent = k
	local e = text(k, m.emoji, UDim2.new(1, 0, 0, 80))
	e.Position = UDim2.fromOffset(0, 16)
	local t = text(k, m.titel, UDim2.new(1, -20, 0, 40))
	t.Position = UDim2.fromOffset(10, 100)
	local ts = Instance.new("UIStroke"); ts.Thickness = 2.5; ts.Transparency = 0.4; ts.Parent = t
	local b = text(k, m.text, UDim2.new(1, -24, 0, 56), Color3.new(1, 1, 1), Enum.Font.GothamMedium)
	b.Position = UDim2.fromOffset(12, 146)
	local los = text(k, "LOS! ▶", UDim2.new(1, -40, 0, 46), m.farbe)
	los.Position = UDim2.new(0, 20, 1, -64)
	los.BackgroundTransparency = 0
	los.BackgroundColor3 = Color3.new(1, 1, 1)
	ecken(los, 14)
	local lp = Instance.new("UIPadding"); lp.PaddingTop = UDim.new(0, 8); lp.PaddingBottom = UDim.new(0, 8); lp.Parent = los
	k.MouseEnter:Connect(function() TweenService:Create(ks, TweenInfo.new(0.15, Enum.EasingStyle.Back), {Scale = 1.06}):Play() end)
	k.MouseLeave:Connect(function() TweenService:Create(ks, TweenInfo.new(0.15), {Scale = 1}):Play() end)
	k.Activated:Connect(function()
		TweenService:Create(ks, TweenInfo.new(0.08), {Scale = 0.94}):Play()
		wahl:FireServer(m.id)
		task.delay(0.08, schliessen)
	end)
end

local function oeffnen()
	if offen then return end
	offen = true
	menue.Visible = true
	abdunkeln.Visible = true
	menueSkala.Scale = 0.6
	TweenService:Create(menueSkala, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
	TweenService:Create(abdunkeln, TweenInfo.new(0.25), {BackgroundTransparency = 0.45}):Play()
end
zu.Activated:Connect(schliessen)
Remotes:WaitForChild("Menue").OnClientEvent:Connect(oeffnen)

-- ================= ANZEIGE IN DER UEBUNG =================
local leiste = Instance.new("Frame")
leiste.AnchorPoint = Vector2.new(0.5, 0)
leiste.Position = UDim2.new(0.5, 0, 0, 58)
leiste.Size = UDim2.fromOffset(460, 64)
leiste.BackgroundColor3 = Color3.fromRGB(28, 30, 42)
leiste.BackgroundTransparency = 0.1
leiste.Visible = false
leiste.Parent = gui
ecken(leiste, 32)
local leisteRand = rand(leiste, Color3.new(1, 1, 1), 3)
local modusText = text(leiste, "", UDim2.new(0.34, 0, 0, 26), Color3.new(1, 1, 1))
modusText.Position = UDim2.fromOffset(22, 6)
modusText.TextXAlignment = Enum.TextXAlignment.Left
local wertText = text(leiste, "", UDim2.new(0.62, -10, 0, 34), Color3.new(1, 1, 1))
wertText.Position = UDim2.new(0.36, 0, 0, 15)
wertText.TextXAlignment = Enum.TextXAlignment.Right
local nebenText = text(leiste, "", UDim2.new(0.34, 0, 0, 22), Color3.fromRGB(190, 195, 215), Enum.Font.GothamMedium)
nebenText.Position = UDim2.fromOffset(22, 34)
nebenText.TextXAlignment = Enum.TextXAlignment.Left
local wertSkala = Instance.new("UIScale"); wertSkala.Parent = wertText

local lobbyKnopf = Instance.new("TextButton")
lobbyKnopf.AnchorPoint = Vector2.new(0, 0)
lobbyKnopf.Position = UDim2.new(0.5, 244, 0, 66)
lobbyKnopf.Size = UDim2.fromOffset(150, 48)
lobbyKnopf.BackgroundColor3 = Color3.fromRGB(0, 200, 180)
lobbyKnopf.Text = "🏠 LOBBY"
lobbyKnopf.Font = Enum.Font.FredokaOne
lobbyKnopf.TextScaled = true
lobbyKnopf.TextColor3 = Color3.new(1, 1, 1)
lobbyKnopf.Visible = false
lobbyKnopf.Parent = gui
ecken(lobbyKnopf, 24)
local lpad = Instance.new("UIPadding"); lpad.PaddingTop = UDim.new(0, 8); lpad.PaddingBottom = UDim.new(0, 8); lpad.Parent = lobbyKnopf
lobbyKnopf.Activated:Connect(function() Remotes:WaitForChild("Zurueck"):FireServer() end)

-- grosser Hinweis in der Bildschirmmitte (GETROFFEN!, +Punkte ...)
local gross = text(gui, "", UDim2.fromOffset(700, 90), Color3.new(1, 1, 1))
gross.AnchorPoint = Vector2.new(0.5, 0.5)
gross.Position = UDim2.fromScale(0.5, 0.32)
gross.TextTransparency = 1
local grossRand = Instance.new("UIStroke"); grossRand.Thickness = 4; grossRand.Transparency = 1; grossRand.Parent = gross
local grossSkala = Instance.new("UIScale"); grossSkala.Parent = gross
local function zeigeGross(t, farbe)
	gross.Text = t
	gross.TextColor3 = farbe
	gross.TextTransparency = 0
	grossRand.Transparency = 0.2
	grossSkala.Scale = 1.4
	TweenService:Create(grossSkala, TweenInfo.new(0.3, Enum.EasingStyle.Back), {Scale = 1}):Play()
	task.delay(0.9, function()
		TweenService:Create(gross, TweenInfo.new(0.4), {TextTransparency = 1}):Play()
		TweenService:Create(grossRand, TweenInfo.new(0.4), {Transparency = 1}):Play()
	end)
end

local FARBE = {ausweichen = MODI[1].farbe, werfen = MODI[2].farbe, duell = MODI[3].farbe, arena = Color3.fromRGB(255, 205, 50)}
local NAME = {ausweichen = "💣 AUSWEICHEN", werfen = "🎯 ZIELWERFEN", duell = "⚔️ 1 VS 1", arena = "🎯 ÜBUNGSARENA"}

local function huepf()
	wertSkala.Scale = 1.25
	TweenService:Create(wertSkala, TweenInfo.new(0.25, Enum.EasingStyle.Back), {Scale = 1}):Play()
end

RunService.RenderStepped:Connect(function()
	local z = player:GetAttribute("UebungZone")
	leiste.Visible = z ~= nil
	lobbyKnopf.Visible = z ~= nil
	if not z then return end
	modusText.Text = NAME[z] or z
	leisteRand.Color = FARBE[z] or Color3.new(1, 1, 1)
	if z == "ausweichen" then
		local seit = player:GetAttribute("AusweichSeit") or workspace:GetServerTimeNow()
		wertText.Text = string.format("⏱ %.1fs", workspace:GetServerTimeNow() - seit)
		nebenText.Text = string.format("🏆 Rekord: %.1fs", player:GetAttribute("AusweichRekord") or 0)
	elseif z == "werfen" or z == "arena" then
		wertText.Text = "⭐ " .. (player:GetAttribute("Punkte") or 0)
		nebenText.Text = "🏆 Rekord: " .. (player:GetAttribute("PunkteRekord") or 0)
	elseif z == "duell" then
		wertText.Text = player:GetAttribute("DuellInfo") or "Stell dich auf ein Feld!"
		nebenText.Text = "🏆 Siege: " .. (player:GetAttribute("DuellSiege") or 0)
	end
end)

local letztePunkte = player:GetAttribute("Punkte") or 0
player:GetAttributeChangedSignal("Punkte"):Connect(function()
	local neu = player:GetAttribute("Punkte") or 0
	if neu > letztePunkte then huepf() end
	letztePunkte = neu
end)
player:GetAttributeChangedSignal("AusweichTreffer"):Connect(function()
	zeigeGross("💥 GETROFFEN!", Color3.fromRGB(255, 90, 60))
end)
player:GetAttributeChangedSignal("AusweichRekord"):Connect(function()
	task.delay(0.9, function() zeigeGross("🏆 NEUER REKORD!", Color3.fromRGB(255, 220, 60)) end)
end)
player:GetAttributeChangedSignal("DuellSiege"):Connect(function()
	zeigeGross("🏆 GEWONNEN!", Color3.fromRGB(255, 220, 60))
end)
player:GetAttributeChangedSignal("DuellInfo"):Connect(function()
	local i = player:GetAttribute("DuellInfo")
	if i and i:find("KAMPF") then zeigeGross("⚔️ KAMPF!", Color3.fromRGB(200, 140, 255)) end
	huepf()
end)

-- ================= BANNER: "Du bist jetzt in der Uebungsarena" =================
local banner = Instance.new("Frame")
banner.AnchorPoint = Vector2.new(0.5, 0.5)
banner.Position = UDim2.fromScale(0.5, 0.3)
banner.Size = UDim2.fromOffset(640, 128)
banner.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
banner.BackgroundTransparency = 0.1
banner.Visible = false
banner.Parent = gui
ecken(banner, 18)
local bannerRand = rand(banner, Color3.fromRGB(255, 205, 50), 4)
local bannerSkala = Instance.new("UIScale"); bannerSkala.Parent = banner
local bannerTitel = text(banner, "🎯 ÜBUNGSARENA", UDim2.new(1, -40, 0, 46), Color3.fromRGB(255, 205, 50))
bannerTitel.Position = UDim2.fromOffset(20, 14)
local bannerTitelRand = Instance.new("UIStroke"); bannerTitelRand.Thickness = 2.5; bannerTitelRand.Transparency = 0.2; bannerTitelRand.Parent = bannerTitel
local bannerText = text(banner, "Du bist jetzt alleine in der Übungsarena!\nTriff Dummys und Zielscheiben mit Bomben.", UDim2.new(1, -40, 0, 50), Color3.new(1, 1, 1), Enum.Font.GothamBold)
bannerText.Position = UDim2.fromOffset(20, 66)

local bannerNr = 0
local function zeigeBanner()
	bannerNr += 1
	local nr = bannerNr
	banner.Visible = true
	banner.BackgroundTransparency = 0.1
	bannerRand.Transparency = 0
	bannerTitel.TextTransparency = 0
	bannerTitelRand.Transparency = 0.2
	bannerText.TextTransparency = 0
	bannerSkala.Scale = 0.4
	TweenService:Create(bannerSkala, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
	task.delay(4.5, function()
		if nr ~= bannerNr then return end
		local info = TweenInfo.new(0.6)
		TweenService:Create(banner, info, {BackgroundTransparency = 1}):Play()
		TweenService:Create(bannerRand, info, {Transparency = 1}):Play()
		TweenService:Create(bannerTitel, info, {TextTransparency = 1}):Play()
		TweenService:Create(bannerTitelRand, info, {Transparency = 1}):Play()
		TweenService:Create(bannerText, info, {TextTransparency = 1}):Play()
		task.wait(0.6)
		if nr == bannerNr then banner.Visible = false end
	end)
end

local letzteZone = player:GetAttribute("UebungZone")
player:GetAttributeChangedSignal("UebungZone"):Connect(function()
	local z = player:GetAttribute("UebungZone")
	-- nur beim Betreten (nicht nach jedem Respawn in der Uebungsarena)
	if z == "arena" and letzteZone ~= "arena" then
		task.delay(0.4, zeigeBanner)
	end
	letzteZone = z
end)
