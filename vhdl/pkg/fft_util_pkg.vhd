------------------------------------------------------------------------------
--  Title         : FFT Utility Package
--  File Name     : fft_util_pkg.vhd
--  Project       : VHDL2: Individual Task
--  Company       : AGSTU AB
--  Engineer      : Harald Fjellström
--
--  Description   :
--    Common utility package for the FFT project. Contains global type 
--    definitions for complex fixed-point arithmetic (Q1.14 format) and 
--    helper functions for hardware-friendly mathematical operations.
--
--    Key features:
--    - complex_q1_14: Standardized record for I/Q data handling.
--    - log2_ceil: Provides parameterization support for generic FFT sizing.
--    - bit_reverse: Essential for reordering Decimation-in-Frequency (DIF) 
--      output bins into natural order.
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

package fft_util_pkg is

    -- Record type for readability (note that records dont play nice with some tools)
    type complex_q1_14 is record
        re : signed(15 downto 0);
        im : signed(15 downto 0);
    end record;

    function log2_ceil(n : integer) return integer;
    function bit_reverse(input : natural; width : natural) return natural;

end package;

package body fft_util_pkg is

    -- Log2 Ceiling: Used to determine required bit-width (STAGE_COUNT) for a given N
    function log2_ceil(n : integer) return integer is
    begin
    if n <= 1 then
        return 0;
    else
        for i in 1 to 32 loop
        if 2**i >= n then
            return i;
        end if;
        end loop;
    end if;
    return 0;
    end function;

    -- Bit Reverse: Reorders Decimation-in-Frequency (DIF) output into natural order.
    -- Example for width 3: "001" (1) becomes "100" (4).
    function bit_reverse(input : natural; width : natural) return natural is
        variable result : unsigned(width-1 downto 0);
        variable temp   : unsigned(width-1 downto 0);
    begin
        temp := to_unsigned(input, width);
        for i in 0 to width-1 loop
            result(i) := temp(width-1-i);
        end loop;
        return to_integer(result);
    end function;

end package body;