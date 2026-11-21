-- Musique de fond : moment selon l'état du joueur, liste de fond, volume (tirage, fanfare, muet), rotation du hub,
-- fondus, pistes déclarées.
return function(T, Loader)
	local Music = Loader.new():require("src/shared/Music")

	T.describe("Music.mood / bed", function()
		T.it("hub tant que le couloir est prêt ou inconnu", function()
			T.expectEqual(Music.mood("Ready", nil), "Hub")
			T.expectEqual(Music.mood(nil, nil), "Hub")
		end)
		T.it("vol pendant le lancer et le décompte du résultat", function()
			T.expectEqual(Music.mood("Flying", nil), "Flight")
			T.expectEqual(Music.mood("Result", nil), "Flight")
		end)
		T.it("le résultat qui suit la révélation reste au hub (pas de retour de la piste du vol)", function()
			T.expectEqual(Music.mood("Result", nil, "Reveal"), "Hub")
			T.expectEqual(Music.mood("Result", nil, "Hub"), "Hub")
			T.expectEqual(Music.mood("Result", nil, "Flight"), "Flight")
			T.expectEqual(Music.mood("Flying", nil, "Hub"), "Flight")
		end)
		T.it("la phase du tirage l'emporte sur l'état du couloir", function()
			T.expectEqual(Music.mood("Result", "Tease"), "Tease")
			T.expectEqual(Music.mood("Result", "Reveal"), "Reveal")
		end)
		T.it("la silhouette garde la piste du vol, la révélation passe au hub sous la fanfare", function()
			T.expectEqual(Music.bed("Hub"), "Hub")
			T.expectEqual(Music.bed("Flight"), "Flight")
			T.expectEqual(Music.bed("Tease"), "Flight")
			T.expectEqual(Music.bed("Reveal"), "Hub")
		end)
	end)

	T.describe("Music.bedLevel", function()
		T.it("pleine au hub et en vol", function()
			T.expectEqual(Music.bedLevel("Hub", false, false), 1)
			T.expectEqual(Music.bedLevel("Flight", false, false), 1)
		end)
		T.it("baissée pendant la silhouette et tant que la fanfare joue, puis reprise", function()
			T.expectEqual(Music.bedLevel("Tease", false, false), Music.DUCK)
			T.expectEqual(Music.bedLevel("Reveal", true, false), Music.DUCK)
			T.expectEqual(Music.bedLevel("Reveal", false, false), 1)
			T.expectEqual(Music.bedLevel("Hub", true, false), Music.DUCK, "GO BACK avant la fin de la fanfare")
			T.expect(Music.DUCK > 0 and Music.DUCK < 1, "baissée, pas coupée")
		end)
		T.it("muet : silence quel que soit le moment", function()
			for _, mood in { "Hub", "Flight", "Tease", "Reveal" } do
				T.expectEqual(Music.bedLevel(mood, true, true), 0)
				T.expectEqual(Music.bedLevel(mood, false, true), 0)
			end
		end)
	end)

	T.describe("Music.nextIndex / firstIndex", function()
		T.it("le hub fait tourner 2 ou 3 pistes dans l'ordre puis revient au début", function()
			local count = #Music.TRACKS.Hub
			T.expect(count >= 2 and count <= 3, "2 ou 3 pistes au hub")
			local seen = {}
			local i = Music.nextIndex("Hub", nil)
			for _ = 1, count do
				T.expect(not seen[i], "piste déjà jouée dans le tour : " .. i)
				seen[i] = true
				local after = Music.nextIndex("Hub", i)
				T.expect(after ~= i, "deux fois la même piste d'affilée")
				i = after
			end
			T.expectEqual(i, Music.nextIndex("Hub", nil), "retour à la première piste après un tour")
		end)
		T.it("le vol n'a qu'une piste", function()
			T.expectEqual(Music.nextIndex("Flight", 1), 1)
		end)
		T.it("première piste du hub tirée dans la liste", function()
			local count = #Music.TRACKS.Hub
			T.expectEqual(Music.firstIndex("Hub", 0), 1)
			T.expectEqual(Music.firstIndex("Hub", 0.999), count)
			T.expectEqual(Music.firstIndex("Hub", 1), count)
		end)
	end)

	T.describe("Music.shouldAdvance / approach", function()
		T.it("enchaîne FADE s avant la fin, pas tant que la durée est inconnue", function()
			T.expect(not Music.shouldAdvance(0, 0), "durée inconnue")
			T.expect(not Music.shouldAdvance(100, 156), "milieu de piste")
			T.expect(Music.shouldAdvance(156 - Music.FADE, 156), "début du fondu de fin")
			T.expect(Music.shouldAdvance(156, 156), "fin de piste")
		end)
		T.it("une piste du hub jamais chargée est sautée après LOAD_TIMEOUT s", function()
			T.expect(not Music.stalled(false, Music.LOAD_TIMEOUT - 1), "encore en chargement")
			T.expect(Music.stalled(false, Music.LOAD_TIMEOUT), "chargement trop long")
			T.expect(not Music.stalled(true, 1000), "chargée")
		end)
		T.it("un fondu complet dure FADE s et s'arrête sur la cible", function()
			local volume = 0
			local frames = 0
			while volume < 1 and frames < 10000 do
				volume = Music.approach(volume, 1, 1, 1 / 60)
				frames += 1
			end
			T.expectNear(frames / 60, Music.FADE, 1 / 30)
			T.expectEqual(Music.approach(0.3, 0.25, 1, 1), 0.25, "pas de dépassement vers le bas")
			T.expectEqual(Music.approach(0.2, 0.25, 1, 1), 0.25, "pas de dépassement vers le haut")
			T.expect(Music.SWITCH_FADE < Music.FADE, "bascule de moment plus vive qu'un enchaînement du hub")
		end)
	end)

	T.describe("Music.TRACKS", function()
		T.it("chaque piste a un id d'asset, un nom et un volume entre 0 et 1", function()
			local all = { Music.TRACKS.Fanfare }
			for _, list in { Music.TRACKS.Hub, Music.TRACKS.Flight } do
				for _, track in list do
					table.insert(all, track)
				end
			end
			for _, track in all do
				T.expect(string.match(track.id, "^rbxassetid://%d+$") ~= nil, "id invalide : " .. tostring(track.id))
				T.expect(type(track.name) == "string" and track.name ~= "", "piste sans nom")
				T.expect(track.volume > 0 and track.volume <= 1, "volume hors bornes : " .. track.name)
			end
		end)
		T.it("le groupe musique reste sous les effets (volume modéré)", function()
			T.expect(Music.GROUP_VOLUME > 0 and Music.GROUP_VOLUME <= 0.5, "volume du groupe musique")
		end)
	end)
end
