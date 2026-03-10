------------------------------------------------------------------------------
--  Title         : FFT Radix-2 DIF 
--  File Name     : fft_dif.vhd
--  Project       : VHDL2: Individual Task
--  Company       : AGSTU AB
--  Engineer      : Harald Fjellström
--
-- Description    :
--   A Radix-2 Decimation-in-Frequency (DIF) Fast Fourier Transform core.
--   Implements Block Floating Point (BFP) scaling to maximize dynamic range
--   while preventing fixed-point overflow.
--
-- State Machine Explanation:
--   S0: Address Generation - Calculates DIF stride, span, and RAM addresses.
--   S1: Twiddle Fetch    - Retrieves twiddle factors; initiates X1 RAM read.
--   S2: Capture X0       - Latches first complex sample from RAM (1-cycle delay).
--   S3: Capture X1       - Latches second complex sample; triggers Butterfly.
--   S4: Butterfly Wait   - Awaits 'done' signal from the butterfly unit.
--   S5: Write-back Y0    - Writes first result; detects overflow for next stage.
--   S6: Write-back Y1    - Writes second result to RAM.
--   S7: Pipeline Advance - Increments butterfly/stage counts or terminates.
--
-- RAM Latency & Timing:
--   - Designed for synchronous RAM with a 1-clock cycle read latency.
--   - Read addresses are issued in S0 (for X0) and S1 (for X1).
--   - Data is captured in S2 and S3 respectively.
--
-- Bit Reversal    :
--   - This DIF implementation produces results in bit-reversed order.
--   - To provide natural order output, bit-reversal is applied to the 
--     write addresses during the FINAL stage of computation (S5 and S6).
--
-- Block Floating Point (BFP):
--   - Initial stage (Stage 0) is always scaled (scale_count = 1) to handle
--     aggressive bit growth from raw input.
--   - blk_exp represents the total number of right-shifts performed.
--------------------------------------------------------------------------------
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

entity fft_dif is
    generic (
        constant N : integer := 64;
        constant SCALE_THRESHOLD : integer := 16383
    );
    port (
        clk         : in std_logic;
        rst_n       : in std_logic;

        -- Run
        en          : in std_logic;
        done        : out std_logic;
        invert      : in std_logic;
        bank_shft   : out std_logic;  -- Indicates switching of pingpong ram
        blk_exp     : out natural range 0 to log2_ceil(N);

        -- RAM Interface, used controller
        rd_data     : in complex_q1_14;
        wr_data     : out complex_q1_14;
        rd_addr     : out integer range 0 to N-1;
        wr_addr     : out integer range 0 to N-1;
        wr_en       : out std_logic
    );
end entity;

architecture rtl of fft_dif is

    constant STAGE_COUNT : integer := log2_ceil(N);
    
    signal stage     : integer range 0 to STAGE_COUNT-1 := 0;
    signal butterfly : integer range 0 to N/2-1 := 0;
    signal processing : std_logic := '0';

    -- Internal address registers to hold values during RAM latency
    signal sample_x0_addr : integer range 0 to N-1 := 0;
    signal sample_x1_addr : integer range 0 to N-1 := 0;

    signal in_data_x0, in_data_x1   : complex_q1_14;
    signal out_data_y0, out_data_y1 : complex_q1_14;
    signal reg_data_y1  : complex_q1_14;
    signal twiddle      : complex_q1_14;

    -- S0-S3: Data Acquisition | S4: Calculation | S5-S7: Memory Write-back
    type state_type is (S0, S1, S2, S3, S4, S5, S6, S7); 
    signal state     : state_type := S0;

    signal bf_en : std_logic;
    signal bf_done : std_logic;

    signal scale, scale_next : std_logic;
    signal scale_count : natural range 0 to STAGE_COUNT;

