class_name HFDefs
extends RefCounted

const TILE := 32
const MAP_W := 46
const MAP_H := 32
const HOURS_PER_DAY := 24
const DAYS_PER_SEASON := 8
const SEASONS: Array[String] = ["Spring", "Summer", "Autumn", "Winter"]
const SEASON_BASE_TEMP: Array[float] = [12.0, 23.0, 13.0, 0.0]
const COLONIST_CAP := 12

const SKILLS := {
	"labor": {"name": "Labor", "desc": "Chopping, mining, building, and hauling."},
	"farming": {"name": "Farming", "desc": "Sowing, tending, and harvesting crops."},
	"cooking": {"name": "Cooking", "desc": "Turning raw ingredients into warm meals."},
	"medicine": {"name": "Medicine", "desc": "Treating injuries and illness."},
	"crafting": {"name": "Crafting", "desc": "Making tools and useful goods."},
	"combat": {"name": "Combat", "desc": "Hunting and defending the colony."},
	"social": {"name": "Social", "desc": "Bonding with neighbors and lifting spirits."},
}

const JOBS := {
	"fire": {"name": "Firefight", "short": "FIRE", "desc": "Put out burning buildings before they collapse."},
	"care": {"name": "Care", "short": "CARE", "desc": "Treat the sick and injured at a clinic."},
	"build": {"name": "Build", "short": "BUILD", "desc": "Finish blueprints and repair damaged structures."},
	"farm": {"name": "Farm", "short": "FARM", "desc": "Sow, tend, and harvest farm plots."},
	"cook": {"name": "Cook", "short": "COOK", "desc": "Turn grain, berries, fish, and meat into meals."},
	"gather": {"name": "Gather", "short": "GATHER", "desc": "Chop, mine, forage, and collect materials."},
	"craft": {"name": "Craft", "short": "CRAFT", "desc": "Make tools and goods at workshops and forges."},
	"haul": {"name": "Haul", "short": "HAUL", "desc": "Carry loose piles into storage."},
	"hunt": {"name": "Hunt", "short": "HUNT", "desc": "Hunt game and drive off dangerous animals."},
	"study": {"name": "Study", "short": "STUDY", "desc": "Research improvements at a research desk."},
}
const JOB_ORDER: Array[String] = ["fire", "care", "build", "farm", "cook", "gather", "craft", "haul", "hunt", "study"]

const RESOURCES := {
	"wood": {"name": "Wood", "icon": "wood", "category": "material", "food": 0.0, "perish": 0.0, "raw": false},
	"stone": {"name": "Stone", "icon": "stone", "category": "material", "food": 0.0, "perish": 0.0, "raw": false},
	"ore": {"name": "Iron Ore", "icon": "ore", "category": "material", "food": 0.0, "perish": 0.0, "raw": false},
	"coal": {"name": "Coal", "icon": "coal", "category": "material", "food": 0.0, "perish": 0.0, "raw": false},
	"clay": {"name": "Clay", "icon": "clay", "category": "material", "food": 0.0, "perish": 0.0, "raw": false},
	"grain": {"name": "Grain", "icon": "seeds", "category": "food", "food": 8.0, "perish": 0.006, "raw": true},
	"pumpkin": {"name": "Pumpkin", "icon": "pumpkin", "category": "food", "food": 26.0, "perish": 0.025, "raw": true},
	"berries": {"name": "Berries", "icon": "berries", "category": "food", "food": 18.0, "perish": 0.040, "raw": true},
	"fish": {"name": "Raw Fish", "icon": "fish", "category": "food", "food": 22.0, "perish": 0.055, "raw": true},
	"meat": {"name": "Raw Meat", "icon": "meat", "category": "food", "food": 25.0, "perish": 0.060, "raw": true},
	"meal": {"name": "Warm Meal", "icon": "meal", "category": "food", "food": 48.0, "perish": 0.018, "raw": false},
	"bread": {"name": "Bread", "icon": "bread", "category": "food", "food": 38.0, "perish": 0.008, "raw": false},
	"herbs": {"name": "Herbs", "icon": "herbs", "category": "medicine", "food": 0.0, "perish": 0.012, "raw": false},
	"medicine": {"name": "Medicine", "icon": "medicine", "category": "medicine", "food": 0.0, "perish": 0.0, "raw": false},
	"tools": {"name": "Tools", "icon": "tools", "category": "goods", "food": 0.0, "perish": 0.0, "raw": false},
	"cloth": {"name": "Cloth", "icon": "cloth", "category": "goods", "food": 0.0, "perish": 0.0, "raw": false},
}

