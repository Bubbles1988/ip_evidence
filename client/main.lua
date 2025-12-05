local RSGCore = exports['rsg-core']:GetCoreObject()

RegisterNetEvent('RSGCore:Client:UpdateObject', function()
    RSGCore = exports['rsg-core']:GetCoreObject()
end)

VisibleMarkers   = VisibleMarkers or {} -- shared with draw.lua
local EvidencePrompts = {}              -- [markerId] = promptHandle
local lastHealth = nil

local function debugPrint(msg)
    if Config.Debug then
        print(('[ib_evidence] %s'):format(msg))
    end
end

local function ClearEvidencePrompts()
    for id, handle in pairs(EvidencePrompts) do
        exports['rsg-core']:deletePrompt(handle)
    end
    EvidencePrompts = {}
end

local function GetEvidenceBaseLabel(evType)
    if evType == 'casing' then
        return 'Hülse'
    elseif evType == 'blood' then
        return 'Blutspur'
    elseif evType == 'fingerprint' then
        return 'Fingerabdruck'
    end
    return 'Beweis'
end

local function GetEvidenceLabel(ev)
    if ev.label and ev.label ~= '' then
        return ev.label
    end
    return GetEvidenceBaseLabel(ev.type)
end

local function CollectEvidenceWithDialog(markerId, ev)
    if not markerId or not ev then return end

    local evLabel = GetEvidenceLabel(ev)
    local title   = ('Beweisdaten – %s'):format(evLabel)

    local input = lib.inputDialog(title, {
        { type = 'input',    label = 'Zeit/Datum', required = false },
        { type = 'input',    label = 'Fundort',    required = false },
        { type = 'textarea', label = 'Notizen',    required = false },
    })

    if not input then
        return
    end

    local collectedAt = input[1] or ''
    local scene       = input[2] or ''
    local notes       = input[3] or ''

    TriggerServerEvent('ib_evidence:server:CollectEvidence', markerId, {
        collected_at = collectedAt,
        scene        = scene,
        notes        = notes,
    })
end

--------------------------------------------------------------------
-- Shooting: send casing attempt to server
--------------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(0)
        local ped = PlayerPedId()

        if IsPedShooting(ped) then
            -- RedM-safe usage of GetCurrentPedWeapon
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

--------------------------------------------------------------------
-- Blood droplets on damage
--------------------------------------------------------------------
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

--------------------------------------------------------------------
-- Marker sync from server + RSG prompts
--------------------------------------------------------------------

RegisterNetEvent('ib_evidence:client:NewMarker', function(data)
    if not data or not data.id or not data.coords then return end

    local now = GetGameTimer()
    local ttl = Config.MarkerVisibleTime or 30000

    VisibleMarkers[data.id] = {
        id           = data.id,
        type         = data.type,
        coords       = vector3(data.coords.x, data.coords.y, data.coords.z),
        label        = data.label,
        visibleUntil = now + ttl,
    }
end)

RegisterNetEvent('ib_evidence:client:ScanResult', function(results)
    -- clear old
    VisibleMarkers = {}
    ClearEvidencePrompts()

    local now = GetGameTimer()
    local ttl = Config.MarkerVisibleTime or 30000
    local key = RSGCore.Shared.Keybinds[Config.EvidencePromptKey or 'E']

    for _, row in ipairs(results) do
        local ev = {
            id           = row.id,
            type         = row.type,
            coords       = vector3(row.x, row.y, row.z),
            label        = row.label,
            visibleUntil = now + ttl,
        }

        VisibleMarkers[row.id] = ev

        -- Create RSG prompt at evidence position
        local promptId = ('ib_evidence_%s'):format(row.id)
        local handle = exports['rsg-core']:createPrompt(
            promptId,
            ev.coords,
            key,
            ('Beweis (%s)'):format(GetEvidenceLabel(ev)),
            {
                type  = 'client',
                event = 'ib_evidence:client:PromptEvidence',
                args  = { markerId = row.id }
            }
        )

        EvidencePrompts[row.id] = handle
    end
end)

RegisterNetEvent('ib_evidence:client:RemoveMarker', function(id)
    VisibleMarkers[id] = nil
    local handle = EvidencePrompts[id]
    if handle then
        exports['rsg-core']:deletePrompt(handle)
        EvidencePrompts[id] = nil
    end
end)

-- Clean up prompts if resource stops
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        ClearEvidencePrompts()
    end
end)

--------------------------------------------------------------------
-- Prompt action (opened via RSG Alt/Eagle Eye + key)
--------------------------------------------------------------------
RegisterNetEvent('ib_evidence:client:PromptEvidence', function(data)
    local markerId = data and data.markerId
    if not markerId then return end

    local ev = VisibleMarkers[markerId]
    if not ev then
        lib.notify({ description = 'Beweis nicht mehr vorhanden.', type = 'error' })
        return
    end

    local label     = GetEvidenceLabel(ev)
    local contextId = ('ib_evidence_ctx_%s'):format(markerId)

    lib.registerContext({
        id    = contextId,
        title = ('Beweis – %s'):format(label),
        options = {
            {
                title       = 'Beweis aufnehmen',
                description = 'Sammelt diesen Beweis.',
                onSelect    = function()
                    CollectEvidenceWithDialog(markerId, ev)
                end,
            },
            {
                title       = 'Beweis entfernen',
                description = 'Säubert die Spur dauerhaft.',
                onSelect    = function()
                    TriggerServerEvent('ib_evidence:server:CleanEvidence', markerId)
                end,
            },
        }
    })

    lib.showContext(contextId)
end)

