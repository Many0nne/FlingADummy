-- Groupes de collision : le mannequin ne se touche pas lui-même et traverse joueurs, canon et éclats de verre ; les
-- avatars ne touchent ni les obstacles de la piste ni sa barrière, qui n'arrête qu'eux.
local PhysicsService = game:GetService("PhysicsService")

local CollisionGroups = {
	DUMMY = "Dummy",
	CHARACTERS = "Characters",
	CANNON = "Cannon",
	DEBRIS = "Debris",
	OBSTACLES = "Obstacles", -- pièces des obstacles partagés (un avatar ne les bouscule pas)
	AVATAR_BARRIER = "AvatarBarrier", -- barrière invisible au départ de la piste : ne collisionne qu'avec Characters
}

-- Cette méthode permet d'enregistrer les groupes et leurs règles de collision lorsque le serveur démarre.
function CollisionGroups.setup()
	for _, name in { "Dummy", "Characters", "Cannon", "Debris", "Obstacles", "AvatarBarrier" } do
		PhysicsService:RegisterCollisionGroup(name)
	end
	PhysicsService:CollisionGroupSetCollidable("Dummy", "Dummy", false)
	PhysicsService:CollisionGroupSetCollidable("Characters", "Dummy", false)
	PhysicsService:CollisionGroupSetCollidable("Characters", "Debris", false)
	PhysicsService:CollisionGroupSetCollidable("Characters", "Obstacles", false)
	PhysicsService:CollisionGroupSetCollidable("Cannon", "Dummy", false)
	PhysicsService:CollisionGroupSetCollidable("Debris", "Dummy", false)
	-- La barrière ne touche que les avatars (Default compris : rien d'autre ne s'y accroche)
	for _, group in PhysicsService:GetRegisteredCollisionGroups() do
		local collides = group.name == "Characters"
		PhysicsService:CollisionGroupSetCollidable("AvatarBarrier", group.name, collides)
	end
end

-- Cette méthode permet de placer toutes les pièces d'une instance dans un groupe lorsqu'un modèle est créé.
function CollisionGroups.assign(root: Instance, group: string)
	if root:IsA("BasePart") then
		root.CollisionGroup = group
	end
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = group
		end
	end
end

return CollisionGroups
