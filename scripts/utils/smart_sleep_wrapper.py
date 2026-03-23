#!/usr/bin/env python3
import subprocess
import time
import os
import sys
import threading
import signal

# Default 30 minutes. Configured via export SMART_SLEEP_TIMEOUT=1800
TIMEOUT_SECONDS = int(os.environ.get("SMART_SLEEP_TIMEOUT", 1800))

def run_app():
    if len(sys.argv) < 2:
        print("Usage: smart_sleep_wrapper.py <command>")
        sys.exit(1)

    cmd = sys.argv[1:]
    
    # Launch the sub-process (e.g. ComfyUI)
    try:
        process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
    except Exception as e:
        print(f"[SMART SLEEP] Failed to launch process: {e}")
        sys.exit(1)
        
    last_output_time = [time.time()]
    
    def monitor_output():
        # Iterate over stdout, echoing it to the real terminal
        for line in process.stdout:
            sys.stdout.write(line)
            sys.stdout.flush()
            last_output_time[0] = time.time()
            
    t = threading.Thread(target=monitor_output, daemon=True)
    t.start()
    
    try:
        # Loop until the process naturally dies, or we kill it
        while process.poll() is None:
            if time.time() - last_output_time[0] > TIMEOUT_SECONDS:
                print(f"\n[SMART SLEEP] Idle detected for {TIMEOUT_SECONDS}s. Freeing VRAM and hibernating...", flush=True)
                # Graceful SIGINT
                process.send_signal(signal.SIGINT)
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    # Violent kill if it refuses to die
                    process.kill()
                    
                # 42 is our magic exit code indicating we went to sleep
                sys.exit(42)
            time.sleep(1)
    except KeyboardInterrupt:
        # If user presses Ctrl+C, gracefully pass it down
        process.send_signal(signal.SIGINT)
        process.wait()
        
    sys.exit(process.returncode)

if __name__ == "__main__":
    run_app()
