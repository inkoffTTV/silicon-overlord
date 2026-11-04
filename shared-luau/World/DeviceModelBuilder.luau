--!strict
-- Parametric low-poly device models built from Parts (no mesh assets). Shared by the server showroom and the
-- client ViewportFrame preview. Sizes are in studs at scale 1 (a phone is ~1.5 studs tall); callers pass a scale.
-- Rounded silhouettes use the "slab + corner cylinders" trick: a centre block, two side blocks and four cylinders.
local DeviceModelBuilder = {}
-- Optional text hook for exploded-view labels (the client sets it to Locale.phrase; the server never shows labels).
DeviceModelBuilder.labelText = function(text: string): string
	return text
end

local colorways: { [string]: Color3 } = {
	graphite = Color3.fromRGB(52, 54, 60), silver = Color3.fromRGB(200, 203, 210), midnight = Color3.fromRGB(28, 32, 48), gold = Color3.fromRGB(214, 180, 120),
	blue = Color3.fromRGB(60, 110, 200), red = Color3.fromRGB(190, 55, 60), green = Color3.fromRGB(70, 140, 95), white = Color3.fromRGB(235, 236, 240),
	purple = Color3.fromRGB(120, 80, 170), black = Color3.fromRGB(20, 20, 24), titanium = Color3.fromRGB(140, 140, 145), orange = Color3.fromRGB(230, 130, 50),
}
DeviceModelBuilder.colorways = colorways
DeviceModelBuilder.colorwayNames = { "graphite", "silver", "midnight", "gold", "blue", "red", "green", "white", "purple", "black", "titanium", "orange" }

local materials: { [string]: Enum.Material } = {
	plastic = Enum.Material.SmoothPlastic, polycarbonate = Enum.Material.Plastic, aluminum = Enum.Material.Metal, glass = Enum.Material.Glass,
	titanium = Enum.Material.Metal, magnesium = Enum.Material.Metal, carbon = Enum.Material.Fabric, steel = Enum.Material.Metal,
}

export type DeviceParams = {
	category: string,
	subtype: string,
	colorway: string?,
	material: string?,
	screenInch: number?,
	lenses: number?,
	foldable: boolean?,
	glassBack: boolean?,
	name: string?,
	scale: number?,
	screenOn: boolean?,
	screenColor: Color3?,
	caseAirflow: number?,
	hasGPU: boolean?,
	accent: Color3?, -- company logo colour used for brand marks / RGB
	-- design-studio options (all optional, defaults keep the old look)
	cameraLayout: string?, -- topLeft | topMiddle | topRight | centre
	bumpShape: string?, -- none | circle | square | pill | bar
	selfiePosition: string?, -- left | centre | right
	cornerRadius: number?, -- 0..1
	bezelInch: number?,
	buttonSide: string?, -- left | right
	buttonHeight: number?, -- 0..1
	portOffset: number?, -- -1..1
	bodyColor: Color3?, -- overrides colorway
	accentColor: Color3?, -- frame / buttons / trims
	lightColor: Color3?, -- LED / glow parts
	finish: string?, -- classic | soft_matte | carbon_fibre | brushed_metal | pearl_ceramic | iridescent | blush_gold | white_marble | glacier | founder
	logoStyle: string?, -- ring | wordmark | monogram | badge | stripe | none
	wallpaper: { a: Color3, b: Color3 }?,
	screenHome: boolean?,
	companyInitial: string?,
	companyName: string?,
	-- component-driven visuals
	displayPanel: string?,
	refreshHz: number?,
	cameraMP: number?,
	ois: boolean?,
	chargerKind: string?, -- mini | micro | usbc | none
	wireless: boolean?,
	batteryWh: number?,
	batteryChem: string?,
	batteryName: string?,
	chipArea: number?,
	chipName: string?,
	chipGen: number?,
	ramGB: number?,
	ramName: string?,
	storageGB: number?,
	storageName: string?,
	coolingMethod: string?,
	coolingName: string?,
	sensorCount: number?,
	osOwn: boolean?,
	osName: string?,
	gpuName: string?,
	gpuVramGB: number?,
	gpuTdpW: number?,
	moboName: string?,
	moboFormFactor: string?,
	psuName: string?,
	psuW: number?,
	storage2Name: string?,
	storage2GB: number?,
	storageGen: number?,
	storage2Gen: number?,
	cameraSensorInch: number?,
	cameraGen: number?,
	displayGen: number?,
	displayNits: number?,
	chargerW: number?,
	sensorName: string?,
	caseForm: string?,
	caseDesign: number?,
}

local DARK = Color3.fromRGB(14, 15, 20)
local SCREEN_OFF = Color3.fromRGB(8, 8, 10)

local function darken(c: Color3, k: number): Color3
	return Color3.new(c.R * k, c.G * k, c.B * k)
end

local function lighten(c: Color3, k: number): Color3
	return Color3.new(c.R + (1 - c.R) * k, c.G + (1 - c.G) * k, c.B + (1 - c.B) * k)
end

local function part(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, name: string?): Part
	local p = Instance.new("Part")
	p.Name = name or "Part"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Cylinder whose axis points along `axis` ("X" | "Y" | "Z"); `length` along the axis, `diameter` across.
local function cylinder(parent: Instance, axis: string, length: number, diameter: number, cf: CFrame, color: Color3, material: Enum.Material, name: string?): Part
	local rot = CFrame.new()
	if axis == "Y" then
		rot = CFrame.Angles(0, 0, math.rad(90))
	elseif axis == "Z" then
		rot = CFrame.Angles(0, math.rad(90), 0)
	end
	local p = part(parent, Vector3.new(length, diameter, diameter), cf * rot, color, material, name)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function ball(parent: Instance, diameter: number, cf: CFrame, color: Color3, material: Enum.Material, name: string?): Part
	local p = part(parent, Vector3.new(diameter, diameter, diameter), cf, color, material, name)
	p.Shape = Enum.PartType.Ball
	return p
end

-- Rounded slab in the XY plane (thickness along Z): centre block + 2 side blocks + 4 corner cylinders along Z.
local function roundedSlab(parent: Instance, w: number, h: number, t: number, radius: number, cf: CFrame, color: Color3, material: Enum.Material, name: string): Part
	local r = math.min(radius, w / 2, h / 2)
	local centre = part(parent, Vector3.new(w - 2 * r, h, t), cf, color, material, name)
	part(parent, Vector3.new(r, h - 2 * r, t), cf * CFrame.new(-w / 2 + r / 2, 0, 0), color, material, name .. "L")
	part(parent, Vector3.new(r, h - 2 * r, t), cf * CFrame.new(w / 2 - r / 2, 0, 0), color, material, name .. "R")
	for _, sx in ipairs({ -1, 1 }) do
		for _, sy in ipairs({ -1, 1 }) do
			cylinder(parent, "Z", t, 2 * r, cf * CFrame.new(sx * (w / 2 - r), sy * (h / 2 - r), 0), color, material, name .. "Corner")
		end
	end
	return centre
end

-- Rounded slab lying flat in the XZ plane (thickness along Y).
local function roundedPlate(parent: Instance, w: number, d: number, t: number, radius: number, cf: CFrame, color: Color3, material: Enum.Material, name: string): Part
	local r = math.min(radius, w / 2, d / 2)
	local centre = part(parent, Vector3.new(w - 2 * r, t, d), cf, color, material, name)
	part(parent, Vector3.new(r, t, d - 2 * r), cf * CFrame.new(-w / 2 + r / 2, 0, 0), color, material, name .. "L")
	part(parent, Vector3.new(r, t, d - 2 * r), cf * CFrame.new(w / 2 - r / 2, 0, 0), color, material, name .. "R")
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			cylinder(parent, "Y", t, 2 * r, cf * CFrame.new(sx * (w / 2 - r), 0, sz * (d / 2 - r)), color, material, name .. "Corner")
		end
	end
	return centre
end

local function screenPart(parent: Instance, size: Vector3, cf: CFrame, on: boolean, tint: Color3?): Part
	local s = part(parent, size, cf, on and (tint or Color3.fromRGB(40, 130, 255)) or SCREEN_OFF, on and Enum.Material.Neon or Enum.Material.Glass, "Screen")
	if not on then
		s.Reflectance = 0.25
	end
	return s
end

local finishLook: { [string]: { material: Enum.Material?, reflect: number?, tint: number?, lift: number? } } = {
	classic = {}, soft_matte = { material = Enum.Material.Fabric, reflect = 0, tint = 0.95 }, carbon_fibre = { material = Enum.Material.Fabric, reflect = 0.05, tint = 0.6 },
	brushed_metal = { material = Enum.Material.Metal, reflect = 0.2 }, pearl_ceramic = { material = Enum.Material.Glass, reflect = 0.35, lift = 0.25 },
	iridescent = { material = Enum.Material.Glass, reflect = 0.45, lift = 0.1 }, blush_gold = { material = Enum.Material.Metal, reflect = 0.25, lift = 0.15 },
	white_marble = { material = Enum.Material.Marble, reflect = 0.1, lift = 0.5 }, glacier = { material = Enum.Material.Glass, reflect = 0.3, lift = 0.35 },
	founder = { material = Enum.Material.Metal, reflect = 0.4, lift = 0.05 },
}

local function bodyLook(params: DeviceParams): (Color3, Enum.Material, number)
	local color = params.bodyColor or colorways[params.colorway or "graphite"] or colorways.graphite
	local mat = materials[params.material or "aluminum"] or Enum.Material.Metal
	local reflect = 0
	if params.material == "titanium" then
		color = darken(color, 0.85)
		reflect = 0.12
	elseif mat == Enum.Material.Metal then
		reflect = 0.08
	elseif mat == Enum.Material.Glass then
		reflect = 0.3
	end
	local fl = params.finish and finishLook[params.finish]
	if fl then
		if fl.material then
			mat = fl.material
		end
		if fl.reflect then
			reflect = fl.reflect
		end
		if fl.tint then
			color = darken(color, fl.tint)
		end
		if fl.lift then
			color = lighten(color, fl.lift)
		end
		if params.finish == "blush_gold" then
			color = color:Lerp(Color3.fromRGB(220, 170, 150), 0.5)
		elseif params.finish == "founder" then
			color = color:Lerp(Color3.fromRGB(240, 200, 90), 0.4)
		end
	end
	return color, mat, reflect
