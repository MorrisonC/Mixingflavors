class_name PaintingCanvas2D
extends Node2D

var _isDrawing: bool = false
var _currentLineStart: Vector2
var _drawnLines: Array[Vector2] = []

# Hidden points of interest on the painting that the player needs to connect.
var _hiddenAnchors: Array[Vector2] = []

func _ready() -> void:
    # Set process_input to true to receive mouse/touch events.
    set_process_input(true)

    # Example of setting up anchors for the Masquerade system.
    _hiddenAnchors.append(Vector2(100, 100)) # Example: An eye
    _hiddenAnchors.append(Vector2(250, 300)) # Example: A fingertip

func _input(event: InputEvent) -> void:
    if GameManager.Instance.CurrentMode != GameManager.GameMode.MasqueradePainting:
        return

    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT:
            if event.pressed:
                StartDrawing(event.position)
            else:
                FinishDrawing(event.position)
    elif event is InputEventScreenTouch:
        if event.pressed:
            StartDrawing(event.position)
        else:
            FinishDrawing(event.position)

func StartDrawing(pos: Vector2) -> void:
    _isDrawing = true
    _currentLineStart = pos

func FinishDrawing(pos: Vector2) -> void:
    if not _isDrawing:
        return
    _isDrawing = false

    _drawnLines.append(_currentLineStart)
    _drawnLines.append(pos)

    queue_redraw()
    ValidateConnection(_currentLineStart, pos)

func ValidateConnection(start: Vector2, end: Vector2) -> void:
    # Simple validation: check if the drawn line connects two hidden anchors within a tolerance.
    var tolerance: float = 20.0
    var tolerance_squared: float = tolerance * tolerance
    var startMatched: bool = false
    var endMatched: bool = false

    for anchor in _hiddenAnchors:
        if start.distance_squared_to(anchor) < tolerance_squared:
            startMatched = true
        if end.distance_squared_to(anchor) < tolerance_squared:
            endMatched = true

    if startMatched and endMatched:
        print("Valid hidden connection found!")
        # Trigger unlock event
        if TelemetryService.Instance != null:
            TelemetryService.Instance.LogPuzzleCompletion("Painting_HiddenLine", 10.5, 0) # Placeholder data
    else:
        if TelemetryService.Instance != null:
            TelemetryService.Instance.LogMisclick("Painting_HiddenLine")

func _draw() -> void:
    # Draw all lines the player has created.
    var i = 0
    while i < _drawnLines.size():
        draw_line(_drawnLines[i], _drawnLines[i+1], Color.RED, 3.0)
        i += 2
