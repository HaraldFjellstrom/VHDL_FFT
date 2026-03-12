# VHDL_FFT
FFT implementation in VHDL for AGSTU VHDL 2 course individual task.

## Requrements
Linux operating system (or WSL) with NVC and python in PATH.

## Setup
To get started follow these steps:
1, Clone this repository
2, Run "source setup_env.sh" to create viritual environment and download python dependaicies.
3, Start jupyter lab server, in the notebook folder there is an example to show how to run the simulations and plot data.

## Simulation setup
The jupyter environment communicates with the cocotb testbench using numpy binary files, these file write and reads
are abstracted away by using helper functions defined in the fft_utils file.

Every trigger of the hardware simulation forces a recompilation of the VHDL source, this is needed because of the 
generics.

## Notes
Might be able to squeace out some more precission by changing to wider twiddles.
