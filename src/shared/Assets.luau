-- Ids des assets publiés sur le compte propriétaire de l'expérience (sources : assets/dummy, Shared.AnimationData).
-- 0 = pas encore publié : le jeu se rabat sur les blocs du gabarit (mannequin) et, dans Studio seulement, sur les
-- clips construits à la volée (animations).
local Assets = {}

-- Maillages du mannequin (assets/dummy/export/dummy.fbx) : une MeshPart par pièce du gabarit et par accessoire
Assets.DUMMY_MESHES = {
	Torso = 133613233785754,
	Head = 86063091423662,
	LeftUpperArm = 114304624461467,
	LeftLowerArm = 106034197377217,
	RightUpperArm = 135967918758689,
	RightLowerArm = 90031260387163,
	LeftUpperLeg = 137052938845723,
	LeftLowerLeg = 119226912137255,
	RightUpperLeg = 88314334717160,
	RightLowerLeg = 80862197937671,
	Helmet = 122532958398710,
	Glasses = 74011413853472,
	Cape = 104540158359045,
} :: { [string]: number }

-- Atlas (assets/dummy/export/dummy_atlas.png) : zones transparentes = couleur de la pièce, noir, cibles. Posé par
-- Shared.DummySurface (SurfaceAppearance) : changer aussi son ColorMap (un test vérifie qu'ils concordent)
Assets.DUMMY_TEXTURE = 84498910179411

-- Animations de l'avatar (assets/anim/export/<Nom>.rbxm)
Assets.ANIMATIONS = {
	Hold = 134156774546186,
	Train = 72035491380919,
	Throw = 98953473271707,
} :: { [string]: number }

-- Icônes d'interface (assets/icons/export/<nom>.png, rendues par assets/icons/build_icons.py). 0 = pas encore
-- publiée : l'interface se rabat sur un emoji (UIKit.icon)
Assets.ICONS = {
	shop = 0,
	index = 0,
	dummies = 0,
	power = 0,
	cash = 0,
	arrow = 0,
} :: { [string]: number }

-- Cette méthode permet de donner l'URI d'un asset publié lorsque l'on le charge ; nil s'il n'est pas publié.
function Assets.uri(id: number?): string?
	if not id or id == 0 then
		return nil
	end
	return "rbxassetid://" .. id
end

return Assets
