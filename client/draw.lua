VisibleMarkers = VisibleMarkers or {}

local function DrawText3D(x, y, z, text)
    -- Project world coords to screen coords
    local onScreen, sx, sy = GetScreenCoordFromWorldCoord(x, y, z)
    if not onScreen then return end

    -- This pattern is based on working RedM examples:
    -- CreateVarString + SetTextScale/Color/Centre + SetTextDropshadow + DisplayText
    local str = CreateVarString(10, "LITERAL_STRING", text)

    SetTextScale(0.30, 0.30)
    SetTextColor(255, 255, 255, 215)
    SetTextCentre(1)
    SetTextDropshadow(1, 0, 0, 0, 255)

    -- 0xADA9255D is commonly used before DisplayText in RedM 2D/3D text helpers
    Citizen.InvokeNative(0xADA9255D, 10)

    DisplayText(str, sx, sy)
end

CreateThread(function()
    while true do
        Wait(0)

        if next(VisibleMarkers) == nil then
            goto continue
        end

        local ped = PlayerPedId()
        local pCoords = GetEntityCoords(ped)
        local now = GetGameTimer()

        for _, ev in pairs(VisibleMarkers) do
            -- Stop drawing old hints, but keep markers in table
            if not ev.visibleUntil or ev.visibleUntil > now then
                local dist = #(pCoords - ev.coords)
                if dist <= (Config.HintDrawDistance or 30.0) then
                    local label = ev.label
                    if not label or label == '' then
                        label = 'Evidence'
                        if ev.type == 'casing' then
                            label = 'Casing'
                        elseif ev.type == 'blood' then
                            label = 'Blood'
                        elseif ev.type == 'fingerprint' then
                            label = 'Fingerprint'
                        end
                    end

                    DrawText3D(ev.coords.x, ev.coords.y, ev.coords.z + 0.4, label)
                end
            end
        end

        ::continue::
    end
end)