const FOOD_PREFERENCE: Array[String] = ["meal", "bread", "pumpkin", "berries", "fish", "meat", "grain"]

const TRAITS := {
	"hard_worker": {"name": "Hard Worker", "desc": "Works quickly, but tires faster.", "work": 1.16, "fatigue": 1.10, "mood": -1.0},
	"lazy": {"name": "Easygoing", "desc": "Takes life slowly and keeps a lighter mood.", "work": 0.88, "mood": 4.0},
	"optimist": {"name": "Optimist", "desc": "Finds hope even in thin times.", "mood": 8.0},
	"pessimist": {"name": "Pessimist", "desc": "Expects the worst, and often finds it.", "mood": -8.0},
	"glutton": {"name": "Big Appetite", "desc": "Needs more food than most.", "hunger": 1.28},
	"light_sleeper": {"name": "Light Sleeper", "desc": "Sleeps poorly when the wind picks up.", "sleep": 0.80},
	"kind": {"name": "Kindhearted", "desc": "Bonds with others more easily.", "social": 1.45, "mood": 2.0},
	"hot_headed": {"name": "Hot-Headed", "desc": "Quick to argue when moods are low.", "social": 0.78, "mood": -2.0},
	"green_thumb": {"name": "Green Thumb", "desc": "Crops respond to their careful hands.", "farm": 1.18, "mood": 2.0},
	"brave": {"name": "Brave", "desc": "Holds their ground when predators come.", "combat": 1.25, "fear": 0.55},
	"coward": {"name": "Faint-Hearted", "desc": "Would rather be behind a wall when danger calls.", "combat": 0.82, "fear": 1.45},
	"neat": {"name": "Neat", "desc": "Stays clean and notices when others do not.", "hygiene": 0.72, "mood": 2.0},
	"slob": {"name": "Unkempt", "desc": "Does not mind a little mud.", "hygiene": 1.30, "mood": 1.0},
	"sickly": {"name": "Sickly", "desc": "Catches whatever is going around.", "illness": 1.55},
	"hardy": {"name": "Hardy", "desc": "Shrugs off cold and sickness.", "illness": 0.68, "warmth": 0.80},
	"night_owl": {"name": "Night Owl", "desc": "Does their best work after dark.", "night_work": 1.18},
	"fast_learner": {"name": "Fast Learner", "desc": "Picks up new skills quickly.", "xp": 1.45},
	"steady_hands": {"name": "Steady Hands", "desc": "Less likely to be hurt on the job.", "accident": 0.62},
}

const BUILD_CATEGORIES := {
	"shelter": {"name": "Shelter", "order": 0},
	"food": {"name": "Food & Water", "order": 1},
	"production": {"name": "Production", "order": 2},
	"care": {"name": "Care", "order": 3},
	"defense": {"name": "Defense", "order": 4},
}

