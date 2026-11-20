-- Mannequin : blocs de repli sans gabarits, MeshPart clonées avec gabarits, déclinaisons (couleur, accessoires).
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
		local loader = Loader.new({
			ReplicatedStorage = {
				FindFirstChild = function(_, name)
					return holder.storage:FindFirstChild(name)
				end,
			},
		})
		local DummyShape = loader:require("src/shared/DummyShape")
		holder.storage = storage(folderFactory and folderFactory(DummyShape))
		return DummyShape
	end

	T.describe("DummyShape.buildVisual sans gabarits", function()
		local DummyShape = load(nil)
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
			local model = DummyShape.buildVisual(1, { accessories = { "Helmet" } })
			T.expectEqual(model:FindFirstChild("Helmet"), nil)
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
			local model = DummyShape.buildVisual(1, { material = roblox.Enum.Material.Neon })
			T.expectEqual(model.Torso:FindFirstChild(DummyShape.SURFACE), nil)
			T.expectEqual(model.Torso.Material, roblox.Enum.Material.Neon)
		end)
		T.it("pose les accessoires sur leur pièce, sans masse ni collision", function()
			local model = DummyShape.buildVisual(1, { accessories = { "Helmet", "Cape" } })
			local helmet = model:FindFirstChild("Helmet")
			T.expect(helmet ~= nil, "casque")
			T.expectEqual(helmet:GetAttribute("Accessory"), true)
			T.expectEqual(helmet.CanCollide, false)
			T.expectEqual(helmet.Massless, true)
			local expected = model.Head.CFrame.Position + DummyShape.ACCESSORIES.Helmet.offset
			T.expectNear((helmet.CFrame.Position - expected).Magnitude, 0, 1e-5, "position du casque")
			T.expect(model:FindFirstChild("Cape") ~= nil, "cape")
			T.expectEqual(model:FindFirstChild("Glasses"), nil)
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