--------------------------------------------------------------------
-- Useable items
--------------------------------------------------------------------
RegisterNetEvent('ib_evidence:client:UseForensicsKit', function()
    local ped    = PlayerPedId()
    local coords = GetEntityCoords(ped)

    TriggerServerEvent('ib_evidence:server:ScanArea', {
        x = coords.x,
        y = coords.y,
        z = coords.z,
    })
end)

-- Bag: just collect nearest (prompts are for Alt/Eagle Eye)
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
        lib.notify({ description = 'Keine Beweise gefunden.', type = 'error' })
        return
    end

    local ev = VisibleMarkers[nearestId]
    if not ev then
        lib.notify({ description = 'Beweis nicht mehr vorhanden.', type = 'error' })
        return
    end

    CollectEvidenceWithDialog(nearestId, ev)
end)

RegisterNetEvent('ib_evidence:client:UseFingerprintKit', function()
    local ped     = PlayerPedId()
    local pCoords = GetEntityCoords(ped)
    local players = GetActivePlayers()
    local closestSrc
    local closestDist = Config.FingerprintRange or 3.0

    for _, pid in ipairs(players) do
        local tPed = GetPlayerPed(pid)
        if tPed ~= ped then
            local coords = GetEntityCoords(tPed)
            local dist   = #(coords - pCoords)
            if dist < closestDist then
                closestDist = dist
                closestSrc  = GetPlayerServerId(pid)
            end
        end
    end

    if closestSrc then
        TriggerServerEvent('ib_evidence:server:RegisterFingerprintCard', closestSrc)
    else
        lib.notify({ description = 'Keine Finger nahbei.', type = 'error' })
    end
end)

--------------------------------------------------------------------
-- Crime folder UI / commands
--------------------------------------------------------------------
RegisterNetEvent('ib_evidence:client:OpenCaseViewer', function(item)
    local info     = item and item.info or {}
    local evidence = info.evidence or {}
    local suspects = info.suspects or {}

    local lines = {}
    lines[#lines+1] = ('Case: %s'):format(info.case_id or 'Unknown')
    lines[#lines+1] = ('Title: %s'):format(info.title or '')
    lines[#lines+1] = ('Lead: %s'):format(info.lead_officer_name or info.lead_officer or '')
    lines[#lines+1] = ('Created: %s'):format(info.created_at or 'n/a')
    lines[#lines+1] = ''

    if info.notes and info.notes ~= '' then
        lines[#lines+1] = 'Notizen:'
        lines[#lines+1] = info.notes
        lines[#lines+1] = ''
    end

    if #suspects > 0 then
        lines[#lines+1] = 'Verdächtige:'
        for i, s in ipairs(suspects) do
            lines[#lines+1] = (('%d) %s (%s) FP: %s'):format(
                i,
                s.suspect_name or 'Unknown',
                s.suspect_cid or 'n/a',
                s.fp_code or 'n/a'
            ))
        end
        lines[#lines+1] = ''
    end

    lines[#lines+1] = 'Beweise:'
    if #evidence == 0 then
        lines[#lines+1] = '- Keine.'
    else
        for i, ev in ipairs(evidence) do
            local label = ev.label or ev.type or 'evidence'
            local loc   = ev.location or 'unbekannt'
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
        header   = info.title or 'Akten',
        content  = table.concat(lines, '\n'),
        centered = true,
    })
end)

RegisterCommand('case_new', function()
    local input = lib.inputDialog('Akte öffnen', {
        { type = 'input', label = 'Titel', required = false }
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
            local label = (item.info and item.info.title) or ('Akte #' .. slot)
            folders[#folders+1] = { value = slot, label = label }
        end
    end

    if #folders == 0 then
        lib.notify({ description = 'Ich habe keine Akten.', type = 'error' })
        return
    end

    local input = lib.inputDialog('Akte bearbeiten', {
        { type = 'select',   label = 'Akte',   options = folders, required = true },
        { type = 'textarea', label = 'Notizen', required = false },
    })
    if not input then return end

    local folderSlot = input[1]
    local notes      = input[2] or ''

    TriggerServerEvent('ib_evidence:server:SetCaseNotes', folderSlot, notes)
end, false)

RegisterNetEvent('ib_evidence:client:AttachMenu', function(folders, evidence)
    if not folders or #folders == 0 then
        lib.notify({ description = 'Ich hab keine Akten.', type = 'error' })
        return
    end
    if not evidence or #evidence == 0 then
        lib.notify({ description = 'Ich habe keine Beweise.', type = 'error' })
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

    local input = lib.inputDialog('Beweise ablegen', {
        { type = 'select',       label = 'Akte',    options = folderOptions, required = true },
        { type = 'multi-select', label = 'Beweise', options = evidenceOptions, required = true },
    })
    if not input then return end

    local folderSlot    = input[1]
    local evidenceSlots = input[2]

    if not folderSlot or not evidenceSlots or #evidenceSlots == 0 then
        lib.notify({ description = 'Fehlerhaft.', type = 'error' })
        return
    end

    TriggerServerEvent('ib_evidence:server:AttachEvidence', folderSlot, evidenceSlots)
end)
