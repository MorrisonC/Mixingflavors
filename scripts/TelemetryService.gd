class_name TelemetryService
extends Node

static var Instance: TelemetryService

# Telemetry tracking variables
var _timeSinceLastSample: float = 0.0
const SampleInterval: float = 5.0 # 5 seconds
const FrameSpikeThresholdMs: float = 33.3 # Roughly < 30 FPS

# Queue for async processing
var _telemetryQueue: Array = []
var _httpClient: HTTPRequest

# Use a generic placeholder or local server for testing
var _telemetryEndpoint: String = "http://localhost:8080/api/telemetry"

func _enter_tree() -> void:
    if Instance == null:
        Instance = self
        _httpClient = HTTPRequest.new()
        add_child(_httpClient)
    else:
        queue_free()

func _process(delta: float) -> void:
    _timeSinceLastSample += delta

    # Track Frame Spikes
    var currentFrameTimeMs: float = delta * 1000.0
    if currentFrameTimeMs > FrameSpikeThresholdMs:
        LogPerformanceSpike(currentFrameTimeMs)

    # Periodic Performance Sampling
    if _timeSinceLastSample >= SampleInterval:
        SamplePerformanceMetrics()
        _timeSinceLastSample = 0.0

        # Flush queue occasionally
        call_deferred("FlushTelemetryQueue")

func LogPerformanceSpike(frameTimeMs: float) -> void:
    var data = {
        "Type": "PerformanceSpike",
        "Timestamp": Time.get_datetime_string_from_system(true),
        "FrameTimeMs": frameTimeMs,
        "MemoryUsage": OS.get_static_memory_usage()
    }
    EnqueueTelemetry(data)

func SamplePerformanceMetrics() -> void:
    var data = {
        "Type": "PerformanceSample",
        "Timestamp": Time.get_datetime_string_from_system(true),
        "FPS": Engine.get_frames_per_second(),
        "MemoryUsage": OS.get_static_memory_usage()
    }
    EnqueueTelemetry(data)

func LogPuzzleCompletion(puzzleId: String, timeToSolveSeconds: float, misclicks: int) -> void:
    var data = {
        "Type": "PuzzleCompletion",
        "Timestamp": Time.get_datetime_string_from_system(true),
        "PuzzleId": puzzleId,
        "SolveTime": timeToSolveSeconds,
        "Misclicks": misclicks
    }
    EnqueueTelemetry(data)

func LogMisclick(puzzleId: String) -> void:
    var data = {
        "Type": "PuzzleMisclick",
        "Timestamp": Time.get_datetime_string_from_system(true),
        "PuzzleId": puzzleId
    }
    EnqueueTelemetry(data)

func LogNarrativeEvent(pageId: String, choiceMade: String) -> void:
    var data = {
        "Type": "NarrativeChoice",
        "Timestamp": Time.get_datetime_string_from_system(true),
        "PageId": pageId,
        "Choice": choiceMade
    }
    EnqueueTelemetry(data)

func EnqueueTelemetry(data: Dictionary) -> void:
    var json_str = JSON.stringify(data)
    _telemetryQueue.append(json_str)
    print("[Telemetry] Enqueued: ", json_str)

func FlushTelemetryQueue() -> void:
    while _telemetryQueue.size() > 0:
        var payload = _telemetryQueue.pop_front()
        # For AI playability testing, we just print the JSON.
        # In production, uncomment the HTTP POST request below.
        print("[Telemetry Flush (AI Test Mode)]: ", payload)

        # var error = _httpClient.request(_telemetryEndpoint, ["Content-Type: application/json"], HTTPClient.METHOD_POST, payload)
        # if error != OK:
        #     printerr("Failed to send telemetry: ", error)