end

local function accentOf(params: DeviceParams, fallback: Color3): Color3
	return params.accentColor or fallback
end

local function lightOf(params: DeviceParams, fallback: Color3): Color3
	return params.lightColor or fallback
end

local panelTint: { [string]: { color: Color3, bright: number } } = {
	TN = { color = Color3.fromRGB(90, 120, 170), bright = 0.6 }, VA = { color = Color3.fromRGB(50, 110, 200), bright = 0.8 }, IPS = { color = Color3.fromRGB(40, 130, 255), bright = 0.9 },
	OLED = { color = Color3.fromRGB(20, 100, 255), bright = 1.0 }, LTPO = { color = Color3.fromRGB(15, 95, 255), bright = 1.05 }, FlexOLED = { color = Color3.fromRGB(30, 90, 250), bright = 1.0 },
	MicroLED = { color = Color3.fromRGB(60, 160, 255), bright = 1.15 }, microOLED = { color = Color3.fromRGB(30, 100, 255), bright = 1.0 },
}

local function screenColorOf(params: DeviceParams): Color3
	if params.wallpaper then
		return params.wallpaper.a
	end
	if params.screenColor then
		return params.screenColor
	end
	local t = params.displayPanel and panelTint[params.displayPanel] or panelTint.IPS
	local c = t.color
	if t.bright < 0.8 then
		c = darken(c, t.bright + 0.2)
	elseif t.bright > 1 then
		c = lighten(c, (t.bright - 1) * 2)
	end
	return c
end

-- Home-screen overlay on the screen part (status bar, 4x4 icons, dock) — <= 25 GUI objects.
local function homeScreen(screen: Part, params: DeviceParams)
	if params.screenHome ~= true then
		return
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "HomeScreen"
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.CanvasSize = Vector2.new(360, 760)
	gui.Parent = screen
	local a = params.wallpaper and params.wallpaper.a or screenColorOf(params)
	local b = params.wallpaper and params.wallpaper.b or darken(a, 0.45)
	if params.osOwn and params.accent and not params.wallpaper then
		a = params.accent
		b = darken(a, 0.4)
	end
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.new(1, 1, 1)
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(a, b)
	grad.Rotation = 90
	grad.Parent = bg
	local status = Instance.new("TextLabel")
	status.Size = UDim2.new(1, -24, 0, 28)
	status.Position = UDim2.new(0, 12, 0, 10)
	status.BackgroundTransparency = 1
	status.Text = "9:41                      " .. (params.chipGen and params.chipGen >= 3 and "5G" or "4G") .. " ▮▮▮ ▰"
	status.TextColor3 = Color3.new(1, 1, 1)
	status.TextSize = 20
	status.Font = Enum.Font.GothamBold
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.Parent = bg
	local palette = { Color3.fromRGB(52, 199, 89), Color3.fromRGB(255, 149, 0), Color3.fromRGB(0, 122, 255), Color3.fromRGB(255, 59, 48), Color3.fromRGB(175, 82, 222), Color3.fromRGB(255, 204, 0), Color3.fromRGB(90, 200, 250), Color3.fromRGB(142, 142, 147) }
	local labels = { "Ms", "Ph", "Ca", "Ma", "Cl", "We", "No", "Mu", "Ph", "Ma", "Se", "St", "Ca", "Ga", "Wa", "Ap" }
	for i = 1, 16 do
		local icon = Instance.new("TextLabel")
		icon.Size = UDim2.new(0, 56, 0, 56)
		icon.Position = UDim2.new(0, 24 + ((i - 1) % 4) * 78, 0, 110 + math.floor((i - 1) / 4) * 92)
		icon.BackgroundColor3 = palette[((i - 1) % #palette) + 1]
		icon.Text = labels[i]
		icon.TextColor3 = Color3.new(1, 1, 1)
		icon.TextSize = 18
		icon.Font = Enum.Font.GothamBold
		icon.BorderSizePixel = 0
		icon.Parent = bg
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 14)
		corner.Parent = icon
	end
	local dock = Instance.new("Frame")
	dock.Size = UDim2.new(1, -24, 0, 76)
	dock.Position = UDim2.new(0, 12, 1, -92)
	dock.BackgroundColor3 = Color3.new(1, 1, 1)
	dock.BackgroundTransparency = 0.75
	dock.BorderSizePixel = 0
	dock.Parent = bg
	local dockCorner = Instance.new("UICorner")
	dockCorner.CornerRadius = UDim.new(0, 22)
	dockCorner.Parent = dock
	for i = 1, 4 do
		local d = Instance.new("Frame")
		d.Size = UDim2.new(0, 52, 0, 52)
		d.Position = UDim2.new(0, 16 + (i - 1) * 80, 0, 12)
		d.BackgroundColor3 = palette[i]
		d.BorderSizePixel = 0
		d.Parent = dock
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 13)
		c.Parent = d
	end
end

-- Back logo in the chosen style (ring with initial by default). Uses the accent colour.
local function brandMark(parent: Instance, cf: CFrame, s: number, params: DeviceParams)
	local style = params.logoStyle or "ring"
	if style == "none" then
		return
	end
	local accent = accentOf(params, params.accent or Color3.fromRGB(79, 140, 255))
	if style == "stripe" then
		local stripe = part(parent, Vector3.new(0.1 * s, 1.2 * s, 0.006 * s), cf, accent, Enum.Material.SmoothPlastic, "BrandMark")
		stripe.Reflectance = 0.15
		return
	end
	local size = style == "badge" and 0.16 or 0.12
	local plate
	if style == "ring" or style == "monogram" then
		plate = cylinder(parent, "Z", 0.008 * s, size * s, cf, accent, Enum.Material.SmoothPlastic, "BrandMark")
		if style == "ring" then
			local inner = cylinder(parent, "Z", 0.009 * s, size * 0.6 * s, cf, darken(accent, 0.35), Enum.Material.SmoothPlastic, "BrandMarkInner")
			inner.CastShadow = false
		end
	else
		plate = part(parent, Vector3.new(size * s, size * (style == "wordmark" and 0.4 or 1) * s, 0.008 * s), cf, accent, Enum.Material.Metal, "BrandMark")
	end
	plate.Reflectance = 0.25
	if style ~= "stripe" and (params.companyInitial or params.companyName) then
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Back
		gui.LightInfluence = 0
		gui.CanvasSize = Vector2.new(120, 120)
		gui.Parent = plate
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = style == "wordmark" and string.upper(string.sub(params.companyName or "", 1, 10)) or string.upper(string.sub(params.companyInitial or "", 1, 1))
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextScaled = true
		label.Font = Enum.Font.GothamBlack
		label.Parent = gui
	end
end

-- ---------------------------------------------------------------------------------------------------- Phone
-- Camera island: lens count, main lens diameter from MP, OIS inner ring, island shape from the wizard.
local function cameraIsland(model: Model, origin: CFrame, params: DeviceParams, s: number, color: Color3)
	local n = math.max(1, math.min(params.lenses or 2, 4))
	local mp = params.cameraMP or 12
	local mainD = (0.09 + 0.07 * math.clamp((mp - 8) / 192, 0, 1)) * s
	-- bigger sensors need bigger glass
	mainD = mainD * (0.85 + 0.4 * math.clamp(((params.cameraSensorInch or 0.43) - 0.3) / 0.7, 0, 1))
	local coatGen = math.clamp(params.cameraGen or 1, 1, 7)
	local shape = params.bumpShape or "circle"
	local islandW = (n <= 2 and 0.26 or 0.44) * s
	local islandH = (n == 1 and 0.26 or 0.44) * s
	if shape == "pill" then
		islandW = (n <= 2 and 0.22 or 0.24) * s
		islandH = (0.2 + 0.18 * n) * s
	elseif shape == "bar" then
		islandW = 0.62 * s
		islandH = 0.22 * s
	end
	local islandColor = darken(color, 0.7)
	if shape ~= "none" then
		local island
		if shape == "circle" then
			island = cylinder(model, "Z", 0.05 * s, math.max(islandW, islandH), origin, islandColor, Enum.Material.Metal, "CameraIsland")
		else
			island = part(model, Vector3.new(islandW, islandH, 0.05 * s), origin, islandColor, Enum.Material.Metal, "CameraIsland")
		end
		island.Reflectance = 0.1
	end
	local positions = {}
	local sp = 0.1 * s
	if shape == "bar" then
		positions = {}
		for i = 1, n do
			positions[i] = Vector3.new((i - (n + 1) / 2) * 0.14 * s, 0, 0)
		end
	elseif shape == "pill" then
		for i = 1, n do
			positions[i] = Vector3.new(0, ((n + 1) / 2 - i) * 0.17 * s, 0)
		end
	elseif n == 1 then
		positions = { Vector3.new(0, 0, 0) }
	elseif n == 2 then
		positions = { Vector3.new(0, sp, 0), Vector3.new(0, -sp, 0) }
	elseif n == 3 then
		positions = { Vector3.new(-sp, sp, 0), Vector3.new(sp, sp, 0), Vector3.new(-sp, -sp, 0) }
	else
		positions = { Vector3.new(-sp, sp, 0), Vector3.new(sp, sp, 0), Vector3.new(-sp, -sp, 0), Vector3.new(sp, -sp, 0) }
	end
	for i, off in ipairs(positions) do
		local d = i == 1 and mainD or mainD * 0.75
		local lensCf = origin * CFrame.new(off.X, off.Y, 0.03 * s)
		cylinder(model, "Z", 0.025 * s, d * 1.3, lensCf, Color3.fromRGB(30, 32, 40), Enum.Material.Metal, "LensRing")
		if i == 1 and params.ois then
			local oisRing = cylinder(model, "Z", 0.027 * s, d * 1.05, lensCf * CFrame.new(0, 0, 0.004 * s), Color3.fromRGB(110, 115, 130), Enum.Material.Metal, "OisRing")
			oisRing.CastShadow = false
		end
		local glass = cylinder(model, "Z", 0.02 * s, d * 0.9, lensCf * CFrame.new(0, 0, 0.012 * s), Color3.fromRGB(8, 10, 24), Enum.Material.Glass, "Lens")
		glass.Reflectance = 0.5
		-- newer lens coatings reflect a deeper blue/violet
		local dot = ball(model, 0.02 * s, lensCf * CFrame.new(d * 0.2, d * 0.2, 0.02 * s), Color3.fromRGB(math.floor(215 - coatGen * 15), math.floor(225 - coatGen * 8), 255), Enum.Material.Neon, "LensHighlight")
		dot.CastShadow = false
	end
	local flashOff = shape == "bar" and Vector3.new(islandW / 2 - 0.05 * s, 0, 0) or (n >= 3 and Vector3.new(sp, -sp, 0) or Vector3.new(0.09 * s, 0, 0))
	local flash = part(model, Vector3.new(0.05 * s, 0.05 * s, 0.01 * s), origin * CFrame.new(flashOff.X, flashOff.Y, 0.03 * s), lightOf(params, Color3.fromRGB(255, 240, 200)), Enum.Material.Neon, "Flash")
	flash.CastShadow = false
