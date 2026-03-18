import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
import numpy as np
import os

@cocotb.test()
async def run_hw_iteration(dut):
    # Start clock (100 MHz)
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    # 1. Load stimulus from the utility script
    stim_path = os.path.join(os.path.dirname(__file__), "stimulus.npz")
    stim_data = np.load(stim_path)
    re_in, im_in = stim_data['re'], stim_data['im']
    N = len(re_in)

    # 2. Reset and Load RAM
    do_invert = int(os.environ.get("HW_INVERT", "0"))
    dut.invert.value = do_invert
    dut.wr_addr.value = 0
    dut.en.value = 0
    dut.rst_n.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    for n in range(N):
        dut.wr_addr.value = n
        dut.wr_data.re.value = int(re_in[n])
        dut.wr_data.im.value = int(im_in[n])
        dut.wr_en.value = 1
        await RisingEdge(dut.clk)
        
    dut.wr_en.value = 0
    await RisingEdge(dut.clk)

    # 3. Pulse Enable and Meassure time until done
    dut.en.value = 1
    while dut.done.value != 0:
        await RisingEdge(dut.clk)
    dut.en.value = 0
    
    t_start = cocotb.utils.get_sim_time(unit='ns')
    while dut.done.value != 1:
        await RisingEdge(dut.clk)
    t_end = cocotb.utils.get_sim_time(unit='ns')
    
    # 4. Readback Result
    res_re = np.zeros(N)
    res_im = np.zeros(N)
    
    # Pre-fetch the first address
    dut.rd_addr.value = 0
    await RisingEdge(dut.clk) 

    for n in range(N):
        # Drive the address for the NEXT cycle
        if n < N - 1:
            dut.rd_addr.value = n + 1
        # Wait for the clock edge that presents data for address 'n'
        await RisingEdge(dut.clk)
        res_re[n] = dut.rd_data.re.value.to_signed()
        res_im[n] = dut.rd_data.im.value.to_signed()

    # 5. Save everything back to Jupyter
    calc_cycles = (t_end - t_start) / 10 # Assuming 100MHz / 10ns clock
    np.savez("results.npz", re=res_re, im=res_im, 
             exp=int(dut.blk_exp.value), cycles=int(calc_cycles))