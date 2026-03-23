import torch
import time
import sys
import warnings

warnings.filterwarnings('ignore')

def run_benchmark():
    # Attempt to gracefully load ROCm
    if not torch.cuda.is_available():
        print("SCORE: 9999.0")
        sys.exit(1)
        
    device = torch.device('cuda')
    
    # 4096x4096 is standard image latent dimensions logic that exercises MIGRAPHX
    size = 4096
    
    try:
        A = torch.randn(size, size, device=device)
        B = torch.randn(size, size, device=device)
    except Exception as e:
        print("SCORE: 9999.0")
        sys.exit(1)
    
    # Warmup the ROCm Pipeline
    for _ in range(3):
        _ = torch.matmul(A, B)
    torch.cuda.synchronize()
    
    start_time = time.time()
    
    # Main benchmark loop heavily mixing matrix math and softmax (attention bottleneck)
    iterations = 50
    for _ in range(iterations):
        C = torch.matmul(A, B)
        # Dummy softmax replicates attention where memory/MIGRAPHX optimizations shine
        _ = torch.nn.functional.softmax(C, dim=-1)
        
    torch.cuda.synchronize()
    duration = time.time() - start_time
    
    # Print exactly the float score for bash script strictly
    print(f"SCORE: {duration:.4f}")

if __name__ == "__main__":
    run_benchmark()
