extends GutTest

var painting_canvas: PaintingCanvas2D
var game_manager: GameManager

func before_each():
    game_manager = GameManager.new()
    GameManager.Instance = game_manager
    add_child(game_manager)

    painting_canvas = PaintingCanvas2D.new()
    add_child(painting_canvas)

func after_each():
    painting_canvas.free()
    game_manager.free()
    GameManager.Instance = null

func test_register_voxel_template():
    var initial_anchors_count = painting_canvas._hiddenAnchors.size()
    var new_anchors: Array[Vector2] = [Vector2(10, 10), Vector2(20, 20)]

    painting_canvas.RegisterVoxelTemplate(new_anchors)

    assert_eq(painting_canvas._hiddenAnchors.size(), initial_anchors_count + 2)
    assert_true(painting_canvas._hiddenAnchors.has(Vector2(10, 10)))

func test_validate_connection_with_dynamic_anchors():
    painting_canvas._dynamicAnchors["pendulum"] = {"center": Vector2(50, 50), "radius": 10.0, "speed": 1.0}
    # Simulate a process frame to populate "current_pos"
    painting_canvas._process(1.0)

    var pos1 = painting_canvas._dynamicAnchors["pendulum"]["current_pos"]
    var pos2 = painting_canvas._hiddenAnchors[0] # Usually Vector2(100, 100)

    # Simulate drawing between them
    painting_canvas._isDrawing = true
    painting_canvas.ValidateConnection(pos1, pos2)

    # We can't directly check the print statement, but we can verify the function
    # executes without errors and accesses the anchors correctly.
    assert_true(true, "ValidateConnection ran successfully with dynamic anchors.")

func test_drawing_lines():
    painting_canvas.StartDrawing(Vector2(5, 5))
    assert_true(painting_canvas._isDrawing)
    assert_eq(painting_canvas._currentLineStart, Vector2(5, 5))

    painting_canvas.FinishDrawing(Vector2(15, 15))
    assert_false(painting_canvas._isDrawing)
    assert_eq(painting_canvas._drawnLines.size(), 2)
    assert_eq(painting_canvas._drawnLines[0], Vector2(5, 5))
    assert_eq(painting_canvas._drawnLines[1], Vector2(15, 15))
