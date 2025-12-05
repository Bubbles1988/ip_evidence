local RSGCore = exports['rsg-core']:GetCoreObject()

RegisterNetEvent('RSGCore:Client:UpdateObject', function()
    RSGCore = exports['rsg-core']:GetCoreObject()
end)

VisibleMarkers = VisibleMarkers or {}   -- shared with draw.lua

local lastHealth = nil

local function debugPrint(msg)
    if Config.Debug then
        print(('[ib_evidence] %s'):format(msg))
    end
end

-- Shooting: send casing attempt to server ------------------------

CreateThread(function()
    while true do
        Wait(0)
        local ped = PlayerPedId()
        if IsPedShooting(ped) then
            -- RedM-safe usage of GetCurrentPedWeapon:
            -- returns (retval, weaponHash)
            local _, weaponHash = GetCurrentPedWeapon(ped, true, 0, false)
            if weaponHash and weaponHash ~= 0 then
                local coords = GetEntityCoords(ped)
                TriggerServerEvent('ib_evidence:server:TryCreateCasing', weaponHash, {
                    x = coords.x,
                    y = coords.y,
                    z = coords.z,
                })
            end
            Wait(200)
        end
    end
end)

-- Blood droplets on damage ---------------------------------------

CreateThread(function()
    local ped = PlayerPedId()
    lastHealth = GetEntityHealth(ped)

    while true do
        Wait(500)
        ped = PlayerPedId()
        local health = GetEntityHealth(ped)

        if Config.BloodOnDamage and health < lastHealth then
            local loss = lastHealth - health
            if loss >= Config.BloodMinHealthLoss then
                local coords = GetEntityCoords(ped)
                TriggerServerEvent('ib_evidence:server:CreateBloodDrop', {
                    x = coords.x,
                    y = coords.y,
                    z = coords.z,
                })
            end
        end

        lastHealth = health
    end
end)

-- Marker sync from server ----------------------------------------

RegisterNetEvent('ib_evidence:client:NewMarker', function(data)
    if not data or not data.id or not data.coords then return end
    VisibleMarkers[data.id] = {
        id    = data.id,
        type  = data.type,
        coords = vector3(data.coords.x, data.coords.y, data.coords.z),
        label = data.label,
        visibleUntil = GetGameTimer() + (Config.MarkerVisibleTime or 30000),
    }
end)


RegisterNetEvent('ib_evidence:client:ScanResult', function(results)
    VisibleMarkers = {}
    local now = GetGameTimer()
    local ttl = Config.MarkerVisibleTime or 30000

    for _, row in ipairs(results) do
        VisibleMarkers[row.id] = {
            id    = row.id,
            type  = row.type,
            coords = vector3(row.x, row.y, row.z),
            label = row.label,
            visibleUntil = now + ttl,
        }
    end
end)


RegisterNetEvent('ib_evidence:client:RemoveMarker', function(id)
    VisibleMarkers[id] = nil
end)

-- Useable items --------------------------------------------------

RegisterNetEvent('ib_evidence:client:UseForensicsKit', function()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    TriggerServerEvent('ib_evidence:server:ScanArea', {
        x = coords.x,
        y = coords.y,
        z = coords.z,
    })
end)

RegisterNetEvent('ib_evidence:client:UseEvidenceBag', function()
    local ped     = PlayerPedId()
    local pCoords = GetEntityCoords(ped)

    local nearestId, nearestDist
    nearestDist = Config.NearbyPickupDistance or 2.0

    for id, ev in pairs(VisibleMarkers) do
        local dist = #(pCoords - ev.coords)
        if dist < nearestDist then
            nearestId  = id
            nearestDist = dist
        end
    end

    if not nearestId then
        lib.notify({ description = 'No evidence close enough to collect.', type = 'error' })
        return
    end

    -- Ask the officer to tag the evidence
    local input = lib.inputDialog('Tag evidence', {
        { type = 'input',    label = 'Collected at (time/date)', required = false },
        { type = 'input',    label = 'Location / Scene',         required = false },
        { type = 'textarea', label = 'Custom Notes',             required = false },
    })

    if not input then
        -- dialog cancelled
        return
    end

    local collectedAt = input[1] or ''
    local scene       = input[2] or ''
    local notes       = input[3] or ''

    TriggerServerEvent('ib_evidence:server:CollectEvidence', nearestId, {
        collected_at = collectedAt,
        scene        = scene,
        notes        = notes,
    })
end)


RegisterNetEvent('ib_evidence:client:UseFingerprintKit', function()
    local ped = PlayerPedId()
    local pCoords = GetEntityCoords(ped)

    local players = GetActivePlayers()
    local closestSrc
    local closestDist = Config.FingerprintRange or 3.0

    for _, pid in ipairs(players) do
        local tPed = GetPlayerPed(pid)
        if tPed ~= ped then
            local coords = GetEntityCoords(tPed)
            local dist = #(coords - pCoords)
            if dist < closestDist then
                closestDist = dist
                closestSrc = GetPlayerServerId(pid)
            end
        end
    end

    if closestSrc then
        TriggerServerEvent('ib_evidence:server:RegisterFingerprintCard', closestSrc)
    else
        lib.notify({
            description = 'No player close enough to fingerprint.',
            type = 'error'
        })
    end
end)

