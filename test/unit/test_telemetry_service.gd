extends GutTest

var TelemetryServiceObj = load("res://Scripts/TelemetryService.gd")
var telemetry_service

func before_each():
    telemetry_service = TelemetryServiceObj.new()
    TelemetryServiceObj.Instance = telemetry_service
    add_child(telemetry_service)

func after_each():
    TelemetryServiceObj.Instance = null
    telemetry_service.free()

func test_frame_spike_detected():
    telemetry_service._telemetryQueue.clear()
    telemetry_service._process(0.034)

    assert_eq(telemetry_service._telemetryQueue.size(), 1, "Queue should have 1 item")
    var payload = JSON.parse_string(telemetry_service._telemetryQueue[0])
    assert_eq(payload["Type"], "PerformanceSpike", "Payload type should be PerformanceSpike")

func test_no_frame_spike():
    telemetry_service._telemetryQueue.clear()
    telemetry_service._process(0.016)

    assert_eq(telemetry_service._telemetryQueue.size(), 0, "Queue should be empty")
