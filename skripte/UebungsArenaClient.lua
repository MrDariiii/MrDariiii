-- UebungsArenaClient: Anzeige in der Uebungsarena
--  * Einblendung beim Betreten (Text tippt sich wie in einem Tutorial ein)
--  * Leiste oben: Punkte + Rekord, Knopf LOBBY (zurueck in die Lobby)
-- (Pixel-Schrift und Pixel-Rahmen machen PixelSchriftClient / PixelRahmenClient automatisch)
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local remotes = RS:WaitForChild("UebungsArena")
local betretenRemote = remotes:WaitForChild("Betreten")
local verlassenRemote = remotes:WaitForChild("Verlassen")

local GOLD = Color3.fromRGB(255, 205, 50)
local TUERKIS = Color3.fromRGB(0, 220, 200)
local WEISS = Color3.new(1, 1, 1)
local SCHWARZ = Color3.new(0, 0, 0)
local DUNKEL = Color3.fromRGB(25, 25, 32)

local function neu(klasse, props, parent)
	local o = Instance.new(klasse)
	for k, v in props do o[k] = v end
	o.Parent = parent
	return o
end
local function rand(obj, dicke, farbe)
	return neu("UIStroke", {Thickness = dicke, Color = farbe or SCHWARZ, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, obj)
end
local function textRand(obj) return neu("UIStroke", {Thickness = 2, Color = SCHWARZ, Transparency = 0.2}, obj) end

local gui = neu("ScreenGui", {Name = "UebungsArenaGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 6, ZIndexBehavior = Enum.ZIndexBehavior.Sibling}, player:WaitForChild("PlayerGui"))
local skala = neu("UIScale", {}, gui)
local function passeAn()
	local vp = workspace.CurrentCamera.ViewportSize
	skala.Scale = math.clamp(math.min(vp.X / 1100, vp.Y / 700), 0.55, 1.15)
end
passeAn()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(passeAn)

-- ================= Einblendung (wie im Tutorial) =================
local banner = neu("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3), Size = UDim2.fromOffset(660, 150), BackgroundColor3 = DUNKEL, BackgroundTransparency = 0.08, Visible = false}, gui)
rand(banner, 4, TUERKIS)
local bSkala = neu("UIScale", {Scale = 1}, banner)
local bTitel = neu("TextLabel", {Position = UDim2.fromOffset(0, 16), Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, Font = Enum.Font.FredokaOne, Text = "", TextColor3 = TUERKIS, TextSize = 32}, banner)
textRand(bTitel)
local bText = neu("TextLabel", {Position = UDim2.fromOffset(24, 66), Size = UDim2.new(1, -48, 0, 70), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = "", TextColor3 = WEISS, TextSize = 15, TextWrapped = true, LineHeight = 1.3, TextYAlignment = Enum.TextYAlignment.Top}, banner)
textRand(bText)

local TITEL = "ÜBUNGSARENA"
local TEXT = "Du bist jetzt in der Übungsarena - ganz allein!\nWirf Bomben auf die Zielscheiben und Übungspuppen und sammle Punkte. Mit LOBBY oben kommst du zurück."

local bannerNr = 0
local function bannerZeigen()
	bannerNr += 1
	local nr = bannerNr
	bTitel.Text = TITEL
	bText.Text = TEXT
	bText.MaxVisibleGraphemes = 0
	banner.Visible = true
	bSkala.Scale = 0.6
	TweenService:Create(bSkala, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
	task.spawn(function()
		task.wait(0.45)
		-- Text tippt sich Buchstabe fuer Buchstabe ein
		local laenge = utf8.len(TEXT) or #TEXT
		for i = 1, laenge do
			if bannerNr ~= nr then return end
			bText.MaxVisibleGraphemes = i
			task.wait(0.022)
		end
		bText.MaxVisibleGraphemes = -1
		task.wait(3.5)
		if bannerNr ~= nr then return end
		local tw = TweenService:Create(bSkala, TweenInfo.new(0.25), {Scale = 0})
		tw:Play()
		tw.Completed:Wait()
		if bannerNr == nr then banner.Visible = false end
	end)
end
betretenRemote.OnClientEvent:Connect(bannerZeigen)

-- ================= Leiste oben + LOBBY-Knopf =================
local leiste = neu("Frame", {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, -84, 0, 58), Size = UDim2.fromOffset(440, 56), BackgroundColor3 = DUNKEL, BackgroundTransparency = 0.1, Visible = false}, gui)
rand(leiste, 3, TUERKIS)
local lTitel = neu("TextLabel", {Position = UDim2.fromOffset(16, 6), Size = UDim2.new(0.5, -16, 0, 22), BackgroundTransparency = 1, Font = Enum.Font.FredokaOne, Text = "ÜBUNGSARENA", TextColor3 = TUERKIS, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left}, leiste)
textRand(lTitel)
local lRekord = neu("TextLabel", {Position = UDim2.fromOffset(16, 32), Size = UDim2.new(0.5, -16, 0, 16), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = "REKORD 0", TextColor3 = Color3.fromRGB(190, 195, 215), TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left}, leiste)
textRand(lRekord)
local lPunkte = neu("TextLabel", {Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.new(0.5, -16, 0, 36), BackgroundTransparency = 1, Font = Enum.Font.FredokaOne, Text = "0", TextColor3 = GOLD, TextSize = 26, TextXAlignment = Enum.TextXAlignment.Right}, leiste)
textRand(lPunkte)
local pSkala = neu("UIScale", {}, lPunkte)

local lobbyKnopf = neu("TextButton", {Position = UDim2.new(0.5, 146, 0, 62), Size = UDim2.fromOffset(150, 48), BackgroundColor3 = TUERKIS, Text = "LOBBY", Font = Enum.Font.FredokaOne, TextSize = 20, TextColor3 = WEISS, AutoButtonColor = true, Visible = false}, gui)
rand(lobbyKnopf, 3, SCHWARZ)
textRand(lobbyKnopf)
local gesendet = 0
lobbyKnopf.Activated:Connect(function()
	if os.clock() - gesendet < 1.5 then return end
	gesendet = os.clock()
	verlassenRemote:FireServer()
end)

local function anzeigen()
	local drin = player:GetAttribute("UebungsArena") == true
	leiste.Visible = drin
	lobbyKnopf.Visible = drin
	if not drin then
		bannerNr += 1
		banner.Visible = false
	end
end
local letztePunkte = 0
local function punkteZeigen()
	local n = player:GetAttribute("UebungsPunkte") or 0
	lPunkte.Text = tostring(n)
	lRekord.Text = "REKORD " .. (player:GetAttribute("UebungsRekord") or 0)
	if n > letztePunkte then
		pSkala.Scale = 1.35
		TweenService:Create(pSkala, TweenInfo.new(0.25, Enum.EasingStyle.Back), {Scale = 1}):Play()
	end
	letztePunkte = n
end
player:GetAttributeChangedSignal("UebungsArena"):Connect(anzeigen)
player:GetAttributeChangedSignal("UebungsPunkte"):Connect(punkteZeigen)
player:GetAttributeChangedSignal("UebungsRekord"):Connect(punkteZeigen)
anzeigen()
punkteZeigen()