end

-- Island origin for a layout on the back face of a body w x h at depth d
local function islandOrigin(layout: string?, w: number, h: number, d: number, s: number, cf: CFrame): CFrame
	local x = -w * 0.28
	local y = h * 0.34
	if layout == "topMiddle" then
		x = 0
	elseif layout == "topRight" then
		x = w * 0.28
	elseif layout == "centre" then
		x = 0
		y = h * 0.12
	end
	return cf * CFrame.new(x, y, d / 2 + 0.02 * s)
end

local function markShell(p: Part)
	p:SetAttribute("Shell", true)
	p:SetAttribute("BaseTransparency", p.Transparency)
end

-- Internal components (hidden by default): battery slab, SoC, RAM, storage, cooling, wireless coil.
local function internals(model: Model, params: DeviceParams, s: number, cf: CFrame, w: number, h: number, d: number)
	local function internal(p: Part, label: string, explode: number)
		p.Transparency = 1
		p.CastShadow = false
		p:SetAttribute("Internal", true)
		p:SetAttribute("Label", label)
		p:SetAttribute("ExplodeOffset", explode * s)
		p:SetAttribute("HomePos", p.CFrame.Position)
		local dir = cf:VectorToWorldSpace(Vector3.new(0, 0, 1))
		p:SetAttribute("ExplodeDir", dir)
	end
	-- battery: height proportional to Wh (18 Wh ~ full length), chemistry colour
	local wh = params.batteryWh or 15
	local chem = params.batteryChem or "LiPo"
	local chemColor = ({ LiPo = Color3.fromRGB(120, 122, 128), LiIon = Color3.fromRGB(60, 62, 70), SiliconCarbon = Color3.fromRGB(70, 110, 200), SolidState = Color3.fromRGB(200, 205, 215) })[chem] or Color3.fromRGB(120, 122, 128)
	local battH = h * math.clamp(0.3 + 0.5 * wh / 18, 0.3, 0.85)
	local batt = part(model, Vector3.new(w * 0.7, battH, d * 0.35), cf * CFrame.new(0, -h * 0.08, d * 0.05), chemColor, Enum.Material.SmoothPlastic, "Internal_Battery")
	internal(batt, string.format("%s · %.0f Wh %s%s", params.batteryName or "Battery", wh, chem, params.chargerW and string.format(" · %.0f W charging", params.chargerW) or ""), 0.45)
	-- board + chips near the top
	local board = part(model, Vector3.new(w * 0.78, h * 0.28, d * 0.12), cf * CFrame.new(0, h * 0.3, -d * 0.05), Color3.fromRGB(20, 70, 45), Enum.Material.SmoothPlastic, "Internal_Board")
	if params.moboName then
		-- desktop boards: bigger for ATX than mATX/ITX
		local k = ({ ATX = 1, mATX = 0.85, ITX = 0.7 })[params.moboFormFactor or "ATX"] or 1
		board.Size = Vector3.new(board.Size.X * k, board.Size.Y * (1 + 0.6 * k), board.Size.Z)
		board.Color = Color3.fromRGB(28, 40, 70)
	end
	internal(board, params.moboName or "Logic board", 0.3)
	local area = params.chipArea or 90
	local dieSize = (0.08 + 0.12 * math.clamp(area / 300, 0, 1)) * s
	local soc = part(model, Vector3.new(dieSize, dieSize, d * 0.14), cf * CFrame.new(-w * 0.15, h * 0.3, -d * 0.18), Color3.fromRGB(40, 42, 50), Enum.Material.Metal, "Internal_SoC")
	internal(soc, string.format("%s%s", params.chipName or "SoC", params.chipGen and string.format(" · Gen %.0f", params.chipGen) or ""), 0.6)
	local ramChips = math.clamp(math.ceil((params.ramGB or 4) / 4), 1, 3)
	for i = 1, ramChips do
		local ram = part(model, Vector3.new(0.07 * s, 0.05 * s, d * 0.12), cf * CFrame.new(w * 0.05 + (i - 1) * 0.085 * s, h * 0.34, -d * 0.18), Color3.fromRGB(30, 30, 36), Enum.Material.SmoothPlastic, "Internal_RAM")
		internal(ram, string.format("%s · %.0f GB", params.ramName or "RAM", params.ramGB or 0), 0.6)
	end
	local sto = part(model, Vector3.new(0.09 * s, 0.07 * s, d * 0.12), cf * CFrame.new(w * 0.12, h * 0.25, -d * 0.18), Color3.fromRGB(26, 28, 34), Enum.Material.SmoothPlastic, "Internal_Storage")
	internal(sto, string.format("%s · %.0f GB%s%s", params.storageName or "Storage", params.storageGB or 0, params.storageGen and string.format(" · Gen %.0f", params.storageGen) or "", params.osName and (" · " .. params.osName) or ""), 0.6)
	if params.osName then
		-- firmware tint: every OS gets its own boot-chip colour
		local hash = 0
		for i = 1, #params.osName do
			hash = (hash * 31 + string.byte(params.osName, i)) % 360
		end
		sto.Color = Color3.fromHSV(hash / 360, 0.35, 0.3)
	end
	if params.storage2Name then
		local sto2 = part(model, Vector3.new(0.09 * s, (0.05 + 0.04 * math.clamp((params.storage2GB or 512) / 4096, 0, 1)) * s, d * 0.12), cf * CFrame.new(w * 0.25, h * 0.25, -d * 0.18), Color3.fromRGB(34, 36, 44), Enum.Material.SmoothPlastic, "Internal_Storage2")
		internal(sto2, string.format("%s · %.0f GB%s", params.storage2Name, params.storage2GB or 0, params.storage2Gen and string.format(" · Gen %.0f", params.storage2Gen) or ""), 0.6)
	end
	if params.gpuName then
		local tdp = params.gpuTdpW or 150
		local gpu = part(model, Vector3.new(w * 0.62, h * (0.08 + 0.08 * math.clamp(tdp / 350, 0, 1)), d * 0.18), cf * CFrame.new(0, h * 0.05, -d * 0.12), Color3.fromRGB(46, 48, 58), Enum.Material.Metal, "Internal_GPU")
		internal(gpu, string.format("%s · %.0f GB", params.gpuName, params.gpuVramGB or 0), 0.7)
	end
	if params.psuW then
		local k = math.clamp(params.psuW / 1000, 0.3, 1.2)
		local psu = part(model, Vector3.new(w * 0.4 * k + w * 0.15, h * 0.14, d * 0.25), cf * CFrame.new(0, -h * 0.4, -d * 0.1), Color3.fromRGB(24, 24, 28), Enum.Material.Metal, "Internal_PSU")
		internal(psu, string.format("%s · %.0f W", params.psuName or "PSU", params.psuW), 0.5)
	end
	-- cooling: graphite sheet or copper vapor chamber
	local method = params.coolingMethod or "graphite"
	local coolColor = method == "vaporChamber" and Color3.fromRGB(190, 120, 70) or (method == "liquidMetal" and Color3.fromRGB(200, 205, 215) or Color3.fromRGB(35, 35, 40))
	local cool = part(model, Vector3.new(w * 0.6, h * 0.4, d * 0.05), cf * CFrame.new(0, h * 0.2, -d * 0.28), coolColor, method == "graphite" and Enum.Material.SmoothPlastic or Enum.Material.Metal, "Internal_Cooling")
	internal(cool, string.format("%s · %s", params.coolingName or "Cooling", method), 0.75)
	-- wireless coil
	if params.wireless then
		local coil = cylinder(model, "Z", d * 0.06, w * 0.45, cf * CFrame.new(0, -h * 0.05, d * 0.3), Color3.fromRGB(200, 140, 60), Enum.Material.Metal, "Internal_Coil")
		internal(coil, "Wireless charging coil", 0.2)
	end
	-- health / tracking sensor hub
	if (params.sensorCount or 0) > 0 then
		local n = params.sensorCount or 1
		local hub = part(model, Vector3.new((0.05 + 0.012 * math.min(n, 12)) * s, 0.05 * s, d * 0.1), cf * CFrame.new(-w * 0.2, -h * 0.3, d * 0.25), Color3.fromRGB(30, 70, 50), Enum.Material.SmoothPlastic, "Internal_Sensors")
		internal(hub, string.format("%s · %.0f sensors", params.sensorName or "Sensors", n), 0.35)
	end
