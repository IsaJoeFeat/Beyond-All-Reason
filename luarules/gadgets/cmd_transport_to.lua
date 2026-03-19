local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name      = "Transport To (Synced)",
		desc      = "Handles the core logic for units requesting a transport to a destination.",
		author    = "YourName (Refining Silla Noble's Concept)",
		date      = "2026",
		license   = "GNU GPL, v2 or later",
		layer     = 0,
		enabled   = true
	}
end

if not gadgetHandler:IsSyncedCode() then return end

-- =============================================================================
-- Constants & IDs
-- =============================================================================
local CMD_TRANSPORT_TO = 34571 
local CMD_TYPE_GROUND  = CMDTYPE.ICON_MAP 
local CMD_LOAD_UNITS   = CMD.LOAD_UNITS
local CMD_UNLOAD_UNITS = CMD.UNLOAD_UNITS
local CMD_MOVE         = CMD.MOVE

-- =============================================================================
-- State & Caches
-- =============================================================================
local transportableUnits = {} 
local transportUnits     = {} 
local unitsWaiting       = {} -- [unitID] = {pos, teamID, assignedTaxi}

local SpInsertUnitCmdDesc = Spring.InsertUnitCmdDesc
local SpGetUnitDefID      = Spring.GetUnitDefID
local SpGetUnitPosition   = Spring.GetUnitPosition
local SpGiveOrderToUnit   = Spring.GiveOrderToUnit
local SpSetUnitMoveGoal   = Spring.SetUnitMoveGoal
local SpGetUnitCommands   = Spring.GetUnitCommands
local SpEcho              = Spring.Echo

-- =============================================================================
-- Logic
-- =============================================================================

local function BuildDefCaches()
	for unitDefID, ud in pairs(UnitDefs) do
		if ud.isTransport and ud.canFly and (ud.transportCapacity or 0) > 0 then
			transportUnits[unitDefID] = true
		end
		if (not ud.canFly and not ud.isBuilding and (ud.cantBeTransported == nil or ud.cantBeTransported == false)) or ud.isFactory then
			transportableUnits[unitDefID] = true
		end
	end
end

function gadget:AllowCommand(unitID, unitDefID, teamID, cmdID, cmdParams, cmdOptions)
	if cmdID == CMD_TRANSPORT_TO then return transportableUnits[unitDefID] ~= nil end
	return true
end

function gadget:CommandFallback(unitID, unitDefID, teamID, cmdID, cmdParams, cmdOptions)
	if cmdID ~= CMD_TRANSPORT_TO then return false end

	if Spring.GetUnitTransporter(unitID) then return true, false end

	local ux, uy, uz = SpGetUnitPosition(unitID)
	local tx, ty, tz = cmdParams[1], cmdParams[2], cmdParams[3]
	local dx, dz = ux - tx, uz - tz
	if (dx*dx + dz*dz) < (35*35) then
		unitsWaiting[unitID] = nil
		return true, true 
	end

	if not unitsWaiting[unitID] then
		unitsWaiting[unitID] = { pos = {tx, ty, tz}, teamID = teamID, assignedTaxi = nil }
		SpSetUnitMoveGoal(unitID, tx, ty, tz)
	end

	if unitsWaiting[unitID].assignedTaxi then
		if not Spring.ValidUnitID(unitsWaiting[unitID].assignedTaxi) or Spring.GetUnitIsDead(unitsWaiting[unitID].assignedTaxi) then
			unitsWaiting[unitID].assignedTaxi = nil -- Taxi died, reset and search again
		else
			SpSetUnitMoveGoal(unitID, ux, uy, uz) -- Wait for pickup
		end
	end

	return true, false
end

function gadget:GameFrame(frame)
	if frame % 30 ~= 0 then return end
	for unitID, data in pairs(unitsWaiting) do
		if not data.assignedTaxi then
			local ux, uy, uz = SpGetUnitPosition(unitID)
			local bestTaxi = nil
			local minPreciseDist = math.huge
			local teamUnits = Spring.GetTeamUnits(data.teamID)
			
			for i = 1, #teamUnits do
				local tID = teamUnits[i]
				if transportUnits[SpGetUnitDefID(tID)] and #SpGetUnitCommands(tID, 0) == 0 then
					local tx, ty, tz = SpGetUnitPosition(tID)
					local dSq = (ux-tx)^2 + (uz-tz)^2
					if dSq < minPreciseDist then
						minPreciseDist = dSq
						bestTaxi = tID
					end
				end
			end

			if bestTaxi then
				data.assignedTaxi = bestTaxi
				local tx, ty, tz = SpGetUnitPosition(bestTaxi)
				SpGiveOrderToUnit(bestTaxi, CMD_LOAD_UNITS, {unitID}, {})
				SpGiveOrderToUnit(bestTaxi, CMD_UNLOAD_UNITS, {data.pos[1], data.pos[2], data.pos[3]}, {"shift"})
				SpGiveOrderToUnit(bestTaxi, CMD_MOVE, {tx, ty, tz}, {"shift"})
			end
		end
	end
end

function gadget:UnitCreated(unitID, unitDefID, teamID)
	if transportableUnits[unitDefID] then
		SpInsertUnitCmdDesc(unitID, {id=CMD_TRANSPORT_TO, type=CMD_TYPE_GROUND, name="Transport To", action="transport_to", tooltip="Call a taxi.", cursor="Transport"})
	end
end

function gadget:UnitDestroyed(unitID) unitsWaiting[unitID] = nil end

function gadget:Initialize()
	BuildDefCaches()
	for _, unitID in ipairs(Spring.GetAllUnits()) do
		gadget:UnitCreated(unitID, SpGetUnitDefID(unitID), Spring.GetUnitTeam(unitID))
	end
end
