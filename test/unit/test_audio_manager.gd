extends GutTest

const AudioManagerClass = preload("res://scripts/AudioManager.gd")
var audio_manager

func before_each():
	audio_manager = AudioManagerClass.new()
	add_child(audio_manager)

func after_each():
	audio_manager.queue_free()

func test_pool_initialization():
	assert_eq(audio_manager.sfx_pool.size(), 8)
	assert_not_null(audio_manager.bgm_player)

func test_play_sfx():
	# Test pool cycling
	var stream = AudioStreamWAV.new() # Dummy stream
	for i in range(10):
		audio_manager.play_sfx(stream)

	assert_eq(audio_manager.next_sfx_index, 2)
	assert_true(audio_manager.sfx_pool[1].playing)
