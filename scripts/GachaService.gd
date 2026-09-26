extends RefCounted
class_name GachaService

## Headless, deterministic gacha domain service.
##
## A profile is optional. Passing an empty dictionary performs a one-roll
## simulation. A non-empty profile is validated and updated transactionally.
## Its canonical fields are:
##   shards: int
##   epic_pity: int
##   legendary_pity: int
##   owned_item_ids: Array[String]
## A nested {"epic": int, "legendary": int} "pity" dictionary is also accepted.

const ROLL_COST_SHARDS: int = 100
const ROLL_COST: int = ROLL_COST_SHARDS
const CURRENT_CATALOG_VERSION: int = 1
const CATALOG_VERSION: int = CURRENT_CATALOG_VERSION
const EPIC_PITY_LIMIT: int = 10
const LEGENDARY_PITY_LIMIT: int = 30

const COMMON: String = "Common"
const RARE: String = "Rare"
const EPIC: String = "Epic"
const LEGENDARY: String = "Legendary"

## Deprecated: the enforced selection buckets are the source of truth. Use
## get_rarity_percentages(), which derives from them.
const RARITY_PERCENTAGES: Dictionary = {
	COMMON: 60,
	RARE: 25,
	EPIC: 12,
	LEGENDARY: 3,
}

const DUPLICATE_SHARD_CONVERSION: Dictionary = {
	COMMON: 10,
	RARE: 25,
	EPIC: 50,
	LEGENDARY: 100,
}

const ITEM_CATALOG: Dictionary = {
	COMMON: [
		"common_peppermint",
		"common_blueberry",
		"common_mint",
		"common_rose",
	],
	RARE: [
		"rare_sapphire",
		"rare_emerald",
		"rare_ruby",
		"rare_amethyst",
	],
	EPIC: [
		"epic_alchemy_flame",
		"epic_alchemy_storm",
		"epic_alchemy_void",
		"epic_alchemy_bloom",
	],
	LEGENDARY: [
		"legendary_phoenix_rebirth",
		"legendary_dragon_hoard",
		"legendary_time_loop",
		"legendary_wish_star",
	],
}

const _ROLL_SCALE: int = 10000
const _COMMON_LIMIT: int = 6000
const _RARE_LIMIT: int = 8500
const _EPIC_LIMIT: int = 9700

## Base rates per pull, as whole percentages. These are the widths of the
## selection buckets below, not the effective rates a player experiences: the
## pity guarantees raise the Epic+ and Legendary rates. Keep the two derived
## from one another so the disclosed numbers cannot drift from the enforced ones.
static func base_rarity_percentages() -> Dictionary:
	return {
		COMMON: int(round(100.0 * float(_COMMON_LIMIT) / float(_ROLL_SCALE))),
		RARE: int(round(100.0 * float(_RARE_LIMIT - _COMMON_LIMIT) / float(_ROLL_SCALE))),
		EPIC: int(round(100.0 * float(_EPIC_LIMIT - _RARE_LIMIT) / float(_ROLL_SCALE))),
		LEGENDARY: int(round(100.0 * float(_ROLL_SCALE - _EPIC_LIMIT) / float(_ROLL_SCALE))),
	}

## Human-readable disclosure of what a roll actually does, including the pity
## guarantees. The screen must show this rather than the raw base table, because
## the base table understates the rare rates the pity system guarantees.
static func get_odds_disclosure() -> String:
	var base: Dictionary = base_rarity_percentages()
	return "Base rates per pull  •  %s %d%%  •  %s %d%%  •  %s %d%%  •  %s %d%%" % [
		COMMON, int(base.get(COMMON, 0)),
		RARE, int(base.get(RARE, 0)),
		EPIC, int(base.get(EPIC, 0)),
		LEGENDARY, int(base.get(LEGENDARY, 0)),
	]


static func get_pity_disclosure() -> String:
	return "Pity guarantee: an %s or better is guaranteed by the %d%s pull without one, and a %s by the %d%s." % [
		EPIC, EPIC_PITY_LIMIT, _ordinal(EPIC_PITY_LIMIT),
		LEGENDARY, LEGENDARY_PITY_LIMIT, _ordinal(LEGENDARY_PITY_LIMIT),
	]


static func _ordinal(value: int) -> String:
	var suffix: String = "th"
	if value % 100 < 11 or value % 100 > 13:
		match value % 10:
			1: suffix = "st"
			2: suffix = "nd"
			3: suffix = "rd"
	return "%d%s" % [value, suffix]


