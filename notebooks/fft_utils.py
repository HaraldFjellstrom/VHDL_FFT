import numpy as np
import os
import logging
from cocotb_tools.runner import get_runner

Q = 14  # Q1.14 fixed-point format
FULL_SCALE = 2**Q
def float_to_q14(x, scale=1.0):
    """Convert float (-1..1) to signed Q1.14 integer."""
    return int(np.clip(x * scale, -1, 0.9999) * FULL_SCALE)

def q14_to_float(x):
    return x / FULL_SCALE

def run_sim(input_signal, invert=False, SCALE_THRESHOLD=8191, wave_file=None):
    N = len(input_signal)
    sim_dir = os.path.abspath("../sim")
    vhdl_dir = os.path.abspath("../vhdl") # Path to your .vhd files

    # 1. Quantization & Stimulus (Same as before)
    re_int = np.clip(np.round(np.real(input_signal) * 16384), -32768, 32767).astype(np.int32)
    im_int = np.clip(np.round(np.imag(input_signal) * 16384), -32768, 32767).astype(np.int32)
    np.savez(os.path.join(sim_dir, "stimulus.npz"), re=re_int, im=im_int)

    # 2. Setup the Runner
    tools_logger = logging.getLogger("cocotb_tools.runner")
    tools_logger.setLevel(logging.ERROR)
    logging.getLogger("cocotb").setLevel(logging.ERROR)
    
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
        test_args.append(f"--format=vcd")

    # Inside run_sim in fft_utils.py
    #print(f"--- Starting Hardware Simulation (N={N}) ---")
    
    # 4. Execute Simulation
    # runner.test() returns None but raises an exception if the sim process fails
    try:
        runner.test(
            hdl_toplevel="fft_top",
            test_module="test_fft",
            test_dir=sim_dir,
            parameters={"N": N, "SCALE_THRESHOLD" : SCALE_THRESHOLD},
            test_args=test_args,
            extra_env={"HW_INVERT": str(int(invert))},
            results_xml="results.xml",
            log_file="sim_output.log"
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


def analyze_fft_performance(input_signal, hw_sig, hw_exp, is_ifft=False):
    """
    Compares Hardware FFT output against NumPy's Golden Model.
    
    Args:
        input_signal: The original complex time-domain signal.
        hw_sig: The output returned from run_sim (already normalized).
        hw_exp: The block exponent returned from run_sim.
        is_ifft: Boolean flag to switch between FFT and IFFT comparison.
    """
    N = len(input_signal)
    
    # 1. Generate Golden Reference
    if is_ifft:
        # If testing IFFT, the input_signal is already in frequency domain
        golden_ref = np.fft.ifft(input_signal)
    else:
        golden_ref = np.fft.fft(input_signal)

    # 2. Alignment and Normalization
    hw_sig = ( hw_sig * (2.0**(hw_exp)) )
    
    # 3. Calculate Mean Squared Error (MSE)
    # MSE = average(|Golden - HW|^2)
    error = golden_ref - hw_sig
    mse = np.mean(np.abs(error)**2)
    
    # 4. Calculate Signal-to-Quantization-Noise Ratio (SQNR)
    signal_power = np.mean(np.abs(golden_ref)**2)
    
    if mse == 0:
        # If the error is zero, the SQNR is effectively limited only by 
        # the precision of the floating point numbers used for the check.
        # Theoretical max SQNR ~= 6.02 x 14 + 1.76 = 86.04 dB
        sqnr = 90.0 # Or any high number that represents "Perfect"
    else:
        sqnr = 10 * np.log10(signal_power / mse)
        sqnr = min(sqnr, 90.0)

    max_diff = np.max(np.abs(error))

    return {
        "mse": mse,
        "sqnr_db": sqnr,
        "max_diff": max_diff,
        "golden": golden_ref,
        "error_vec": error
    }