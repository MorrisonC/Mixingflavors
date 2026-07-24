extends SceneTree

var TelemetryServiceObj = load("res://Scripts/TelemetryService.gd")
var telemetry_service

func _init():
    telemetry_service = TelemetryServiceObj.new()
    TelemetryServiceObj.Instance = telemetry_service

    test_frame_spike_detected()
    test_no_frame_spike()

    print("All tests passed.")

    TelemetryServiceObj.Instance = null
    telemetry_service.free()

    quit(0)

func test_frame_spike_detected():
    telemetry_service._telemetryQueue.clear()
    telemetry_service._process(0.034)

    assert(telemetry_service._telemetryQueue.size() == 1, "Queue should have 1 item")
    var payload = JSON.parse_string(telemetry_service._telemetryQueue[0])
    assert(payload["Type"] == "PerformanceSpike", "Payload type should be PerformanceSpike")

func test_no_frame_spike():
    telemetry_service._telemetryQueue.clear()
    telemetry_service._process(0.016)

    assert(telemetry_service._telemetryQueue.size() == 0, "Queue should be empty")
