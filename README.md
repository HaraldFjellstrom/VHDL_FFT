# Fixed-Point FFT Core (VHDL)
[![VHDL Verification](https://github.com/YOUR_USERNAME/VHDL_FFT/actions/workflows/main.yml/badge.svg)](https://github.com/YOUR_USERNAME/VHDL_FFT/actions)

A parameterizable, high-performance Fast Fourier Transform (FFT) implementation developed for the **AGSTU VHDL 2** advanced digital design course. This project demonstrates a modern hardware-to-software verification flow, bridging VHDL RTL with Python-based signal analysis and automated CI/CD reporting.

## 🚀 Key Features
* **Parameterizable Architecture:** Fully configurable FFT length and bit-widths via VHDL generics.
* **Python-Driven Verification:** Integration of `cocotb` and `nvc` for rigorous hardware-in-the-loop testing.
* **Automated Reporting:** A custom GitHub Actions pipeline executes simulations on every push, generating a timestamped PDF report containing SQNR, ENOB, and signal reconstruction analysis.
* **Fixed-Point Analysis:** Built-in tools for quantifying quantization noise and validating bit-accurate behavior.

## 🛠 Prerequisites
* **OS:** Linux or WSL2 (Ubuntu recommended).
* **VHDL Simulator:** [NVC](https://github.com/nickg/nvc).
* **Environment:** Python 3.10+ with `venv`.

## 📦 Getting Started

### 1. Clone the Repository
```bash
git clone [https://github.com/YOUR_USERNAME/VHDL_FFT.git](https://github.com/YOUR_USERNAME/VHDL_FFT.git)
cd VHDL_FFT

### 2. Initialize Environment
The setup script automates the creation of a Python virtual environment and installs the required toolchain (Cocotb, NumPy, Matplotlib, Papermill).

```bash
source setup_env.sh

[!NOTE]
This script ensures all dependencies are pinned to compatible versions. If you encounter permissions issues with the simulator (NVC), ensure it is correctly mapped in your $PATH.

### 3. Run Interactive Analysis
The project includes a Jupyter-based analysis suite that serves as both a development playground and a verification engine. 

To launch the environment:
```bash
jupyter lab notebooks/Verification_report.ipynb

**Within the notebook, you can:**

* **Modify Hardware Generics:** Test different FFT point sizes ($N$) and bit-widths on the fly to evaluate hardware resource trade-offs.
* **Visualize Results:** Generate real-time plots for **SQNR** (Signal-to-Quantization-Noise Ratio) and **ENOB** (Effective Number of Bits) to quantify precision loss.
* **Debug Bit-Accuracy:** Compare the VHDL fixed-point output against a double-precision NumPy reference to identify potential overflow, saturation, or rounding issues.

## 🧪 Verification Methodology

The verification environment utilizes a hybrid hardware/software co-simulation strategy to ensure the bit-accuracy of the VHDL implementation:

* **Stimulus Generation:** High-level test vectors (Harmonics, Impulses, and White Noise) are generated using **NumPy** to provide a wide range of spectral coverage.
* **Co-Simulation Flow:** Data is transferred between the Python test environment and the VHDL testbench via binary files. This process is abstracted through the `fft_utils` library, allowing for seamless data flow between the high-level model and the RTL.
* **Automated Regression:** To validate the design's parameterizable nature, the pipeline forces a clean re-compilation of the VHDL source for every configuration. This ensures that **generics** (such as FFT length and scaling factors) are correctly applied and verified across the full regression suite.
* **Metrics & Analysis:** The hardware output is compared against a floating-point reference model to calculate key performance indicators:
    * **SQNR / ENOB:** Quantifies the noise floor introduced by fixed-point arithmetic.
    * **Roundtrip Analysis:** Validates the IFFT(FFT(x)) chain to ensure signal reconstruction integrity.

Here is the Project Structure section in Markdown. I’ve organized it using a clean directory tree format, which is the standard way to help others navigate your codebase quickly.

Markdown
## 📝 Project Structure

The repository is organized to separate the hardware implementation from the verification and documentation layers:

* **`rtl/`**: Contains the VHDL source files for the FFT core, including the butterfly units and address generation logic.
* **`sim/`**: Includes the `cocotb` testbenches, simulation makefiles, and raw simulation results.
* **`notebooks/`**: Jupyter notebooks used for regression execution, data visualization, and automated report generation.
* **`fft_utils/`**: A Python helper library for fixed-point/floating-point conversions and binary data handling.
* **`docs/`**: Contains the final architecture documentation and the completed **H