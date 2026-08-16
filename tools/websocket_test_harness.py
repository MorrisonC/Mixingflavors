import asyncio
import json
import websockets
import sys

async def run_harness():
    uri = "ws://127.0.0.1:9080"
    print(f"[TestHarness] Connecting to {uri}...")

    try:
        async with websockets.connect(uri) as ws:
            print("[TestHarness] Connected successfully!")

            # 1. Ping test
            req = {"id": "1", "action": "ping", "data": {}}
            await ws.send(json.dumps(req))
            resp = json.loads(await ws.recv())
            print("[TestHarness] Ping Response:", resp)
            assert resp.get("result") == "pong", "Ping failed"

            # 2. Get current game mode
            req = {"id": "2", "action": "get_current_mode", "data": {}}
            await ws.send(json.dumps(req))
            resp = json.loads(await ws.recv())
            print("[TestHarness] Mode Response:", resp)

            # 3. Switch mode to ESCAPE_GAUNTLET (2)
            req = {"id": "3", "action": "switch_mode", "data": {"mode": 2}}
            await ws.send(json.dumps(req))
            resp = json.loads(await ws.recv())
            print("[TestHarness] Switch Mode Response:", resp)
            await asyncio.sleep(0.5)

            # 4. Check puzzle state
            req = {"id": "4", "action": "get_puzzle_state", "data": {}}
            await ws.send(json.dumps(req))
            resp = json.loads(await ws.recv())
            print("[TestHarness] Puzzle State Response:", resp)

            # 5. Execute Chisel action at (0, 0, 0)
            req = {"id": "5", "action": "chisel", "data": {"x": 0, "y": 0, "z": 0}}
            await ws.send(json.dumps(req))
            resp = json.loads(await ws.recv())
            print("[TestHarness] Chisel Response:", resp)
            assert resp.get("result") == True, "Chisel action failed"

            # 6. Execute Mark action at (1, 1, 1)
            req = {"id": "6", "action": "mark", "data": {"x": 1, "y": 1, "z": 1}}
            await ws.send(json.dumps(req))
            resp = json.loads(await ws.recv())
            print("[TestHarness] Mark Response:", resp)
            assert resp.get("result") == True, "Mark action failed"

            # 7. Set Slice X = 2
            req = {"id": "7", "action": "set_slice", "data": {"axis": "x", "value": 2}}
            await ws.send(json.dumps(req))
            resp = json.loads(await ws.recv())
            print("[TestHarness] Set Slice Response:", resp)
            assert resp.get("result") == True, "Set slice failed"

            # 8. Force solve puzzle
            req = {"id": "8", "action": "solve_puzzle", "data": {}}
            await ws.send(json.dumps(req))
            resp = json.loads(await ws.recv())
            print("[TestHarness] Solve Puzzle Response:", resp)
            assert resp.get("result") == True, "Solve puzzle failed"

            print("\n==========================================")
            print("ALL WEBSOCKET HARNESS TESTS PASSED 100%!")
            print("==========================================\n")

    except Exception as e:
        print(f"[TestHarness] ERROR: {e}")
        sys.exit(1)

if __name__ == "__main__":
    asyncio.run(run_harness())