## Rolls once and returns the next deterministic seed. The input seed is
## available as "roll_seed". Pity snapshots contain separate Epic and Legendary
## counters because an Epic resets Epic pity but not Legendary pity.
func roll(seed_value: int, catalog_version: int, profile: Dictionary = {}) -> Dictionary:
	if seed_value < 0:
		return _failure(
			"INVALID_SEED",
			"Seed must be a non-negative integer.",
			seed_value,
			catalog_version
		)
	if catalog_version != CURRENT_CATALOG_VERSION:
		return _failure(
			"INVALID_CATALOG_VERSION",
			"Catalog version %d is not supported." % catalog_version,
			seed_value,
			catalog_version
		)

	var profile_was_provided: bool = not profile.is_empty()
	var working_profile: Dictionary = profile.duplicate(true) if profile_was_provided else _new_profile()
	if profile_was_provided and not working_profile.has("shards"):
		return _failure(
			"INVALID_PROFILE",
			"A supplied profile must include an integer shards balance.",
			seed_value,
			catalog_version
		)

	var shards_value: Variant = working_profile.get("shards", -1)
	if typeof(shards_value) != TYPE_INT:
		return _failure(
			"INVALID_PROFILE",
			"The shards balance must be an integer.",
			seed_value,
			catalog_version
		)

	var shards_before: int = shards_value
	if shards_before < 0:
		return _failure(
			"INVALID_PROFILE",
			"The shards balance cannot be negative.",
			seed_value,
			catalog_version
		)
	if shards_before < ROLL_COST_SHARDS:
		return _failure(
			"INSUFFICIENT_SHARDS",
			"%d shards are required for a roll." % ROLL_COST_SHARDS,
			seed_value,
			catalog_version
		)

	var pity_data: Dictionary = _read_pity(working_profile)
	if not bool(pity_data.get("valid", false)):
		return _failure(
			"INVALID_PROFILE",
			"Pity counters must be integers within their configured limits.",
			seed_value,
			catalog_version
		)

	if working_profile.has("owned_item_ids"):
		var owned_value: Variant = working_profile.get("owned_item_ids", [])
		if not _owned_item_ids_are_valid(owned_value):
			return _failure(
				"INVALID_PROFILE",
				"owned_item_ids must contain only non-empty string item IDs.",
				seed_value,
				catalog_version
			)
	var owned_item_ids: Array = _read_owned_item_ids(working_profile)

	var epic_pity_before: int = int(pity_data.get("epic", 0))
	var legendary_pity_before: int = int(pity_data.get("legendary", 0))
	var roll_value: int = _stable_value(seed_value, catalog_version, "rarity") % _ROLL_SCALE
	var rarity: String = _select_rarity(
		roll_value,
		epic_pity_before,
		legendary_pity_before
	)
	var item_id: String = _select_item_id(seed_value, catalog_version, rarity)
	var is_duplicate: bool = owned_item_ids.has(item_id)
	var shard_conversion: int = duplicate_shard_conversion(rarity) if is_duplicate else 0
	var pity_after: Dictionary = _next_pity(
		rarity,
		epic_pity_before,
		legendary_pity_before
	)

	if not is_duplicate:
		owned_item_ids.append(item_id)

	var shards_after: int = shards_before - ROLL_COST_SHARDS + shard_conversion
	if profile_was_provided:
		_commit_profile(
			profile,
			shards_after,
			int(pity_after.get("epic", 0)),
			int(pity_after.get("legendary", 0)),
			owned_item_ids
		)

	var pity_before: Dictionary = {
		"epic": epic_pity_before,
		"legendary": legendary_pity_before,
	}
	return {
		"success": true,
		"error": "",
		"error_code": "",
		"rarity": rarity,
		"item_id": item_id,
		"is_duplicate": is_duplicate,
		"pity_before": pity_before,
		"pity_after": pity_after,
		"epic_pity_before": epic_pity_before,
		"legendary_pity_before": legendary_pity_before,
		"epic_pity_after": int(pity_after.get("epic", 0)),
		"legendary_pity_after": int(pity_after.get("legendary", 0)),
		"roll_seed": seed_value,
		"seed": _next_seed(seed_value, catalog_version),
		"catalog_version": catalog_version,
		"shards_spent": ROLL_COST_SHARDS,
		"shard_conversion": shard_conversion,
		"shards_refunded": shard_conversion,
		"shards_balance": shards_after,
	}


static func is_supported_catalog_version(catalog_version: int) -> bool:
	return catalog_version == CURRENT_CATALOG_VERSION


static func duplicate_shard_conversion(rarity: String) -> int:
	return int(DUPLICATE_SHARD_CONVERSION.get(rarity, 0))


static func get_rarity_percentages() -> Dictionary:
	# Derived from the enforced bucket widths rather than a separate table, so a
	# change to the selection can never leave the disclosed numbers stale.
	return base_rarity_percentages()


static func get_catalog() -> Dictionary:
	return ITEM_CATALOG.duplicate(true)


