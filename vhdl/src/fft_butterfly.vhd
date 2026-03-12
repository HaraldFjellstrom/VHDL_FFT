------------------------------------------------------------------------------
--  Title         : FFT Butterfly Unit (Radix-2 DIF)
--  File Name     : fft_butterfly.vhd
--  Project       : VHDL2: Individual Task
--  Company       : AGSTU AB
--  Engineer      : Harald Fjellström
--
--  Description   :
--    Core arithmetic unit for the Decimation-in-Frequency (DIF) FFT. Performs 
--    the butterfly operation: 
--    Y0 = X0 + X1 
--    Y1 = (X0 - X1) * W
--
--    Interface Logic:
--    The 'en' (enable) and 'done' signals are implemented to facilitate 
--    future pipelining. By treating the butterfly as an asynchronous or 
--    multi-cycle task, the main FFT FSM remains agnostic to the internal 
--    latency of the arithmetic. This allows for a modular transition from 
--    this single-cycle behavioral model to a multi-stage pipelined 
--    hardware implementation without requiring logic changes to the 
--    master state machine.
--
--    Features include optional downscaling (for overflow prevention), IFFT 
--    support via twiddle inversion, and rounded fixed-point arithmetic.
--
--  Synthesis & Hardware Note:
--    This component is designed for simulation and behavioral clarity. It 
--    is NOT optimized for direct synthesis on resource-constrained FPGAs 
--    like the iCE40. The use of behavioral '*' operators for 16x16 complex 
--    multiplication will likely infer a large amount of PLB/LUT logic, 
--    resulting in poor timing performance and high area usage. 
--
--    To target iCE40 hardware efficiently, this logic should be refactored 
--    to explicitly instantiate the SB_MAC16 (DSP) blocks, or pipelined 
--    extensively to allow the synthesizer to map the logic to those blocks 
--    automatically.
--
--  Revision History :
--  --------------------------------------------------------------------------
--   Date        Version   Author               Description
--  --------------------------------------------------------------------------
--   2026-03-05  1.0       Harald Fjellström    Initial release
------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.fft_util_pkg.all;

entity fft_butterfly is
    port (
        clk : in std_logic;
        rst_n : in std_logic;
        en : in std_logic;
        done : out std_logic;
        invert : in std_logic;
        scale : in std_logic;
        x0 : in complex_q1_14;
        x1 : in complex_q1_14;
        w : in complex_q1_14;
        y0 : out complex_q1_14;
        y1 : out complex_q1_14
    );
end entity;

architecture rtl of fft_butterfly is

begin

    process(clk, rst_n)
        -- Calculation variables
        variable sum_re, diff_re : signed(16 downto 0);
        variable sum_im, diff_im : signed(16 downto 0);
        variable ac, bd, ad, bc  : signed(33 downto 0);
        variable mul_re, mul_im  : signed(34 downto 0);
        variable w_re_ext, w_im_ext : signed(16 downto 0);
        variable tmp_y1_re, tmp_y1_im : signed(15 downto 0);
    begin
        if rst_n = '0' then
            y0 <= (re => (others => '0'), im => (others => '0'));
            y1 <= (re => (others => '0'), im => (others => '0'));
            done <= '0';
        elsif rising_edge(clk) then
            -- Stage 1: Summation (Y0 path)
            -- Resize to Q2.14 to prevent overflow during addition
            sum_re := resize(x0.re, x0.re'length+1) + resize(x1.re, x1.re'length+1);    --Q2.14
            sum_im := resize(x0.im, x0.im'length+1) + resize(x1.im, x1.im'length+1);

            -- Extract Q1.14 from sum
            -- Apply conditional scaling (divide by 2) for bit-growth management
            if scale = '1' then
                y0.re <= sum_re(16 downto 1);
                y0.im <= sum_im(16 downto 1);
            else
                y0.re <= sum_re(15 downto 0);
                y0.im <= sum_im(15 downto 0);
            end if;  

            -- Stage 2: Difference and Complex Multiplication (Y1 path)
            diff_re := resize(x0.re, x0.re'length+1) - resize(x1.re, x1.re'length+1);    -- Q2.14
            diff_im := resize(x0.im, x0.im'length+1) - resize(x1.im, x1.im'length+1);

            -- Handle Twiddle (W) inversion for IFFT mode
            w_re_ext := resize(w.re, 17);  -- Q1.16
            if invert = '0' then
                w_im_ext := resize(w.im, 17);
            else 
                w_im_ext := -resize(w.im, 17); -- Conjugate for IFFT
            end if;

            -- 16x16 bit multiplication (Q2.14 * Q1.14 = Q4.28)
            ac := diff_re * w_re_ext;  
            bd := diff_im * w_im_ext;  
            ad := diff_re * w_im_ext;  
            bc := diff_im * w_re_ext;  

            -- Combine partial products
            mul_re := resize(ac, 35) - resize(bd, 35);   -- Q5.28
            mul_im := resize(ad, 35) + resize(bc, 35);

            -- Convergent Rounding: Add half-LSB (2^14) before truncation
            mul_re := mul_re + to_signed(2**14, mul_re'length);
            mul_im := mul_im + to_signed(2**14, mul_im'length);

            -- Final scaling and assignment for Y1, slicing back to Q1.14
            if scale = '1' then
                y1.re <= mul_re(30 downto 15);
                y1.im <= mul_im(30 downto 15);
            else
                y1.re <= mul_re(29 downto 14);
                y1.im <= mul_im(29 downto 14);
            end if;  
            
            -- Pulse done to indicate single-cycle calculation completion
            if en = '1' then
                done <= '1';
            else
                done <= '0';
            end if;
        end if;
    end process;

end architecture;
