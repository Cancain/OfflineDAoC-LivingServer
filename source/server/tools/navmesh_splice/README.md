# Navmesh tile compare and splice

`navdiff.py` compares two Detour MSET `.nav` files tile by tile and can splice tiles from a
freshly built mesh into an installed one.

```
python navdiff.py <a.nav> <b.nav>        # tiles only in A/B, differing tiles with world bounds
```

```python
from navdiff import splice
splice("installed.nav", "built.nav", "out.nav", x, y, half)  # tiles touching the square
```

`splice` keeps the installed file's header, tile order, tile refs and padding bytes, and only
swaps the tile data of the picked tiles. Splicing nothing (`half=-1`) reproduces the installed
file byte for byte; check that before trusting a splice. Detour joins neighbouring tiles by
matching their shared border edges at load, so always verify the seams with a real-Detour
probe (for example `UT_SiPortalPlatformProbe` or `UT_FloorAtPointsProbe`).

Used on 2026-10-05 for the solid Shrouded Isles portal platforms in Camelot Hills (000),
Vale of Mularn (100) and Lough Derg (200): 49 tiles (about 900 units) around each portal from
an OpenDAoC-BuildNav build of the current client, spliced into the installed meshes.
Builder note: zone 200 rebuilds byte-identical to the installed mesh, zones 000/100 do not
(their installed meshes have raised "New Towns" plazas around the portals that this client
does not have).

# Zone road graph (navmesh/roads.json)

Detour's search stops at a dead end when the only way to a far point first leads away from it.
The server then falls back to a graph of short legs proven with its own corridor check
(`AutonomousZoneRoads`): the corridor check, the zone itinerary and the bot mover all use it.
Area ids match `seams.json` (both come from `navcomp`), so the same meshes must produce both.
Regenerate after rebuilding any mesh (server stopped, about a minute in all):

```
python roadgraph.py ..\..\..\..\runtime\data\opendaoc.sqlite3.db ..\..\..\..\runtime\server\navmesh roads.candidates.json
set OFFLINE_DAOC_NAV_ROOT=<runtime\server>
set OFFLINE_DAOC_ROADS_IN=<this folder>\roads.candidates.json
set OFFLINE_DAOC_ROADS_OUT=<this folder>\roads.generated.json
dotnet test Tests/Tests.csproj -c Release --filter "FullyQualifiedName~UT_ZoneRoadBuild"
copy roads.generated.json <runtime\server>\navmesh\roads.json
```

Check routes with `UT_ZoneStepProbe` (its result line now ends with the navmesh query profile,
including `Road=calls/ms`). Without `roads.json` everything behaves as before it existed.
First built 2026-10-13: 63 zones of regions 1, 100, 200, 51, 151, 181; 99.6% of candidate legs proven.
