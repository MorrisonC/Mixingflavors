using Godot;
using System;
using System.Collections.Generic;

namespace HybridTacticalPuzzleRPG
{
    public partial class PaintingCanvas2D : Node2D
    {
        private bool _isDrawing = false;
        private Vector2 _currentLineStart;
        private List<Vector2> _drawnLines = new List<Vector2>();

        // Hidden points of interest on the painting that the player needs to connect.
        private List<Vector2> _hiddenAnchors = new List<Vector2>();

        public override void _Ready()
        {
            // Set ProcessInput to true to receive mouse/touch events.
            SetProcessInput(true);

            // Example of setting up anchors for the Masquerade system.
            _hiddenAnchors.Add(new Vector2(100, 100)); // Example: An eye
            _hiddenAnchors.Add(new Vector2(250, 300)); // Example: A fingertip
        }

        public override void _Input(InputEvent @event)
        {
            if (GameManager.Instance.CurrentMode != GameMode.MasqueradePainting) return;

            if (@event is InputEventMouseButton mouseEvent)
            {
                if (mouseEvent.ButtonIndex == MouseButton.Left)
                {
                    if (mouseEvent.Pressed)
                    {
                        StartDrawing(mouseEvent.Position);
                    }
                    else
                    {
                        FinishDrawing(mouseEvent.Position);
                    }
                }
            }
            else if (@event is InputEventScreenTouch touchEvent)
            {
                if (touchEvent.Pressed)
                {
                    StartDrawing(touchEvent.Position);
                }
                else
                {
                    FinishDrawing(touchEvent.Position);
                }
            }
        }

        private void StartDrawing(Vector2 position)
        {
            _isDrawing = true;
            _currentLineStart = position;
        }

        private void FinishDrawing(Vector2 position)
        {
            if (!_isDrawing) return;
            _isDrawing = false;

            _drawnLines.Add(_currentLineStart);
            _drawnLines.Add(position);

            QueueRedraw();
            ValidateConnection(_currentLineStart, position);
        }

        private void ValidateConnection(Vector2 start, Vector2 end)
        {
            // Simple validation: check if the drawn line connects two hidden anchors within a tolerance.
            float tolerance = 20.0f;
            bool startMatched = false;
            bool endMatched = false;

            foreach (var anchor in _hiddenAnchors)
            {
                if (start.DistanceTo(anchor) < tolerance) startMatched = true;
                if (end.DistanceTo(anchor) < tolerance) endMatched = true;
            }

            if (startMatched && endMatched)
            {
                GD.Print("Valid hidden connection found!");
                // Trigger unlock event
                if (TelemetryService.Instance != null)
                {
                    TelemetryService.Instance.LogPuzzleCompletion("Painting_HiddenLine", 10.5f, 0); // Placeholder data
                }
            }
            else
            {
                 if (TelemetryService.Instance != null)
                {
                    TelemetryService.Instance.LogMisclick("Painting_HiddenLine");
                }
            }
        }

        public override void _Draw()
        {
            // Draw all lines the player has created.
            for (int i = 0; i < _drawnLines.Count; i += 2)
            {
                DrawLine(_drawnLines[i], _drawnLines[i+1], Colors.Red, 3.0f);
            }
        }
    }
}
