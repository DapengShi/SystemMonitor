#!/usr/bin/env python3

'''
CPU stress test script
This script will create a high CPU load to test the SystemMonitor app
'''

import multiprocessing
import time

def cpu_stress():
    # Infinite loop to consume CPU
    while True:
        pass

if __name__ == "__main__":
    print("Starting CPU stress test...")
    print("This script will create high CPU load to test the SystemMonitor app")
    print("Press Ctrl+C to stop the test")
    
    # Create processes equal to half the available cores
    num_cores = multiprocessing.cpu_count()
    num_processes = max(1, num_cores // 2)
    
    print(f"Creating {num_processes} worker processes on a {num_cores}-core system")
    
    # Start the worker processes
    processes = []
    for _ in range(num_processes):
        p = multiprocessing.Process(target=cpu_stress)
        p.start()
        processes.append(p)
    
    try:
        # Keep the main process running
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        # Terminate all processes when Ctrl+C is pressed
        print("\nStopping CPU stress test...")
        for p in processes:
            p.terminate()
        print("Test completed")
