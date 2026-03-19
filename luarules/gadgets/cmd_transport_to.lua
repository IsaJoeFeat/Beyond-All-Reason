local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name      = "Transport To (Synced)",
		desc      = "Implements the Ferry command spec for air transports.",
		author    = "Isajoefeat & Gemini",
		date      = "2026",
		license   = "GNU GPL, v2 or later",
		layer     = 0,
		enabled   = true
	}
end

if not gadgetHandler:IsSyncedCode() then return end

-- =============================================================================
-- Constants
-- =============================================================================
local CMD_TRANSPORT_TO = 34571 
local CMD_TYPE_GROUND  = CMDTYPE.ICON_MAP 
local CMD_LOAD_UNITS   = CMD.LOAD_UNITS
local CMD_UNLOAD_UNITS = CMD.UNLOAD_UNITS
local CMD_MOVE         = CMD.MOVE
local CMD_OPT_SHIFT    = CMD.OPT_SHIFT

local transportableUnits = {} 
local transportStats     = {} 
local unitStats          = {}
local unitsWaiting       = {} -- [unitID] = {pos, teamID, assignedTaxi}
local taxiHomePos        = {} -- [taxiID] = {x, y, z}

local SpGetUnitDefID      = Spring.GetUnitDefID
local SpGetUnitPosition   = Spring.GetUnitPosition
local SpGiveOrderToUnit   = Spring.GiveOrderToUnit
local SpSetUnitMoveGoal   = Spring.SetUnitMoveGoal
local SpGetUnitCommands   = Spring.GetUnitCommands
local SpSetUnitRulesParam = Spring.SetUnitRulesParam

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
	-- Transport must be empty to be 'eligible'
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
	
	-- In flight: Clear UI icon
	if Spring.GetUnitTransporter(unitID) then 
		SpSetUnitRulesParam(unitID, "waiting_for_taxi", 0, {public = true})
		return true, false 
	end

	local ux, uy, uz = SpGetUnitPosition(unitID)
	local tx, ty, tz = cmdParams[1], cmdParams[2], cmdParams[3]
	
	-- Arrival Check (Mission Complete)
	if ((ux-tx)^2 + (uz-tz)^2) < (45*45) then
		unitsWaiting[unitID] = nil
		SpSetUnitRulesParam(unitID, "waiting_for_taxi", 0, {public = true})
		return true, true 
	end

	-- Register/Update Waiting State
	if not unitsWaiting[unitID] then
		unitsWaiting[unitID] = { pos = {tx, ty, tz}, teamID = teamID, assignedTaxi = nil }
		SpSetUnitRulesParam(unitID, "waiting_for_taxi", 1, {public = true})
	end

	-- Behavior logic based on Taxi assignment
	local taxi = unitsWaiting[unitID].assignedTaxi
	if taxi and Spring.ValidUnitID(taxi) and not Spring.GetUnitIsDead(taxi) then
		local taxiCmds = SpGetUnitCommands(taxi, 1)
		if taxiCmds and #taxiCmds > 0 then
			SpSetUnitMoveGoal(unitID, ux, uy, uz) -- SPEC: Wait for pickup
		else
			-- Taxi lost its orders (player intervened), reset
			unitsWaiting[unitID].assignedTaxi = nil
		end
	else
		-- SPEC: Behavior as move command if no taxi
		SpSetUnitMoveGoal(unitID, tx, ty, tz)
		unitsWaiting[unitID].assignedTaxi = nil
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
				-- SPEC: Closest eligible idle transport
				if transportStats[SpGetUnitDefID(tID)] and #SpGetUnitCommands(tID, 0) == 0 and CanLink(tID, unitID) then
					local tx, ty, tz = SpGetUnitPosition(tID)
					local dSq = (ux-tx)^2 + (uz-tz)^2
					if dSq < minD then bestTaxi, minD = tID, dSq end
				end
			end
			
			if bestTaxi then
				data.assignedTaxi = bestTaxi
				local hx, hy, hz = SpGetUnitPosition(bestTaxi)
				taxiHomePos[bestTaxi] = {hx, hy, hz} -- SPEC: Save original position
				
				-- 1. Order: Load
				SpGiveOrderToUnit(bestTaxi, CMD_LOAD_UNITS, {unitID}, {})
				
				-- 2. Order: Chain Waypoints (SPEC: No-Drop logic)
				local unitQueue = SpGetUnitCommands(unitID, 5) -- Look at next 5 cmds
				for i = 1, #unitQueue do
					local cmd = unitQueue[i]
					if cmd.id == CMD_TRANSPORT_TO then
						local isLast = (i == #unitQueue or unitQueue[i+1].id ~= CMD_TRANSPORT_TO)
						if isLast then
							SpGiveOrderToUnit(bestTaxi, CMD_UNLOAD_UNITS, {cmd.params[1], cmd.params[2], cmd.params[3]}, {"shift"})
						else
							SpGiveOrderToUnit(bestTaxi, CMD_MOVE, {cmd.params[1], cmd.params[2], cmd.params[3]}, {"shift"})
						end
					else break end
				end
				
				-- 3. Order: Return Home (SPEC: Return to original position)
				SpGiveOrderToUnit(bestTaxi, CMD_MOVE, {hx, hy, hz}, {"shift"}) 
			end
		end
	end
end

function gadget:UnitDestroyed(unitID)
	unitsWaiting[unitID] = nil
	taxiHomePos[unitID] = nil
end

function gadget:Initialize()
	BuildDefCaches()
	
	gadgetHandler:RegisterCMDID(CMD_TRANSPORT_TO)

	local transportToCmdDesc = { 
		id      = CMD_TRANSPORT_TO, 
		type    = CMD_TYPE_GROUND, 
		name    = "Transport To", 
		action  = "transport_to", 
		tooltip = "Taxi service.", 
		cursor  = "Transport" 
	}

	for _, unitID in ipairs(Spring.GetAllUnits()) do
		local unitDefID = SpGetUnitDefID(unitID)
		if transportableUnits[unitDefID] then 
			Spring.InsertUnitCmdDesc(unitID, transportToCmdDesc) 
		end
	end
end
