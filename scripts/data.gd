extends RefCounted
## Constants and lore tables shared by every script.

const W := 128
const H := 96
const TS := 16
const TICKS_PER_DAY := 3600
const TICKS_PER_HOUR := 150
const DAYS_PER_YEAR := 12

# Ground
const G_ASH := 0
const G_DUST := 1
const G_FLOOR := 2
const G_WATER := 3

# Features on a tile
const F_NONE := 0
const F_TREE := 1
const F_ROCK := 2
const F_PLANT := 3
const F_BARE := 4
const F_RUIN := 5
const F_CWALL := 6
const F_GATEWAY := 7
const F_SAPLING := 8

const RANKS := ["Sleeper", "Awakened", "Master"]
const RANK_HP := [80.0, 150.0, 360.0]
const RANK_DMG := [8.0, 15.0, 36.0]
const ARMS := ["bare hands and clubs", "fire-hardened spears", "stone axes and spears", "shard-edged blades"]
const ARMS_MULT := [1.0, 1.5, 2.0, 2.7]

const SKILLS := ["combat", "labor", "build", "cook", "forage", "heal"]
const SKILL_NAMES := {"combat": "Combat", "labor": "Labour", "build": "Building", "cook": "Cooking", "forage": "Foraging", "heal": "Healing"}

# Nature -> colour, skill bonuses, perk. The thirty Natures are the mod's live roster.
const NATURES := {
	"Ember": ["#f08a4b", {"combat": 2, "cook": 3}, "fire"],
	"Mist": ["#9fb7d9", {"forage": 2, "combat": 1}, "speed"],
	"Stone": ["#9a9488", {"labor": 3, "build": 1}, "ward"],
	"Tide": ["#4fa3c7", {"forage": 2, "heal": 1}, "none"],
	"Warden": ["#c9c26b", {"combat": 2, "build": 1}, "ward"],
	"Seer": ["#b490f0", {"heal": 1, "forage": 1}, "foresee"],
	"Reaper": ["#8c2f45", {"combat": 3}, "reaper"],
	"Wellspring": ["#6fd6c0", {"heal": 4}, "heal"],
	"Forge": ["#e0703a", {"build": 3, "labor": 1}, "none"],
	"Delve": ["#a07a52", {"labor": 4}, "none"],
	"Mason": ["#b8a68a", {"build": 4}, "none"],
	"Verdant": ["#69b858", {"forage": 3}, "regrow"],
	"Wayfarer": ["#d9b26f", {"forage": 1, "labor": 1}, "speed"],
	"Lull": ["#7f86c9", {"heal": 2}, "lull"],
	"Gloam": ["#5b4a8a", {"combat": 2}, "speed"],
	"Rime": ["#a8e0f0", {"combat": 2}, "ward"],
	"Fury": ["#d9483b", {"combat": 3}, "rage"],
	"Threshold": ["#8a7fb0", {"build": 2}, "none"],
	"Anchor": ["#6b6f7a", {"labor": 2, "combat": 1}, "ward"],
	"Hourglass": ["#d8c48a", {"cook": 1, "build": 1}, "none"],
	"Herald": ["#e8c54f", {"combat": 1}, "rally"],
	"Keeper": ["#7aa36b", {"build": 1, "heal": 1}, "ward"],
	"Fortune": ["#e6d35a", {"forage": 1}, "luck"],
	"Cantor": ["#d68fb8", {"heal": 1}, "rally"],
	"Shepherd": ["#a7c98a", {"heal": 2, "forage": 1}, "heal"],
	"Vessel": ["#8fa0b8", {"cook": 2}, "none"],
	"Masque": ["#b0a0c0", {"combat": 1, "forage": 1}, "none"],
	"Unbroken": ["#c0b090", {"labor": 1, "combat": 1}, "unbroken"],
	"Saboteur": ["#7a8a5a", {"build": 1, "combat": 1}, "none"],
	"Standard": ["#c86a6a", {"combat": 1}, "rally"],
}

