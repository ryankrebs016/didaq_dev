library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.defs.all;

entity pps_handler is
    --generic(
    --        );
    
    port(
            rst_i           : in std_logic;
            clk_250_i       : in std_logic;
            clk_125_i       : in std_logic;

            pps_i           : in std_logic; -- raw pps pin input

            pps_125_o       : out std_logic; -- 1 clock wide pulse on 125 MHz clock
            pps_125_long_o  : out std_logic; -- pps pulse matching gps pps duty cycle on 125 MHz, for scaler gating
            pps_250_o       : out std_logic; -- 1 clock wide pulse on 250 MHz clock, for pps triggers

            );
    end pps_handler;

architecture rtl of pps_handler is

    -- internal pps signal @ 125
    signal pps_int_125 : std_logic := '0';
    signal pps_int_last_125 : std_logic := '0';
    signal pps_sync_125 : std_logic_vector(2 downto 0) := "000";

    -- internal pps signal @ 250
    signal pps_int_250 : std_logic := '0';
    signal pps_int_last_250 : std_logic := '0';
    signal pps_sync_250 : std_logic_vector(2 downto 0) := "000";

begin

    -- capture raw pps to 125 clk, the slow clock first
    proc_pps : process(rst_i, clk_125_i)
    begin
        if rst_i = '1' then
            pps_sync_125 <= (others=>'0');
            pps_int_125 <= '0';
            pps_int_last_125 <= '0';

        elsif rising_edge(clk_125_i) then
            pps_sync_125(2 downto 0) <= pps_sync_125(1 downto 0) & pps_i; 

            --may need debounce?

            pps_int_125 <= pps_sync_125(2); 
            pps_int_last_125 <= pps_int_125;
            pps_125_long_o <= pps_int_125;

            if pps_int_125 and (not pps_int_last_125) then
                pps_125_o <= '1';
            else
                pps_125_o <= '0';
            end if;
        end if;
    end process;


    -- sync 125 clk pps signal to the 250 clk
    proc_fast_clk_pps : process(rst_i, clk_250_i)
    begin
        if rst_i = '1' then
            pps_sync_125 <= (others=>'0');
            pps_int_125 <= '0';
            pps_int_last_125 <= '0';

        elsif rising_edge(clk_250_i) then
            pps_sync_250(2 downto 0) <= pps_sync_250(1 downto 0) & pps_125_int; 
            pps_int_250 <= pps_sync_250(2); 
            pps_int_last_250 <= pps_int_250;

            if pps_int_250 and (not pps_int_last_250) then
                pps_250_o <= '1';
            else
                pps_250_o <= '0';
            end if;
        end if;
    end process;

end rtl;