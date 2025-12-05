ib_evidence - Evidence & Crime Folder system for RSG Core / rsg-lawman

Version: 1.2.3

Fixes from 1.2.2:
- Replaced GTA-style SetTextColour with RedM's SetTextColor.
- Switched to GetGameplayCamCoords and a 3D text pattern verified in current
  RedM community examples (GetScreenCoordFromWorldCoord + CreateVarString + DisplayText).

Core behaviour:
- World evidence markers (casings, blood, fingerprints) are persisted in the database
  table `ib_evidence_markers` so they survive server restarts.
- Each marker has a lifetime (Config.EvidenceLifetime, default 60 minutes). Expired
  entries are removed from memory and DB automatically.
- Collected evidence is turned into inventory items and can be attached into
  crime_folder items, which store full case info in their metadata until destroyed/lost.
