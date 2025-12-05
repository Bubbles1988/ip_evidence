local RSGCore = exports['rsg-core']:GetCoreObject()

RegisterNetEvent('RSGCore:Server:UpdateObject', function()
    RSGCore = exports['rsg-core']:GetCoreObject()
end)

-- In-memory evidence markers ------------------------------------

local EvidenceMarkers = {}   -- [id] = { id, type, coords = vector3, createdBy, meta = {}, createdAt }
local PlayerCasings  = {}   -- [citizenid] = count
local TotalCasings   = 0

local function debugPrint(msg)
    if Config.Debug then
        print(('[ib_evidence] %s'):format(msg))
    end
end

local function isLawJob(job)
    return job and Config.LawJobs[job] == true
end

local function WeaponUsesAmmo(weaponHash)
    return Config.WeaponsThatDropCasings[weaponHash] == true
end

local function GenerateFingerprintCode(citizenid)
    if not citizenid or citizenid == '' then
        return ('FP-%03d-%03d'):format(math.random(0, 999), math.random(0, 999))
    end

    local sum = 0
    for i = 1, #citizenid do
        sum = sum + string.byte(citizenid, i)
    end

    local a = sum % 1000
    local b = (sum * 7) % 1000
    return ('FP-%03d-%03d'):format(a, b)
end

local function RemoveEvidenceMarker(id)
    local ev = EvidenceMarkers[id]
    if not ev then return end

    if ev.type == 'casing' and ev.createdBy then
        local cid = ev.createdBy
        PlayerCasings[cid] = PlayerCasings[cid] or 0
        if PlayerCasings[cid] > 0 then
            PlayerCasings[cid] = PlayerCasings[cid] - 1
        end
        if TotalCasings > 0 then
            TotalCasings = TotalCasings - 1
        end
    end

    EvidenceMarkers[id] = nil
    TriggerClientEvent('ib_evidence:client:RemoveMarker', -1, id)
    MySQL.update('DELETE FROM ib_evidence_markers WHERE id = ?', { id })
end

local function NewEvidenceMarker(evType, coords, citizenid, meta)
    local createdAt = os.time()
    local metaJson  = meta and json.encode(meta) or '[]'

    local id = MySQL.insert.await(
        'INSERT INTO ib_evidence_markers (`type`,`x`,`y`,`z`,`created_by`,`meta`,`created_at`) VALUES (?,?,?,?,?,?,?)',
        { evType, coords.x, coords.y, coords.z, citizenid, metaJson, createdAt }
    )

    if not id then
        debugPrint(('Failed to insert evidence marker type=%s'):format(evType))
        return nil
    end

    EvidenceMarkers[id] = {
        id        = id,
        type      = evType,
        coords    = coords,
        createdBy = citizenid,
        meta      = meta or {},
        createdAt = createdAt,
    }

    debugPrint(('New evidence #%d type=%s at (%.2f, %.2f, %.2f)'):format(
        id, evType, coords.x, coords.y, coords.z
    ))

    if evType == 'casing' and citizenid then
        PlayerCasings[citizenid] = PlayerCasings[citizenid] or 0
        PlayerCasings[citizenid] = PlayerCasings[citizenid] + 1
        TotalCasings             = TotalCasings + 1
    end

    return id
end

