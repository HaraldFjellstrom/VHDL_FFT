import numpy as np
import os

def run_sim(input_signal, invert=False, wave_file=None):
    N = len(input_signal)
    sim_dir = os.path.abspath("../sim")
    vhdl_dir = os.path.abspath("../vhdl") # Path to your .vhd files

    # 1. Quantization & Stimulus (Same as before)
    re_int = np.clip(np.round(np.real(input_signal) * 16384), -32768, 32767).astype(np.int32)
    im_int = np.clip(np.round(np.imag(input_signal) * 16384), -32768, 32767).astype(np.int32)
    np.savez(os.path.join(sim_dir, "stimulus.npz"), re=re_int, im=im_int)

    # 2. Setup the Runner
    from cocotb_tools.runner import get_runner
    runner = get_runner("nvc")

    # 3. THE FIX: Build Step
    # List all your VHDL files here. Cocotb 2.0 uses this to initialize the runner object.
    vhdl_sources = [
        os.path.join(vhdl_dir, "pkg/fft_util_pkg.vhd"),
        os.path.join(vhdl_dir, "pkg/twiddle_dif_q1_14_pkg.vhd"),
        os.path.join(vhdl_dir, "src/fft_butterfly.vhd"),
        os.path.join(vhdl_dir, "src/fft_pingpong_ram.vhd"),
        os.path.join(vhdl_dir, "src/fft_dif.vhd"),
        os.path.join(vhdl_dir, "src/fft_top.vhd")
    ]

    runner.build(
        sources=vhdl_sources,
        hdl_toplevel="fft_top",
        always=True        # Force re-compile
    )

    # 4. Run Test
    test_args = []
    if wave_file:
        test_args.append(f"--wave={os.path.join(sim_dir, wave_file)}")

    # Inside run_sim in fft_utils.py
    print(f"--- Starting Hardware Simulation (N={N}) ---")
    
    # 4. Execute Simulation
    # runner.test() returns None but raises an exception if the sim process fails
    try:
        runner.test(
            hdl_toplevel="fft_top",
            test_module="test_fft",
            test_dir=sim_dir,
            parameters={"N": N, "SCALE_THRESHOLD" : 8191},
            test_args=test_args,
            extra_env={"HW_INVERT": str(int(invert))}
        )
    except Exception as e:
        print("❌ The simulator process crashed or returned an error.")
        print("Check the terminal output above for the specific VHDL/Cocotb error.")
        raise e
    
    # 5. Reconstruct
    results_path = os.path.join(sim_dir, "results.npz")
    data = np.load(results_path)
    #sig_hw = (data['re'] + 1j*data['im']) * (2.0**data['exp']) / 16384.0
    sig_hw = np.zeros(N, dtype=complex)
    sig_hw = (data['re'] + 1j*data['im']) / (16384.0)
    
    # If inverted scale back to original amplitude
    #if invert:
    #    sig_hw = sig_hw / N
        
    return sig_hw, int(data['exp']), int(data['cycles'])