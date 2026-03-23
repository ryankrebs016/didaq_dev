---------------------------------------------------------------------------------
-- Penn State
--    --Department of Physics--
--
-- PROJECT:      DiDAQ
-- FILE:         scalers_top.vhd
-- AUTHOR:       Ryan Krebs
-- EMAIL         rjk5416@psu.edu
-- DATE:         3/22/2026
--
-- DESCRIPTION:  manage board scalers and readout of scalers, adapted from FLOWER from Eric Oberla 
--               
---------------------------------------------------------------------------------
library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.defs.all;

entity scalers_top is
	generic(
		scaler_width   : integer := 16);
	port(
		rst_i				: in std_logic;
		clk_i				: in std_logic;

		coinc_trig_bits_i	: in std_logic_vector(2*NUM_CHANNELS+4-1 downto 0);
		phased_trig_bits_i		: in std_logic_vector(2*NUM_BEAMS+2-1 downto 0);

		pps_i				: in std_logic;
		gate_i				: in std_logic;

		scaler_refresh_i	: in std_logic; -- from regs
		scaler_to_read_i	: in std_logic_vector(9 downto 0); --from regs
		scaler_o			: out std_logic_vector(31 downto 0)); -- to regs, 2 scalers per reg file
end scalers_top;

architecture rtl of scalers_top is

constant num_pa_scalers : integer := 3*2*(NUM_BEAMS+1); -- 3: 1Hz, 100Hz, 100mHz , 2: trig and servo, +1: total trig/servo
constant num_rf_scalers: integer := 3*2*(NUM_CHANNELS+2); -- 3: 1Hz, 100Hz, 100mHz , 2: trig and servo, +2: total trig0, trig1, (servo) 
type phased_scaler_array_type is array(num_pa_scalers-1 downto 0) of std_logic_vector(scaler_width-1 downto 0);
type coinc_scaler_array_type is array(num_rf_scalers-1 downto 0) of std_logic_vector(scaler_width-1 downto 0);

signal phased_internal_scaler_array : phased_scaler_array_type := (others=>(others=>'0'));
signal coinc_internal_scaler_array : coinc_scaler_array_type := (others=>(others=>'0'));

constant num_scalers: integer := num_pa_scalers + num_rf_scalers + 6;
type scaler_array_type is array(num_scalers-1 downto 0) of std_logic_vector(scaler_width-1 downto 0);
signal internal_scaler_array : scaler_array_type;
signal latched_scaler_array : scaler_array_type; --//assigned after refresh pulse
signal pps_cycle_counter : std_logic_vector(47 downto 0);
signal latched_pps_cycle_counter : std_logic_vector(47 downto 0);

--//need to create a single pulse every Hz with width of 10 MHz clock period
signal refresh_clk_counter_100Hz	:	std_logic_vector(31 downto 0) := (others=>'0');
signal refresh_clk_counter_1Hz		:	std_logic_vector(31 downto 0) := (others=>'0');
signal refresh_clk_counter_100mHz	:	std_logic_vector(31 downto 0) := (others=>'0');
signal refresh_clk_100Hz			:	std_logic := '0';
signal refresh_clk_1Hz				:	std_logic := '0';
signal refresh_clk_100mHz			:	std_logic := '0';

--//for 125 MHz clock
constant REFRESH_CLK_MATCH_100Hz 	: 	std_logic_vector(31 downto 0) := x"001312D0";
constant REFRESH_CLK_MATCH_1HZ 		: 	std_logic_vector(31 downto 0) := x"07735940";
constant REFRESH_CLK_MATCH_100mHz 	: 	std_logic_vector(31 downto 0) := x"4A817C80";

--signal gate_counter : std_logic_vector(31 downto 0) := (others=>'0');, to add configurable gate length instead of the gps pps signal?

component scaler
port(
	rst_i 		: in std_logic;
	clk_i		: in std_logic;
	refresh_i	: in std_logic;
	count_i		: in std_logic;
	scaler_o	: out std_logic_vector(scaler_width-1 downto 0));
end component;
-------------------------------------------------------------------------------
begin
-------------------------------------------------------------------------------
--proc_assign_scalers_to_metadata : running_scalers_o <= internal_scaler_array(32) & internal_scaler_array(0);
-------------------------------------------------------------------------------

--//scalers 2,3,4,5 are the 
proc_assign_pps_counter : process(clk_i) --maybe use the 1hz refresh clock, idk
begin 
	if rising_edge(clk_i) then
		if refresh_clk_1Hz = '1' then
			internal_scaler_array(0) <= std_logic_vector(unsigned(internal_scaler_array(0)) + 1);
		end if;
		
		internal_scaler_array(1) <= pps_cycle_counter(SCALER_WIDTH-1 downto 0);
		internal_scaler_array(2) <= pps_cycle_counter(2*SCALER_WIDTH-1 downto SCALER_WIDTH);
		internal_scaler_array(3) <= pps_cycle_counter(3*SCALER_WIDTH-1 downto 2*SCALER_WIDTH);
		internal_scaler_array(4) <= pps_cycle_counter(4*SCALER_WIDTH-1 downto 3*SCALER_WIDTH);

		if pps_i = '1' and pps_i'event then
			pps_cycle_counter <= std_logic_vector(unsigned(pps_cycle_counter) + 1);
		end if;
	end if;
