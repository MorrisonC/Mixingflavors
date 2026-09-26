extends GutTest

const GachaServiceClass = preload("res://scripts/GachaService.gd")

var service: Object


func before_each() -> void:
	service = GachaServiceClass.new()


func test_roll_cost_rates_and_supported_catalog_are_explicit() -> void:
	assert_eq(int(GachaServiceClass.ROLL_COST_SHARDS), 100)
	assert_eq(int(GachaServiceClass.EPIC_PITY_LIMIT), 10)
	assert_eq(int(GachaServiceClass.LEGENDARY_PITY_LIMIT), 30)
	assert_true(bool(GachaServiceClass.is_supported_catalog_version(1)))

	var rates: Dictionary = GachaServiceClass.get_rarity_percentages()
	assert_eq(int(rates.get("Common", 0)), 60)
	assert_eq(int(rates.get("Rare", 0)), 25)
	assert_eq(int(rates.get("Epic", 0)), 12)
	assert_eq(int(rates.get("Legendary", 0)), 3)


func test_roll_is_deterministic_for_seed_and_catalog() -> void:
	var first_profile: Dictionary = _make_profile()
	var second_profile: Dictionary = _make_profile()
	var first: Dictionary = service.call("roll", 24680, 1, first_profile)
	var second: Dictionary = service.call("roll", 24680, 1, second_profile)

	assert_true(bool(first.get("success", false)))
	assert_eq(str(first.get("rarity", "")), str(second.get("rarity", "")))
	assert_eq(str(first.get("item_id", "")), str(second.get("item_id", "")))
	assert_eq(bool(first.get("is_duplicate", true)), bool(second.get("is_duplicate", true)))
	assert_eq(int(first.get("seed", -1)), int(second.get("seed", -2)))
	assert_has(first, "rarity")
	assert_has(first, "item_id")
	assert_has(first, "is_duplicate")
	assert_has(first, "pity_before")
	assert_has(first, "pity_after")
	assert_has(first, "seed")


func test_base_rates_match_the_configured_distribution() -> void:
	var sample_count: int = 5000
	var counts: Dictionary = {
		"Common": 0,
		"Rare": 0,
		"Epic": 0,
		"Legendary": 0,
	}
	for seed_value: int in range(sample_count):
		var result: Dictionary = service.call("roll", seed_value, 1)
		var rarity: String = str(result.get("rarity", ""))
		counts[rarity] = int(counts.get(rarity, 0)) + 1

	var common_rate: float = 100.0 * float(counts["Common"]) / float(sample_count)
	var rare_rate: float = 100.0 * float(counts["Rare"]) / float(sample_count)
	var epic_rate: float = 100.0 * float(counts["Epic"]) / float(sample_count)
	var legendary_rate: float = 100.0 * float(counts["Legendary"]) / float(sample_count)
	assert_gt(common_rate, 55.0)
	assert_lt(common_rate, 65.0)
	assert_gt(rare_rate, 20.0)
	assert_lt(rare_rate, 30.0)
	assert_gt(epic_rate, 8.0)
	assert_lt(epic_rate, 16.0)
	assert_gt(legendary_rate, 1.0)
	assert_lt(legendary_rate, 5.0)


func test_tenth_non_epic_pull_is_epic_or_better() -> void:
	var profile: Dictionary = _make_profile(1000)
	profile["epic_pity"] = 9
	var result: Dictionary = service.call("roll", 13579, 1, profile)

	assert_true(bool(result.get("success", false)))
	assert_gte(_rarity_rank(str(result.get("rarity", ""))), 2)
	var pity_after: Dictionary = result.get("pity_after", {})
	assert_eq(int(pity_after.get("epic", -1)), 0)
	if str(result.get("rarity", "")) == "Legendary":
		assert_eq(int(pity_after.get("legendary", -1)), 0)
	else:
		assert_eq(int(pity_after.get("legendary", -1)), 1)
	assert_eq(int(profile.get("epic_pity", -1)), 0)


