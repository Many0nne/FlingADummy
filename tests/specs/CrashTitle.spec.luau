-- CrashTitle : titre du crash selon os + objets / 2, seuils 0 / 4 / 10 / 18 / 28.
return function(T, Loader)
	local CrashTitle = Loader.new():require("src/shared/CrashTitle")

	local function text(bones, smashed)
		return CrashTitle.titleFor(bones, smashed).text
	end

	T.describe("CrashTitle.TITLES", function()
		T.it("garde les cinq titres, par seuils croissants", function()
			local expected = {
				{ 0, "OUCH!" },
				{ 4, "NICE CRASH!" },
				{ 10, "BRUTAL!" },
				{ 18, "DEVASTATING!" },
				{ 28, "CATASTROPHIC!" },
			}
			T.expectEqual(#CrashTitle.TITLES, #expected)
			for i, entry in expected do
				T.expectEqual(CrashTitle.TITLES[i].score, entry[1])
				T.expectEqual(CrashTitle.TITLES[i].text, entry[2])
				T.expect(typeof(CrashTitle.TITLES[i].color) == "Color3", entry[2] .. " : couleur")
			end
		end)
	end)

	T.describe("CrashTitle.titleFor", function()
		T.it("choisit OUCH! sans os ni objet", function()
			T.expectEqual(text(0, 0), "OUCH!")
		end)
		T.it("respecte chaque seuil aux bornes (os seuls)", function()
			T.expectEqual(text(3, 0), "OUCH!")
			T.expectEqual(text(4, 0), "NICE CRASH!")
			T.expectEqual(text(9, 0), "NICE CRASH!")
			T.expectEqual(text(10, 0), "BRUTAL!")
			T.expectEqual(text(17, 0), "BRUTAL!")
			T.expectEqual(text(18, 0), "DEVASTATING!")
			T.expectEqual(text(27, 0), "DEVASTATING!")
			T.expectEqual(text(28, 0), "CATASTROPHIC!")
		end)
		T.it("compte un objet pour un demi-point", function()
			T.expectEqual(text(0, 7), "OUCH!") -- 3.5
			T.expectEqual(text(0, 8), "NICE CRASH!") -- 4
			T.expectEqual(text(0, 19), "NICE CRASH!") -- 9.5
			T.expectEqual(text(0, 20), "BRUTAL!") -- 10
			T.expectEqual(text(0, 35), "BRUTAL!") -- 17.5
			T.expectEqual(text(0, 36), "DEVASTATING!") -- 18
			T.expectEqual(text(0, 55), "DEVASTATING!") -- 27.5
			T.expectEqual(text(0, 56), "CATASTROPHIC!") -- 28
		end)
		T.it("additionne os et objets", function()
			T.expectEqual(text(3, 1), "OUCH!") -- 3.5
			T.expectEqual(text(3, 2), "NICE CRASH!") -- 4
			T.expectEqual(text(9, 1), "NICE CRASH!") -- 9.5
			T.expectEqual(text(9, 2), "BRUTAL!") -- 10
			T.expectEqual(text(27, 1), "DEVASTATING!") -- 27.5
			T.expectEqual(text(27, 2), "CATASTROPHIC!") -- 28
		end)
		T.it("reste sur CATASTROPHIC! pour de très grandes valeurs", function()
			T.expectEqual(text(1e9, 1e9), "CATASTROPHIC!")
			T.expectEqual(text(0, 1e12), "CATASTROPHIC!")
		end)
	end)
end
