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

-- =============================================================================
-- Performance Caches
-- =============================================================================
local transportableUnits = {} -- Cache for units that can be picked up
local transportUnits     = {} -- Cache for the 'Taxis' (Flyers with capacity)

-- =============================================================================
-- Localize Spring APIs (Performance Optimization)
-- =============================================================================
local SpInsertUnitCmdDesc = Spring.InsertUnitCmdDesc
local SpGetUnitDefID      = Spring.GetUnitDefID
local SpEcho              = Spring.Echo

-- =============================================================================
-- Cache Builder
-- =============================================================================
-- This runs once at game start to tag every unit type in the game.
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
		-- Logic: Grounded, not a building, and not explicitly marked 'cantBeTransported'
		local isGrounded = not ud.canFly
		local notBuilding = not ud.isBuilding
		local canBeCarried = (ud.cantBeTransported == nil) or (ud.cantBeTransported == false)
		
		if isGrounded and notBuilding and canBeCarried then
			transportableUnits[unitDefID] = true
		end
		
		-- Special Case: Mobile Nanos and Factories (if they meet the criteria)
		if ud.isFactory or (ud.isBuilder and not ud.canMove) then
			transportableUnits[unitDefID] = true
		end
	end
end

-- =============================================================================
-- Command Descriptor
-- =============================================================================
-- This defines how the button looks in the unit's UI panel.
local transportToCmdDesc = {
	id      = CMD_TRANSPORT_TO,
	type    = CMD_TYPE_GROUND,
	name    = "Transport To",
	action  = "transport_to",
	tooltip = "Call the nearest idle air transport to move this unit to the destination.",
	cursor  = "Transport", -- We will link this to your custom .txt cursor file later
}

-- =============================================================================
-- Gadget Callins
-- =============================================================================

function gadget:UnitCreated(unitID, unitDefID, teamID)
	-- If the unit is transportable, give it the 'Transport To' button
	if transportableUnits[unitDefID] then
		SpInsertUnitCmdDesc(unitID, transportToCmdDesc)
	end
end

function gadget:Initialize()
	BuildDefCaches()
	
	-- If the gadget is reloaded mid-game (for dev), add the button to existing units
	for _, unitID in ipairs(Spring.GetAllUnits()) do
		local unitDefID = SpGetUnitDefID(unitID)
		gadget:UnitCreated(unitID, unitDefID, Spring.GetUnitTeam(unitID))
	end
	
	SpEcho("Transport To Gadget: Initialized and Caches Built.")
end

function gadget:Shutdown()
	-- Cleanup command description on all units if gadget is disabled
	for _, unitID in ipairs(Spring.GetAllUnits()) do
		Spring.RemoveUnitCmdDesc(unitID, Spring.FindUnitCmdDesc(unitID, CMD_TRANSPORT_TO))
	end
end
