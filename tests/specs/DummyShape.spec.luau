-- Mannequin : blocs de repli sans gabarits, MeshPart clonées avec gabarits, déclinaisons (couleur, pièces ajoutées,
-- couleurs par pièce, pièces masquées, effets, animation des pièces ajoutées).
return function(T, Loader)
	local roblox = require("@lune/roblox")

	-- Cette méthode permet de simuler ReplicatedStorage lorsqu'un test choisit d'avoir ou non des gabarits.
	local function storage(folder)
		return {
			FindFirstChild = function(_, name)
				return if folder and name == folder.Name then folder else nil
			end,
		}
	end

	-- Cette méthode permet de créer un dossier de gabarits maillés prêt (une MeshPart avec atlas par pièce et par
	-- accessoire) lorsqu'un test simule des assets publiés.
	local function templates(DummyShape)
		local folder = roblox.Instance.new("Folder")
		folder.Name = DummyShape.TEMPLATES
		for _, piece in DummyShape.PIECES do
			local part = roblox.Instance.new("MeshPart")
			part.Name = piece.name
			local surface = roblox.Instance.new("SurfaceAppearance")
			surface.Name = DummyShape.SURFACE
			surface.Parent = part
			part.Parent = folder
		end
		for name in DummyShape.ACCESSORIES do
			local part = roblox.Instance.new("MeshPart")
			part.Name = name
			part.Parent = folder
		end
		folder:SetAttribute("Ready", true)
		return folder
	end

	-- Cette méthode permet de charger DummyShape avec ou sans gabarits lorsqu'un groupe de tests démarre.
	local function load(folderFactory)
		local holder = {}
		local shared = Loader.new().game:GetService("ReplicatedStorage").Shared
		local loader = Loader.new({
			ReplicatedStorage = {
				FindFirstChild = function(_, name)
					return holder.storage:FindFirstChild(name)
				end,
				WaitForChild = function(_, name)
					assert(name == "Shared", name)
					return shared
				end,
			},
		})
		local DummyShape = loader:require("src/shared/DummyShape")
		holder.storage = storage(folderFactory and folderFactory(DummyShape))
		return DummyShape
	end

	T.describe("DummyShape.buildVisual sans gabarits", function()
		local DummyShape = load(nil)
		T.it("garde les pièces remplacées (pas de queue de fantôme sans maillages)", function()
			local model = DummyShape.buildVisual(1, { hidden = { "LeftUpperLeg" } })
			T.expectEqual(model.LeftUpperLeg.Transparency, 0)
		end)
		T.it("teint aussi une pièce sombre qui a sa couleur propre", function()
			local red = Color3.new(1, 0, 0)
			local model = DummyShape.buildVisual(1, { pieceColors = { LeftLowerArm = red } })
			T.expectEqual(model.LeftLowerArm.Color, red)
			T.expectEqual(model.RightLowerArm.Color, DummyShape.DARK)
		end)
		T.it("construit 10 blocs soudés au torse, cibles peintes", function()
			local model = DummyShape.buildVisual(1)
			local parts = 0
			for _, child in model:GetChildren() do
				if child:IsA("BasePart") then
					parts += 1
					T.expectEqual(child.ClassName, "Part")
					if child ~= model.PrimaryPart then
						T.expect(child:FindFirstChildOfClass("WeldConstraint") ~= nil, child.Name .. " soudé")
					end
				end
			end
			T.expectEqual(parts, 10)
			T.expectEqual(model.PrimaryPart.Name, "Torso")
			T.expect(model.PrimaryPart:FindFirstChildOfClass("SurfaceGui") ~= nil, "cible du torse")
		end)
		T.it("ignore les accessoires faute de maillage", function()
			local model = DummyShape.buildVisual(1, { accessories = { "rookie_Helmet" } })
			T.expectEqual(model:FindFirstChild("rookie_Helmet"), nil)
		end)
		T.it("ne teinte que les zones jaunes", function()
			local red = Color3.new(1, 0, 0)
			local model = DummyShape.buildVisual(1, { color = red })
			T.expectEqual(model.Torso.Color, red)
			T.expectEqual(model.LeftLowerArm.Color, DummyShape.DARK)
		end)
	end)

	T.describe("DummyShape.buildVisual avec gabarits maillés", function()
		local DummyShape = load(templates)
		T.it("teinte chaque pièce ajoutée et impose leur matériau (variantes générées, #94)", function()
			local pink = Color3.fromRGB(255, 80, 160)
			local model = DummyShape.buildVisual(1, {
				accessories = { "rookie_Helmet", "rookie_FloatyL" },
				accessoryColors = { rookie_Helmet = pink },
				accessoryMaterial = roblox.Enum.Material.Foil,
			})
			T.expectEqual(model.rookie_Helmet.Color, pink)
			T.expectEqual(model.rookie_FloatyL.Color, DummyShape.ACCESSORIES.rookie_FloatyL.color)
			T.expectEqual(model.rookie_Helmet.Material, roblox.Enum.Material.Foil)
			T.expectEqual(model.rookie_FloatyL.Material, roblox.Enum.Material.Foil)
			local visor = DummyShape.buildVisual(1, {
				accessories = { "biker_Visor" },
				accessoryMaterial = roblox.Enum.Material.Neon,
			})
			T.expectEqual(visor.biker_Visor.Material, roblox.Enum.Material.Glass, "une vitre reste en verre")
		end)
		T.it("clone les MeshPart à la taille du gabarit et à l'échelle", function()
			local model = DummyShape.buildVisual(0.5)
			T.expectEqual(model.Torso.ClassName, "MeshPart")
			T.expectNear(model.Torso.Size.Y, 1.2, 1e-5)
			T.expectNear(model.Head.CFrame.Position.Y, 1.05, 1e-5)
			T.expectEqual(model.PrimaryPart:FindFirstChildOfClass("SurfaceGui"), nil)
		end)
		T.it("teinte tout le corps (le noir est dans la texture)", function()
			local blue = Color3.new(0, 0, 1)
			local model = DummyShape.buildVisual(1, { color = blue })
			T.expectEqual(model.LeftLowerArm.Color, blue)
			T.expectEqual(DummyShape.buildVisual(1).LeftLowerArm.Color, DummyShape.YELLOW)
		end)
		T.it("garde l'atlas sans matériau de déclinaison", function()
			local model = DummyShape.buildVisual(1, { color = Color3.new(0, 0, 1) })
			T.expect(model.Torso:FindFirstChild(DummyShape.SURFACE) ~= nil, "atlas du torse")
			T.expectEqual(model.Torso.Material, roblox.Enum.Material.SmoothPlastic)
		end)
		T.it("retire l'atlas pour un matériau de déclinaison", function()
			local red = Color3.new(1, 0, 0)
			local model = DummyShape.buildVisual(1, { color = red, material = roblox.Enum.Material.Neon })
			T.expectEqual(model.Torso:FindFirstChild(DummyShape.SURFACE), nil)
			T.expectEqual(model.Torso.Material, roblox.Enum.Material.Neon)
			T.expectEqual(model.Torso.Color, red)
			T.expectEqual(model.LeftLowerArm.Color, DummyShape.DARK, "pièces sombres gardées sans atlas")
		end)
		T.it(
			"pose les pièces ajoutées sur leur pièce, sans masse ni collision, couleur et matériau du modèle",
			function()
				local def = DummyShape.ACCESSORIES.rookie_Helmet
				local model = DummyShape.buildVisual(1, { accessories = { "rookie_Helmet", "biker_Visor" } })
				local helmet = model:FindFirstChild("rookie_Helmet")
				T.expect(helmet ~= nil, "casque")
				T.expectEqual(helmet:GetAttribute("Accessory"), true)
				T.expectEqual(helmet.CanCollide, false)
				T.expectEqual(helmet.Massless, true)
				T.expectEqual(helmet.Color, def.color)
				local expected = model.Head.CFrame.Position + def.offset
				T.expectNear((helmet.CFrame.Position - expected).Magnitude, 0, 1e-5, "position du casque")
				T.expectNear((helmet.Size - def.size).Magnitude, 0, 1e-5, "taille du casque")
				local visor = model:FindFirstChild("biker_Visor")
				T.expectEqual(visor.Material, roblox.Enum.Material.Glass)
				T.expect(visor.Transparency > 0, "visière transparente")
				T.expect(helmet:FindFirstChildOfClass("WeldConstraint") ~= nil, "soudure fixe")
			end
		)
		T.it("impose la couleur de la silhouette aux pièces ajoutées", function()
			local black = Color3.new(0, 0, 0)
			local model = DummyShape.buildVisual(1, { accessories = { "rookie_Helmet" }, accessoryColor = black })
			T.expectEqual(model.rookie_Helmet.Color, black)
		end)
		T.it("étiquette les pièces animées, soudées par un Weld à leur position de repos", function()
			local model = DummyShape.buildVisual(2, { accessories = { "gold_CoinRing" } })
			local ring = model.gold_CoinRing
			T.expect(ring:HasTag(DummyShape.FX_TAG), "étiquette")
			local weld = ring:FindFirstChild(DummyShape.FX_WELD)
			T.expectEqual(weld.ClassName, "Weld")
			T.expectEqual(weld.Part0, model.Torso)
			T.expectEqual(ring:FindFirstChildOfClass("WeldConstraint"), nil)
			local base = ring:GetAttribute("FxBase")
			T.expectNear((base.Position - DummyShape.ACCESSORIES.gold_CoinRing.offset * 2).Magnitude, 0, 1e-5)
			T.expectNear(ring:GetAttribute("FxSpin").Magnitude, DummyShape.ACCESSORIES.gold_CoinRing.spin.speed, 1e-4)
		end)
		T.it("flotte d'une amplitude à l'échelle de construction", function()
			local def = DummyShape.ACCESSORIES.ghost_LanternFlame
			local model = DummyShape.buildVisual(2, { accessories = { "ghost_LanternFlame" } })
			local bob = model.ghost_LanternFlame:GetAttribute("FxBob")
			T.expectNear(bob.X, def.bob.amplitude * 2, 1e-5)
			T.expectNear(bob.Y, def.bob.period, 1e-5)
		end)
		T.it("teinte chaque pièce de sa couleur propre et masque les pièces remplacées", function()
			local red, blue = Color3.new(1, 0, 0), Color3.new(0, 0, 1)
			local model = DummyShape.buildVisual(1, {
				color = red,
				pieceColors = { LeftUpperLeg = blue },
				hidden = { "RightLowerLeg" },
			})
			T.expectEqual(model.LeftUpperLeg.Color, blue)
			T.expectEqual(model.Torso.Color, red)
			T.expectEqual(model.RightLowerLeg.Transparency, 1)
			T.expectEqual(model.Torso.Transparency, 0)
		end)
		T.it("pose les effets (particules, lumière) sur des attachements à l'échelle", function()
			local effects = {
				{
					kind = "particles",
					preset = "sparkle",
					piece = "Torso",
					offset = Vector3.new(0, 1, 0),
					color = Color3.new(1, 1, 0),
				},
				{
					kind = "light",
					piece = "Head",
					offset = Vector3.new(0, 1, 0),
					color = Color3.new(1, 0, 0),
					range = 10,
					brightness = 2,
				},
				{
					kind = "particles",
					preset = "inconnu",
					piece = "Torso",
					offset = Vector3.zero,
					color = Color3.new(),
				},
			}
			local model = DummyShape.buildVisual(2, { effects = effects })
			local attachment = model.Torso:FindFirstChild("Fx1")
			T.expectNear(attachment.Position.Y, 2, 1e-5)
			T.expect(attachment:FindFirstChildOfClass("ParticleEmitter") ~= nil, "émetteur")
			local light = model.Head.Fx2:FindFirstChildOfClass("PointLight")
			T.expectNear(light.Range, 20, 1e-5)
			T.expectEqual(model.Torso.Fx3:FindFirstChildOfClass("ParticleEmitter"), nil, "préréglage inconnu ignoré")
		end)
	end)

	T.describe("DummyShape.fxOffset", function()
		local DummyShape = load(nil)
		local base = CFrame.new(1, 2, 3)
		T.it("donne la position de repos à t = 0, à l'échelle", function()
			local offset = DummyShape.fxOffset(base, 2, 0, Vector3.new(0, 90, 0), roblox.Vector2.new(0.5, 2))
			T.expectNear((offset.Position - Vector3.new(2, 4, 6)).Magnitude, 0, 1e-5)
		end)
		T.it("tourne sur place de speed degrés par seconde", function()
			local offset = DummyShape.fxOffset(base, 1, 1, Vector3.new(0, 90, 0), nil)
			T.expectNear((offset.Position - base.Position).Magnitude, 0, 1e-5, "centre fixe")
			T.expectNear(offset.LookVector.X, -1, 1e-5, "quart de tour")
		end)
		T.it("flotte de l'amplitude à l'échelle au quart de période", function()
			local offset = DummyShape.fxOffset(base, 2, 0.5, nil, roblox.Vector2.new(0.25, 2))
			T.expectNear(offset.Position.Y, 4.5, 1e-5)
		end)
	end)

	T.describe("Shared.DummyModels", function()
		local DummyShape = load(nil)
		local Collection = Loader.new():require("src/shared/Collection")
		local Assets = Loader.new():require("src/shared/Assets")
		local Models = Loader.new():require("src/shared/DummyModels")
		T.it("donne un modèle à chaque mannequin, aux pièces ajoutées connues", function()
			for _, dummy in Collection.DUMMIES do
				local look = Collection.look(dummy.id)
				T.expect(look ~= nil, "modèle de " .. dummy.id)
				for _, name in look.accessories do
					local def = Models.ADDONS[name]
					T.expect(def ~= nil, name)
					T.expect(
						table.find({ "Torso", "Head" }, def.piece) ~= nil
							or string.find(def.piece, "Arm")
							or string.find(def.piece, "Leg"),
						def.piece
					)
				end
				for _, effect in look.effects or {} do
					T.expect(effect.kind == "light" or DummyShape.PARTICLES[effect.preset] ~= nil, dummy.id .. " effet")
				end
			end
		end)
		T.it("a un maillage publié pour chaque pièce ajoutée", function()
			for name in Models.ADDONS do
				local id = Assets.DUMMY_MESHES[name]
				T.expect(type(id) == "number" and id > 0, name .. " publié")
			end
		end)
		T.it(
			"a une icône publiée pour chaque mannequin dessiné (barre d'outils ; les générés : celle de leur rareté)",
			function()
				for _, dummy in Collection.DRAWN do
					local id = Assets.DUMMY_ICONS[dummy.id]
					T.expect(type(id) == "number" and id > 0, dummy.id .. " a son icône")
				end
			end
		)
		T.it("monte en spectacle avec la rareté (pièces ajoutées, effets dès Uncommon, taille)", function()
			local byRarity = {}
			for _, dummy in Collection.DUMMIES do
				local look = Collection.look(dummy.id)
				local variant = Collection.variant({ id = dummy.id, size = 1 })
				local stats = byRarity[dummy.rarity] or { parts = 0, effects = 0, count = 0, animated = 0 }
				stats.parts += #look.accessories
				stats.effects += #(variant.effects or {})
				stats.count += 1
				for _, name in look.accessories do
					if Models.ADDONS[name].spin or Models.ADDONS[name].bob then
						stats.animated += 1
					end
				end
				if dummy.rarity >= 2 then
					T.expect(variant.effects and #variant.effects > 0, dummy.id .. " a des effets")
				end
				for _, effect in variant.effects or {} do
					T.expect(
						effect.kind == "light" or effect.kind == "beam" or DummyShape.PARTICLES[effect.preset] ~= nil,
						dummy.id .. " effet " .. tostring(effect.preset)
					)
				end
				byRarity[dummy.rarity] = stats
			end
			for rarity = 2, 7 do
				local now, before = byRarity[rarity], byRarity[rarity - 1]
				T.expect(
					(now.parts + now.effects) / now.count >= (before.parts + before.effects) / before.count,
					"pièces et effets, rareté " .. rarity
				)
				T.expect(now.effects / now.count > before.effects / before.count, "effets, rareté " .. rarity)
				T.expect(
					Collection.RARITY_SCALE[rarity] > Collection.RARITY_SCALE[rarity - 1],
					"taille, rareté " .. rarity
				)
			end
			for rarity = 5, 7 do
				T.expect(byRarity[rarity].animated >= 3, "pièces animées en rareté " .. rarity)
			end
		end)
		T.it("a une texture publiée pour chaque préréglage qui en utilise une du jeu (assets/fx)", function()
			for name, preset in DummyShape.PARTICLES do
				if not string.find(preset.texture, "rbxasset://", 1, true) then
					local id = Assets.FX_TEXTURES[preset.texture]
					T.expect(type(id) == "number" and id > 0, name .. " : texture " .. preset.texture .. " publiée")
				end
			end
			T.expect((Assets.FX_TEXTURES.beam or 0) > 0, "faisceau publié")
		end)
		T.it("pose une colonne de lumière (faisceau) sur un mannequin Secret", function()
			local model = DummyShape.buildVisual(1, Collection.variant({ id = "king", size = 1 }) :: any)
			local beams = 0
			for _, item in model:GetDescendants() do
				if item:IsA("Beam") then
					beams += 1
					T.expect(item.Attachment0 ~= nil and item.Attachment1 ~= nil, "faisceau attaché")
					T.expect(item.Attachment1.Position.Y - item.Attachment0.Position.Y > 10, "faisceau dressé")
				end
			end
			T.expectEqual(beams, 1)
		end)
	end)

	T.describe("Shared.DummySurface", function()
		T.it("porte l'atlas publié (Shared.Assets.DUMMY_TEXTURE), en Overlay", function()
			local fs = require("@lune/fs")
			local serde = require("@lune/serde")
			local Assets = Loader.new():require("src/shared/Assets")
			local model = serde.decode("json", fs.readFile("src/shared/DummySurface.model.json"))
			T.expectEqual(model.className, "SurfaceAppearance")
			T.expectEqual(model.properties.AlphaMode, "Overlay")
			T.expectEqual(model.properties.ColorMap, "rbxassetid://" .. Assets.DUMMY_TEXTURE)
		end)
	end)
end
