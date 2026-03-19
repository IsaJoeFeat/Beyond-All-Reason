local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name      = "Transport To (Synced)",
		desc      = "Clean implementation of the 'Taxi' system.",
		author    = "IsaJoeFeat & Gemini",
		date      = "2026",
		license   = "POOP",
		layer     = 0,
		enabled   = true
	}
end

if not gadgetHandler:IsSyncedCode() then return end

local CMD_TRANSPORT_TO = 34571 
local CMD_TYPE_GROUND  = CMDTYPE.ICON_MAP 
local CMD_LOAD_UNITS   = CMD.LOAD_UNITS
local CMD_UNLOAD_UNITS = CMD.UNLOAD_UNITS
local CMD_MOVE         = CMD.MOVE

local transportableUnits = {} 
local transportStats     = {} 
local unitStats          = {}
local unitsWaiting       = {} -- [unitID] = {pos, teamID, assignedTaxi}

local SpGetUnitDefID      = Spring.GetUnitDefID
local SpGetUnitPosition   = Spring.GetUnitPosition
local SpGiveOrderToUnit   = Spring.GiveOrderToUnit
local SpSetUnitMoveGoal   = Spring.SetUnitMoveGoal
local SpGetUnitCommands   = Spring.GetUnitCommands

-- =============================================================================
-- Helpers
-- =============================================================================

local function BuildDefCaches()
	for unitDefID, ud in pairs(UnitDefs) do
		if ud.isTransport and ud.canFly then
			transportStats[unitDefID] = { massLimit = ud.transportMass or 0, sizeLimit = ud.transportSize or 0 }
		end
		unitStats[unitDefID] = { mass = ud.mass or 0, size = ud.xsize or 0 }
		if (not ud.canFly and not ud.isBuilding and (ud.cantBeTransported == nil or ud.cantBeTransported == false)) or ud.isFactory then
			transportableUnits[unitDefID] = true
		end
	end
end

local function CanLink(taxiID, cargoID)
	local tStat = transportStats[SpGetUnitDefID(taxiID)]
	local uStat = unitStats[SpGetUnitDefID(cargoID)]
	if not tStat or not uStat then return false end
	if #(Spring.GetUnitIsTransporting(taxiID) or {}) > 0 then return false end
	return (uStat.mass <= tStat.massLimit) and (uStat.size <= tStat.sizeLimit * 2)
end

-- =============================================================================
-- Callins
-- =============================================================================

function gadget:AllowCommand(unitID, unitDefID, teamID, cmdID, cmdParams, cmdOptions)
	if cmdID == CMD_TRANSPORT_TO then return transportableUnits[unitDefID] ~= nil end
	return true
end

function gadget:CommandFallback(unitID, unitDefID, teamID, cmdID, cmdParams, cmdOptions)
	if cmdID ~= CMD_TRANSPORT_TO then return false end
	if Spring.GetUnitTransporter(unitID) then return true, false end

	local ux, uy, uz = SpGetUnitPosition(unitID)
	local tx, ty, tz = cmdParams[1], cmdParams[2], cmdParams[3]
	if ((ux-tx)^2 + (uz-tz)^2) < (35*35) then
		unitsWaiting[unitID] = nil
		return true, true 
	end

	if not unitsWaiting[unitID] then
		unitsWaiting[unitID] = { pos = {tx, ty, tz}, teamID = teamID, assignedTaxi = nil }
		SpSetUnitMoveGoal(unitID, tx, ty, tz)
	end

	if unitsWaiting[unitID].assignedTaxi then
		local taxi = unitsWaiting[unitID].assignedTaxi
		if not Spring.ValidUnitID(taxi) or Spring.GetUnitIsDead(taxi) or #(SpGetUnitCommands(taxi, 1) or {}) == 0 then
			unitsWaiting[unitID].assignedTaxi = nil -- Reset if taxi died or lost orders
		else
			SpSetUnitMoveGoal(unitID, ux, uy, uz) -- Stop and Wait
		end
	end
	return true, false
end

function gadget:GameFrame(frame)
	if frame % 30 ~= 0 then return end
	for unitID, data in pairs(unitsWaiting) do
		if not data.assignedTaxi then
			local ux, uy, uz = SpGetUnitPosition(unitID)
			local bestTaxi, minD = nil, math.huge
			local teamUnits = Spring.GetTeamUnits(data.teamID)
			for i = 1, #teamUnits do
				local tID = teamUnits[i]
				if transportStats[SpGetUnitDefID(tID)] and #SpGetUnitCommands(tID, 0) == 0 and CanLink(tID, unitID) then
					local tx, ty, tz = SpGetUnitPosition(tID)
					local dSq = (ux-tx)^2 + (uz-tz)^2
					if dSq < minD then bestTaxi, minD = tID, dSq end
				end
			end
			if bestTaxi then
				data.assignedTaxi = bestTaxi
				local hx, hy, hz = SpGetUnitPosition(bestTaxi)
				SpGiveOrderToUnit(bestTaxi, CMD_LOAD_UNITS, {unitID}, {})
				SpGiveOrderToUnit(bestTaxi, CMD_UNLOAD_UNITS, {data.pos[1], data.pos[2], data.pos[3]}, {"shift"})
				SpGiveOrderToUnit(bestTaxi, CMD_MOVE, {hx, hy, hz}, {"shift"}) -- Return to start
			end
		end
	end
end

function gadget:UnitCreated(unitID, unitDefID)
	if transportableUnits[unitDefID] then
		Spring.InsertUnitCmdDesc(unitID, {id=CMD_TRANSPORT_TO, type=CMD_TYPE_GROUND, name="Transport To", action="transport_to", tooltip="Request air transport.", cursor="Transport"})
	end
end

function gadget:UnitDestroyed(unitID) unitsWaiting[unitID] = nil end
function gadget:Initialize()
	BuildDefCaches()
	for _, unitID in ipairs(Spring.GetAllUnits()) do gadget:UnitCreated(unitID, SpGetUnitDefID(unitID)) end
end
