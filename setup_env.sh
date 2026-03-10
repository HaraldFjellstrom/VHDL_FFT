#!/bin/bash
python3 -m venv .vhdl_env
source .vhdl_env/bin/activate
pip install -r requirements.txt
python3 -m ipykernel install --user --name=vhdl_fft --display-name "VHDL FFT Project"
echo "Setup Complete. Launch Jupyter and select the 'VHDL FFT Project' kernel."
