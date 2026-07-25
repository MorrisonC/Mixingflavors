extends GutTest

var game_manager: GameManager

func before_each():
    game_manager = GameManager.new()
    add_child(game_manager)

func after_each():
    game_manager.free()

func test_initial_stats():
    assert_eq(game_manager.perception_level, 1)
    assert_eq(game_manager.health, 100)
    assert_eq(game_manager.endurance, 100)
    assert_eq(game_manager.lore_discipline, 1)
    assert_eq(game_manager.alchemy_discipline, 1)

func test_mode_switching():
    assert_eq(game_manager.CurrentMode, GameManager.GameMode.LoneWolfNarrative)

    game_manager.SwitchMode(GameManager.GameMode.DetectiveCrimeScene)
    assert_eq(game_manager.CurrentMode, GameManager.GameMode.DetectiveCrimeScene)

    game_manager.SwitchMode(GameManager.GameMode.EscapeGauntlet)
    assert_eq(game_manager.CurrentMode, GameManager.GameMode.EscapeGauntlet)

    game_manager.SwitchMode(GameManager.GameMode.TimeShiftPalimpsest)
    assert_eq(game_manager.CurrentMode, GameManager.GameMode.TimeShiftPalimpsest)