const PERK_TEXT := {
	"fire": "Strikes burn: +25% damage, cooks faster.",
	"speed": "Moves 35% faster.",
	"ward": "Takes 25% less damage.",
	"foresee": "Senses raids before they come.",
	"reaper": "More soul shards from kills.",
	"heal": "Heals the wounded nearby.",
	"regrow": "Ashroot regrows fast around them.",
	"lull": "Needs half as much sleep.",
	"rage": "Hits harder the more they bleed.",
	"rally": "Nearby allies fight harder.",
	"luck": "Sometimes dodges a blow.",
	"unbroken": "Survives one killing blow.",
	"none": "",
}

const FIRST := ["Aren", "Bel", "Cass", "Dara", "Eli", "Fen", "Gale", "Hollis", "Ira", "Jun", "Kai", "Lior", "Mara", "Nico", "Oren", "Pell", "Quinn", "Rhea", "Sol", "Tamsin", "Uri", "Vale", "Wren", "Yara", "Zev", "Ash", "Brin", "Cyr", "Deva", "Emry", "Fae", "Iven", "Kestrel", "Lumi", "Noor", "Remy", "Sable", "Tove", "Vesna", "Ilse", "Juno", "Mika", "Ottar", "Peri", "Rook", "Sage", "Teo"]
const LAST := ["Arden", "Blackwell", "Corrin", "Dusk", "Ellery", "Farrow", "Graves", "Hale", "Ivers", "Jarrah", "Kade", "Lorne", "Marsh", "Nyle", "Orr", "Penhal", "Quill", "Rask", "Stroud", "Thorne", "Ulric", "Vance", "Wilde", "Zahir", "Cole", "Rhys", "Sato", "Okoro", "Moreau", "Novak", "Haddad", "Kim", "Reyes", "Volkov", "Adeyemi", "Laine"]
const TRAITS := ["Steady", "Brave", "Timid", "Glutton", "Night owl", "Tireless", "Gentle", "Hot-headed", "Hopeful", "Grim"]
const CIT_A := ["Ash", "Bone", "Thorn", "Grey", "Star", "Iron", "Hollow", "Pale", "Ember", "Silent", "Weeping", "Sunken", "Raven", "Glass", "Salt"]
const CIT_B := ["hold", "spire", "keep", "gate", "crown", "watch", "bastion", "reach", "fall", "haven"]

# Nightmare Creatures: the mod's roster plus a later threat.
const CREATURES := {
	"burrower": {"name": "Ash Burrower", "rank": "Dormant Beast", "hp": 34.0, "dmg": 4.0, "speed": 0.12, "size": 0.55, "shard": 0.55, "col": "#6b5a4a"},
	"chainback": {"name": "Chainback", "rank": "Dormant Monster", "hp": 70.0, "dmg": 7.0, "speed": 0.085, "size": 0.75, "shard": 0.8, "col": "#4a4f5c"},
	"mimic": {"name": "Hollow Mimic", "rank": "Awakened Monster", "hp": 140.0, "dmg": 12.0, "speed": 0.1, "size": 0.8, "shard": 1.3, "col": "#3c3346"},
	"fiend": {"name": "Ember Fiend", "rank": "Fallen Demon", "hp": 340.0, "dmg": 22.0, "speed": 0.1, "size": 1.0, "shard": 1.0, "col": "#5a2420"},
	"tyrant": {"name": "Ashen Tyrant", "rank": "Fallen Tyrant", "hp": 800.0, "dmg": 18.0, "speed": 0.07, "size": 1.7, "shard": 1.0, "col": "#2a2228"},
}

const BUILD := {
	"bed": {"name": "Bed", "wood": 6, "stone": 0, "work": 180, "solid": false},
	"cook": {"name": "Cooking fire", "wood": 8, "stone": 0, "work": 220, "solid": false},
	"wall": {"name": "Palisade", "wood": 4, "stone": 0, "work": 90, "solid": true, "hp": 120},
	"swall": {"name": "Stone wall", "wood": 0, "stone": 5, "work": 150, "solid": true, "hp": 320},
	"torch": {"name": "Brazier", "wood": 3, "stone": 2, "work": 80, "solid": false},
}
