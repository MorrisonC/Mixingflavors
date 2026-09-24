extends GutTest

const AudioManagerClass = preload("res://scripts/AudioManager.gd")

var audio_manager: Node

func before_each() -> void:
	audio_manager = AudioManagerClass.new()
	add_child_autoqfree(audio_manager)

func test_pool_initialization() -> void:
	assert_eq(audio_manager.sfx_pool.size(), 8)
	assert_not_null(audio_manager.bgm_player)

func test_play_sfx_cycles_pool() -> void:
	var stream := AudioStreamWAV.new()
	for _index: int in range(10):
		audio_manager.play_sfx(stream)
	assert_eq(audio_manager.next_sfx_index, 2)
	assert_true(audio_manager.sfx_pool[1].playing)

func test_bundled_cc0_gameplay_sounds_are_available() -> void:
	assert_not_null(audio_manager.CHISEL_SFX)
	assert_not_null(audio_manager.MARK_SFX)
	assert_not_null(audio_manager.ERROR_SFX)
	assert_not_null(audio_manager.TOGGLE_SFX)
	assert_not_null(audio_manager.VICTORY_SFX)
	audio_manager.play_chisel_sfx(4)
	assert_true(audio_manager.sfx_pool[0].playing)
	assert_almost_eq(audio_manager.sfx_pool[0].pitch_scale, 1.2, 0.001)
