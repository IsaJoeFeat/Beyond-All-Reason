local widget = widget ---@type Widget

function widget:GetInfo()
	return {
		name      = "Transport To UI",
		desc      = "Handles Taxi icons and Formation Dragging for the Transport To command.",
		author    = "Isajoefeat & Gemini",
		layer     = 0,
		enabled   = true
	}
end

local CMD_TRANSPORT_TO = 34571
local taxiIcon = "anims/cursortransport_0.png"

function widget:Initialize()
	-- Tells the engine to allow dragging lines for this custom command
	-- This makes it compatible with the standard BAR formation behavior
	Spring.SetCustomCommandDrawData(CMD_TRANSPORT_TO, "Transport", {1, 0.8, 0, 1}, true)
end

function widget:DrawWorld()
	-- Only draw icons for our own team's units
	local myUnits = Spring.GetTeamUnits(Spring.GetMyTeamID())
	
	--gl.Texture(taxiIcon)
	for i = 1, #myUnits do
		local uID = myUnits[i]
		if Spring.GetUnitRulesParam(uID, "waiting_for_taxi") == 1 then
			local x, y, z = Spring.GetUnitPosition(uID)
			if x then
				gl.PushMatrix()
				gl.Translate(x, y + 50, z)
				gl.Billboard()
				local alpha = 0.6 + 0.3 * math.sin(Spring.GetTimer() * 6)
				gl.Color(1, 1, 1, alpha)
				gl.TexRect(-12, -12, 12, 12)
				gl.PopMatrix()
			end
		end
	end
	gl.Texture(false)
	gl.Color(1, 1, 1, 1)
end
