function gadget:GetInfo()
    return {
        name = "Transport To Command",
        desc = "Adds ferry command",
        author = "You",
        date = "2026",
        license = "GPL",
        layer = 0,
        enabled = true
    }
end

if not gadgetHandler:IsSyncedCode() then
    return
end

local CMD_TRANSPORT_TO = 19990

local cmdDesc = {
    id = CMD_TRANSPORT_TO,
    type = CMDTYPE.ICON_MAP,
    name = "Ferry",
    cursor = "Attack",
    action = "ferry",
}