const BUILDINGS := {
	"cabin": {
		"name": "Cabin", "category": "shelter", "size": [2, 2], "cost": {"wood": 20, "stone": 5},
		"hp": 120, "beds": 2, "warmth": 4, "desc": "Two proper beds and a hearth. Sleep restores more energy indoors.",
		"build_time": 10.0, "icon": "cabin",
	},
	"longhouse": {
		"name": "Longhouse", "category": "shelter", "size": [3, 2], "cost": {"wood": 42, "stone": 12},
		"hp": 190, "beds": 4, "warmth": 7, "desc": "A roomy timber hall for four colonists, with a shared fire at its heart.",
		"build_time": 18.0, "icon": "longhouse",
	},
	"cookhouse": {
		"name": "Cookhouse", "category": "food", "size": [2, 2], "cost": {"wood": 24, "stone": 14},
		"hp": 110, "warmth": 3, "station": "cook", "desc": "Turns grain, berries, fish, or meat into nourishing warm meals.",
		"build_time": 12.0, "icon": "cookhouse",
	},
	"food_shed": {
		"name": "Food Shed", "category": "food", "size": [2, 2], "cost": {"wood": 16, "stone": 6},
		"hp": 90, "storage": 160, "spoil": 0.52, "desc": "Cool, raised storage. Preserves food far longer and adds storage space.",
		"build_time": 8.0, "icon": "food_shed",
	},
	"stockpile": {
		"name": "Stockpile", "category": "production", "size": [2, 2], "cost": {"wood": 10, "stone": 2},
		"hp": 100, "storage": 220, "walkable": true, "desc": "Open ground for lumber, stone, ore, and goods. Haulers bring loose piles here.",
		"build_time": 4.0, "icon": "stockpile",
	},
	"farm_plot": {
		"name": "Farm Plot", "category": "food", "size": [2, 2], "cost": {"wood": 8},
		"hp": 70, "farm": true, "walkable": true, "desc": "Sow grain or pumpkins. Crops depend on warmth, rain, season, and farmer skill.",
		"build_time": 6.0, "icon": "farm_plot",
	},
	"well": {
		"name": "Stone Well", "category": "food", "size": [1, 1], "cost": {"wood": 8, "stone": 14},
		"hp": 100, "water": true, "desc": "Clean water for washing and a faster response to fire.",
		"build_time": 8.0, "icon": "well",
	},
	"workshop": {
		"name": "Workshop", "category": "production", "size": [2, 2], "cost": {"wood": 28, "stone": 10},
		"hp": 130, "station": "craft", "desc": "A sturdy bench for making tools from wood, stone, and iron.",
		"build_time": 14.0, "icon": "workshop",
	},
	"forge": {
		"name": "Forge", "category": "production", "size": [2, 2], "cost": {"wood": 24, "stone": 24, "ore": 4},
		"hp": 140, "station": "forge", "desc": "A hot forge for better tools. Speeds crafting and makes work safer.",
		"build_time": 16.0, "icon": "forge",
	},
	"clinic": {
		"name": "Clinic", "category": "care", "size": [2, 2], "cost": {"wood": 24, "stone": 12, "herbs": 4},
		"hp": 120, "healing": true, "desc": "A clean, quiet place for treating injury and illness with herbs or medicine.",
		"build_time": 14.0, "icon": "clinic",
	},
	"lumber_camp": {
		"name": "Lumber Camp", "category": "production", "size": [2, 2], "cost": {"wood": 14, "stone": 4},
		"hp": 90, "work_bonus": {"gather": 1.12}, "desc": "Tools, sawhorses, and a roof for the woodcutters. Gathering wood is faster nearby.",
		"build_time": 8.0, "icon": "lumber_camp",
	},
	"mine": {
		"name": "Mine Head", "category": "production", "size": [2, 2], "cost": {"wood": 24, "stone": 18},
		"hp": 130, "work_bonus": {"gather": 1.12}, "desc": "A timber headframe and rail cart. Makes mining stone, coal, and ore faster.",
		"build_time": 16.0, "icon": "mine",
	},
	"research_desk": {
		"name": "Research Desk", "category": "production", "size": [2, 2], "cost": {"wood": 18, "stone": 4, "cloth": 2},
		"hp": 80, "station": "study", "desc": "Maps, ledgers, and a lantern. Study unlocks better tools, farming, and medicine.",
		"build_time": 10.0, "icon": "research_desk",
	},
	"wall": {
		"name": "Palisade", "category": "defense", "size": [1, 1], "cost": {"wood": 5},
		"hp": 160, "defense": 2, "desc": "A sharpened timber wall. Predators must go around it.",
		"build_time": 3.0, "icon": "wall",
	},
	"gate": {
		"name": "Gate", "category": "defense", "size": [1, 1], "cost": {"wood": 9, "stone": 2},
		"hp": 140, "walkable": true, "defense": 1, "desc": "A heavy gate that lets colonists through but slows animals down.",
		"build_time": 4.0, "icon": "gate",
	},
	"watchtower": {
		"name": "Watchtower", "category": "defense", "size": [1, 1], "cost": {"wood": 20, "stone": 8},
		"hp": 120, "defense": 4, "vision": 8, "desc": "High ground and a warning bell. Gives early warning of predators.",
		"build_time": 10.0, "icon": "watchtower",
	},
	"campfire": {
		"name": "Campfire", "category": "shelter", "size": [1, 1], "cost": {"wood": 4, "stone": 3},
		"hp": 50, "warmth": 8, "light": true, "hidden": true, "custom_sprite": true,
		"desc": "A ring of stones and a steady flame. The first hearth of the colony.",
		"build_time": 2.0, "icon": "meal",
	},
}

