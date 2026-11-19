-- Ids des assets publiés sur le compte propriétaire de l'expérience (sources : assets/dummy, Shared.AnimationData).
-- 0 = pas encore publié : le jeu se rabat sur les blocs du gabarit (mannequin) et, dans Studio seulement, sur les
-- clips construits à la volée (animations).
local Assets = {}

-- Maillages du mannequin (assets/dummy/export/dummy.fbx) : une MeshPart par pièce du gabarit et par accessoire
Assets.DUMMY_MESHES = {
	Torso = 0,
	Head = 0,
	LeftUpperArm = 0,
	LeftLowerArm = 0,
	RightUpperArm = 0,
	RightLowerArm = 0,
	LeftUpperLeg = 0,
	LeftLowerLeg = 0,
	RightUpperLeg = 0,
	RightLowerLeg = 0,
	Helmet = 0,
	Glasses = 0,
	Cape = 0,
} :: { [string]: number }

-- Atlas (assets/dummy/export/dummy_atlas.png) : zones transparentes = couleur de la pièce, noir, cibles
Assets.DUMMY_TEXTURE = 0

-- Animations de l'avatar (assets/anim/export/<Nom>.rbxm)
Assets.ANIMATIONS = {
	Hold = 0,
	Train = 0,
	Throw = 0,
} :: { [string]: number }

-- Cette méthode permet de donner l'URI d'un asset publié lorsque l'on le charge ; nil s'il n'est pas publié.
function Assets.uri(id: number?): string?
	if not id or id == 0 then
		return nil
	end
	return "rbxassetid://" .. id
end

return Assets