end
DeviceModelBuilder.buildInternals = internals

-- Port notch on the bottom edge by charger kind
local function portNotch(model: Model, params: DeviceParams, s: number, cf: CFrame, w: number, h: number, d: number)
	local kind = params.chargerKind or "usbc"
	if kind == "none" then
		return
	end
	local x = (params.portOffset or 0) * w * 0.3
	local size = Vector3.new(0.09 * s, 0.012 * s, 0.03 * s)
	if kind == "mini" then
		size = Vector3.new(0.11 * s, 0.012 * s, 0.045 * s)
	elseif kind == "micro" then
		size = Vector3.new(0.07 * s, 0.012 * s, 0.025 * s)
	end
	local port = part(model, size, cf * CFrame.new(x, -h / 2 - 0.004 * s, 0), DARK, Enum.Material.SmoothPlastic, "Port")
	port:SetAttribute("PortKind", kind)
	-- speaker holes either side of the port
	for i = 1, 3 do
		local hole = part(model, Vector3.new(0.012 * s, 0.01 * s, 0.012 * s), cf * CFrame.new(x + (size.X / 2 + 0.04 * s + (i - 1) * 0.03 * s), -h / 2 - 0.003 * s, 0), DARK, Enum.Material.SmoothPlastic, "SpeakerHole")
		hole.CastShadow = false
	end
end

local function finishDetails(model: Model, params: DeviceParams, s: number, cf: CFrame, w: number, h: number, d: number, color: Color3)
	local finish = params.finish
	if finish == "carbon_fibre" then
		for i = -2, 2 do
			local stripe = part(model, Vector3.new(w * 0.9, 0.012 * s, 0.004 * s), cf * CFrame.new(0, i * 0.22 * s, d / 2 + 0.003 * s) * CFrame.Angles(0, 0, math.rad(35)), darken(color, 0.45), Enum.Material.SmoothPlastic, "FinishStripe")
			stripe.CastShadow = false
		end
	elseif finish == "brushed_metal" or params.material == "aluminum" or params.material == "titanium" then
		for i = -3, 3 do
			local line = part(model, Vector3.new(0.004 * s, h * 0.9, 0.004 * s), cf * CFrame.new(i * 0.1 * s, 0, d / 2 + 0.003 * s), lighten(color, 0.08), Enum.Material.Metal, "BrushLine")
			line.CastShadow = false
			line.Transparency = 0.6
		end
	end
end

local function phoneHalf(model: Model, params: DeviceParams, s: number, w: number, h: number, d: number, cf: CFrame, name: string, withIsland: boolean, simpleBack: boolean): Part
	local color, mat, reflect = bodyLook(params)
	local radius = (0.04 + 0.16 * (params.cornerRadius or 0.5)) * s
	local frameColor = params.accentColor or darken(color, 0.75)
	local frame = roundedSlab(model, w, h, d, radius, cf, frameColor, Enum.Material.Metal, name .. "Frame")
	frame.Reflectance = 0.15
	markShell(frame)
	local back
	if simpleBack then
		back = part(model, Vector3.new(w * 0.9, h * 0.94, d * 0.55), cf * CFrame.new(0, 0, d * 0.25), color, mat, name .. "Back")
	else
		back = roundedSlab(model, w * 0.985, h * 0.99, d * 0.55, radius * 0.9, cf * CFrame.new(0, 0, d * 0.25), color, mat, name .. "Back")
	end
	back.Reflectance = reflect
	markShell(back)
	if params.glassBack then
		local gloss = part(model, Vector3.new(w * 0.9, h * 0.95, 0.006 * s), cf * CFrame.new(0, 0, d / 2 + 0.003 * s), lighten(color, 0.1), Enum.Material.Glass, name .. "Gloss")
		gloss.Reflectance = 0.35
		gloss.Transparency = 0.2
		markShell(gloss)
	end
	-- bezel from the wizard: 0.3" on a 6.4" phone ~ 5% inset
	local inch = params.screenInch or 6.4
	local bezelFrac = math.clamp((params.bezelInch or 0.3) / inch * 0.7, 0.015, 0.12)
	local bezel = part(model, Vector3.new(w * 0.96, h * 0.975, 0.01 * s), cf * CFrame.new(0, 0, -d / 2 - 0.002 * s), DARK, Enum.Material.SmoothPlastic, name .. "Bezel")
	markShell(bezel)
	local screen = screenPart(model, Vector3.new(w * (0.96 - 2 * bezelFrac), h * (0.975 - 2 * bezelFrac), 0.008 * s), cf * CFrame.new(0, 0, -d / 2 - 0.009 * s), params.screenOn ~= false, screenColorOf(params))
	markShell(screen)
	homeScreen(screen, params)
	if (params.refreshHz or 60) >= 90 and params.screenOn ~= false then
		local strip = part(model, Vector3.new(w * 0.5, 0.01 * s, 0.004 * s), cf * CFrame.new(0, h * 0.47, -d / 2 - 0.014 * s), lightOf(params, Color3.fromRGB(200, 240, 255)), Enum.Material.Neon, name .. "RefreshStrip")
		strip.CastShadow = false
		strip:SetAttribute("Animated", "refresh")
	end
	if withIsland then
		cameraIsland(model, islandOrigin(params.cameraLayout, w, h, d, s, cf), params, s, color)
		brandMark(model, cf * CFrame.new(0, -h * 0.05, d / 2 + 0.006 * s), s, params)
		finishDetails(model, params, s, cf, w, h, d, color)
		internals(model, params, s, cf, w, h, d)
	end
	return frame
end

-- Selfie punch-hole, earpiece, side buttons, charging port and back sensor dots for a phone body (or the
-- outer half of a foldable) centred at cf with size w x h x d.
local function phoneExtras(model: Model, params: DeviceParams, s: number, cf: CFrame, w: number, h: number, d: number, frameColor: Color3)
	local sx = 0
	if params.selfiePosition == "left" then
		sx = -w * 0.3
	elseif params.selfiePosition == "right" then
		sx = w * 0.3
	end
	local hole = cylinder(model, "Z", 0.012 * s, 0.045 * s, cf * CFrame.new(sx, h * 0.44, -d / 2 - 0.012 * s), Color3.fromRGB(4, 4, 8), Enum.Material.SmoothPlastic, "Selfie")
	hole.CastShadow = false
	part(model, Vector3.new(0.2 * s, 0.012 * s, 0.01 * s), cf * CFrame.new(0, h / 2 - 0.02 * s, -d / 2 - 0.004 * s), Color3.fromRGB(30, 30, 34), Enum.Material.SmoothPlastic, "Speaker")
	-- side buttons: side + height from the wizard
	local side = params.buttonSide == "left" and -1 or 1
	local by = (-0.25 + 0.6 * (params.buttonHeight or 0.6)) * h
	local btnColor = lighten(accentOf(params, frameColor), 0.1)
	local power = part(model, Vector3.new(0.02 * s, 0.18 * s, 0.035 * s), cf * CFrame.new(side * (w / 2 + 0.008 * s), by, 0), btnColor, Enum.Material.Metal, "PowerButton")
	local volume = part(model, Vector3.new(0.02 * s, 0.28 * s, 0.035 * s), cf * CFrame.new(side * (w / 2 + 0.008 * s), by + 0.3 * s, 0), btnColor, Enum.Material.Metal, "VolumeButton")
	power:SetAttribute("Highlightable", true)
	volume:SetAttribute("Highlightable", true)
	portNotch(model, params, s, cf, w, h, d)
	-- back sensors (wearable-like health dots) when the device carries sensors
	if (params.sensorCount or 0) > 0 then
		for i = 1, math.min(params.sensorCount or 0, 4) do
			local dot = cylinder(model, "Z", 0.01 * s, 0.03 * s, cf * CFrame.new((i - 2.5) * 0.05 * s, -h * 0.3, d / 2 + 0.006 * s), Color3.fromRGB(20, 60, 40), Enum.Material.Glass, "SensorDot")
			dot.CastShadow = false
		end
	end
end

local function phone(model: Model, params: DeviceParams, s: number)
	local inch = params.screenInch or 6.4
	local k = inch / 6.4
	local h = 1.5 * s * k
	local w = 0.72 * s * k
	local d = 0.08 * s
	if params.foldable then
		local half = w * 0.95
		local tilt = math.rad(7.5)
		local left = phoneHalf(model, params, s, half, h, d, CFrame.new(-half / 2 - 0.02 * s, 0, 0) * CFrame.Angles(0, -tilt, 0), "Left", false, true)
		local rightCf = CFrame.new(half / 2 + 0.02 * s, 0, 0) * CFrame.Angles(0, tilt, 0)
		local right = phoneHalf(model, params, s, half, h, d, rightCf, "Right", true, true)
		local hinge = cylinder(model, "Y", h * 0.96, d * 1.3, CFrame.new(0, 0, 0), accentOf(params, Color3.fromRGB(100, 102, 110)), Enum.Material.Metal, "Hinge")
		markShell(hinge)
		local crease = part(model, Vector3.new(0.012 * s, h * 0.9, 0.004 * s), CFrame.new(0, 0, -d / 2 - 0.012 * s), Color3.fromRGB(60, 70, 90), Enum.Material.SmoothPlastic, "Crease")
		crease.CastShadow = false
		phoneExtras(model, params, s, rightCf, half, h, d, right.Color)
		model.PrimaryPart = left
		return
	end
	local frame = phoneHalf(model, params, s, w, h, d, CFrame.new(), "", true, false)
	phoneExtras(model, params, s, CFrame.new(), w, h, d, frame.Color)
	model.PrimaryPart = frame
end

