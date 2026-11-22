-- Attribution des places du lobby (#142) : la première place libre à l'arrivée, une file d'attente quand le lobby est
-- plein (la place peut accueillir plus de joueurs que SLOT_COUNT), et la place libérée au plus ancien joueur en
-- attente. Logique pure (testée) ; Server.SlotService l'applique aux joueurs.
local SlotQueue = {}
SlotQueue.__index = SlotQueue

export type Queue<T> = typeof(setmetatable(
	{} :: { count: number, owners: { [number]: T }, slotOf: { [T]: number }, waiting: { T } },
	SlotQueue
))

-- Cette méthode permet de créer le suivi des places lorsque le serveur démarre : `count` places, toutes libres.
function SlotQueue.new<T>(count: number): Queue<T>
	return setmetatable({ count = count, owners = {}, slotOf = {}, waiting = {} }, SlotQueue)
end

-- Cette méthode permet de placer un joueur lorsqu'il arrive : sa place (la première libre), ou nil s'il rejoint la file
-- d'attente (lobby plein) ; sans effet s'il est déjà placé ou en attente.
function SlotQueue.join<T>(self: Queue<T>, id: T): number?
	if self.slotOf[id] then
		return self.slotOf[id]
	elseif table.find(self.waiting, id) then
		return nil
	end
	for index = 1, self.count do
		if self.owners[index] == nil then
			self.owners[index] = id
			self.slotOf[id] = index
			return index
		end
	end
	table.insert(self.waiting, id)
	return nil
end

-- Cette méthode permet de libérer la place d'un joueur lorsqu'il part : le joueur en attente le plus ancien qui la
-- reprend et sa place (nil, nil si personne n'attend ou si le joueur n'avait pas de place) ; un joueur en attente qui
-- part quitte simplement la file.
function SlotQueue.leave<T>(self: Queue<T>, id: T): (T?, number?)
	local waitingAt = table.find(self.waiting, id)
	if waitingAt then
		table.remove(self.waiting, waitingAt)
		return nil, nil
	end
	local index = self.slotOf[id]
	if not index then
		return nil, nil
	end
	self.slotOf[id] = nil
	self.owners[index] = nil
	local next = table.remove(self.waiting, 1)
	if next == nil then
		return nil, nil
	end
	self.owners[index] = next
	self.slotOf[next] = index
	return next, index
end

-- Cette méthode permet de savoir si une place est sans joueur lorsque le serveur cherche des places pour les
-- mannequins de test.
function SlotQueue.isFree<T>(self: Queue<T>, index: number): boolean
	return self.owners[index] == nil
end

-- Cette méthode permet de savoir si un joueur attend une place lorsque l'on affiche son message.
function SlotQueue.isWaiting<T>(self: Queue<T>, id: T): boolean
	return table.find(self.waiting, id) ~= nil
end

return SlotQueue
