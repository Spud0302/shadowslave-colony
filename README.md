# Shadow Slave Colony

A colony simulation set in the world of _Shadow Slave_ (an unofficial fan project). You watch; the colony runs itself.

Six Sleepers wake on the ash beneath a ruined Citadel in the Dream Realm. Its Gateway is sealed by the Guardian in the keep, an Ashen Tyrant. To Awaken they have to survive long enough to kill it.

## What happens on its own

- **Work.** Colonists fell dead trees, break stone and ruins, gather ashroot, cook meals, build beds, a cooking fire, braziers and a palisade that later turns to stone. They carve spears, then stone axes, then shard-edged blades.
- **Needs.** Hunger, rest, health and mood. Thoughts like "Ate a hot meal" or "Saw Remy die" move mood, and a broken spirit sends someone wandering in despair.
- **Aspects.** Every colonist has one of the mod's 30 Natures. It shapes their skills and gives a perk: Ember burns, Wellspring heals the wounded nearby, Seer foresees raids, Wayfarer is fast, Unbroken survives one killing blow, and so on.
- **Danger.** Ash Burrowers and Chainbacks wander and get hunted for meat and soul shards. Raids come at night and grow over time, with Hollow Mimics and Ember Fiends later.
- **Soul cores.** Soul shards from kills fill colonists' cores and make them stronger.
- **The keep.** When the colony is strong enough it storms the keep. If the Tyrant falls, the Gateway opens: Sleepers walk through, wake in the real world and come back Awakened. Awakened with full cores may face the Second Nightmare and return as Masters, or never return.
- **Arrivals.** New Sleepers descend at each winter solstice (every 12 days), and lone survivors stumble in.

## Watching

- Drag to pan, scroll to zoom.
- Click a colonist or creature to inspect them (needs, skills, thoughts, their story so far). Press F to follow.
- Space pauses, 1 to 5 set the speed (1x, 2x, 4x, 8x, 20x).
- Click a name in the Chronicle to jump to that person.

## Running

Linux: `./play.sh`. Windows: `play.bat`. Either one downloads Godot 4.3 into `.engine/` the first time and then starts the game. Or open the folder in the Godot 4.3 editor and press F5.

Testing: `godot --headless --path . -- --simtest=30` runs 30 days without graphics and prints a daily summary and the chronicle. `-- --autoshot=DIR` takes a set of screenshots. `-- --seed=N` picks the world.

## Roadmap

The long-term goal is a Factorio/RimWorld-style game where the colony keeps its own life but you guide it: orders, zones, research and production chains on top of the systems already here.