-- ---------------------------------------------------------------------------------------------------- Laptop
local function laptop(model: Model, params: DeviceParams, s: number)
	local inch = params.screenInch or 14
	local k = inch / 14
	local w = 2.2 * s * k
	local depth = 1.5 * s * k
	local thick = 0.08 * s
	local color, mat, reflect = bodyLook(params)
	local base = roundedPlate(model, w, depth, thick, 0.1 * s, CFrame.new(), color, mat, "Base")
	base.Reflectance = reflect
	-- keyboard deck
	local deckCf = CFrame.new(0, thick / 2 + 0.004 * s, depth * 0.02)
	if s >= 2 then
		local cols, rows = 8, 4
		local keyW = (w * 0.78) / cols
		local keyD = (depth * 0.42) / rows
		for r = 1, rows do
			for c = 1, cols do
				local x = -w * 0.39 + keyW * (c - 0.5)
				local z = -depth * 0.19 + keyD * (r - 0.5)
				local key = part(model, Vector3.new(keyW * 0.82, 0.008 * s, keyD * 0.8), deckCf * CFrame.new(x, 0, z), Color3.fromRGB(28, 29, 34), Enum.Material.SmoothPlastic, "Key")
				key.CastShadow = false
			end
		end
	else
		part(model, Vector3.new(w * 0.78, 0.006 * s, depth * 0.42), deckCf, Color3.fromRGB(26, 27, 32), Enum.Material.SmoothPlastic, "Keyboard")
	end
	local pad = part(model, Vector3.new(w * 0.32, 0.004 * s, depth * 0.22), deckCf * CFrame.new(0, 0, depth * 0.34), lighten(color, 0.05), Enum.Material.SmoothPlastic, "Trackpad")
	pad.Reflectance = 0.05
	-- rubber feet
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			part(model, Vector3.new(0.12 * s, 0.015 * s, 0.08 * s), CFrame.new(sx * w * 0.42, -thick / 2 - 0.006 * s, sz * depth * 0.4), Color3.fromRGB(30, 30, 32), Enum.Material.Rubber, "Foot")
		end
	end
	-- hinge barrel + lid at 105 degrees
	local hingeCf = CFrame.new(0, thick / 2, -depth / 2 + 0.02 * s)
	cylinder(model, "X", w * 0.6, thick * 1.1, hingeCf, darken(color, 0.7), Enum.Material.Metal, "Hinge")
	local lidT = 0.05 * s
	local lidCf = hingeCf * CFrame.Angles(math.rad(-105), 0, 0) * CFrame.new(0, 0, -depth * 0.5)
	local lid = roundedPlate(model, w, depth, lidT, 0.1 * s, lidCf, color, mat, "Lid")
	lid.Reflectance = reflect
	-- lid bezel + screen on the inner face (local +Y of the lid faces the user after rotation)
	part(model, Vector3.new(w * 0.96, 0.006 * s, depth * 0.94), lidCf * CFrame.new(0, lidT / 2 + 0.003 * s, 0), DARK, Enum.Material.SmoothPlastic, "Bezel")
	local screen = screenPart(model, Vector3.new(w * 0.92, 0.006 * s, depth * 0.88), lidCf * CFrame.new(0, lidT / 2 + 0.009 * s, 0.01 * s), params.screenOn ~= false, params.screenColor)
	if params.screenOn ~= false then
		-- a second, lighter strip approximates a soft gradient without textures
		local glow = part(model, Vector3.new(w * 0.92, 0.004 * s, depth * 0.3), lidCf * CFrame.new(0, lidT / 2 + 0.013 * s, -depth * 0.25), lighten(screen.Color, 0.35), Enum.Material.Neon, "ScreenGlow")
		glow.Transparency = 0.5
		glow.CastShadow = false
	end
	brandMark(model, lidCf * CFrame.new(0, -lidT / 2 - 0.004 * s, 0) * CFrame.Angles(math.rad(90), 0, 0), s, params)
	if params.hasGPU then
		for i = -2, 2 do
			part(model, Vector3.new(0.14 * s, thick * 0.6, 0.02 * s), CFrame.new(i * 0.22 * s, 0, -depth / 2 - 0.005 * s), DARK, Enum.Material.SmoothPlastic, "Vent")
		end
	end
	model.PrimaryPart = base
end

-- ---------------------------------------------------------------------------------------------------- PC
local function fanRing(model: Model, cf: CFrame, diameter: number, depth: number, accent: Color3, name: string)
	local housing = cylinder(model, "Z", depth, diameter, cf, Color3.fromRGB(26, 27, 32), Enum.Material.SmoothPlastic, name)
	local _ = housing
	local ring = cylinder(model, "Z", depth * 0.4, diameter * 0.86, cf * CFrame.new(0, 0, -depth * 0.35), accent, Enum.Material.Neon, name .. "Ring")
	ring.CastShadow = false
	cylinder(model, "Z", depth * 0.5, diameter * 0.6, cf * CFrame.new(0, 0, -depth * 0.3), Color3.fromRGB(40, 42, 48), Enum.Material.SmoothPlastic, name .. "Hub")
end

local function tower(model: Model, params: DeviceParams, s: number)
	local accent = params.accent or Color3.fromRGB(80, 120, 255)
	local isOffice = params.subtype == "OfficePC" or params.hasGPU == false
	local w, h, d = (isOffice and 0.7 or 1.0) * s, (isOffice and 1.5 or 2.1) * s, (isOffice and 1.6 or 2.2) * s
	local color = colorways[params.colorway or "black"] or colorways.black
	local mat = materials[params.material or "steel"] or Enum.Material.Metal
	-- case form factor scales the tower; airflow opens the front mesh; design score adds polish
	local formK = ({ ITX = 0.86, mATX = 0.94, ATX = 1, EATX = 1.08, ["E-ATX"] = 1.08 })[params.caseForm or "ATX"] or 1
	w, h, d = w * formK, h * formK, d * formK
	local case = part(model, Vector3.new(w, h, d), CFrame.new(), color, mat, "Case")
	case.Reflectance = 0.04 + 0.12 * math.clamp(params.caseDesign or 0.3, 0, 1)
	-- front mesh plate
	local mesh = part(model, Vector3.new(w * 0.9, h * 0.9, 0.03 * s), CFrame.new(0, 0, -d / 2 - 0.015 * s), darken(color, 0.6), Enum.Material.DiamondPlate, "FrontMesh")
	mesh.Transparency = math.clamp(0.7 - 0.6 * (params.caseAirflow or 0.6), 0, 0.6)
	-- power button
	local pwr = cylinder(model, "Y", 0.01 * s, 0.08 * s, CFrame.new(w * 0.3, h / 2 + 0.005 * s, -d * 0.35), accent, Enum.Material.Neon, "Power")
	pwr.CastShadow = false
	-- rubber feet
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			part(model, Vector3.new(0.12 * s, 0.04 * s, 0.12 * s), CFrame.new(sx * w * 0.4, -h / 2 - 0.02 * s, sz * d * 0.4), Color3.fromRGB(20, 20, 22), Enum.Material.Rubber, "Foot")
		end
	end
	if isOffice then
		part(model, Vector3.new(w * 0.6, 0.02 * s, 0.01 * s), CFrame.new(0, h * 0.3, -d / 2 - 0.035 * s), Color3.fromRGB(60, 60, 66), Enum.Material.SmoothPlastic, "DriveBay")
		model.PrimaryPart = case
		return
	end
	-- glass side panel on -X (slightly larger so it reads as a separate pane)
	local glass = part(model, Vector3.new(0.012 * s, h * 0.9, d * 0.88), CFrame.new(-w / 2 - 0.006 * s, 0, 0.03 * s), Color3.fromRGB(120, 150, 180), Enum.Material.Glass, "SidePanel")
	glass.Transparency = 0.55
	glass.Reflectance = 0.2
	-- interior (visible through the glass): motherboard on +X wall, RAM, cooler, GPU, shrouds
	part(model, Vector3.new(0.02 * s, h * 0.8, d * 0.72), CFrame.new(w * 0.4, 0.02 * s, 0.08 * s), Color3.fromRGB(18, 55, 38), Enum.Material.SmoothPlastic, "Motherboard")
	for i = 1, 4 do
		part(model, Vector3.new(0.06 * s, 0.5 * s, 0.02 * s), CFrame.new(w * 0.3, 0.45 * s, -0.18 * s + i * 0.07 * s), i % 2 == 0 and Color3.fromRGB(50, 52, 60) or accent, i % 2 == 0 and Enum.Material.Metal or Enum.Material.Neon, "RamStick")
	end
	-- CPU cooler: base + 5 fin plates + heat pipes
	local coolerCf = CFrame.new(w * 0.14, 0.42 * s, -0.25 * s)
	part(model, Vector3.new(0.24 * s, 0.1 * s, 0.24 * s), coolerCf * CFrame.new(0, -0.3 * s, 0), Color3.fromRGB(150, 150, 155), Enum.Material.Metal, "CoolerBase")
	for i = 1, 5 do
		part(model, Vector3.new(0.02 * s, 0.5 * s, 0.4 * s), coolerCf * CFrame.new(-0.12 * s + (i - 1) * 0.06 * s, 0.05 * s, 0), Color3.fromRGB(190, 190, 196), Enum.Material.Metal, "Fin")
	end
	cylinder(model, "Y", 0.6 * s, 0.03 * s, coolerCf * CFrame.new(-0.16 * s, 0, 0.1 * s), Color3.fromRGB(180, 120, 80), Enum.Material.Metal, "HeatPipe")
	cylinder(model, "Y", 0.6 * s, 0.03 * s, coolerCf * CFrame.new(-0.16 * s, 0, -0.1 * s), Color3.fromRGB(180, 120, 80), Enum.Material.Metal, "HeatPipe")
	-- GPU with 2 fans
	local gpuCf = CFrame.new(w * 0.05, -0.25 * s, 0.15 * s)
	part(model, Vector3.new(0.5 * s, 0.14 * s, 1.1 * s), gpuCf, Color3.fromRGB(36, 38, 44), Enum.Material.Metal, "GPU")
	for i = -1, 1, 2 do
		local fan = cylinder(model, "Y", 0.02 * s, 0.32 * s, gpuCf * CFrame.new(-0.05 * s, -0.08 * s, i * 0.28 * s), Color3.fromRGB(20, 20, 24), Enum.Material.SmoothPlastic, "GpuFan")
		local _ = fan
		local ring = cylinder(model, "Y", 0.01 * s, 0.28 * s, gpuCf * CFrame.new(-0.05 * s, -0.095 * s, i * 0.28 * s), accent, Enum.Material.Neon, "GpuFanRing")
		ring.CastShadow = false
	end
	-- PSU shroud + cable shroud
	part(model, Vector3.new(w * 0.9, 0.3 * s, d * 0.8), CFrame.new(0, -h / 2 + 0.2 * s, 0.05 * s), darken(color, 0.8), Enum.Material.Metal, "PsuShroud")
	part(model, Vector3.new(w * 0.9, h * 0.7, 0.2 * s), CFrame.new(0, 0.12 * s, d / 2 - 0.25 * s), darken(color, 0.8), Enum.Material.Metal, "CableShroud")
	-- 3 front RGB fans
	for i = 1, 3 do
		fanRing(model, CFrame.new(0, (i - 2) * 0.55 * s, -d / 2 + 0.12 * s), 0.46 * s, 0.1 * s, accent, "Fan" .. tostring(i))
	end
	local light = Instance.new("PointLight")
	light.Color = accent
	light.Range = 2.5 * s
	light.Brightness = 0.7 * (params.caseAirflow or 0.6)
	light.Parent = case
	model.PrimaryPart = case