begin
    -- Structural instantiation of the Butterfly Unit
    bf_inst : entity work.fft_butterfly
        port map (
            clk     => clk,
            rst_n   => rst_n,
            en      => bf_en,
            done    => bf_done,
            invert  => invert,
            scale   => scale, -- Dynamic scaling to prevent overflow
            x0      => in_data_x0,
            x1      => in_data_x1,
            w       => twiddle,
            y0      => out_data_y0,
            y1      => out_data_y1
        );

    process(clk, rst_n)
        variable stride : integer := N/2;
        variable span : integer := N;
        variable group_i : integer := 0;
        variable offset : integer := 0;
        variable v_rd_x0_addr : integer range 0 to N-1 := 0;
        variable v_rd_x1_addr : integer range 0 to N-1 := 0;
    begin
        if rst_n = '0' then
            state           <= S0;
            stage           <= 0;
            butterfly       <= 0;
            processing      <= '0';
            done            <= '1';
            stride          := N/2;
            span            := N;
            group_i         := 0;
            offset          := 0;
            scale           <= '0';
            scale_next      <= '0';
            sample_x0_addr  <= 0;
            sample_x1_addr  <= 0;
            bank_shft       <= '0';
            wr_en           <= '0';
            bf_en           <= '0';
            scale_count     <= 0;
            in_data_x0      <= (re => (others => '0'), im => (others => '0'));
            in_data_x1      <= (re => (others => '0'), im => (others => '0'));
            reg_data_y1     <= (re => (others => '0'), im => (others => '0'));
            twiddle         <= (re => (others => '0'), im => (others => '0'));
        elsif rising_edge(clk) then
            bank_shft <= '0'; -- Default to no bank switch

            -- Clear butterfly enable once handshake is acknowledged
            if bf_done = '1' then
                bf_en <= '0';
            end if;

            -- Trigger FFT Calculation
            if en = '1' and processing = '0' then
                -- start FFT
                processing  <= '1';
                stage       <= 0;
                butterfly   <= 0;
                state       <= S0;
                scale_count <= 1;   -- Initial stage scaling
                scale       <= '1';
                bank_shft   <= '1';
                done        <= '0';
                -- Clear internal registers
                in_data_x0  <= (re => (others => '0'), im => (others => '0'));
                in_data_x1  <= (re => (others => '0'), im => (others => '0'));
                twiddle     <= (re => (others => '0'), im => (others => '0'));

            elsif processing = '1' then
                case state is

                    -- STATE S0: Address Generation
                    -- Logic: Decimation in Frequency (DIF) stride/span calculation
                    when S0 =>
                        stride  := N / (2 ** (stage + 1));
                        span    := 2 * stride;
                        group_i := butterfly / stride;
                        offset  := butterfly mod stride;

                        v_rd_x0_addr := group_i * span + offset;
                        v_rd_x1_addr := v_rd_x0_addr + stride;

                        sample_x0_addr <= v_rd_x0_addr;
                        sample_x1_addr <= v_rd_x1_addr;

                        rd_addr <= v_rd_x0_addr; -- Start RAM read for X0
                        state   <= S1;

                    -- STATE S1: Twiddle Fetch & RAM Latency 
                    when S1 =>
                        twiddle <= get_twiddle(stage, butterfly mod (N / (2 ** (stage + 1))) , N);
                        rd_addr <= sample_x1_addr;   -- Start RAM read for X1
                        state   <= S2;

                    -- STATE S2: Capture X0
                    when S2 =>                  
                        in_data_x0 <= rd_data; -- X0 data arrives from RAM    
                        state      <= S3;
                        
                    -- STATE S3: Capture X1 & Trigger Butterfly
                    when S3 =>
                        in_data_x1 <= rd_data; -- X1 data arrives from RAM
                        bf_en      <= '1';          -- Start calculation
                        state      <= S4;

                    -- STATE S4: Butterfly Computation Wait
                    -- Accommodates multi-cycle hardware implementations
                    when S4 =>
                        if bf_done = '1' then
                            state <= S5;
                        end if;

                    -- STATE S5: Write-back Y0 & Overflow Detection
                    -- Bit-reversal is applied ONLY on the final stage
                    when S5 =>
                        if stage = STAGE_COUNT-1 then
                            wr_addr <= bit_reverse(sample_x0_addr, STAGE_COUNT);
                        else
                            wr_addr <= sample_x0_addr;
                        end if;

                        reg_data_y1 <= out_data_y1; -- Store Y1 for next cycle
                        
                        -- Block Floating Point: Monitor for potential overflow in NEXT stage
                        if (abs(out_data_y0.re) + abs(out_data_y0.im)) > SCALE_THRESHOLD
                            or (abs(out_data_y1.re) + abs(out_data_y1.im)) > SCALE_THRESHOLD then
                            scale_next <= '1';
                            if scale_next = '0' and stage < STAGE_COUNT-1 then
                                scale_count <= scale_count + 1;
                            end if;
                        end if; 

                        wr_data <= out_data_y0;
                        wr_en   <= '1';
                        state   <= S6;

                    -- STATE S6: Write-back Y1
                    when S6 =>
                        if stage = STAGE_COUNT-1 then
                            wr_addr <= bit_reverse(sample_x1_addr, STAGE_COUNT);
                        else
                            wr_addr <= sample_x1_addr;
                        end if;
                        wr_data <= reg_data_y1;
                        state <= S7;

                    -- STATE S7: Pipeline Advance / Stage Management
                    when S7 =>
                        wr_en <= '0';
                        if butterfly = N/2-1 then
                            butterfly <= 0;
                            if stage < STAGE_COUNT-1 then
                                stage       <= stage + 1;
                                bank_shft   <= '1';        -- Ping-pong switch
                                scale       <= scale_next; -- Update scaling for new stage
                                scale_next  <= '0';
                            end if;
                        else
                            butterfly <= butterfly + 1;                            
                        end if;
                        state <= S0;

                    when others => 
                        null;
                end case;

                -- Termination Logic: Check if last butterfly of last stage is complete
                if stage = STAGE_COUNT-1 and butterfly = N/2-1 and state = S7 then
                    processing <= '0';
                    done       <= '1';
                    blk_exp    <= scale_count;
                    bank_shft  <= '1'; -- Final switch to present output to user
                end if;
            
            end if;
        end if;
    end process;

end architecture;