func test_thirtieth_non_legendary_pull_is_legendary() -> void:
	var profile: Dictionary = _make_profile(1000)
	profile["epic_pity"] = 0
	profile["legendary_pity"] = 29
	var result: Dictionary = service.call("roll", 86420, 1, profile)

	assert_true(bool(result.get("success", false)))
	assert_eq(str(result.get("rarity", "")), "Legendary")
	var pity_before: Dictionary = result.get("pity_before", {})
	var pity_after: Dictionary = result.get("pity_after", {})
	assert_eq(int(pity_before.get("legendary", -1)), 29)
	assert_eq(int(pity_after.get("epic", -1)), 0)
	assert_eq(int(pity_after.get("legendary", -1)), 0)
	assert_eq(int(profile.get("legendary_pity", -1)), 0)


func test_duplicate_returns_shards_without_adding_item_again() -> void:
	var initial_profile: Dictionary = _make_profile(1000)
	var initial_result: Dictionary = service.call("roll", 112233, 1, initial_profile)
	var item_id: String = str(initial_result.get("item_id", ""))
	var rarity: String = str(initial_result.get("rarity", ""))
	assert_false(bool(initial_result.get("is_duplicate", true)))
	assert_eq((initial_profile.get("owned_item_ids", []) as Array).size(), 1)

	var duplicate_profile: Dictionary = _make_profile(1000)
	duplicate_profile["owned_item_ids"] = [item_id]
	var duplicate_result: Dictionary = service.call("roll", 112233, 1, duplicate_profile)
	var expected_refund: int = int(GachaServiceClass.duplicate_shard_conversion(rarity))

	assert_true(bool(duplicate_result.get("is_duplicate", false)))
	assert_eq(str(duplicate_result.get("item_id", "")), item_id)
	assert_eq(int(duplicate_result.get("shard_conversion", -1)), expected_refund)
	assert_eq(int(duplicate_result.get("shards_balance", -1)), 900 + expected_refund)
	assert_eq(int(duplicate_profile.get("shards", -1)), 900 + expected_refund)
	assert_eq((duplicate_profile.get("owned_item_ids", []) as Array).size(), 1)


func test_insufficient_balance_fails_without_spending_or_mutating_pity() -> void:
	var profile: Dictionary = _make_profile(99)
	var before: Dictionary = profile.duplicate(true)
	var result: Dictionary = service.call("roll", 42, 1, profile)

	assert_false(bool(result.get("success", true)))
	assert_eq(str(result.get("error", "")), "INSUFFICIENT_SHARDS")
	assert_eq(int(result.get("shards_spent", -1)), 0)
	assert_eq(int(profile.get("shards", -1)), 99)
	assert_eq(profile, before)


func test_invalid_seed_and_catalog_version_fail_transactionally() -> void:
	var profile: Dictionary = _make_profile(1000)
	var before: Dictionary = profile.duplicate(true)

	var invalid_seed: Dictionary = service.call("roll", -1, 1, profile)
	var invalid_catalog: Dictionary = service.call("roll", 10, 999, profile)

	assert_false(bool(invalid_seed.get("success", true)))
	assert_eq(str(invalid_seed.get("error_code", "")), "INVALID_SEED")
	assert_false(bool(invalid_catalog.get("success", true)))
	assert_eq(str(invalid_catalog.get("error_code", "")), "INVALID_CATALOG_VERSION")
	assert_eq(profile, before)


func test_seed_zero_and_two_argument_simulation_are_valid() -> void:
	var result: Dictionary = service.call("roll", 0, 1)
	assert_true(bool(result.get("success", false)))
	assert_gte(int(result.get("seed", -1)), 0)
	assert_eq(int(result.get("shards_spent", -1)), 100)


func _make_profile(shards: int = 1000) -> Dictionary:
	return {
		"shards": shards,
		"epic_pity": 0,
		"legendary_pity": 0,
		"owned_item_ids": [],
	}


func _rarity_rank(rarity: String) -> int:
	match rarity:
		"Common":
			return 0
		"Rare":
			return 1
		"Epic":
			return 2
		"Legendary":
			return 3
		_:
			return -1