end

-- ---------------------------------------------------------------------------------------------------- Console
local function console(model: Model, params: DeviceParams, s: number)
	local color, mat, reflect = bodyLook(params)
	local accent = params.accent or Color3.fromRGB(80, 160, 255)
	if params.subtype == "HandheldConsole" then
		local w, h, d = 1.7 * s, 0.75 * s, 0.14 * s
		local body = part(model, Vector3.new(w, h, d), CFrame.new(), color, mat, "Body")
		body.Reflectance = reflect
		-- rounded grips
		for _, sx in ipairs({ -1, 1 }) do
			local grip = cylinder(model, "Y", h * 1.05, d * 2.2, CFrame.new(sx * (w / 2 + 0.02 * s), -h * 0.05, d * 0.3), darken(color, 0.85), mat, "Grip")
			grip.Reflectance = reflect
		end
		part(model, Vector3.new(w * 0.6, h * 0.84, 0.006 * s), CFrame.new(0, 0, -d / 2 - 0.003 * s), DARK, Enum.Material.SmoothPlastic, "Bezel")
		screenPart(model, Vector3.new(w * 0.56, h * 0.78, 0.006 * s), CFrame.new(0, 0, -d / 2 - 0.009 * s), params.screenOn ~= false, params.screenColor)
		-- sticks
		for _, sx in ipairs({ -1, 1 }) do
			local base = cylinder(model, "Z", 0.03 * s, 0.14 * s, CFrame.new(sx * w * 0.4, 0.12 * s, -d / 2 - 0.015 * s), Color3.fromRGB(30, 30, 34), Enum.Material.SmoothPlastic, "StickBase")
			local _ = base
			cylinder(model, "Z", 0.04 * s, 0.09 * s, CFrame.new(sx * w * 0.4, 0.12 * s, -d / 2 - 0.05 * s), Color3.fromRGB(40, 42, 48), Enum.Material.Rubber, "StickTop")
		end
		-- face buttons (4 coloured) on the right, d-pad on the left
		local faceColors = { Color3.fromRGB(240, 80, 80), Color3.fromRGB(80, 200, 120), Color3.fromRGB(80, 140, 255), Color3.fromRGB(250, 200, 60) }
		local offsets = { Vector3.new(0, 0.06, 0), Vector3.new(0.06, 0, 0), Vector3.new(0, -0.06, 0), Vector3.new(-0.06, 0, 0) }
		for i = 1, 4 do
			local off = offsets[i]
			local btn = cylinder(model, "Z", 0.015 * s, 0.045 * s, CFrame.new(w * 0.4 + off.X * s, -0.15 * s + off.Y * s, -d / 2 - 0.008 * s), faceColors[i], Enum.Material.SmoothPlastic, "FaceButton")
			btn.CastShadow = false
		end
		part(model, Vector3.new(0.14 * s, 0.045 * s, 0.015 * s), CFrame.new(-w * 0.4, -0.15 * s, -d / 2 - 0.008 * s), Color3.fromRGB(40, 42, 48), Enum.Material.SmoothPlastic, "DpadH")
		part(model, Vector3.new(0.045 * s, 0.14 * s, 0.015 * s), CFrame.new(-w * 0.4, -0.15 * s, -d / 2 - 0.008 * s), Color3.fromRGB(40, 42, 48), Enum.Material.SmoothPlastic, "DpadV")
		-- triggers
		for _, sx in ipairs({ -1, 1 }) do
			part(model, Vector3.new(0.25 * s, 0.05 * s, 0.1 * s), CFrame.new(sx * w * 0.35, h / 2 + 0.02 * s, 0.02 * s), darken(color, 0.7), mat, "Trigger")
		end
		model.PrimaryPart = body
		return
	end
	-- home console: slanted two-tone body, glossy centre strip, LED line
	local w, h, d = 1.5 * s, 0.32 * s, 1.5 * s
	local lower = part(model, Vector3.new(w, h * 0.55, d), CFrame.new(0, -h * 0.22, 0), darken(color, 0.8), mat, "Lower")
	lower.Reflectance = reflect
	local upper = part(model, Vector3.new(w * 0.98, h * 0.5, d * 0.98), CFrame.new(0, h * 0.25, -0.01 * s) * CFrame.Angles(math.rad(2.5), 0, 0), color, mat, "Upper")
	upper.Reflectance = reflect
	local strip = part(model, Vector3.new(w * 0.3, h * 1.06, d * 1.01), CFrame.new(0, 0, 0), lighten(color, 0.08), Enum.Material.Glass, "GlossStrip")
	strip.Reflectance = 0.35
	strip.Transparency = 0.1
	local led = part(model, Vector3.new(w * 0.5, 0.015 * s, 0.01 * s), CFrame.new(0, 0, -d / 2 - 0.005 * s), accent, Enum.Material.Neon, "LED")
	led.CastShadow = false
	part(model, Vector3.new(w * 0.86, 0.008 * s, d * 0.5), CFrame.new(0, h / 2 + 0.004 * s, d * 0.2), DARK, Enum.Material.DiamondPlate, "TopVent")
	-- disc slot + usb
	part(model, Vector3.new(0.4 * s, 0.01 * s, 0.01 * s), CFrame.new(-w * 0.2, -h * 0.05, -d / 2 - 0.005 * s), DARK, Enum.Material.SmoothPlastic, "DiscSlot")
	part(model, Vector3.new(0.06 * s, 0.02 * s, 0.01 * s), CFrame.new(w * 0.3, -h * 0.1, -d / 2 - 0.005 * s), DARK, Enum.Material.SmoothPlastic, "Usb")
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			part(model, Vector3.new(0.12 * s, 0.03 * s, 0.12 * s), CFrame.new(sx * w * 0.4, -h / 2 - 0.015 * s, sz * d * 0.4), Color3.fromRGB(20, 20, 22), Enum.Material.Rubber, "Foot")
		end
	end
	model.PrimaryPart = lower
end

-- ---------------------------------------------------------------------------------------------------- Wearables
local function arcSegments(model: Model, name: string, segments: number, radius: number, thickness: number, width: number, startDeg: number, endDeg: number, cf: CFrame, color: Color3, mat: Enum.Material)
	local step = (endDeg - startDeg) / segments
	local chord = math.abs(2 * radius * math.sin(math.rad(step) / 2)) * 1.08
	for i = 1, segments do
		local a = math.rad(startDeg + step * (i - 0.5))
		local seg = part(model, Vector3.new(width, thickness, chord), cf * CFrame.Angles(a, 0, 0) * CFrame.new(0, radius, 0), color, mat, name)
		seg.CastShadow = true
	end
end