static func _select_rarity(
	roll_value: int,
	epic_pity_before: int,
	legendary_pity_before: int
) -> String:
	# The stronger guarantee wins when both thresholds are reached.
	if legendary_pity_before + 1 >= LEGENDARY_PITY_LIMIT:
		return LEGENDARY
	if epic_pity_before + 1 >= EPIC_PITY_LIMIT:
		return EPIC
	if roll_value < _COMMON_LIMIT:
		return COMMON
	if roll_value < _RARE_LIMIT:
		return RARE
	if roll_value < _EPIC_LIMIT:
		return EPIC
	return LEGENDARY


static func _select_item_id(
	seed_value: int,
	catalog_version: int,
	rarity: String
) -> String:
	var rarity_items: Array = ITEM_CATALOG.get(rarity, [])
	if rarity_items.is_empty():
		return ""
	var item_index: int = _stable_value(
		seed_value,
		catalog_version,
		"item:%s" % rarity
	) % rarity_items.size()
	return str(rarity_items[item_index])


static func _next_pity(
	rarity: String,
	epic_pity_before: int,
	legendary_pity_before: int
) -> Dictionary:
	if rarity == LEGENDARY:
		return {"epic": 0, "legendary": 0}
	if rarity == EPIC:
		return {"epic": 0, "legendary": legendary_pity_before + 1}
	return {
		"epic": epic_pity_before + 1,
		"legendary": legendary_pity_before + 1,
	}


static func _stable_value(seed_value: int, catalog_version: int, purpose: String) -> int:
	var source: String = "%d|%d|%s" % [seed_value, catalog_version, purpose]
	var digest: String = source.sha256_text()
	# Twelve hex digits stay below 2^48 and therefore fit in a positive int64.
	return digest.substr(0, 12).hex_to_int()


static func _next_seed(seed_value: int, catalog_version: int) -> int:
	return _stable_value(seed_value, catalog_version, "next_seed")


static func _new_profile() -> Dictionary:
	return {
		"shards": ROLL_COST_SHARDS,
		"epic_pity": 0,
		"legendary_pity": 0,
		"owned_item_ids": [],
	}


static func _read_pity(profile: Dictionary) -> Dictionary:
	var epic_value: Variant = null
	var legendary_value: Variant = null

	if profile.has("pity"):
		var nested_pity_value: Variant = profile.get("pity", null)
		if typeof(nested_pity_value) != TYPE_DICTIONARY:
			return {"valid": false}
		var nested_pity: Dictionary = nested_pity_value
		epic_value = nested_pity.get("epic", 0)
		legendary_value = nested_pity.get("legendary", 0)
	else:
		epic_value = profile.get("epic_pity", 0)
		legendary_value = profile.get("legendary_pity", 0)

	if typeof(epic_value) != TYPE_INT or typeof(legendary_value) != TYPE_INT:
		return {"valid": false}
	var epic_value_int: int = epic_value
	var legendary_value_int: int = legendary_value
	if epic_value_int < 0 or epic_value_int > EPIC_PITY_LIMIT:
		return {"valid": false}
	if legendary_value_int < 0 or legendary_value_int > LEGENDARY_PITY_LIMIT:
		return {"valid": false}
	return {
		"valid": true,
		"epic": epic_value_int,
		"legendary": legendary_value_int,
	}


static func _read_owned_item_ids(profile: Dictionary) -> Array:
	if not profile.has("owned_item_ids"):
		return []
	var owned_value: Variant = profile.get("owned_item_ids", [])
	return owned_value.duplicate() if owned_value is Array else []


static func _owned_item_ids_are_valid(owned_value: Variant) -> bool:
	if typeof(owned_value) != TYPE_ARRAY:
		return false
	var owned_ids: Array = owned_value
	for owned_id: Variant in owned_ids:
		if typeof(owned_id) != TYPE_STRING or str(owned_id).is_empty():
			return false
	return true


static func _commit_profile(
	profile: Dictionary,
	shards: int,
	epic_pity: int,
	legendary_pity: int,
	owned_item_ids: Array
) -> void:
	profile["shards"] = shards
	profile["epic_pity"] = epic_pity
	profile["legendary_pity"] = legendary_pity
	profile["pity"] = {
		"epic": epic_pity,
		"legendary": legendary_pity,
	}
	profile["owned_item_ids"] = owned_item_ids


static func _failure(
	error_code: String,
	message: String,
	seed_value: int,
	catalog_version: int
) -> Dictionary:
	var empty_pity: Dictionary = {"epic": 0, "legendary": 0}
	return {
		"success": false,
		"error": error_code,
		"error_code": error_code,
		"message": message,
		"rarity": "",
		"item_id": "",
		"is_duplicate": false,
		"pity_before": empty_pity.duplicate(true),
		"pity_after": empty_pity.duplicate(true),
		"roll_seed": seed_value,
		"seed": seed_value,
		"catalog_version": catalog_version,
		"shards_spent": 0,
		"shard_conversion": 0,
		"shards_refunded": 0,
		"shards_balance": -1,
	}
