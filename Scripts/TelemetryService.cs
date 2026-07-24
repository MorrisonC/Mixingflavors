using Godot;
using System;
using System.Collections.Concurrent;
using System.Net.Http;
using System.Text.Json;
using System.Threading.Tasks;

namespace HybridTacticalPuzzleRPG
{
    public partial class TelemetryService : Node
    {
        public static TelemetryService Instance { get; private set; }

        // Telemetry tracking variables
        private double _timeSinceLastSample = 0.0;
        private const double SampleInterval = 5.0; // 5 seconds
        private const double FrameSpikeThresholdMs = 33.3; // Roughly < 30 FPS

        // Thread-safe queues for async processing
        private ConcurrentQueue<string> _telemetryQueue = new ConcurrentQueue<string>();
        private System.Net.Http.HttpClient _httpClient;

        // Use a generic placeholder or local server for testing
        private string _telemetryEndpoint = "http://localhost:8080/api/telemetry";

        public override void _EnterTree()
        {
            if (Instance == null)
            {
                Instance = this;
                _httpClient = new System.Net.Http.HttpClient();
            }
            else
            {
                QueueFree();
            }
        }

        public override void _Process(double delta)
        {
            _timeSinceLastSample += delta;

            // Track Frame Spikes
            double currentFrameTimeMs = delta * 1000.0;
            if (currentFrameTimeMs > FrameSpikeThresholdMs)
            {
                LogPerformanceSpike(currentFrameTimeMs);
            }

            // Periodic Performance Sampling
            if (_timeSinceLastSample >= SampleInterval)
            {
                SamplePerformanceMetrics();
                _timeSinceLastSample = 0.0;

                // Flush queue occasionally (simplified)
                Task.Run(() => FlushTelemetryQueue());
            }
        }

        private void LogPerformanceSpike(double frameTimeMs)
        {
            var data = new
            {
                Type = "PerformanceSpike",
                Timestamp = DateTime.UtcNow,
                FrameTimeMs = frameTimeMs,
                MemoryUsage = OS.GetStaticMemoryUsage()
            };
            EnqueueTelemetry(data);
        }

        private void SamplePerformanceMetrics()
        {
            var data = new
            {
                Type = "PerformanceSample",
                Timestamp = DateTime.UtcNow,
                FPS = Engine.GetFramesPerSecond(),
                MemoryUsage = OS.GetStaticMemoryUsage()
            };
            EnqueueTelemetry(data);
        }

        public void LogPuzzleCompletion(string puzzleId, float timeToSolveSeconds, int misclicks)
        {
            var data = new
            {
                Type = "PuzzleCompletion",
                Timestamp = DateTime.UtcNow,
                PuzzleId = puzzleId,
                SolveTime = timeToSolveSeconds,
                Misclicks = misclicks
            };
            EnqueueTelemetry(data);
        }

        public void LogMisclick(string puzzleId)
        {
             var data = new
            {
                Type = "PuzzleMisclick",
                Timestamp = DateTime.UtcNow,
                PuzzleId = puzzleId
            };
            EnqueueTelemetry(data);
        }

        public void LogNarrativeEvent(string pageId, string choiceMade)
        {
            var data = new
            {
                Type = "NarrativeChoice",
                Timestamp = DateTime.UtcNow,
                PageId = pageId,
                Choice = choiceMade
            };
            EnqueueTelemetry(data);
        }

        private void EnqueueTelemetry(object data)
        {
            string json = JsonSerializer.Serialize(data);
            _telemetryQueue.Enqueue(json);
            GD.Print($"[Telemetry] Enqueued: {json}");
        }

        private async Task FlushTelemetryQueue()
        {
            while (_telemetryQueue.TryDequeue(out string payload))
            {
                try
                {
                    // For AI playability testing, we just print the JSON.
                    // In production, uncomment the HTTP POST request below.
                    GD.Print($"[Telemetry Flush (AI Test Mode)]: {payload}");

                    /*
                    var content = new StringContent(payload, System.Text.Encoding.UTF8, "application/json");
                    var response = await _httpClient.PostAsync(_telemetryEndpoint, content);
                    if (!response.IsSuccessStatusCode)
                    {
                        GD.PrintErr($"Failed to send telemetry: {response.StatusCode}");
                    }
                    */
                }
                catch (Exception e)
                {
                    GD.PrintErr($"Telemetry exception: {e.Message}");
                }
            }
        }
    }
}