local function wearable(model: Model, params: DeviceParams, s: number)
	local color, mat, reflect = bodyLook(params)
	local accent = params.accent or Color3.fromRGB(80, 160, 255)
	if params.subtype == "Smartwatch" then
		local w, h, d = 0.5 * s, 0.6 * s, 0.14 * s
		local case = roundedSlab(model, w, h, d, 0.12 * s, CFrame.new(), color, mat, "Case")
		case.Reflectance = reflect
		part(model, Vector3.new(w * 0.9, h * 0.9, 0.006 * s), CFrame.new(0, 0, -d / 2 - 0.003 * s), DARK, Enum.Material.SmoothPlastic, "Bezel")
		screenPart(model, Vector3.new(w * 0.84, h * 0.84, 0.006 * s), CFrame.new(0, 0, -d / 2 - 0.009 * s), params.screenOn ~= false, params.screenColor)
		cylinder(model, "X", 0.05 * s, 0.1 * s, CFrame.new(w / 2 + 0.02 * s, 0.1 * s, 0), lighten(color, 0.15), Enum.Material.Metal, "Crown")
		part(model, Vector3.new(0.04 * s, 0.14 * s, 0.05 * s), CFrame.new(w / 2 + 0.015 * s, -0.12 * s, 0), lighten(color, 0.1), Enum.Material.Metal, "SideButton")
		-- curved straps: 6 segments each, bending away from the viewer
		local strapColor = Color3.fromRGB(40, 42, 48)
		arcSegments(model, "StrapTop", 6, 0.9 * s, 0.05 * s, w * 0.75, 0, 70, CFrame.new(0, h / 2 - 0.9 * s, 0.02 * s) * CFrame.Angles(0, 0, 0), strapColor, Enum.Material.Fabric)
		arcSegments(model, "StrapBottom", 6, 0.9 * s, 0.05 * s, w * 0.75, 180, 110, CFrame.new(0, -h / 2 + 0.9 * s, 0.02 * s), strapColor, Enum.Material.Fabric)
		model.PrimaryPart = case
	elseif params.subtype == "WirelessHeadphones" then
		local bandColor = darken(color, 0.9)
		-- headband arc (7 segments) over the top, cups at both ends
		arcSegments(model, "Band", 7, 0.7 * s, 0.1 * s, 0.22 * s, -80, 80, CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, math.rad(90)), bandColor, mat)
		local band = model:FindFirstChild("Band") :: Part
		for _, sx in ipairs({ -1, 1 }) do
			local cupCf = CFrame.new(sx * 0.7 * s, 0, 0)
			local cup = cylinder(model, "X", 0.28 * s, 0.6 * s, cupCf, color, mat, "Cup")
			cup.Reflectance = reflect
			cylinder(model, "X", 0.1 * s, 0.58 * s, cupCf * CFrame.new(-sx * 0.18 * s, 0, 0), Color3.fromRGB(36, 36, 40), Enum.Material.Fabric, "Cushion")
			brandMark(model, cupCf * CFrame.new(sx * 0.145 * s, 0, 0) * CFrame.Angles(0, math.rad(90), 0), s, params)
			part(model, Vector3.new(0.08 * s, 0.4 * s, 0.1 * s), cupCf * CFrame.new(0, 0.4 * s, 0), Color3.fromRGB(70, 70, 76), Enum.Material.Metal, "Yoke")
		end
		part(model, Vector3.new(1.0 * s, 0.08 * s, 0.26 * s), CFrame.new(0, 0.66 * s, 0), Color3.fromRGB(36, 36, 40), Enum.Material.Fabric, "BandCushion")
		model.PrimaryPart = band
	elseif params.subtype == "VRHeadset" then
		local body = part(model, Vector3.new(1.3 * s, 0.7 * s, 0.6 * s), CFrame.new(), color, mat, "Body")
		body.Reflectance = reflect
		local visor = roundedSlab(model, 1.24 * s, 0.6 * s, 0.05 * s, 0.15 * s, CFrame.new(0, 0, -0.32 * s), Color3.fromRGB(10, 10, 16), Enum.Material.Glass, "Visor")
		visor.Reflectance = 0.45
		for _, sx in ipairs({ -1, 1 }) do
			local cam = cylinder(model, "Z", 0.02 * s, 0.1 * s, CFrame.new(sx * 0.45 * s, -0.15 * s, -0.35 * s), Color3.fromRGB(8, 10, 24), Enum.Material.Glass, "TrackingCam")
			cam.Reflectance = 0.5
		end
		part(model, Vector3.new(1.2 * s, 0.62 * s, 0.12 * s), CFrame.new(0, 0, 0.36 * s), Color3.fromRGB(36, 36, 40), Enum.Material.Fabric, "FaceGasket")
		arcSegments(model, "Strap", 7, 0.75 * s, 0.06 * s, 0.3 * s, 10, 170, CFrame.new(0, 0.05 * s, 0.3 * s) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(40, 40, 44), Enum.Material.Fabric)
		part(model, Vector3.new(0.3 * s, 0.1 * s, 0.9 * s), CFrame.new(0, 0.42 * s, 0.6 * s), Color3.fromRGB(40, 40, 44), Enum.Material.Fabric, "TopStrap")
		brandMark(model, CFrame.new(0, 0.2 * s, -0.355 * s), s, params)
		model.PrimaryPart = body
	elseif params.subtype == "SmartGlasses" then
		local frame = part(model, Vector3.new(1.3 * s, 0.06 * s, 0.05 * s), CFrame.new(0, 0.16 * s, 0), color, mat, "Frame")
		frame.Reflectance = reflect
		part(model, Vector3.new(0.12 * s, 0.04 * s, 0.05 * s), CFrame.new(0, 0.08 * s, 0), color, mat, "Bridge")
		for _, sx in ipairs({ -1, 1 }) do
			local lensCf = CFrame.new(sx * 0.33 * s, 0, 0)
			local rim = roundedSlab(model, 0.56 * s, 0.36 * s, 0.03 * s, 0.1 * s, lensCf, darken(color, 0.8), mat, "Rim")
			local _ = rim
			local lens = roundedSlab(model, 0.5 * s, 0.3 * s, 0.015 * s, 0.09 * s, lensCf * CFrame.new(0, 0, -0.004 * s), Color3.fromRGB(60, 80, 110), Enum.Material.Glass, "Lens")
			lens.Transparency = 0.45
			lens.Reflectance = 0.3
			part(model, Vector3.new(0.04 * s, 0.06 * s, 1.1 * s), CFrame.new(sx * 0.63 * s, 0.1 * s, 0.55 * s), color, mat, "Temple")
			part(model, Vector3.new(0.05 * s, 0.07 * s, 0.25 * s), CFrame.new(sx * 0.63 * s, 0.1 * s, 0.2 * s), darken(color, 0.7), Enum.Material.SmoothPlastic, "TempleModule")
		end
		local cam = cylinder(model, "Z", 0.015 * s, 0.05 * s, CFrame.new(-0.6 * s, 0.16 * s, -0.03 * s), Color3.fromRGB(8, 10, 24), Enum.Material.Glass, "Camera")
		cam.Reflectance = 0.5
		model.PrimaryPart = frame
	else -- SmartHome speaker
		local body = cylinder(model, "Y", 0.95 * s, 0.8 * s, CFrame.new(), color, mat, "Body")
		body.Reflectance = reflect
		cylinder(model, "Y", 0.6 * s, 0.82 * s, CFrame.new(0, -0.05 * s, 0), Color3.fromRGB(60, 62, 70), Enum.Material.Fabric, "FabricBand")
		cylinder(model, "Y", 0.02 * s, 0.84 * s, CFrame.new(0, 0.49 * s, 0), DARK, Enum.Material.SmoothPlastic, "TopPlate")
		local ring = cylinder(model, "Y", 0.015 * s, 0.7 * s, CFrame.new(0, 0.5 * s, 0), accent, Enum.Material.Neon, "Ring")
		ring.CastShadow = false
		cylinder(model, "Y", 0.02 * s, 0.6 * s, CFrame.new(0, 0.505 * s, 0), DARK, Enum.Material.SmoothPlastic, "RingInner")
		cylinder(model, "Y", 0.03 * s, 0.7 * s, CFrame.new(0, -0.49 * s, 0), Color3.fromRGB(20, 20, 22), Enum.Material.Rubber, "Foot")
		brandMark(model, CFrame.new(0, 0.3 * s, -0.4 * s), s, params)
		model.PrimaryPart = body
	end
end

-- ---------------------------------------------------------------------------------------------------- API
function DeviceModelBuilder.build(params: DeviceParams): Model
	local model = Instance.new("Model")
	model.Name = params.name or (params.subtype or "Device")
	local s = params.scale or 1
	if params.category == "Smartphone" then
		phone(model, params, s)
	elseif params.category == "Laptop" then
		laptop(model, params, s)
	elseif params.category == "PC" then
		tower(model, params, s)
	elseif params.category == "Console" then
		console(model, params, s)
	else
		wearable(model, params, s)
	end
	if not model.PrimaryPart then
		model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart")
	end
	-- every category gets internals (phones build theirs inside phoneHalf)
	local hasInternal = false
	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") and p:GetAttribute("Internal") then
			hasInternal = true
			break
		end
	end
	if not hasInternal and model.PrimaryPart then
		local ext = DeviceModelBuilder.extents(params)
		local pp = model.PrimaryPart :: BasePart
		local cf = pp.CFrame
		if params.category == "Laptop" then
			cf = cf * CFrame.Angles(math.rad(-90), 0, 0) * CFrame.new(0, 0, 0)
			internals(model, params, s, cf, ext.X * 0.8, ext.Z * 0.8, 0.08 * s)
		elseif params.category == "PC" then
			cf = cf * CFrame.Angles(0, math.rad(90), 0)
			internals(model, params, s, cf, ext.Z * 0.6, ext.Y * 0.6, ext.X * 0.6)
		else
			internals(model, params, s, cf, ext.X * 0.6, ext.Y * 0.6, math.max(ext.Z * 0.5, 0.08 * s))
		end
		local marked = 0
		for _, p in ipairs(model:GetChildren()) do
			if p:IsA("BasePart") and not p:GetAttribute("Internal") and (p.Name == "Base" or p.Name == "Case" or p.Name == "Body" or p.Name == "Lid" or p.Name == "Screen" or p.Name == "Band" or p.Name == "Cup" or string.find(p.Name, "Frame") or string.find(p.Name, "Back") or string.find(p.Name, "Body")) then
				markShell(p :: Part)
				marked = marked + 1
			end
		end
		if marked == 0 then
			markShell(pp :: Part)
		end
	end
	-- display tech on every screen: newer generations get better anti-glare, brighter panels glow lighter
	if params.displayGen or params.displayNits then
		for _, p in ipairs(model:GetDescendants()) do
			local isDisplay = p.Name == "Screen" or p.Name == "Visor" or (params.subtype == "SmartGlasses" and p.Name == "Lens")
			if p:IsA("BasePart") and isDisplay then
				p.Reflectance = math.clamp(0.2 - 0.025 * (params.displayGen or 1), 0.02, 0.2)
				if params.displayNits and params.screenOn ~= false then
					p.Color = lighten(p.Color, math.clamp(((params.displayNits or 250) - 200) / 4000, 0, 0.3))
				end
			end
		end
	end
	return model
end