const OBJECTS := {
	"pine": {"name": "Pine", "sprite": "pine", "blocking": true, "resource": "wood", "qty": [8, 13], "work": 4.2, "regrow": 9.0, "becomes": "stump"},
	"oak": {"name": "Oak", "sprite": "oak", "blocking": true, "resource": "wood", "qty": [10, 16], "work": 5.0, "regrow": 10.0, "becomes": "stump"},
	"birch": {"name": "Birch", "sprite": "birch", "blocking": true, "resource": "wood", "qty": [7, 11], "work": 3.8, "regrow": 8.0, "becomes": "stump"},
	"stump": {"name": "Stump", "sprite": "stump", "blocking": false, "resource": "wood", "qty": [2, 4], "work": 1.8, "becomes": ""},
	"berry_bush": {"name": "Berry Bush", "sprite": "berry_bush", "blocking": true, "resource": "berries", "qty": [5, 9], "work": 3.0, "regrow": 1.2, "becomes": "dead_shrub"},
	"boulder": {"name": "Boulder", "sprite": "boulder", "blocking": true, "resource": "stone", "qty": [7, 12], "work": 5.2, "becomes": ""},
	"stone_outcrop": {"name": "Stone Outcrop", "sprite": "stone_outcrop", "blocking": true, "resource": "stone", "qty": [14, 22], "work": 7.0, "becomes": "boulder"},
	"iron_vein": {"name": "Iron Vein", "sprite": "iron_vein", "blocking": true, "resource": "ore", "qty": [8, 15], "work": 7.5, "becomes": "stone_outcrop"},
	"coal_seam": {"name": "Coal Seam", "sprite": "coal_seam", "blocking": true, "resource": "coal", "qty": [7, 13], "work": 6.5, "becomes": "boulder"},
	"clay": {"name": "Clay Deposit", "sprite": "clay_deposit", "blocking": true, "resource": "clay", "qty": [5, 9], "work": 4.0, "becomes": ""},
	"mushrooms": {"name": "Mushroom Patch", "sprite": "mushrooms", "blocking": false, "resource": "herbs", "qty": [2, 5], "work": 2.0, "regrow": 2.0, "becomes": "dead_shrub"},
	"dead_shrub": {"name": "Dead Shrub", "sprite": "dead_shrub", "blocking": false, "resource": "wood", "qty": [1, 2], "work": 1.0, "becomes": ""},
	"reeds": {"name": "Reeds", "sprite": "reeds", "blocking": false, "resource": "wood", "qty": [1, 3], "work": 1.2, "regrow": 4.0, "becomes": "reeds"},
	"pumpkin": {"name": "Wild Pumpkin", "sprite": "pumpkin", "blocking": false, "resource": "pumpkin", "qty": [2, 4], "work": 1.8, "becomes": "dead_shrub"},
	"wheat": {"name": "Wild Wheat", "sprite": "wheat", "blocking": false, "resource": "grain", "qty": [3, 6], "work": 1.8, "becomes": "dead_shrub"},
}

const WEATHER := {
	"clear": {"name": "Clear", "desc": "Clear skies", "temp": 1.5, "crop": 1.0, "move": 1.0, "wet": 0.0},
	"overcast": {"name": "Overcast", "desc": "Grey cloud", "temp": -0.5, "crop": 0.92, "move": 1.0, "wet": 0.0},
	"rain": {"name": "Rain", "desc": "Steady rain", "temp": -3.0, "crop": 1.16, "move": 0.88, "wet": 1.0},
	"storm": {"name": "Storm", "desc": "Wind and lightning", "temp": -5.0, "crop": 0.95, "move": 0.78, "wet": 1.0},
	"fog": {"name": "Fog", "desc": "Low mist", "temp": -2.0, "crop": 0.82, "move": 0.92, "wet": 0.25},
	"snow": {"name": "Snow", "desc": "Falling snow", "temp": -6.0, "crop": 0.28, "move": 0.76, "wet": 0.6},
	"heatwave": {"name": "Heatwave", "desc": "Still, baking heat", "temp": 9.0, "crop": 0.78, "move": 0.90, "wet": 0.0},
}

const WEATHER_BY_SEASON := {
	0: ["clear", "clear", "overcast", "rain", "rain", "fog", "storm"],
	1: ["clear", "clear", "clear", "overcast", "heatwave", "storm", "rain"],
	2: ["clear", "overcast", "overcast", "rain", "fog", "rain", "clear"],
	3: ["snow", "snow", "overcast", "fog", "clear", "snow", "storm"],
}