-- Crime folder UI ------------------------------------------------

RegisterNetEvent('ib_evidence:client:OpenCaseViewer', function(item)
    local info     = item and item.info or {}
    local evidence = info.evidence or {}
    local suspects = info.suspects or {}

    local lines = {}
    lines[#lines+1] = ('Case: %s'):format(info.case_id or 'Unknown')
    lines[#lines+1] = ('Title: %s'):format(info.title or '')
    lines[#lines+1] = ('Lead: %s'):format(info.lead_officer_name or info.lead_officer or '')
    -- created_at is printed raw (number or string), no os.date on client
    lines[#lines+1] = ('Created: %s'):format(info.created_at or 'n/a')
    lines[#lines+1] = ''

    if info.notes and info.notes ~= '' then
        lines[#lines+1] = 'Notes:'
        lines[#lines+1] = info.notes
        lines[#lines+1] = ''
    end

    if #suspects > 0 then
        lines[#lines+1] = 'Suspects:'
        for i, s in ipairs(suspects) do
            lines[#lines+1] = (('%d) %s (%s)  FP: %s'):format(
                i,
                s.suspect_name or 'Unknown',
                s.suspect_cid or 'n/a',
                s.fp_code or 'n/a'
            ))
        end
        lines[#lines+1] = ''
    end

        lines[#lines+1] = 'Evidence:'
    if #evidence == 0 then
        lines[#lines+1] = '- None attached.'
    else
        for i, ev in ipairs(evidence) do
            local label = ev.label or ev.type or 'evidence'
            local loc   = ev.location or 'unknown location'
            local when  = ev.collected_at or 'n/a'
            local by    = ev.collected_by_name or ev.collected_by or 'n/a'
            local extra = ''

            if ev.weapon then
                extra = extra .. (' WEAPON:%s'):format(ev.weapon)
            end
            if ev.custom_notes and ev.custom_notes ~= '' then
                extra = extra .. (' | NOTES:%s'):format(ev.custom_notes)
            end

            lines[#lines+1] = (('%d) [%s] %s (by %s at %s)%s'):format(
                i, label, loc, by, when, extra
            ))
        end
    end

    lib.alertDialog({
        header   = info.title or 'Case file',
        content  = table.concat(lines, '\n'),
        centered = true,
    })
end)


-- Commands: create folder & attach evidence ----------------------

RegisterCommand('case_new', function()
    local input = lib.inputDialog('Create Case Folder', {
        { type = 'input', label = 'Title', required = false }
    })
    if not input then return end
    TriggerServerEvent('ib_evidence:server:CreateCaseFolder', input[1] or '')
end, false)

RegisterCommand('case_attach', function()
    TriggerServerEvent('ib_evidence:server:OpenAttachMenu')
end, false)

RegisterCommand('case_note', function()
    local player = RSGCore.Functions.GetPlayerData()
    if not player then return end

    local items   = player.items or {}
    local folders = {}

    for slot, item in pairs(items) do
        if item and item.name == Config.CrimeFolderItem then
            local label = (item.info and item.info.title) or ('Folder #' .. slot)
            folders[#folders+1] = { value = slot, label = label }
        end
    end

    if #folders == 0 then
        lib.notify({ description = 'You have no crime folders.', type = 'error' })
        return
    end

    local input = lib.inputDialog('Edit case notes', {
        { type = 'select',   label = 'Crime Folder', options = folders, required = true },
        { type = 'textarea', label = 'Notes',        required = false },
    })

    if not input then return end

    local folderSlot = input[1]
    local notes      = input[2] or ''

    TriggerServerEvent('ib_evidence:server:SetCaseNotes', folderSlot, notes)
end, false)


RegisterNetEvent('ib_evidence:client:AttachMenu', function(folders, evidence)
    if not folders or #folders == 0 then
        lib.notify({ description = 'You have no crime folders.', type = 'error' })
        return
    end
    if not evidence or #evidence == 0 then
        lib.notify({ description = 'You have no loose evidence.', type = 'error' })
        return
    end

    local folderOptions = {}
    for _, f in ipairs(folders) do
        folderOptions[#folderOptions+1] = { value = f.slot, label = f.label }
    end

    local evidenceOptions = {}
    for _, e in ipairs(evidence) do
        evidenceOptions[#evidenceOptions+1] = { value = e.slot, label = e.label }
    end

    local input = lib.inputDialog('Attach Evidence to Case', {
        { type = 'select', label = 'Crime Folder', options = folderOptions, required = true },
        { type = 'multi-select', label = 'Evidence Items', options = evidenceOptions, required = true },
    })

    if not input then return end

    local folderSlot = input[1]
    local evidenceSlots = input[2]

    if not folderSlot or not evidenceSlots or #evidenceSlots == 0 then
        lib.notify({ description = 'Selection incomplete.', type = 'error' })
        return
    end

    TriggerServerEvent('ib_evidence:server:AttachEvidence', folderSlot, evidenceSlots)
end)