-- "Inside" view: normal | xray (shell transparent, internals visible) | exploded (internals slide apart along the device normal)
function DeviceModelBuilder.setInsideMode(model: Model, mode: string)
	local TweenService = game:GetService("TweenService")
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			if p:GetAttribute("Internal") then
				p.Transparency = mode == "normal" and 1 or 0
				local home = p:GetAttribute("HomePos")
				local dir = p:GetAttribute("ExplodeDir")
				local off = p:GetAttribute("ExplodeOffset")
				if typeof(home) == "Vector3" and typeof(dir) == "Vector3" and type(off) == "number" then
					local target = mode == "exploded" and (home + dir * off) or home
					local rot = p.CFrame - p.CFrame.Position
					local goal = rot + target
					if mode == "exploded" then
						pcall(function()
							TweenService:Create(p, TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { CFrame = goal }):Play()
						end)
					else
						p.CFrame = goal
					end
				end
				local label = p:FindFirstChild("InsideLabel")
				if mode ~= "normal" then
					if not label then
						local gui = Instance.new("BillboardGui")
						gui.Name = "InsideLabel"
						gui.Size = UDim2.new(0, 140, 0, 28)
						gui.StudsOffset = Vector3.new(0, 0.25, 0)
						gui.AlwaysOnTop = true
						gui.LightInfluence = 0
						local text = Instance.new("TextLabel")
						text.Size = UDim2.fromScale(1, 1)
						text.BackgroundColor3 = Color3.fromRGB(10, 12, 20)
						text.BackgroundTransparency = 0.25
						text.TextColor3 = Color3.new(1, 1, 1)
						text.TextScaled = true
						text.Font = Enum.Font.GothamMedium
						text.Text = DeviceModelBuilder.labelText(tostring(p:GetAttribute("Label") or p.Name))
						text.Parent = gui
						gui.Parent = p
						label = gui
					end
					local gui = label :: BillboardGui
					gui.Enabled = true
				elseif label then
					local gui = label :: BillboardGui
					gui.Enabled = false
				end
			elseif p:GetAttribute("Shell") then
				local base = p:GetAttribute("BaseTransparency")
				if mode == "xray" then
					p.Transparency = 0.75
				elseif mode == "exploded" then
					p.Transparency = 0.6
				else
					p.Transparency = type(base) == "number" and base or 0
				end
			end
		end
	end
end

-- Approximate bounding size (studs) for camera framing; does not require building the model.
function DeviceModelBuilder.extents(params: DeviceParams): Vector3
	local s = params.scale or 1
	if params.category == "Smartphone" then
		local k = (params.screenInch or 6.4) / 6.4
		if params.foldable then
			return Vector3.new(1.45 * s * k, 1.5 * s * k, 0.3 * s)
		end
		return Vector3.new(0.76 * s * k, 1.52 * s * k, 0.16 * s)
	elseif params.category == "Laptop" then
		local k = (params.screenInch or 14) / 14
		return Vector3.new(2.2 * s * k, 1.55 * s * k, 1.9 * s * k)
	elseif params.category == "PC" then
		if params.subtype == "OfficePC" or params.hasGPU == false then
			return Vector3.new(0.72 * s, 1.55 * s, 1.65 * s)
		end
		return Vector3.new(1.05 * s, 2.15 * s, 2.25 * s)
	elseif params.category == "Console" then
		if params.subtype == "HandheldConsole" then
			return Vector3.new(2.1 * s, 0.85 * s, 0.35 * s)
		end
		return Vector3.new(1.5 * s, 0.36 * s, 1.52 * s)
	end
	local sub = params.subtype
	if sub == "Smartwatch" then
		return Vector3.new(0.52 * s, 1.5 * s, 0.9 * s)
	elseif sub == "WirelessHeadphones" then
		return Vector3.new(1.7 * s, 1.45 * s, 0.62 * s)
	elseif sub == "VRHeadset" then
		return Vector3.new(1.32 * s, 0.9 * s, 1.7 * s)
	elseif sub == "SmartGlasses" then
		return Vector3.new(1.32 * s, 0.4 * s, 1.15 * s)
	end
	return Vector3.new(0.84 * s, 1.0 * s, 0.84 * s)
end

local chargerKindOf = function(charger: any): string
	if not charger then
		return "usbc"
	end
	if charger.wireless and (charger.wattage or 0) >= 120 then
		return "none"
	end
	local w = charger.wattage or 10
	if w <= 10 then
		return "mini"
	elseif w <= 25 then
		return "micro"
	end
	return "usbc"
end

local function hexColor(hex: any): Color3?
	if type(hex) ~= "string" or not string.find(hex, "^#%x%x%x%x%x%x$") then
		return nil
	end
	local ok, c = pcall(Color3.fromHex, hex)
	if ok then
		return c
	end
	return nil
end

-- Derives DeviceParams from a blueprint + resolved components (works with catalog tables).
-- `brand` (optional): { initial, name, colorA, colorB } for logo/wallpaper defaults; `finishes` (optional) the Finishes data module.
function DeviceModelBuilder.paramsFromBlueprint(blueprint: any, resolve: (string) -> any, scale: number?, accent: Color3?, brand: any?): DeviceParams
	local slots = blueprint.slots or {}
	local opt = blueprint.options or {}
	local chassis = slots.Chassis and resolve(slots.Chassis)
	local display = slots.Display and resolve(slots.Display)
	local camera = slots.Camera and resolve(slots.Camera)
	local case = slots.Case and resolve(slots.Case)
	local charger = slots.Charger and resolve(slots.Charger)
	local battery = slots.Battery and resolve(slots.Battery)
	local chip = (slots.SoC and resolve(slots.SoC)) or (slots.CPU and resolve(slots.CPU))
	local ram = slots.RAM and resolve(slots.RAM)
	local storage = slots.Storage and resolve(slots.Storage)
	local cooling = slots.Cooling and resolve(slots.Cooling)
	local sensors = slots.Sensors and resolve(slots.Sensors)
	local os = slots.OS and resolve(slots.OS)
	local params: DeviceParams = {
		category = blueprint.category, subtype = blueprint.subtype, colorway = opt.colorway or "graphite",
		material = chassis and chassis.material or (case and case.material) or "aluminum", screenInch = display and display.sizeInch or nil,
		lenses = camera and camera.lenses or 2, foldable = display and display.foldable or false, glassBack = chassis ~= nil and chassis.material == "glass",
		name = blueprint.name, scale = scale or 1, screenOn = true, hasGPU = slots.GPU ~= nil, caseAirflow = case and case.airflow or 0.6, accent = accent,
		cameraLayout = opt.cameraLayout, bumpShape = opt.bumpShape, selfiePosition = opt.selfiePosition, cornerRadius = opt.cornerRadius, bezelInch = opt.bezelInch,
		buttonSide = opt.buttonSide, buttonHeight = opt.buttonHeight, portOffset = opt.portOffset, bodyColor = hexColor(opt.bodyColorHex), finish = opt.finish,
		logoStyle = opt.logoStyle, screenHome = true,
		displayPanel = display and display.panel or nil, refreshHz = display and display.refreshHz or nil, cameraMP = camera and camera.mainMP or nil, ois = camera and camera.ois or false,
		chargerKind = chargerKindOf(charger), wireless = charger and charger.wireless or false, batteryWh = battery and battery.capacityWh or nil, batteryChem = battery and battery.chemistry or nil,
		batteryName = battery and battery.name or nil, chipArea = chip and chip.dieAreaMm2 or nil, chipName = chip and chip.name or nil, chipGen = chip and chip.generation or nil,
		ramGB = ram and ram.capacityGB or nil, ramName = ram and ram.name or nil, storageGB = storage and storage.capacityGB or nil, storageName = storage and storage.name or nil,
		coolingMethod = cooling and cooling.method or nil, coolingName = cooling and cooling.name or nil, sensorCount = sensors and sensors.healthSensors or nil,
		osOwn = os ~= nil and os.manufacturer == "SELF", osName = os and os.name or nil,
	}
	local gpu = slots.GPU and resolve(slots.GPU)
	if gpu then
		params.gpuName = gpu.name
		params.gpuVramGB = gpu.vramGB
		params.gpuTdpW = gpu.tdpW
	end
	local mobo = slots.Motherboard and resolve(slots.Motherboard)
	if mobo then
		params.moboName = mobo.name
		params.moboFormFactor = mobo.formFactor
	end
	local psu = slots.PSU and resolve(slots.PSU)
	if psu then
		params.psuName = psu.name
		params.psuW = psu.wattage
	end
	local storage2 = slots.Storage2 and resolve(slots.Storage2)
	if storage2 then
		params.storage2Name = storage2.name
		params.storage2GB = storage2.capacityGB
		params.storage2Gen = storage2.generation
	end
	params.storageGen = storage and storage.generation or nil
	params.cameraSensorInch = camera and camera.sensorSizeInch or nil
	params.cameraGen = camera and camera.generation or nil
	params.displayGen = display and display.generation or nil
	params.displayNits = display and display.nits or nil
	params.chargerW = charger and charger.wattage or nil
	params.sensorName = sensors and sensors.name or nil
	params.caseForm = case and case.formFactor or nil
	params.caseDesign = case and case.designScore or nil
	if brand then
		params.companyInitial = brand.initial
		params.companyName = brand.name
	end
	-- accent / light colours from the Finishes palette names
	local okF, Finishes = pcall(function()
		return require(script.Parent.Parent.Data.Finishes)
	end)
	if okF and Finishes then
		local a = opt.accentColor and Finishes.accentById[opt.accentColor]
		if a and a.hex then
			params.accentColor = hexColor(a.hex)
		end
		local l = opt.lightColor and Finishes.lightById[opt.lightColor]
		if l and l.hex then
			params.lightColor = hexColor(l.hex)
		end
		local wp = opt.wallpaper and Finishes.wallpaperById[opt.wallpaper]
		if wp and wp.a then
			local ca, cb = hexColor(wp.a), hexColor(wp.b)
			if ca and cb then
				params.wallpaper = { a = ca, b = cb }
			end
		end
	end
	return params
end

return DeviceModelBuilder
