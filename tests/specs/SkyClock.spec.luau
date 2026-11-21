-- Ciel de nuit de la Galaxy (#97) : sens du fondu de l'heure, sans repasser par le plein jour.
return function(T, Loader)
	local loader = Loader.new()
	local SkyClock = loader:require("src/shared/SkyClock")
	local DAY = 13.5

	T.describe("SkyClock.target", function()
		T.it("fait tomber la nuit en avançant par le coucher depuis le plein jour", function()
			T.expectEqual(SkyClock.target(DAY, true, DAY), 24)
			T.expectEqual(SkyClock.target(20, true, DAY), 24) -- nuit reprise après un fondu interrompu au crépuscule
		end)

		T.it("revient à minuit en reculant depuis le matin d'un retour du jour interrompu", function()
			-- Sinon 3 h → 24 h passerait par midi : un jour entier en 1,2 s
			T.expectEqual(SkyClock.target(3, true, DAY), 0)
			T.expectEqual(SkyClock.target(0, true, DAY), 0)
		end)

		T.it("rend l'heure du jour au retour, depuis minuit (0 ou 24) comme depuis un crépuscule", function()
			for _, current in { 0, 24, 3, 20 } do
				T.expectEqual(SkyClock.target(current, false, DAY), DAY)
			end
		end)
	end)
end
