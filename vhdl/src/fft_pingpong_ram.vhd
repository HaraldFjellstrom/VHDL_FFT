------------------------------------------------------------------------------
--  Title         : FFT Dual-Bank RAM (Single-Port iCE40 Optimized)
--  File Name     : fft_pingpong_ram.vhd
--  Project       : VHDL2: Individual Task
--  Company       : AGSTU AB
--  Engineer      : Harald Fjellström
--
--  Description   :
--    A single-port memory structure behaving as a ping-pong buffer via
--    MSB address decoding.
--
--  Hardware Implementation Note:
--    By treating both banks as a single contiguous array, this design allows
--    synthesis tools to map the memory efficiently into available FPGA 
--    resources such as iCE40 EBR or SPRAM. For physical hardware targets, 
--    it is recommended to split the 'complex_q1_14' record into separate 
--    Real and Imaginary 16-bit wide RAM blocks to align with native FPGA 
--    memory slice architectures.
--
--    Operational Logic:
--    - Bank Selection: Controlled via the 'bank_sel' port.
--    - Read Path: Inverts bank_sel (Reads from the "inactive" bank).
--    - Write Path: Uses bank_sel (Writes to the "active" bank).
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
use work.twiddle_dif_q1_14_pkg.all;

use work.fft_util_pkg.all;

entity fft_pingpong_ram is
    generic (
        constant N : integer := 64      -- Number of samples/size of each bank
    );
    port (
        clk    : in std_logic;
        -- RAM Interface
        rd_data : out complex_q1_14;
        wr_data : in complex_q1_14;
        rd_addr : in integer range 0 to N-1;
        wr_addr : in integer range 0 to N-1;
        wr_en   : in std_logic;
        bank_sel : in std_logic
    );
end entity;

architecture rtl of fft_pingpong_ram is

    type complex_q1_14_array is array (natural range <>) of complex_q1_14;
    signal ram : complex_q1_14_array(0 to N*2-1);

    constant W : integer := log2_ceil(N);    -- Address bit width

begin

    process(clk)
    begin
        -- Synchronous singleport RAM, MSB is used as bank selection
        if rising_edge(clk) then
            rd_data <= ram(to_integer(unsigned(not bank_sel & std_logic_vector(to_unsigned(rd_addr, W)))));
            if wr_en = '1' then
                ram(to_integer(unsigned(bank_sel & std_logic_vector(to_unsigned(wr_addr, W))))) <= wr_data;
            end if;
        end if;
    end process;

end architecture;