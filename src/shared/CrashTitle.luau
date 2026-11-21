-- Titre du crash (« OUCH! » à « CATASTROPHIC! ») selon le score os + objets / 2 : logique pure, testable sous Lune.
local CrashTitle = {}

-- Titre selon le score de crash (os + objets / 2), du plus faible au plus fort
CrashTitle.TITLES = {
	{ score = 0, text = "OUCH!", color = Color3.fromRGB(255, 255, 255) },
	{ score = 4, text = "NICE CRASH!", color = Color3.fromRGB(120, 220, 255) },
	{ score = 10, text = "BRUTAL!", color = Color3.fromRGB(255, 170, 60) },
	{ score = 18, text = "DEVASTATING!", color = Color3.fromRGB(255, 90, 60) },
	{ score = 28, text = "CATASTROPHIC!", color = Color3.fromRGB(230, 60, 255) },
}

-- Cette méthode permet de choisir le titre du crash lorsque l'on connaît le nombre d'os et d'objets.
function CrashTitle.titleFor(bones: number, smashed: number)
	local score = bones + smashed / 2
	local chosen = CrashTitle.TITLES[1]
	for _, entry in CrashTitle.TITLES do
		if score >= entry.score then
			chosen = entry
		end
	end
	return chosen
end

return CrashTitle
