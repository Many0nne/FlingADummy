-- Caméra de la bande de lancer (#158) : cadrage derrière l'épaule vers le bout de la piste, fondus sans saut (entrée
-- depuis la caméra libre, passage au gros plan du geste), coupe directe en mouvement réduit.
return function(T, Loader)
	local loader = Loader.new()
	local ThrowFraming = loader:require("src/shared/ThrowFraming")
	local GameConfig = loader:require("src/shared/GameConfig")
	local roblox = require("@lune/roblox")
	local CFrame = roblox.CFrame
	local Vector3 = roblox.Vector3

	-- Joueur figé sur la bande par le serveur : face à la piste (+Z), HumanoidRootPart à 3 studs du sol (CFrame.lookAt
	-- de Lune donne un regard inversé : rotation construite à la main)
	local SPOT = Vector3.new(12, 3, -8)
	local ROOT = CFrame.new(SPOT) * CFrame.Angles(0, math.pi, 0)
	local STEPS_IN = math.round(GameConfig.BAND_CAM_IN * 60) -- images du fondu à 60 i/s
	local STEPS_THROW = math.round(GameConfig.THROW_CAM_BLEND * 60)

	-- Cette méthode permet de donner les images d'un fondu (position, direction du regard) lorsqu'un test le parcourt
	-- image par image.
	local function sweep(fromPosition, fromFocus, toPosition, toFocus, pivot, steps)
		local frames = {}
		for i = 0, steps do
			local k = ThrowFraming.progress(i, steps) -- avancement adouci, comme en jeu
			local p, f = ThrowFraming.blend(fromPosition, fromFocus, toPosition, toFocus, pivot, k)
			table.insert(frames, { position = p, look = (f - p).Unit })
		end
		return frames
	end

	-- Cette méthode permet de donner le plus grand saut (position en studs, regard en degrés) entre deux images
	-- consécutives lorsqu'un test vérifie qu'un fondu ne saute pas.
	local function maxJump(frames)
		local move, turn = 0, 0
		for i = 2, #frames do
			move = math.max(move, (frames[i].position - frames[i - 1].position).Magnitude)
			local dot = math.clamp(frames[i].look:Dot(frames[i - 1].look), -1, 1)
			turn = math.max(turn, math.deg(math.acos(dot)))
		end
		return move, turn
	end

	T.describe("ThrowFraming.band", function()
		local position, focus = ThrowFraming.band(ROOT)
		local look = (focus - position).Unit

		T.it("place la caméra derrière l'épaule droite, à hauteur de tête", function()
			local local_ = ROOT:PointToObjectSpace(position)
			T.expect(local_.Z > 6, string.format("derrière : %.1f", local_.Z))
			T.expect(local_.X > 1 and local_.X < 4, string.format("à droite : %.1f", local_.X))
			T.expect(local_.Y > 1 and local_.Y < 3.5, string.format("hauteur : %.1f", local_.Y))
		end)

		T.it("regarde vers le bout de la piste, presque à l'horizontale", function()
			T.expect(look.Z > 0.99, string.format("axe de la piste : %.3f", look.Z))
			T.expect(look.Y < 0 and look.Y > -0.1, string.format("légère plongée : %.3f", look.Y))
		end)

		T.it("montre l'avatar à gauche du centre, comme 09 à la jauge", function()
			local right = look:Cross(Vector3.new(0, 1, 0)).Unit
			local seen = SPOT - position
			-- Écran 16:9, champ de vision vertical BAND_CAM_FOV : abscisse de l'avatar de 0 (gauche) à 1 (droite)
			local halfWidth = math.tan(math.rad(GameConfig.BAND_CAM_FOV / 2)) * 16 / 9
			local x = 0.5 + 0.5 * (seen:Dot(right) / seen:Dot(look)) / halfWidth
			T.expect(x > 0.3 and x < 0.45, string.format("abscisse %.2f", x))
		end)

		T.it("resserre le champ de vision (70 → 55)", function()
			T.expectNear(GameConfig.BAND_CAM_FOV, 55)
		end)
	end)

	T.describe("ThrowFraming.progress", function()
		T.it("va de 0 à 1 sans à-coup au départ ni à l'arrivée", function()
			T.expectNear(ThrowFraming.progress(0, 0.35), 0)
			T.expectNear(ThrowFraming.progress(0.35, 0.35), 1)
			T.expectNear(ThrowFraming.progress(1, 0.35), 1)
			T.expect(ThrowFraming.progress(0.01, 0.35) < 0.01, "départ lent")
			T.expect(ThrowFraming.progress(0.34, 0.35) > 0.99, "arrivée lente")
		end)

		T.it("coupe directement quand la durée est nulle (mouvement réduit)", function()
			T.expectNear(ThrowFraming.progress(0, 0), 1)
		end)
	end)

	T.describe("ThrowFraming.blend", function()
		local bandPosition, bandFocus = ThrowFraming.band(ROOT)

		T.it("part exactement du cadrage de départ et arrive exactement sur le cadrage visé", function()
			local free = SPOT + Vector3.new(-3, 9, -14)
			local freeFocus = SPOT
			local p0, f0 = ThrowFraming.blend(free, freeFocus, bandPosition, bandFocus, SPOT, 0)
			local p1, f1 = ThrowFraming.blend(free, freeFocus, bandPosition, bandFocus, SPOT, 1)
			T.expect((p0 - free).Magnitude < 1e-6 and (f0 - freeFocus).Magnitude < 1e-6, "départ")
			T.expect((p1 - bandPosition).Magnitude < 1e-6 and (f1 - bandFocus).Magnitude < 1e-6, "arrivée")
		end)

		T.it("entre sur la bande depuis la caméra libre sans saut, quel que soit son angle", function()
			for _, angle in { 0, 60, 135, 180, 225, 300 } do
				local a = math.rad(angle)
				local free = SPOT + Vector3.new(math.sin(a) * 14, 6, -math.cos(a) * 14)
				local freeFocus = SPOT + Vector3.new(0, 1.5, 0) -- caméra libre : regard sur l'avatar
				local frames = sweep(free, freeFocus, bandPosition, bandFocus, SPOT, STEPS_IN)
				local move, turn = maxJump(frames)
				T.expect(move < 3, string.format("caméra à %d° : %.2f studs par image", angle, move))
				T.expect(turn < 14, string.format("caméra à %d° : %.1f° par image", angle, turn))
				-- L'avatar reste devant la caméra pendant tout le fondu
				for _, frame in frames do
					T.expect(
						(SPOT - frame.position).Unit:Dot(frame.look) > 0.3,
						"avatar à l'image à " .. angle .. "°"
					)
				end
			end
		end)

		T.it("passe de la bande au gros plan du geste en tournant autour de l'avatar, sans le traverser", function()
			local closePosition, closeFocus = ThrowFraming.closeUp(ROOT, 0)
			local frames = sweep(bandPosition, bandFocus, closePosition, closeFocus, SPOT, STEPS_THROW)
			local move, turn = maxJump(frames)
			print(
				string.format(
					"[mesure] bande → gros plan (60 i/s) : %.2f studs et %.1f° par image au plus",
					move,
					turn
				)
			)
			T.expect(move < 1.5, string.format("%.2f studs par image", move))
			T.expect(turn < 10, string.format("%.1f° par image", turn))
			for _, frame in frames do
				local offset = frame.position - SPOT
				local flat = Vector3.new(offset.X, 0, offset.Z).Magnitude
				T.expect(flat > 3, string.format("à %.1f studs de l'axe de l'avatar", flat))
				T.expect(-offset.Unit:Dot(frame.look) > 0.3, "avatar à l'image")
			end
		end)

		T.it("garde un point visé devant une caméra libre collée à l'avatar (première personne)", function()
			local head = CFrame.new(SPOT + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, math.pi, 0)
			local focus = ThrowFraming.focusOf(head, SPOT)
			T.expect((focus - head.Position).Magnitude >= ThrowFraming.MIN_FOCUS - 1e-6, "point visé distinct")
		end)
	end)

	T.describe("ThrowFraming.closeUp", function()
		T.it("garde le gros plan d'avant #158 (côté du bras qui lance, devant, inclinaison au bout)", function()
			local p0, focus, roll0 = ThrowFraming.closeUp(ROOT, 0)
			local p1, _, roll1 = ThrowFraming.closeUp(ROOT, 1)
			T.expect((ROOT:PointToObjectSpace(p0) - Vector3.new(5.6, 2.9, -3.2)).Magnitude < 1e-6, "départ")
			T.expect((ROOT:PointToObjectSpace(p1) - Vector3.new(4.5, 2.6, -2.5)).Magnitude < 1e-6, "arrivée")
			T.expect((ROOT:PointToObjectSpace(focus) - Vector3.new(0.5, 2.6, 0)).Magnitude < 1e-6, "point visé")
			T.expectNear(roll0, 0)
			T.expectNear(roll1, math.rad(-5))
		end)
	end)
end
