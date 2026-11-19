-- Groupes de collision : le mannequin ne se touche pas lui-même et traverse joueurs, canon et éclats de verre.
local PhysicsService = game:GetService("PhysicsService")

local CollisionGroups = {
	DUMMY = "Dummy",
	CHARACTERS = "Characters",
	CANNON = "Cannon",
	DEBRIS = "Debris",
}

-- Cette méthode permet d'enregistrer les groupes et leurs règles de collision lorsque le serveur démarre.
function CollisionGroups.setup()
	for _, name in { "Dummy", "Characters", "Cannon", "Debris" } do
		PhysicsService:RegisterCollisionGroup(name)
	end
	PhysicsService:CollisionGroupSetCollidable("Dummy", "Dummy", false)
	PhysicsService:CollisionGroupSetCollidable("Characters", "Dummy", false)
	PhysicsService:CollisionGroupSetCollidable("Characters", "Debris", false)
	PhysicsService:CollisionGroupSetCollidable("Cannon", "Dummy", false)
	PhysicsService:CollisionGroupSetCollidable("Debris", "Dummy", false)
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
