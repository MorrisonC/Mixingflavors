import socket
import json
import time
import os
import sys

CYCLE_DIR = os.environ.get('CYCLE_DIR', 'cycle_00')
OUT_DIR = f"gauntlet_runs/{CYCLE_DIR}"
os.makedirs(OUT_DIR, exist_ok=True)

class GauntletDriver:
    def __init__(self):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.connected = False

    def connect(self, retries=10, delay=2):
        for i in range(retries):
            try:
                self.sock.connect(('127.0.0.1', 8090))
                self.connected = True
                print("Connected to GauntletBridge")
                return
            except Exception as e:
                print(f"Connection failed, retrying... ({i+1}/{retries})")
                time.sleep(delay)
        raise Exception("Failed to connect to Godot process")

    def send_cmd(self, cmd_dict):
        if not self.connected:
            return None
        msg = json.dumps(cmd_dict) + "\n"
        self.sock.sendall(msg.encode('utf-8'))

        buffer = ""
        while True:
            chunk = self.sock.recv(4096).decode('utf-8')
            if not chunk:
                break
            buffer += chunk
            if "\n" in buffer:
                break

        resp = buffer.strip()
        try:
            return json.loads(resp)
        except:
            return resp

    def close(self):
        self.sock.close()

def main():
    driver = GauntletDriver()
    driver.connect()

    def capture(name, wait_after=0.5):
        time.sleep(wait_after) # wait for render
        path = os.path.join(OUT_DIR, f"{name}.png")
        # Ensure path is absolute for godot
        path = os.path.abspath(path)
        print(f"Capturing: {path}")
        resp = driver.send_cmd({"cmd": "capture", "name": path})
        print(resp)

    try:
        driver.send_cmd({"cmd": "switch_mode", "target": 4})
        time.sleep(1)

        driver.send_cmd({"cmd": "switch_mode", "target": 2})
        time.sleep(1)

        capture("before_chisel")

        driver.send_cmd({"cmd": "trigger_chisel_at", "x": 1, "y": 1, "z": 1})

        capture("anim_chisel_1", 0.05)
        capture("anim_chisel_2", 0.05)
        capture("anim_chisel_3", 0.05)
        capture("anim_chisel_4", 0.05)

        driver.send_cmd({"cmd": "trigger_mark_at", "x": 0, "y": 1, "z": 1})

        capture("anim_mark_1", 0.05)
        capture("anim_mark_2", 0.05)
        capture("anim_mark_3", 0.05)
        capture("anim_mark_4", 0.05)

    finally:
        driver.close()
        print("Done")

if __name__ == "__main__":
    main()