local function LoadEvidenceFromDB()
    local rows = MySQL.query.await('SELECT * FROM ib_evidence_markers', {})
    if not rows or #rows == 0 then
        debugPrint('No evidence markers loaded from DB.')
        return
    end

    local now = os.time()

    for _, row in ipairs(rows) do
        local createdAt = row.created_at or now
        local expired   = false

        if Config.EvidenceLifetime and Config.EvidenceLifetime > 0 then
            if (now - createdAt) > Config.EvidenceLifetime then
                expired = true
            end
        end

        if expired then
            MySQL.update('DELETE FROM ib_evidence_markers WHERE id = ?', { row.id })
        else
            local v = vector3(row.x + 0.0, row.y + 0.0, row.z + 0.0)
            local meta = {}
            if row.meta and row.meta ~= '' then
                local ok, decoded = pcall(json.decode, row.meta)
                if ok and decoded then
                    meta = decoded
                end
            end

            EvidenceMarkers[row.id] = {
                id        = row.id,
                type      = row.type,
                coords    = v,
                createdBy = row.created_by,
                meta      = meta,
                createdAt = createdAt,
            }

            if row.type == 'casing' and row.created_by then
                PlayerCasings[row.created_by] = PlayerCasings[row.created_by] or 0
                PlayerCasings[row.created_by] = PlayerCasings[row.created_by] + 1
                TotalCasings                  = TotalCasings + 1
            end
        end
    end

    debugPrint(('Loaded %d evidence markers from DB.'):format(#rows))
end

CreateThread(function()
    Wait(2000)
    LoadEvidenceFromDB()

    if Config.EvidenceLifetime and Config.EvidenceLifetime > 0 then
        while true do
            Wait(60000) -- check every minute
            local now = os.time()
            for id, ev in pairs(EvidenceMarkers) do
                if (now - (ev.createdAt or now)) > Config.EvidenceLifetime then
                    debugPrint(('Evidence #%d expired (type=%s)'):format(id, ev.type))
                    RemoveEvidenceMarker(id)
                end
            end
        end
    end
end)

-- Exports for other resources (doors, crates, etc.) --------------

exports('CreateFingerprintAtCoords', function(src, coords, locationLabel)
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid
    local charinfo  = Player.PlayerData.charinfo or {}
    local fullname  = ((charinfo.firstname or '') ..
        ' ' ..
        (charinfo.lastname or '')):gsub('^%s+', '')

    local fpCode = GenerateFingerprintCode(citizenid)

    local meta = {
        fp_code      = fpCode,
        location     = locationLabel or 'Unknown surface',
        suspect_cid  = citizenid,
        suspect_name = fullname ~= '' and fullname or nil,
    }

    local v  = vector3(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
    local id = NewEvidenceMarker('fingerprint', v, citizenid, meta)
    if not id then return end
end)

-- Shooting: attempt to create casing -----------------------------

RegisterNetEvent('ib_evidence:server:TryCreateCasing', function(weaponHash, coords)
    local src = source
    if not src then return end

    if math.random() > Config.CasingDropChance then return end
    if not WeaponUsesAmmo(weaponHash) then return end

    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid
    PlayerCasings[citizenid] = PlayerCasings[citizenid] or 0
    if PlayerCasings[citizenid] >= Config.MaxCasingsPerPlayer then return end
    if TotalCasings >= Config.MaxCasingsGlobal then return end

    local v = vector3(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)

    local meta = {
        weapon   = weaponHash,
        location = ('%.1f / %.1f'):format(v.x, v.y),
    }

    -- readable weapon label for later
    if Config.WeaponLabels and Config.WeaponLabels[weaponHash] then
        meta.weapon_label = Config.WeaponLabels[weaponHash]
    else
        meta.weapon_label = tostring(weaponHash)
    end

    local id = NewEvidenceMarker('casing', v, citizenid, meta)
    if not id then return end
end)

-- Blood droplets -------------------------------------------------

RegisterNetEvent('ib_evidence:server:CreateBloodDrop', function(coords)
    local src = source
    if not src then return end

    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid
    local v         = vector3(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)

    local meta = {
        location = ('%.1f / %.1f'):format(v.x, v.y),
    }

    local id = NewEvidenceMarker('blood', v, citizenid, meta)
    if not id then return end
end)

-- Forensics scan -------------------------------------------------

RegisterNetEvent('ib_evidence:server:ScanArea', function(coords)
    local src    = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local job = Player.PlayerData.job and Player.PlayerData.job.name
    if not isLawJob(job) then
        debugPrint(('Player %d tried to scan without law job (%s)'):format(src, tostring(job)))
        return
    end

    local hasKit = exports['rsg-inventory']:HasItem(src, Config.ForensicsKitItem, 1)
    if not hasKit then
        TriggerClientEvent('ox_lib:notify', src, {
            description = 'Du brauchst die passende Ausrüstung.',
            type        = 'error'
        })
        return
    end

    local v = vector3(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
    local r = Config.ForensicsRange

    local results = {}

    for id, ev in pairs(EvidenceMarkers) do
        local dist = #(v - ev.coords)
        if dist <= r then
            local label = 'Beweise'

            if ev.type == 'casing' then
                local meta = ev.meta or {}
                if meta.weapon_label then
                    label = meta.weapon_label .. ' casing'
                else
                    label = 'Hülse'
                end
            elseif ev.type == 'blood' then
                label = 'Blut'
            elseif ev.type == 'fingerprint' then
                label = 'Fingerabdruck'
            end

            results[#results+1] = {
                id    = id,
                type  = ev.type,
                x     = ev.coords.x,
                y     = ev.coords.y,
                z     = ev.coords.z,
                label = label,
            }
        end
    end

    TriggerClientEvent('ib_evidence:client:ScanResult', src, results)
end)

-- Collect evidence with evidence_bag -----------------------------

RegisterNetEvent('ib_evidence:server:CollectEvidence', function(markerId, details)
    local src    = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local job = Player.PlayerData.job and Player.PlayerData.job.name
    if not isLawJob(job) then
        debugPrint(('Player %d tried to collect evidence without law job (%s)'):format(src, tostring(job)))
        return
    end

    local hasBag = exports['rsg-inventory']:HasItem(src, Config.EvidenceBagItem, 1)
    if not hasBag then
        TriggerClientEvent('ox_lib:notify', src, {
            description = 'Ich brauche eine Tüte.',
            type        = 'error'
        })
        return
    end

    local ev = EvidenceMarkers[markerId]
    if not ev then
        TriggerClientEvent('ox_lib:notify', src, {
            description = 'Beweise nicht gefunden.',
            type        = 'error'
        })
        return
    end

    local itemName = Config.EvidenceItems[ev.type]
    if not itemName then
        TriggerClientEvent('ox_lib:notify', src, {
            description = 'Unbekannte Beweise.',
            type        = 'error'
        })
        debugPrint(('Evidence #%s has unknown type %s'):format(tostring(markerId), tostring(ev.type)))
        return
    end

    details = type(details) == 'table' and details or {}

    local charinfo    = Player.PlayerData.charinfo or {}
    local officerName = ((charinfo.firstname or '') ..
        ' ' ..
        (charinfo.lastname or '')):gsub('^%s+', '')

    local meta = ev.meta or {}

    -- Weapon label (from Config.WeaponLabels) if available
    local weaponLabel = meta.weapon_label
    if not weaponLabel and meta.weapon and Config.WeaponLabels and Config.WeaponLabels[meta.weapon] then
        weaponLabel = Config.WeaponLabels[meta.weapon]
    end

    -- Scene / location text
    local scene = details.scene
    if not scene or scene == '' then
        scene = meta.location or ('%.1f / %.1f'):format(ev.coords.x, ev.coords.y)
    end

    -- Collected at (text shown to officers)
    local collectedAtText = details.collected_at
    if not collectedAtText or collectedAtText == '' then
        collectedAtText = os.date('%Y-%m-%d %H:%M')
    end

    local notes = details.notes or ''

    -- Human-readable base label for the item
    local baseLabel
    if ev.type == 'casing' then
        baseLabel = (weaponLabel and (weaponLabel .. 'casing')) or 'Patrone'
    elseif ev.type == 'blood' then
        baseLabel = 'Blut'
    elseif ev.type == 'fingerprint' then
        baseLabel = 'Fingerabdruck'
    else
        baseLabel = ev.type
    end

    -- User-facing metadata
    local info = {
        label        = baseLabel,
        scene        = scene,
        collected_at = collectedAtText,
        notes        = notes,
        weapon       = weaponLabel,

        -- Technical/internal metadata (used for crime folder, not for tooltip)
        internal = {
            type              = ev.type,
            created_by        = ev.createdBy,
            location_raw      = meta.location,
            collected_by      = Player.PlayerData.citizenid,
            collected_by_name = officerName,
            collected_at_ts   = os.time(),
            weapon_hash       = meta.weapon,
            fp_code           = meta.fp_code,
            dna_code          = meta.dna_code,
        }
    }

    exports['rsg-inventory']:AddItem(src, itemName, 1, nil, info)
    RemoveEvidenceMarker(markerId)

    debugPrint(('Player %d collected evidence #%s (%s) -> item %s'):format(
        src, tostring(markerId), tostring(ev.type), itemName
    ))
end)


-- Fingerprint kit: create fingerprint card -----------------------

RegisterNetEvent('ib_evidence:server:RegisterFingerprintCard', function(targetId)
    local src     = source
    local Officer = RSGCore.Functions.GetPlayer(src)
    if not Officer then return end

    local job = Officer.PlayerData.job and Officer.PlayerData.job.name
    if not isLawJob(job) then return end

    local hasKit = exports['rsg-inventory']:HasItem(src, Config.FingerprintKitItem, 1)
    if not hasKit then
        TriggerClientEvent('ox_lib:notify', src, {
            description = 'Ich brauche Tinte und Papier.',
            type        = 'error'
        })
        return
    end

    local Target = RSGCore.Functions.GetPlayer(targetId)
    if not Target then
        TriggerClientEvent('ox_lib:notify', src, {
            description = 'Target not found.',
            type        = 'error'
        })
        return
    end

    local tCid  = Target.PlayerData.citizenid
    local tInfo = Target.PlayerData.charinfo or {}
    local tName = ((tInfo.firstname or '') ..
        ' ' ..
        (tInfo.lastname or '')):gsub('^%s+', '')

    local fpCode = GenerateFingerprintCode(tCid)

    local officerInfo = Officer.PlayerData.charinfo or {}
    local officerName = ((officerInfo.firstname or '') ..
        ' ' ..
        (officerInfo.lastname or '')):gsub('^%s+', '')

    local info = {
        suspect_cid   = tCid,
        suspect_name  = tName,
        fp_code       = fpCode,
        taken_at      = os.time(),
        taken_by      = Officer.PlayerData.citizenid,
        taken_by_name = officerName,
        notes         = '',
    }

    exports['rsg-inventory']:AddItem(src, Config.FingerprintCardItem, 1, nil, info)

    TriggerClientEvent('ox_lib:notify', src, {
        description = ('Fingerabdruck erhalten: %s'):format(fpCode),
        type        = 'success'
    })
end)

-- Crime folders --------------------------------------------------

RegisterNetEvent('ib_evidence:server:CreateCaseFolder', function(title)
    local src    = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local job = Player.PlayerData.job and Player.PlayerData.job.name
    if not isLawJob(job) then return end

    local cid     = Player.PlayerData.citizenid
    local caseId  = ('%s-%03d'):format(os.date('%y%m%d'), math.random(1, 999))
    local charinfo = Player.PlayerData.charinfo or {}
    local officerName = ((charinfo.firstname or '') ..
        ' ' ..
        (charinfo.lastname or '')):gsub('^%s+', '')

    local info = {
        case_id          = caseId,
        title            = title ~= '' and title or ('Case ' .. caseId),
        lead_officer     = cid,
        lead_officer_name= officerName,
        created_at       = os.date('%Y-%m-%d %H:%M'),
        notes            = '',
        evidence         = {},
        suspects         = {},
    }

    exports['rsg-inventory']:AddItem(src, Config.CrimeFolderItem, 1, nil, info)

    TriggerClientEvent('ox_lib:notify', src, {
        description = ('Akte erstellt: %s'):format(info.title),
        type        = 'success'
    })
end)

RegisterNetEvent('ib_evidence:server:OpenAttachMenu', function()
    local src    = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local job = Player.PlayerData.job and Player.PlayerData.job.name
    if not isLawJob(job) then return end

    local folders  = {}
    local evidence = {}

    local items = Player.PlayerData.items or {}

    for slot, item in pairs(items) do
        if item and item.name == Config.CrimeFolderItem then
            local label = (item.info and item.info.title) or ('Folder #' .. slot)
            folders[#folders+1] = { slot = slot, label = label }
        elseif item and (item.name == Config.EvidenceItems.casing
            or item.name == Config.EvidenceItems.blood
            or item.name == Config.EvidenceItems.fingerprint
            or item.name == Config.FingerprintCardItem) then

            local label = item.name .. ' (slot ' .. slot .. ')'
            evidence[#evidence+1] = {
                slot = slot,
                label = label,
                name  = item.name,
            }
        end
    end

    TriggerClientEvent('ib_evidence:client:AttachMenu', src, folders, evidence)
end)

RegisterNetEvent('ib_evidence:server:AttachEvidence', function(folderSlot, evidenceSlots)
    local src    = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local job = Player.PlayerData.job and Player.PlayerData.job.name
    if not isLawJob(job) then return end

    local folderItem = exports['rsg-inventory']:GetItemBySlot(src, folderSlot)
    if not folderItem or folderItem.name ~= Config.CrimeFolderItem then return end

    local folderInfo = folderItem.info or {}
    folderInfo.evidence = folderInfo.evidence or {}
    folderInfo.suspects = folderInfo.suspects or {}

    local items = Player.PlayerData.items or {}

    for _, slot in ipairs(evidenceSlots) do
        slot = tonumber(slot)
        local item = items[slot]

        if item then
            local info = item.info or {}

            if item.name == Config.FingerprintCardItem then
                folderInfo.suspects[#folderInfo.suspects+1] = {
                    suspect_cid  = info.suspect_cid,
                    suspect_name = info.suspect_name,
                    fp_code      = info.fp_code,
                    notes        = info.notes or '',
                }
            else
                local internal = info.internal or {}

                folderInfo.evidence[#folderInfo.evidence+1] = {
                    label             = info.label or info.type or item.name,
                    type              = internal.type or info.type or item.name,
                    location          = info.scene or info.location or internal.location_raw or 'Unknown',
                    collected_at      = info.collected_at or internal.collected_at_ts or 'n/a',
                    collected_by      = internal.collected_by,
                    collected_by_name = internal.collected_by_name,
                    fp_code           = internal.fp_code,
                    dna_code          = internal.dna_code,
                    weapon            = info.weapon or internal.weapon_hash,
                    custom_notes      = info.notes or internal.custom_notes or '',
                }
            end

            exports['rsg-inventory']:RemoveItem(src, item.name, 1, slot)
        end
    end

    exports['rsg-inventory']:RemoveItem(src, Config.CrimeFolderItem, 1, folderSlot)
    exports['rsg-inventory']:AddItem(src, Config.CrimeFolderItem, 1, nil, folderInfo)

    TriggerClientEvent('ox_lib:notify', src, {
        description = ('Beweise beigefügt %s'):format(folderInfo.case_id or ''),
        type        = 'success'
    })
end)

-- Case notes -----------------------------------------------------

RegisterNetEvent('ib_evidence:server:SetCaseNotes', function(folderSlot, notes)
    local src    = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local job = Player.PlayerData.job and Player.PlayerData.job.name
    if not isLawJob(job) then return end

    local folderItem = exports['rsg-inventory']:GetItemBySlot(src, folderSlot)
    if not folderItem or folderItem.name ~= Config.CrimeFolderItem then
        return
    end

    local info = folderItem.info or {}
    info.notes = notes or ''

    exports['rsg-inventory']:RemoveItem(src, Config.CrimeFolderItem, 1, folderSlot)
    exports['rsg-inventory']:AddItem(src, Config.CrimeFolderItem, 1, nil, info)

    TriggerClientEvent('ox_lib:notify', src, {
        description = 'Akte angepasst.',
        type        = 'success'
    })
end)

-- Useable items --------------------------------------------------

RSGCore.Functions.CreateUseableItem(Config.ForensicsKitItem, function(source, item)
    TriggerClientEvent('ib_evidence:client:UseForensicsKit', source)
end)

RSGCore.Functions.CreateUseableItem(Config.EvidenceBagItem, function(source, item)
    TriggerClientEvent('ib_evidence:client:UseEvidenceBag', source)
end)

RSGCore.Functions.CreateUseableItem(Config.FingerprintKitItem, function(source, item)
    TriggerClientEvent('ib_evidence:client:UseFingerprintKit', source)
end)

RSGCore.Functions.CreateUseableItem(Config.CrimeFolderItem, function(source, item)
    TriggerClientEvent('ib_evidence:client:OpenCaseViewer', source, item)
end)
