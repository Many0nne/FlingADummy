-- Effets ajoutés aux modèles de collection (#66, retour de test : « il en faut plus ») : une aura par rareté, de plus en
-- plus fournie (éclats dès Rare, onde au sol et lumière dès Epic, flaque de lumière et poussières montantes dès
-- Legendary, gloire de rayons derrière dès Mythic, colonne de lumière et gerbe d'étoiles en Secret), et des effets à
-- thème par mannequin dès Uncommon (notes de Mint, bulles d'Ocean, réacteur de Pilot, flocons d'Ice…). Données pures,
-- ajoutées aux effets du modèle (Shared.DummyModels) par Collection.variant et posées par Shared.DummyShape. Décalages
-- en studs à l'échelle 1, depuis le centre de la pièce porteuse.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local DummyModels = require(Shared:WaitForChild("DummyModels"))
local Rarity = require(Shared:WaitForChild("Rarity"))

type Effect = DummyModels.Effect

local DummyAura = {}

local WHITE = Color3.fromRGB(255, 255, 255)
local GROUND = Vector3.new(0, -3.7, 0) -- sol sous les pieds, depuis le centre du torse
local GROUND_LEVEL = -2 -- sous les hanches (depuis le centre du torse) : effet posé au sol
local BACK = Vector3.new(0, 0.6, 0.9) -- derrière le torse (le mannequin regarde vers -Z)

-- Cette méthode permet de décrire un émetteur de particules lorsque l'on compose une aura ou un thème.
local function particles(
	preset: string,
	piece: string,
	offset: Vector3,
	color: Color3,
	color2: Color3?,
	more: any?
): Effect
	local effect: any = { kind = "particles", preset = preset, piece = piece, offset = offset, color = color }
	effect.color2 = color2 or color
	for key, value in more or {} do
		effect[key] = value
	end
	return effect
end

-- Cette méthode permet de donner l'aura d'une rareté (couleur `color` de la rareté) lorsque l'on habille un
-- mannequin de collection ; vide en Common et Uncommon.
function DummyAura.rarity(rarity: number, color: Color3): { Effect }
	local effects: { Effect } = {}
	if rarity < 3 then
		return effects
	end
	-- Au-delà de Secret (#94) : un cran de plus par rareté (éclats, poussières, colonne de lumière plus haute)
	local beyond = math.max(0, rarity - 7)
	local glints = ({ 1, 1.4, 1.6, 2, 2.4 })[math.min(rarity - 2, 5)] + 0.3 * beyond
	table.insert(effects, particles("glint", "Torso", Vector3.new(0, 0.3, 0), color, WHITE, { rate = glints }))
	if rarity >= 4 then
		local ringSize = if rarity >= 7 then 1.3 + 0.1 * beyond else 1
		table.insert(effects, particles("ring", "Torso", GROUND, color, WHITE, { size = ringSize }))
	end
	if rarity == 4 then
		table.insert(effects, {
			kind = "light",
			piece = "Torso",
			offset = Vector3.new(0, 0, -1.5),
			color = color,
			range = 10,
			brightness = 1.5,
		})
	end
	if rarity >= 5 then
		table.insert(effects, particles("pool", "Torso", GROUND, color))
		local motes = ({ 1, 1.5, 2 })[math.min(rarity - 4, 3)] + 0.3 * beyond
		table.insert(effects, particles("motes", "Torso", GROUND, color, WHITE, { rate = motes }))
	end
	if rarity >= 6 then
		table.insert(
			effects,
			particles("rays", "Torso", BACK, color, WHITE, { size = if rarity >= 7 then 1.15 else 1 })
		)
	end
	if rarity >= 7 then
		table.insert(effects, {
			kind = "beam",
			piece = "Torso",
			offset = GROUND,
			color = color,
			color2 = WHITE,
			height = 18 + 4 * beyond,
			width = 4 + 0.5 * beyond,
		})
		table.insert(
			effects,
			particles(
				"burst",
				"Torso",
				Vector3.new(0, 0.5, 0),
				Color3.fromRGB(255, 120, 220),
				Color3.fromRGB(120, 230, 255)
			)
		)
	end
	return effects
end

-- Effets à thème par mannequin (en plus de ceux du modèle dans Shared.DummyModels)
-- stylua: ignore
DummyAura.THEMES = {
	mint = { particles("notes", "Head", Vector3.new(0, 1, 0), Color3.fromRGB(120, 255, 200), WHITE) },
	biker = { particles("smoke", "LeftLowerLeg", Vector3.new(0, -0.5, 0.4), Color3.fromRGB(150, 150, 160)) },
	nerd = { particles("sparkle", "Head", Vector3.new(0, 1, 0), Color3.fromRGB(255, 230, 90), WHITE, { rate = 0.5 }) },
	ocean = {
		particles("bubbles", "Head", Vector3.new(0, 1.2, 0), Color3.fromRGB(170, 230, 255), WHITE),
		particles("bubbles", "Torso", Vector3.new(0, 1.3, 1.3), Color3.fromRGB(170, 230, 255), WHITE, { rate = 0.6, size = 0.7 }),
	},
	hero = { particles("glint", "Torso", Vector3.new(0, 0.3, -0.7), Color3.fromRGB(255, 220, 60), WHITE, { rate = 0.6 }) },
	pilot = {
		particles("jet", "Torso", Vector3.new(-0.4, -1.3, 1), Color3.fromRGB(255, 200, 60), Color3.fromRGB(255, 80, 20)),
		particles("jet", "Torso", Vector3.new(0.4, -1.3, 1), Color3.fromRGB(255, 200, 60), Color3.fromRGB(255, 80, 20)),
		particles("smoke", "Torso", Vector3.new(0, -2.2, 1), Color3.fromRGB(200, 200, 210), nil, { rate = 0.8 }),
	},
	ice = {
		particles("snow", "Head", Vector3.new(0, 2, 0), Color3.fromRGB(220, 245, 255), WHITE),
		particles("wisp", "Torso", GROUND, Color3.fromRGB(190, 235, 255), nil, { rate = 0.6 }),
	},
	toxic = {
		particles("bubbles", "Torso", Vector3.new(0, 1, 1.25), Color3.fromRGB(150, 255, 60), Color3.fromRGB(210, 255, 120)),
		particles("smoke", "Torso", GROUND, Color3.fromRGB(110, 220, 60), nil, { rate = 0.7 }),
	},
	royal = {
		particles("glint", "RightLowerArm", Vector3.new(0, -2.6, -0.25), Color3.fromRGB(255, 215, 90), WHITE, { rate = 0.6 }),
		particles("sparkle", "Head", Vector3.new(0, 1.3, 0), Color3.fromRGB(200, 120, 255), WHITE, { rate = 0.6 }),
	},
	gold = { particles("burst", "Torso", Vector3.new(0, 0.5, 0), Color3.fromRGB(255, 215, 60), Color3.fromRGB(255, 250, 200), { rate = 0.6 }) },
	lava = { particles("smoke", "Head", Vector3.new(0, 1.4, 0), Color3.fromRGB(70, 60, 60)) },
	diamond = { particles("glint", "Head", Vector3.new(0, 2.4, 0), Color3.fromRGB(180, 250, 255), WHITE) },
	galaxy = { particles("motes", "Head", Vector3.new(0, 0, 0), Color3.fromRGB(200, 160, 255), WHITE, { rate = 0.5, size = 0.7 }) },
	ghost = { particles("motes", "RightLowerArm", Vector3.new(0, -1, -0.45), Color3.fromRGB(150, 255, 220), WHITE, { rate = 0.6 }) },
	neon = { particles("vortex", "Torso", Vector3.new(0, 0.2, 0), Color3.fromRGB(0, 255, 255), Color3.fromRGB(255, 0, 220), { rate = 0.6 }) },
	king = { particles("sparkle", "Head", Vector3.new(0, 1.5, 0), Color3.fromRGB(255, 215, 60), WHITE) },
	void = { particles("vortex", "Torso", Vector3.new(0, 1, 1.7), Color3.fromRGB(160, 60, 255), Color3.fromRGB(20, 0, 40), { rate = 0.8 }) },
	cosmic = { particles("stars", "Torso", Vector3.new(0, 1, 1.7), Color3.fromRGB(255, 200, 255), Color3.fromRGB(150, 220, 255), { rate = 0.8 }) },
} :: { [string]: { Effect } }

-- Cette méthode permet de savoir si un effet est posé au sol (onde, flaque, poussières, brume, colonne de lumière)
-- lorsque l'on habille un mannequin porté en main, où le sol est loin sous lui.
function DummyAura.isGrounded(effect: Effect): boolean
	return effect.kind == "beam" or (effect.piece == "Torso" and effect.offset.Y <= GROUND_LEVEL)
end

-- Cette méthode permet de donner tous les effets ajoutés d'un mannequin (thème, puis aura de sa rareté) lorsque l'on
-- construit sa déclinaison ; `carried` (porté en main) écarte les effets posés au sol.
function DummyAura.effects(id: string, rarity: number, carried: boolean?): { Effect }
	local effects: { Effect } = {}
	for _, list in { DummyAura.THEMES[id] or {}, DummyAura.rarity(rarity, Rarity.get(rarity).color) } do
		for _, effect in list do
			if not (carried and DummyAura.isGrounded(effect)) then
				table.insert(effects, effect)
			end
		end
	end
	return effects
end

return DummyAura