const ANIMALS := {
	"wolf_grey": {"name": "Grey Wolf", "sprite": "wolf_grey", "hp": 34, "speed": 1.55, "damage": 8, "hostile": true, "meat": [8, 12], "fear": 0.2},
	"wolf_black": {"name": "Black Wolf", "sprite": "wolf_black", "hp": 42, "speed": 1.65, "damage": 10, "hostile": true, "meat": [10, 14], "fear": 0.1},
	"bear": {"name": "Brown Bear", "sprite": "bear", "hp": 70, "speed": 1.15, "damage": 16, "hostile": false, "defensive": true, "meat": [16, 24], "fear": 0.0},
	"boar": {"name": "Wild Boar", "sprite": "boar", "hp": 38, "speed": 1.45, "damage": 12, "hostile": false, "defensive": true, "meat": [12, 18], "fear": 0.0},
	"deer_stag": {"name": "Stag", "sprite": "deer_stag", "hp": 28, "speed": 1.8, "damage": 4, "hostile": false, "meat": [14, 20], "fear": 0.75},
	"deer_doe": {"name": "Doe", "sprite": "deer_doe", "hp": 22, "speed": 1.9, "damage": 2, "hostile": false, "meat": [10, 16], "fear": 0.85},
	"rabbit": {"name": "Rabbit", "sprite": "rabbit", "hp": 8, "speed": 2.2, "damage": 0, "hostile": false, "meat": [3, 5], "fear": 1.0},
	"fox": {"name": "Fox", "sprite": "fox", "hp": 15, "speed": 1.95, "damage": 3, "hostile": false, "meat": [4, 6], "fear": 0.8},
	"turkey": {"name": "Wild Turkey", "sprite": "turkey", "hp": 12, "speed": 1.5, "damage": 2, "hostile": false, "meat": [5, 8], "fear": 0.9},
	"owl": {"name": "Owl", "sprite": "owl", "hp": 6, "speed": 2.0, "damage": 1, "hostile": false, "meat": [1, 2], "fear": 1.0},
}

const NAMES: Array[String] = [
	"Mara", "Elias", "Tamsin", "Rowan", "Isolde", "Bram", "Nell", "Orin", "Sable", "Corin",
	"Ada", "Finn", "Mabel", "Hollis", "Juno", "Silas", "Wren", "Edda", "Pike", "Alma",
	"Ansel", "Briar", "Cael", "Dara", "Ewan", "Faye", "Gideon", "Hazel", "Ivo", "Jory",
	"Kira", "Lenn", "Maeve", "Niko", "Opal", "Perrin", "Quin", "Rhea", "Soren", "Thea",
]
const SURNAMES: Array[String] = [
	"Ashdown", "Bellweather", "Cinder", "Dunmore", "Elmwood", "Fallow", "Greaves", "Hollow",
	"Ironwood", "Juniper", "Kestrel", "Lark", "Moss", "North", "Oakenshield", "Pike", "Quill",
	"Reed", "Stone", "Thorne", "Underhill", "Vale", "Whitlock", "Yarrow",
]

const THOUGHTS: Array[String] = [
	"watches the smoke curl into the trees and thinks of the road behind them.",
	"runs a thumb along a fresh splinter and decides it was worth it.",
	"hears something move at the edge of the clearing. Probably the wind.",
	"counts the stores twice. The number does not get any larger.",
	"trades a quiet joke with a neighbor and feels the day lift a little.",
	"looks at the unfinished wall and imagines what it will keep out.",
	"remembers a warm kitchen from somewhere far away.",
	"takes a long breath of pine air. This place could become home.",
	"listens to the fire pop and lets their shoulders drop.",
	"wonders whether the colony will still be here come winter.",
]

const TECH = [
	{"id": "better_tools", "name": "Better Tools", "desc": "Work speed +12% across the colony.", "bonus": "work", "value": 1.12},
	{"id": "crop_rotation", "name": "Crop Rotation", "desc": "Crop growth +20%.", "bonus": "farm", "value": 1.20},
	{"id": "herbal_remedies", "name": "Herbal Remedies", "desc": "Treatment is 25% more effective.", "bonus": "medicine", "value": 1.25},
	{"id": "raised_storage", "name": "Raised Storage", "desc": "Spoilage reduced by 20%.", "bonus": "spoil", "value": 0.80},
]

static func building_size(key: String) -> Vector2i:
	var s: Array = BUILDINGS.get(key, {}).get("size", [1, 1])
	return Vector2i(int(s[0]), int(s[1]))

static func job_short(job_id: String) -> String:
	return str(JOBS.get(job_id, {}).get("short", job_id.to_upper()))

static func skill_name(skill_id: String) -> String:
	return str(SKILLS.get(skill_id, {}).get("name", skill_id.capitalize()))

static func resource_name(resource_id: String) -> String:
	return str(RESOURCES.get(resource_id, {}).get("name", resource_id.capitalize()))
