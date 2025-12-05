Config = {}

-- General evidence behaviour
Config.CasingDropChance = 0.30          -- 30% chance a casing spawns when shooting
Config.MaxCasingsPerPlayer = 5          -- per suspect
Config.MaxCasingsGlobal = 50            -- server-wide

-- Only for weapons that actually use ammo.
-- Fill with the hashes you use on your server (examples below).
Config.WeaponsThatDropCasings = {
    [`WEAPON_REVOLVER_CATTLEMAN`] = true,
    [`WEAPON_PISTOL_MAUSER`] = true,
    [`WEAPON_REPEATER_WINCHESTER`] = true,
    [`WEAPON_RIFLE_SPRINGFIELD`] = true,
    -- add others…
}

Config.WeaponLabels = {
    [`WEAPON_REVOLVER_CATTLEMAN`]   = 'Cattleman Revolver',
    [`WEAPON_PISTOL_MAUSER`]       = 'Mauser Pistol',
    [`WEAPON_REPEATER_WINCHESTER`] = 'Winchester Repeater',
    [`WEAPON_RIFLE_SPRINGFIELD`]   = 'Springfield Rifle',
    -- add all weapons you use
}



-- Fingerprints / Blood
Config.BloodOnDamage = true
Config.BloodMinHealthLoss = 5           -- health drop required to spawn blood

-- Scan / visuals
Config.ForensicsRange = 20.0            -- scan radius (meters)
Config.NearbyPickupDistance = 2.0       -- distance to pick up evidence
Config.HintDrawDistance = 30.0          -- max distance to draw hint text

-- How long world evidence (not collected) stays before auto removal (seconds).
-- 60 * 60 = 1 hour. Set to 0 to disable auto removal.
Config.EvidenceLifetime = 60 * 60

-- Law jobs allowed to use forensic tools & folders
Config.LawJobs = {
    vallaw = true,
    rholaw = true,
    blklaw = true,
    -- add others…
}

-- Items used by this resource
Config.ForensicsKitItem    = 'forensics_kit'
Config.EvidenceBagItem     = 'evidence_bag'
Config.FingerprintKitItem  = 'fingerprint_kit'

-- Evidence items created when collecting
Config.EvidenceItems = {
    casing      = 'evidence_casing',
    blood       = 'evidence_blood',
    fingerprint = 'evidence_fingerprint',
}

-- Fingerprint card for suspects
Config.FingerprintCardItem = 'fingerprint_card'

-- Crime folder item
Config.CrimeFolderItem = 'crime_folder'

-- Max distance to fingerprint another player
Config.FingerprintRange = 3.0

-- How long (ms) hints stay rendered after a scan
Config.MarkerVisibleTime = 30 * 1000  -- 30 seconds


Config.Debug = false


-- Optional: labels for casing hints
Config.WeaponLabels = {
    [`WEAPON_REVOLVER_CATTLEMAN`] = 'Cattleman casing',
    [`WEAPON_PISTOL_MAUSER`] = 'Mauser casing',
    [`WEAPON_REPEATER_WINCHESTER`] = 'Repeater casing',
    [`WEAPON_RIFLE_SPRINGFIELD`] = 'Springfield casing',
}