end process;

CoincTrigScalers1Hz : for i in 0 to 52-1 generate
	xCOINC1Hz : scaler
	port map(
		rst_i => rst_i,
		clk_i => clk_i,
		refresh_i => refresh_clk_1Hz,
		count_i => coinc_trig_bits_i(i),
		scaler_o => internal_scaler_array(i+6));
end generate;

CoincTrigScalers1HzGated : for i in 0 to 52-1 generate
	xCOINCGATED1Hz : scaler
	port map(
		rst_i => rst_i,
		clk_i => clk_i,
		refresh_i => refresh_clk_1Hz,
		count_i => coinc_trig_bits_i(i) and gate_i,
		scaler_o => internal_scaler_array(i+6+52));
end generate;

CoincTrigScalers100Hz : for i in 0 to 52-1 generate
	xCOINC100Hz : scaler
	port map(
		rst_i => rst_i,
		clk_i => clk_i,
		refresh_i => refresh_clk_100Hz,
		count_i => coinc_trig_bits_i(i),
		scaler_o => internal_scaler_array(i+6+2*52));
end generate;

PhasedTrigScalers1Hz : for i in 0 to 2*(NUM_BEAMS+1)-1 generate
	xPHASED1Hz : scaler
	port map(
		rst_i => rst_i,
		clk_i => clk_i,
		refresh_i => refresh_clk_1Hz,
		count_i => phased_trig_bits_i(i),
		scaler_o => internal_scaler_array(i+6+3*52));
end generate;

PhasedTrigScalers1HzGated : for i in 0 to 2*(NUM_BEAMS+1)-1 generate
	xPHASEDGATED1Hz : scaler
	port map(
		rst_i => rst_i,
		clk_i => clk_i,
		refresh_i => refresh_clk_1Hz,
		count_i => phased_trig_bits_i(i) and gate_i,
		scaler_o => internal_scaler_array(i+6+3*52+26));
end generate;

PhasedTrigScalers100Hz : for i in 0 to 2*(num_beams+1)-1 generate
	xPHASED100Hz : scaler
	port map(
		rst_i => rst_i,
		clk_i => clk_i,
		refresh_i => refresh_clk_100Hz,
		count_i => phased_trig_bits_i(i),
		scaler_o => internal_scaler_array(i+6+3*52+2*26));
end generate;
-------------------------------------	

-------------------------------------		
proc_save_scalers : process(rst_i, clk_i)
begin
	if rst_i = '1' then
		latched_scaler_array <= (others=>(others=>'0'));
		latched_pps_cycle_counter <= (others=>'0');
		scaler_o <= (others=>'0');
	
	elsif rising_edge(clk_i) and scaler_refresh_i = '1' then
		latched_scaler_array <= internal_scaler_array;
		
	elsif rising_edge(clk_i) then
	
		if to_integer(unsigned(scaler_to_read_i))<num_scalers then
			scaler_o<=latched_scaler_array(2*to_integer(unsigned(scaler_to_read_i))+1)&latched_scaler_array(2*to_integer(unsigned(scaler_to_read_i)));
		else
			--scaler_to_read_o<=latched_scaler_array(1)&latched_scaler_array(0);
			scaler_o<=x"ffffffff";
		end if;
	end if;
end process;

-------------------------------------------------------------------
--//make 1 Hz and 100mHz refresh pulses from the main iface clock (10 MHz)
proc_make_refresh_pulse : process(clk_i)
begin
	if rising_edge(clk_i) then
		
		if refresh_clk_1Hz = '1' then
			refresh_clk_counter_1Hz <= (others=>'0');
		else
			refresh_clk_counter_1Hz <= std_logic_vector(unsigned(refresh_clk_counter_1Hz) + 1);
		end if;
		--//pulse refresh when refresh_clk_counter = REFRESH_CLK_MATCH
		case refresh_clk_counter_1Hz is
			when REFRESH_CLK_MATCH_1HZ =>
				refresh_clk_1Hz <= '1';
			when others =>
				refresh_clk_1Hz <= '0';
		end case;
		
		--//////////////////////////////////////
		
		if refresh_clk_100mHz = '1' then
			refresh_clk_counter_100mHz <= (others=>'0');
		else
			refresh_clk_counter_100mHz <= std_logic_vector(unsigned(refresh_clk_counter_100mHz) + 1);
		end if;
		--//pulse refresh when refresh_clk_counter = REFRESH_CLK_MATCH
		case refresh_clk_counter_100mHz is
			when REFRESH_CLK_MATCH_100mHz =>
				refresh_clk_100mHz <= '1';
			when others =>
				refresh_clk_100mHz <= '0';
		end case;
		
		--//////////////////////////////////////
		
		if refresh_clk_100Hz = '1' then
			refresh_clk_counter_100Hz <= (others=>'0');
		else
			refresh_clk_counter_100Hz <= std_logic_vector(unsigned(refresh_clk_counter_100Hz) + 1);
		end if;
		--//pulse refresh when refresh_clk_counter = REFRESH_CLK_MATCH
		case refresh_clk_counter_100Hz is
			when REFRESH_CLK_MATCH_100Hz =>
				refresh_clk_100Hz <= '1';
			when others =>
				refresh_clk_100Hz <= '0';
		end case;
		
	end if;
end process;
end rtl;
