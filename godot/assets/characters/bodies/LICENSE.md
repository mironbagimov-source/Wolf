# Character body models

Mixamo characters (Adobe Mixamo royalty-free terms; FBX files provided by
the project owner), one body per playable archetype:
- michelle.glb    — "Michelle" (Курьер, civilian A; from three.js examples, MIT repo)
- medea.fbx       — "Medea" by M. Arrebola (Медтех, civilian B)
- ch45.fbx        — "Ch45" (Мясник, psycho A)
- xbot.fbx        — "X Bot" (Богомол, psycho B)
- erika.fbx       — "Erika Archer" (Клинок, merc A)
- heraklios.fbx   — "Heraklios" by A. Dizon (Броня, merc B)
- pumpkinhulk.fbx — "Pumpkinhulk" by L. Shaw (Альфа)

soldier.glb (../) — "Vanguard" (three.js examples): fallback body and the
Idle/Walk/Run animation source; clips are retargeted onto every body at bake
time by tools/retarget.gd (exact local-delta transfer — all rigs share
Mixamo bone conventions, including the "mixamorig1_" numbered variants).
