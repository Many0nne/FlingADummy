-- Animations de l'avatar : clips cohérents (temps, marqueurs, hiérarchie), geste lisible, séquence générée.
return function(T, Loader, Lib)
	local loader = Loader.new()
	local AnimationData = loader:require("src/shared/AnimationData")
	local GameConfig = loader:require("src/shared/GameConfig")
	local R15Rig = Lib.R15Rig

	-- Cette méthode permet de donner la direction du bras (pendant au repos) dans le repère du torse lorsqu'un test
	-- vérifie la rotation d'épaule d'une pose.
	local function armDirection(pose)
		return AnimationData.toCFrame(pose):VectorToWorldSpace(Vector3.new(0, -1, 0))
	end

	-- Cette méthode permet de trouver la keyframe d'un clip la plus proche d'un instant lorsqu'un test vérifie une pose.
	local function keyframeAt(clip, t)
		local best = clip.keyframes[1]
		for _, keyframe in clip.keyframes do
			if math.abs(keyframe.t - t) < math.abs(best.t - t) then
				best = keyframe
			end
		end
		return best
	end

	T.describe("AnimationData.CLIPS", function()
		T.it("chaque clip commence à 0, finit à sa durée, keyframes croissantes", function()
			for _, clip in AnimationData.CLIPS do
				T.expectEqual(clip.keyframes[1].t, 0, clip.name .. " début")
				T.expectNear(clip.keyframes[#clip.keyframes].t, clip.length, 1e-9, clip.name .. " fin")
				for i = 2, #clip.keyframes do
					T.expect(clip.keyframes[i].t > clip.keyframes[i - 1].t, clip.name .. " keyframe " .. i)
				end
			end
		end)
		T.it("les clips en boucle reviennent à leur pose de départ", function()
			for _, clip in AnimationData.CLIPS do
				if clip.loop then
					local first, last = clip.keyframes[1].poses, clip.keyframes[#clip.keyframes].poses
					for name, pose in first do
						for i, v in pose do
							T.expectNear(last[name][i], v, 1e-9, clip.name .. " " .. name)
						end
					end
				end
			end
		end)
		T.it("toutes les pièces animées ont un parent R15 connu", function()
			for _, clip in AnimationData.CLIPS do
				for name in AnimationData.animatedParts(clip) do
					T.expect(AnimationData.PARENT[name] ~= nil, clip.name .. " : " .. name)
				end
			end
		end)
		T.it("les marqueurs tombent dans la durée du clip", function()
			for _, clip in AnimationData.CLIPS do
				for name, t in clip.markers do
					T.expect(t > 0 and t < clip.length, clip.name .. " marqueur " .. name)
				end
			end
		end)
	end)

	T.describe("AnimationData.THROW", function()
		local clip = AnimationData.THROW
		T.it("lâche au marqueur Release, à THROW_RELEASE_TIME", function()
			T.expectNear(clip.markers.Release, GameConfig.THROW_RELEASE_TIME, 1e-9)
		end)
		T.it("part de la pose tenue : bras droit levé", function()
			local dir = armDirection(clip.keyframes[1].poses.RightUpperArm)
			T.expect(dir.Y > 0.9, "bras vers le haut, obtenu " .. tostring(dir))
		end)
		-- Cette méthode permet de donner les positions de la main droite et de la tête (cinématique directe d'un avatar
		-- R15, tests/lib/R15Rig) à la keyframe la plus proche de `t` : la direction du haut du bras ne suffit pas, le
		-- buste tourné et le coude replié peuvent ramener la main dans le dos.
		local function handAndHead(t)
			local poses
			local best = math.huge
			for _, keyframe in AnimationData.filledKeyframes(clip) do
				if math.abs(keyframe.t - t) < best then
					best, poses = math.abs(keyframe.t - t), keyframe.poses
				end
			end
			local head = R15Rig.partFrame("Head", poses, AnimationData.toCFrame).Position
			return R15Rig.rightHand(poses, AnimationData.toCFrame), head
		end
		T.it("arme la main au-dessus et derrière la tête à l'élan", function()
			for _, t in { 0.42, 0.56 } do
				local hand, head = handAndHead(t)
				T.expect(hand.Y > head.Y, "t = " .. t .. " : main au-dessus de la tête, obtenu " .. tostring(hand))
				T.expect(hand.Z > head.Z + 0.5, "t = " .. t .. " : main derrière la tête, obtenu " .. tostring(hand))
			end
		end)
		T.it("projette la main devant, à hauteur de tête, au lâcher", function()
			local hand, head = handAndHead(clip.markers.Release)
			T.expect(hand.Z < head.Z - 0.8, "main devant, obtenu " .. tostring(hand))
			T.expect(hand.Y > head.Y - 0.3, "main à hauteur de tête, obtenu " .. tostring(hand))
		end)
		T.it("tourne le buste : épaule droite en arrière à l'élan, en avant au lâcher", function()
			local back = keyframeAt(clip, 0.5).poses
			local front = keyframeAt(clip, clip.markers.Release).poses
			T.expect(back.LowerTorso[2] + back.UpperTorso[2] < -40, "rotation d'élan")
			T.expect(front.LowerTorso[2] + front.UpperTorso[2] > 40, "rotation au lâcher")
		end)
	end)

	T.describe("AnimationData.HOLD et TRAIN", function()
		T.it("tient le mannequin bras droit tendu au-dessus de la tête", function()
			for _, keyframe in AnimationData.HOLD.keyframes do
				T.expect(armDirection(keyframe.poses.RightUpperArm).Y > 0.9, "t = " .. keyframe.t)
			end
		end)
		T.it("développe le poids au-dessus de la tête au sommet (marqueur Top)", function()
			local top = keyframeAt(AnimationData.TRAIN, AnimationData.TRAIN.markers.Top).poses
			T.expect(armDirection(top.RightUpperArm).Y > 0.9, "bras droit")
			T.expect(armDirection(top.LeftUpperArm).Y > 0.9, "bras gauche")
		end)
	end)

	T.describe("assets/anim/export (fichiers publiés)", function()
		T.it(
			"correspondent aux clips (keyframes, marqueur Release) : sinon relancer tools/build-anims et republier",
			function()
				local fs = require("@lune/fs")
				local roblox = require("@lune/roblox")
				for _, clip in AnimationData.CLIPS do
					local sequence =
						roblox.deserializeModel(fs.readFile("assets/anim/export/" .. clip.name .. ".rbxm"))[1]
					local times, markers = {}, {}
					for _, keyframe in sequence:GetChildren() do
						local marker = keyframe:FindFirstChildOfClass("KeyframeMarker")
						if marker then
							markers[marker.Name] = keyframe.Time
						else
							table.insert(times, keyframe.Time)
						end
					end
					table.sort(times)
					T.expectEqual(#times, #clip.keyframes, clip.name .. " : nombre de keyframes")
					for i, keyframe in clip.keyframes do
						T.expectNear(times[i], keyframe.t, 1e-4, clip.name .. " keyframe " .. i)
					end
					for name, t in clip.markers do
						T.expectNear(markers[name] or -1, t, 1e-4, clip.name .. " marqueur " .. name)
					end
				end
			end
		)
	end)

	T.describe("AnimationData.buildSequence", function()
		T.it("produit une KeyframeSequence complète, parents non animés à poids nul", function()
			local clip = AnimationData.THROW
			local sequence = AnimationData.buildSequence(clip)
			T.expectEqual(sequence.ClassName, "KeyframeSequence")
			T.expectEqual(sequence.Loop, false)
			local keyframes, markers = 0, 0
			for _, keyframe in sequence:GetChildren() do
				local marker = keyframe:FindFirstChildOfClass("KeyframeMarker")
				if marker then
					markers += 1
					T.expectEqual(marker.Name, "Release")
					T.expectNear(keyframe.Time, clip.markers.Release, 1e-6)
				else
					keyframes += 1
					local root = keyframe:FindFirstChild("HumanoidRootPart")
					T.expect(root ~= nil, "pose racine")
					T.expectEqual(root.Weight, 0)
					local arm = keyframe:FindFirstChild("RightUpperArm", true)
					T.expectEqual(arm.Parent.Name, "UpperTorso")
					T.expectEqual(arm.Weight, 1)
				end
			end
			T.expectEqual(keyframes, #clip.keyframes)
			T.expectEqual(markers, 1)
		end)
	end)
end
