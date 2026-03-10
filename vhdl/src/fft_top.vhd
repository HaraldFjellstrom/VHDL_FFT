------------------------------------------------------------------------------
--  Title        : FFT Top
--  File Name    : fft_top.vhd
--  Project      : VHDL2: Individual Task
--  Company      : AGSTU AB
--  Engineer     : Harald Fjellström
--
--  Description   :
--    Top-level integration component for the FFT. Architected for 
--    simulation-first verification with a modular path toward synthesis.
--
--    Provides a simplified interface for loading samples into memory and 
--    monitoring the calculation. Memory access follows a synchronous 
--    1-cycle latency model (data captured on the second rising edge 
--    following address presentation).
--
--  Sub-components:
--    - fft_pingpong_ram: Unified memory space acting as dual banks.
--    - fft_dif: Master FSM for DIF sequencing and address generation.
--    - fft_butterfly: Arithmetic worker for complex operations.
--
--  Generics      :
--    - N is the number of samples to use in calculation.
--    - SCALE_THRESHOLD is the value, summing the I and Q parts of a sample,
--      that when its reached the next calculation stage will downscale complex
--      multiplication to prevent overflow
--
--  Target Device : Simulation using GHDL or NVC
--  Tool Versions : GHDL 2.0.0 or NVC 1.20
--
--  Dependencies  :
--    - fft_util_pkg package
--    - twiddle_dif_q1_14_pkg package
--
--
--  Revision History :
--  --------------------------------------------------------------------------
--   Date        Version   Author              Description
--  --------------------------------------------------------------------------
--   2026-03-05  1.0       Harald Fjellström   Initial release
------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.twiddle_dif_q1_14_pkg.all;
use work.fft_util_pkg.all;

entity fft_top is
    generic (
        constant N : integer := 64;     -- Sample size
        constant SCALE_THRESHOLD : integer := 16383 -- Threshold for downscaling
    );
    port (
        clk    : in std_logic;          -- Clock input
        rst_n  : in std_logic;          -- Active-low reset

        -- Control input and output
        en     : in std_logic;          -- High Pulse starts calculation
        invert : in std_logic;          -- Set high to calculate IFFT
        done   : out std_logic;         -- Indicates complete calculation
        blk_exp: out natural range 0 to log2_ceil(N); -- Exponent for calculated data

        -- RAM Interface
        rd_data : out complex_q1_14;    -- Read data output
        wr_data : in complex_q1_14;     -- Write data input
        rd_addr : in integer range 0 to N-1;    -- Read adress
        wr_addr : in integer range 0 to N-1;    -- Write adress
        wr_en   : in std_logic          -- Write enable
    );
end entity;

architecture rtl of fft_top is

    -- Internal Ram Signals
    signal bank_sel : std_logic;
    signal bank_shft : std_logic;
    signal i_rd_addr : integer range 0 to N-1 := 0;
    signal i_wr_addr : integer range 0 to N-1 := 0;
    signal i_wr_en : std_logic;
    signal i_rd_data, i_wr_data : complex_q1_14;

    signal fft_rd_addr : integer range 0 to N-1 := 0;
    signal fft_wr_addr : integer range 0 to N-1 := 0;
    signal fft_wr_data : complex_q1_14;
    signal fft_wr_en : std_logic;

begin
    -- Throw compilation/simulation if N is not a power of two
    assert (2**log2_ceil(N) = N)
        report "N must be a power of 2"
        severity failure;

    -- Pingpong RAM instansiation
    inst_ppram: entity work.fft_pingpong_ram
        generic map(
            N => N
        )
        port map(
            clk    => clk,
            rd_data => i_rd_data,
            wr_data => i_wr_data,
            rd_addr => i_rd_addr,
            wr_addr => i_wr_addr,
            wr_en   => i_wr_en,
            bank_sel => bank_sel
        );

    -- FFT DIF instansiation
    inst_fft: entity work.fft_dif
        generic map(
            N => N,
            SCALE_THRESHOLD => SCALE_THRESHOLD
        )
        port map(
            clk => clk,
            rst_n => rst_n,

            -- Run
            en => en,
            done => done,
            invert => invert,
            bank_shft => bank_shft,
            blk_exp => blk_exp,

            -- RAM Interface, used controller
            rd_data => i_rd_data,
            wr_data => fft_wr_data,
            rd_addr => fft_rd_addr,
            wr_addr => fft_wr_addr,
            wr_en   => fft_wr_en
        );

    -- Process for muxing RAM access between FFT component during calculation
    -- and the interface used by testbenches.
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            bank_sel    <= '0';
            i_wr_en     <= '0';

        elsif rising_edge(clk) then
            -- Swap RAM banks
            if bank_shft = '1' then
                bank_sel <= not bank_sel;
            end if;

            -- When calculating, RAM used by FFT else exposed.
            if done = '0' then
                i_wr_data <= fft_wr_data;
                i_wr_addr <= fft_wr_addr;
                i_wr_en   <= fft_wr_en;
            else
                i_wr_data <= wr_data;
                i_wr_addr <= wr_addr;
                i_wr_en   <= wr_en;
            end if;

        end if;
    end process;
    
    i_rd_addr <= fft_rd_addr when done = '0' else rd_addr;
    rd_data <= i_rd_data;

end architecture;