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

-- Only run this on the Synced side (The Simulation/Server)
if not gadgetHandler:IsSyncedCode() then
	return
end

-- =============================================================================
-- Constants & Command IDs
-- =============================================================================
local CMD_TRANSPORT_TO = 34571 -- Custom ID for the 'Taxi' command
local CMD_TYPE_GROUND  = CMDTYPE.ICON_MAP -- Map-click destination cursor
local CMD_STOP         = CMD.STOP

-- =============================================================================
-- Performance Caches & State
-- =============================================================================
local transportableUnits = {} -- Cache for unit types that can be picked up
local transportUnits     = {} -- Cache for the 'Taxis' (Flyers with capacity)

local unitsWaiting = {} -- [unitID] = {targetPos, teamID, assignedTaxiID}

-- =============================================================================
-- Localize Spring APIs (Performance Optimization)
-- =============================================================================
local SpInsertUnitCmdDesc = Spring.InsertUnitCmdDesc
local SpGetUnitDefID      = Spring.GetUnitDefID
local SpGetUnitPosition   = Spring.GetUnitPosition
local SpGiveOrderToUnit   = Spring.GiveOrderToUnit
local SpSetUnitMoveGoal   = Spring.SetUnitMoveGoal
local SpEcho              = Spring.Echo

-- =============================================================================
-- Cache Builder
-- =============================================================================
local function BuildDefCaches()
	for unitDefID, ud in pairs(UnitDefs) do
		-- 1. Identify valid flying Transports (Taxis)
		if ud.isTransport and ud.canFly and (ud.transportCapacity or 0) > 0 then
			transportUnits[unitDefID] = {
				massLimit = ud.transportMass or 0,
				sizeLimit = ud.transportSize or 0,
				slots     = ud.transportCapacity or 0
			}
		end

		-- 2. Identify Transportables (Ground units/Factories/Nanos)
		local isGrounded = not ud.canFly
		local notBuilding = not ud.isBuilding
		local canBeCarried = (ud.cantBeTransported == nil) or (ud.cantBeTransported == false)
		
		if (isGrounded and notBuilding and canBeCarried) or ud.isFactory then
			transportableUnits[unitDefID] = true
		end
	end
end

-- =============================================================================
-- Command Descriptor
-- =============================================================================
local transportToCmdDesc = {
	id      = CMD_TRANSPORT_TO,
	type    = CMD_TYPE_GROUND,
	name    = "Transport To",
	action  = "transport_to",
	tooltip = "Call the nearest idle air transport to move this unit to the destination.",
	cursor  = "Transport", 
}

-- =============================================================================
-- Callins: Command Logic
-- =============================================================================

function gadget:AllowCommand(unitID, unitDefID, teamID, cmdID, cmdParams, cmdOptions)
	if cmdID == CMD_TRANSPORT_TO then
		return transportableUnits[unitDefID] ~= nil
	end
	return true
end

function gadget:CommandFallback(unitID, unitDefID, teamID, cmdID, cmdParams, cmdOptions)
	if cmdID ~= CMD_TRANSPORT_TO then return false end

	-- 1. If the unit is currently inside a transport, it's 'in flight'
	if Spring.GetUnitTransporter(unitID) then
		return true, false -- Handled, stay in queue
	end

	-- 2. Check for arrival at destination (within 30 pixels)
	local ux, uy, uz = SpGetUnitPosition(unitID)
	local tx, ty, tz = cmdParams[1], cmdParams[2], cmdParams[3]
	local dx, dz = ux - tx, uz - tz
	local distSq = (dx * dx) + (dz * dz)

	if distSq < (30 * 30) then
		unitsWaiting[unitID] = nil
		return true, true -- Handled, remove from queue
	end

	-- 3. Manage the 'Waiting' state
	if not unitsWaiting[unitID] then
		unitsWaiting[unitID] = {
			pos = {tx, ty, tz},
			teamID = teamID,
			assignedTaxi = nil
		}
		
		-- If no taxi is assigned yet, fulfill spec: "behave as a move command"
		-- We set a move goal so the unit starts walking while waiting for a pickup.
		SpSetUnitMoveGoal(unitID, tx, ty, tz)
	end

	-- If a taxi has been assigned, we clear the move goal so it stops and waits
	if unitsWaiting[unitID].assignedTaxi then
		SpSetUnitMoveGoal(unitID, ux, uy, uz) -- Force stop
	end

	return true, false -- Handled, but not finished
end

-- =============================================================================
-- Callins: Lifecycle
-- =============================================================================

function gadget:UnitCreated(unitID, unitDefID, teamID)
	if transportableUnits[unitDefID] then
		SpInsertUnitCmdDesc(unitID, transportToCmdDesc)
	end
end

function gadget:UnitDestroyed(unitID, unitDefID, teamID)
	unitsWaiting[unitID] = nil
end

function gadget:Initialize()
	BuildDefCaches()
	for _, unitID in ipairs(Spring.GetAllUnits()) do
		local unitDefID = SpGetUnitDefID(unitID)
		gadget:UnitCreated(unitID, unitDefID, Spring.GetUnitTeam(unitID))
	end
	SpEcho("Transport To Gadget: Logic Loaded.")
end

function gadget:Shutdown()
	for _, unitID in ipairs(Spring.GetAllUnits()) do
		local cmdDescID = Spring.FindUnitCmdDesc(unitID, CMD_TRANSPORT_TO)
		if cmdDescID then Spring.RemoveUnitCmdDesc(unitID, cmdDescID) end
	end
end
