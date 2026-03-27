#!/usr/bin/env python3
import subprocess
import time
import os
import sys
import threading
import signal
import pty

# Default 30 minutes. Configured via export SMART_SLEEP_TIMEOUT=1800
TIMEOUT_SECONDS = int(os.environ.get("SMART_SLEEP_TIMEOUT", 1800))

def run_app():
    if len(sys.argv) < 2:
        print("Usage: smart_sleep_wrapper.py <command>")
        sys.exit(1)

    cmd = sys.argv[1:]
    
    # Create pseudo-terminal to preserve TTY behavior (fixes colorama/progress bar crashes)
    master_fd, slave_fd = pty.openpty()
    
    try:
        process = subprocess.Popen(
            cmd,
            stdin=slave_fd,
            stdout=slave_fd,
            stderr=slave_fd,
            close_fds=True
        )
    except Exception as e:
        print(f"[SMART SLEEP] Failed to launch process: {e}")
        sys.exit(1)
        
    os.close(slave_fd) # Close slave in parent so we get EOF when child exits
    
    last_output_time = [time.time()]
    
    def monitor_output():
        while True:
            try:
                data = os.read(master_fd, 1024)
                if not data:
                    break
                # Echo data to the real terminal
                sys.stdout.buffer.write(data)
                sys.stdout.flush()
                # Reset idle timer
                last_output_time[0] = time.time()
            except OSError:
                break
                
    t = threading.Thread(target=monitor_output, daemon=True)
    t.start()
    
    try:
        # Loop until the process naturally dies, or we kill it due to idle
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
