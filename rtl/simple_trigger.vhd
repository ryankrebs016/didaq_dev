---------------------------------------------------------------------------------
-- Penn State
--    --Dept. of Physics--
--
-- PROJECT:      DiDAQ 24 Channel Board
-- FILE:         simple_trigger.vhd
-- AUTHOR:       Ryan Krebs
-- EMAIL         rjk5416@psu.edu
-- DATE:         1/2026
--
-- DESCRIPTION:  coincidence-based high (and/or) low trigger on 24 maskable channels.
--				 Adapted from Eric Oberla in the FLOWER firmware
--
---------------------------------------------------------------------------------
library IEEE;
use ieee.std_logic_1164.all;
--use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

use work.defs.all;

entity simple_trigger is
generic(
		-- placeholder to be filled with project level constants
		NUM_CHANNELS : integer := 24;
		NUM_SAMPLES : integer := 4;
		SAMPLE_LENGTH : integer:= 8;

		-- Trigger number label (unused)
		RF_TRIGGER_NUM : std_logic_vector(1 downto 0) := "00"

		);

port(
		rst_i			: in std_logic := '1'; --global reset on start up
		clk_data_i		: in std_logic := '0'; --register clock
		ch_data_i		: in std_logic_vector(NUM_CHANNELS*NUM_SAMPLES*SAMPLE_LENGTH - 1 downto 0); --formated where 4 samples of a channel are continuous
		ch_data_valid_i	: in std_logic_vector(NUM_CHANNELS-1 downto 0);

		clk_reg_i			: in std_logic := '0'; --data clock, these might be the same on the didaq
		enable_i			: in std_logic; -- from regs
		ch_mask_i			: in std_logic_vector(NUM_CHANNELS-1 downto 0); -- from regs
		vpp_mode_i			: in std_logic; -- from regs
		coinc_window_i		: in std_logic_vector(4 downto 0); --from regs
		num_coinc_i			: in std_logic_vector(4 downto 0); -- from regs
		trig_thresholds_i	: in std_logic_vector(NUM_CHANNELS*8-1 downto 0);
		servo_thresholds_i	: in std_logic_vector(NUM_CHANNELS*8-1 downto 0);

		trig_bits_o		: out	std_logic_vector(NUM_CHANNELS*2+2 -1 downto 0) := (others=>'0'); --24 trig scaler, 24 servo scaler, total trig scaler, total servo scaler
		trig_o			: out	std_logic := '0'; --trigger output
		trig_metadata_o	: out std_logic_vector(NUM_CHANNELS-1 downto 0):= (others=>'0') --triggering channels causing trig_o, same time as trig_o
		);
end simple_trigger;

architecture rtl of simple_trigger is

	signal internal_trig_en : std_logic := '0'; --enable this trigger block from sw

	signal coinc_require_int : unsigned(4 downto 0) := "00010"; --num of channels needed in coincidence
	signal coinc_window_int	: std_logic_vector(4 downto 0) := "01000"; --//num of clk_data_i periods
	signal vppmode_int			: std_logic := '1'; -- hi-lo vs just low
	constant baseline : unsigned(7 downto 0) := x"80";
	signal channel_mask : std_logic_vector(NUM_CHANNELS-1 downto 0):=x"ffffff";
	
	signal triggering_channels: std_logic_vector(NUM_CHANNELS-1 downto 0):=x"000000"; --metadata to record which are causing trigger
	signal triggering_channels_past: std_logic_vector(NUM_CHANNELS-1 downto 0):=x"000000"; --metadata to record which are causing trigger
	signal triggering_channels_past_past: std_logic_vector(NUM_CHANNELS-1 downto 0):=x"000000"; --metadata to record which are causing trigger

	signal servoing_channels: std_logic_vector(NUM_CHANNELS-1 downto 0):=x"000000"; --metadata to record which are causing trigger

	type threshold_array is array (NUM_CHANNELS-1 downto 0) of std_logic_vector(7 downto 0);
	signal trig_threshold_int	: threshold_array := (others=>"00111111");
	signal servo_threshold_int	: threshold_array := (others=>"00111111");

	type streaming_data_array is array(NUM_CHANNELS-1 downto 0) of std_logic_vector(2*NUM_SAMPLES*SAMPLE_LENGTH-1 downto 0);
	signal streaming_data_trig	:streaming_data_array := (others=>x"8080808080808080"); --pipelined trigger data
	signal streaming_data_servo	: streaming_data_array := (others=>x"8080808080808080"); --pipelined servo data (split assuming trig/servo is more efficient on two sep. buffers)

	signal channel_trig_hi		: std_logic_vector(NUM_CHANNELS-1 downto 0) := (others=>'0'); --for hi/lo coinc
	signal channel_trig_lo		: std_logic_vector(NUM_CHANNELS-1 downto 0) := (others=>'0'); --for hi/lo coinc
	signal channel_servo_hi		: std_logic_vector(NUM_CHANNELS-1 downto 0) := (others=>'0'); --for hi/lo coinc
	signal channel_servo_lo		: std_logic_vector(NUM_CHANNELS-1 downto 0) := (others=>'0'); --for hi/lo coinc

	type coincidence_array is array(NUM_CHANNELS-1 downto 0) of std_logic_vector(31 downto 0);

	signal channel_trig_reg		: coincidence_array := (others=>(others=>'0')); --for coincidenc'ing
	signal channel_servo_reg	: coincidence_array := (others=>(others=>'0')); --for coincidenc'ing

	signal trig_array_for_scalers : std_logic_vector(NUM_CHANNELS*2+1 downto 0) := (others=>'0'); -- on clk_data, 1 for total trig, 24 for channel trig, and then servos

	signal coincidence_trigger_reg : std_logic_vector(1 downto 0) := (others=>'0');
	signal coincidence_trigger : std_logic :='0'; --actual trigger, one clk_data_i cycle
	signal coincidence_servo_reg : std_logic_vector(1 downto 0) := (others=>'0');
	signal coincidence_servo : std_logic :='0'; --one clk_data_i period


	--------------
	component signal_sync is
	port(
		clkA			: in	std_logic;
		clkB			: in	std_logic;
		SignalIn_clkA	: in	std_logic;
		SignalOut_clkB	: out	std_logic);
	end component;
	component flag_sync is
	port(
		clkA			: in	std_logic;
		clkB			: in	std_logic;
		in_clkA			: in	std_logic;
		busy_clkA		: out	std_logic;
		out_clkB		: out	std_logic);
	end component;
	--------------
begin
	------------------------------------------------
	proc_pipeline_data : process(clk_data_i)
	begin
		if rst_i = '1' then
			streaming_data_trig <= (others=>x"8080808080808080");
			streaming_data_servo <= (others=>x"8080808080808080");

		elsif rising_edge(clk_data_i) and internal_trig_en = '0' then
			streaming_data_trig <= (others=>x"8080808080808080");
			streaming_data_servo <= (others=>x"8080808080808080");

		elsif rising_edge(clk_data_i) then
			-- pipeline samples into 2x clock cycle buffer for trig and servo path. apply mask here to limit activity down the line or change to later
			for i in 0 to NUM_CHANNELS-1 loop
				if channel_mask(i)='1' and ch_data_valid_i(i)='1' then
					streaming_data_trig(i)(63 downto 0) <= streaming_data_trig(i)(31 downto 0) & ch_data_i((i+1)*NUM_SAMPLES*SAMPLE_LENGTH - 1 downto i*NUM_SAMPLES*SAMPLE_LENGTH);
					streaming_data_servo(i)(63 downto 0) <= streaming_data_servo(i)(31 downto 0) & ch_data_i((i+1)*NUM_SAMPLES*SAMPLE_LENGTH - 1 downto i*NUM_SAMPLES*SAMPLE_LENGTH);

				else
					streaming_data_trig(i)<=x"8080808080808080";
					streaming_data_servo(i)<=x"8080808080808080";
				end if;
			end loop;
		end if;
	end process;
	------------------------------------------------
	-- single channel trigger bits
	proc_single_channel : process(clk_data_i, rst_i)
	begin
		for i in 0 to NUM_CHANNELS-1 loop
			if rst_i = '1' then
				channel_trig_reg(i) 	<= (others=>'0');
				channel_trig_lo(i) 		<= '0';
				channel_trig_hi(i) 		<= '0';
				channel_servo_reg(i)	<= (others=>'0');
				channel_servo_lo(i)		<= '0';
				channel_servo_hi(i)		<= '0';

			elsif rising_edge(clk_data_i) and internal_trig_en = '0' then
				channel_trig_reg(i) 	<= (others=>'0');
				channel_trig_lo(i) 		<= '0';
				channel_trig_hi(i) 		<= '0';
				channel_servo_reg(i)	<= (others=>'0');
				channel_servo_lo(i)		<= '0';
				channel_servo_hi(i)		<= '0';

			elsif rising_edge(clk_data_i) then
				--lo-side threshold: take 4 samples + 2 sample overlap. This is a 6 ns window, or thereabouts
				if unsigned(streaming_data_trig(i)(6*SAMPLE_LENGTH-1 downto 5*SAMPLE_LENGTH)) <= (baseline - unsigned(trig_threshold_int(i))) or 
					unsigned(streaming_data_trig(i)(5*SAMPLE_LENGTH-1 downto 4*SAMPLE_LENGTH)) <= (baseline - unsigned(trig_threshold_int(i))) or 
					unsigned(streaming_data_trig(i)(4*SAMPLE_LENGTH-1 downto 3*SAMPLE_LENGTH)) <= (baseline - unsigned(trig_threshold_int(i))) or 
					unsigned(streaming_data_trig(i)(3*SAMPLE_LENGTH-1 downto 2*SAMPLE_LENGTH)) <= (baseline - unsigned(trig_threshold_int(i))) or
					unsigned(streaming_data_trig(i)(2*SAMPLE_LENGTH-1 downto SAMPLE_LENGTH)) <= (baseline - unsigned(trig_threshold_int(i))) or
					unsigned(streaming_data_trig(i)(SAMPLE_LENGTH-1 downto 0)) <= (baseline - unsigned(trig_threshold_int(i))) then
					--
					channel_trig_lo(i) <= '1';
				else
					channel_trig_lo(i) <= '0';
				end if;

				--same for hi
				if unsigned(streaming_data_trig(i)(6*SAMPLE_LENGTH-1 downto 5*SAMPLE_LENGTH)) >= (baseline + unsigned(trig_threshold_int(i))) or 
					unsigned(streaming_data_trig(i)(5*SAMPLE_LENGTH-1 downto 4*SAMPLE_LENGTH)) >= (baseline + unsigned(trig_threshold_int(i))) or 
					unsigned(streaming_data_trig(i)(4*SAMPLE_LENGTH-1 downto 3*SAMPLE_LENGTH)) >= (baseline + unsigned(trig_threshold_int(i))) or 
					unsigned(streaming_data_trig(i)(3*SAMPLE_LENGTH-1 downto 2*SAMPLE_LENGTH)) >= (baseline + unsigned(trig_threshold_int(i))) or
					unsigned(streaming_data_trig(i)(2*SAMPLE_LENGTH-1 downto SAMPLE_LENGTH)) >= (baseline + unsigned(trig_threshold_int(i))) or
					unsigned(streaming_data_trig(i)(SAMPLE_LENGTH-1 downto 0)) >= (baseline + unsigned(trig_threshold_int(i))) then
					--
					channel_trig_hi(i) <= '1';
				else
					channel_trig_hi(i) <= '0';
				end if;

				if channel_trig_lo(i) = '1' and channel_trig_hi(i) = '1' and vppmode_int = '1' then
					channel_trig_reg(i)(0) <= '1';
				elsif (channel_trig_lo(i) = '1' or channel_trig_hi(i) = '1') and vppmode_int = '0' then
					channel_trig_reg(i)(0) <= '1';
				else
					channel_trig_reg(i)(0) <= '0';
				end if;
				channel_trig_reg(i)(31 downto 1) <= channel_trig_reg(i)(30 downto 0);
				--------------------
				--servo thresholding, using `streaming_data_2'
				--lo-side threshold: take 4 samples + 2 sample overlap. This is a ~13 ns window, or thereabouts
				if unsigned(streaming_data_servo(i)(6*SAMPLE_LENGTH-1 downto 5*SAMPLE_LENGTH)) <= (baseline - unsigned(servo_threshold_int(i))) or 
					unsigned(streaming_data_servo(i)(5*SAMPLE_LENGTH-1 downto 4*SAMPLE_LENGTH)) <= (baseline - unsigned(servo_threshold_int(i))) or 
					unsigned(streaming_data_servo(i)(4*SAMPLE_LENGTH-1 downto 3*SAMPLE_LENGTH)) <= (baseline - unsigned(servo_threshold_int(i))) or 
					unsigned(streaming_data_servo(i)(3*SAMPLE_LENGTH-1 downto 2*SAMPLE_LENGTH))<= (baseline - unsigned(servo_threshold_int(i))) or
					unsigned(streaming_data_servo(i)(2*SAMPLE_LENGTH-1 downto SAMPLE_LENGTH)) <= (baseline - unsigned(servo_threshold_int(i))) or
					unsigned(streaming_data_servo(i)(SAMPLE_LENGTH-1 downto 0)) <= (baseline - unsigned(servo_threshold_int(i))) then
					--
					channel_servo_lo(i) <= '1';
				else
					channel_servo_lo(i) <= '0';
				end if;

				--same for hi
				if unsigned(streaming_data_servo(i)(6*SAMPLE_LENGTH-1 downto 5*SAMPLE_LENGTH)) >= (baseline + unsigned(servo_threshold_int(i))) or 
					unsigned(streaming_data_servo(i)(5*SAMPLE_LENGTH-1 downto 4*SAMPLE_LENGTH)) >= (baseline + unsigned(servo_threshold_int(i))) or 
					unsigned(streaming_data_servo(i)(4*SAMPLE_LENGTH-1 downto 3*SAMPLE_LENGTH)) >= (baseline + unsigned(servo_threshold_int(i))) or 
					unsigned(streaming_data_servo(i)(3*SAMPLE_LENGTH-1 downto 2*SAMPLE_LENGTH)) >= (baseline + unsigned(servo_threshold_int(i))) or
					unsigned(streaming_data_servo(i)(2*SAMPLE_LENGTH-1 downto SAMPLE_LENGTH)) >= (baseline + unsigned(servo_threshold_int(i))) or
					unsigned(streaming_data_servo(i)(SAMPLE_LENGTH-1 downto 0)) >= (baseline + unsigned(servo_threshold_int(i))) then
					--
					channel_servo_hi(i) <= '1';
				else
					channel_servo_hi(i) <= '0';
				end if;


				--single-channel coinc:
				if channel_servo_lo(i) = '1' and channel_servo_hi(i) = '1' and vppmode_int = '1' then
					channel_servo_reg(i)(0) <= '1';
				elsif (channel_servo_lo(i) = '1' or channel_servo_hi(i) = '1') and vppmode_int = '0' then
					channel_servo_reg(i)(0) <= '1';
				else
					channel_servo_reg(i)(0) <= '0';
				end if;
				channel_servo_reg(i)(31 downto 1) <= channel_servo_reg(i)(30 downto 0);

				----------------------------------------------
			
			end if;
		end loop;
	end process;
	------------------------------------------------
	--coinc window
	proc_coinc_trig : process(rst_i, clk_data_i)
	begin
		if rst_i = '1' then
			triggering_channels<=(others=>'0');
			servoing_channels<=(others=>'0');

			coincidence_trigger_reg <= "00";
			coincidence_trigger <= '0'; -- the trigger

			coincidence_servo_reg <= "00";
			coincidence_servo <= '0';  --the servo trigger

		elsif rising_edge(clk_data_i) and internal_trig_en = '0' then
			triggering_channels<=(others=>'0');
			servoing_channels<=(others=>'0');

			coincidence_trigger_reg <= "00";
			coincidence_trigger <= '0'; -- the trigger

			coincidence_servo_reg <= "00";
			coincidence_servo <= '0';  --the servo trigger

		elsif rising_edge(clk_data_i) then
			--loop over the channels
			for i in 0 to NUM_CHANNELS-1 loop

				if unsigned(channel_trig_reg(i)(to_integer(unsigned(coinc_window_int))-1 downto 0)) > 0 then
					triggering_channels(i) <= '1';
				else
					triggering_channels(i) <= '0';
				end if;

				if unsigned(channel_servo_reg(i)(to_integer(unsigned(coinc_window_int))-1 downto 0)) > 0 then
					servoing_channels(i) <= '1';
				else
					servoing_channels(i) <= '0';
				end if;

			end loop;

			-- sync trigger_o and triggering_channels meta data
			triggering_channels_past <= triggering_channels;
			triggering_channels_past_past <= triggering_channels_past;

			if unsigned(triggering_channels) >= coinc_require_int then
				coincidence_trigger_reg(0) <= '1';
			else
				coincidence_trigger_reg(0) <= '0';
			end if;
			
			if unsigned(servoing_channels) >= coinc_require_int then
				coincidence_servo_reg(0) <= '1';
			else
				coincidence_servo_reg(0) <= '0';
			end if;
			
			--trig_metadata_o(23 downto 0) <= triggering_channels;

			-- I think coincidence_trigger_reg'event may work instead of this, but it's whatevs
			coincidence_trigger_reg(1) <= coincidence_trigger_reg(0);
			--dumb way to trigger on "01", rising edge
			if coincidence_trigger_reg = "01" then
			--if coincidence_trigger_reg(0) = '1' then

				coincidence_trigger <= '1';
				trig_metadata_o <= triggering_channels_past;
				--trig_metadata_o(7 downto 0) <= std_logic_vector(trig_threshold_int(0));
			else
				coincidence_trigger <= '0';
			end if;

			coincidence_servo_reg(1) <= coincidence_servo_reg(0);
			--dumb way to trigger on "01", rising edge
			if coincidence_servo_reg = "01" then
				coincidence_servo <= '1';
			else
				coincidence_servo <= '0';
			end if;

		end if;
	end process;
	
	trig_o <= coincidence_trigger; --coincidence_trigger;
	trig_array_for_scalers <= servoing_channels(NUM_CHANNELS-1 downto 0) & coincidence_servo &
								triggering_channels(NUM_CHANNELS-1 downto 0) & coincidence_trigger;


	
	--------------
	/* -- TODO: clock sync these for the scalers. flag sync is okay, just doesn't compile for GHDL
	TrigToScalers	:	 for i in 0 to NUM_CHANNELS*2+1 generate
		xTRIGSYNC : flag_sync
		port map(
			clkA 		=> clk_data_i,
			clkB		=> clk_i,
			in_clkA		=> trig_array_for_scalers(i),
			busy_clkA	=> open,
			out_clkB	=> trig_bits_o(i));
	end generate TrigToScalers;
	*/


	-- sync some software commands to the data clock.
	-- these should be set before enable starts and held for the duration of a run. ie don't care about bus sync
	xTRIGENABLESYNC : signal_sync
	port map(
	clkA			=> clk_reg_i,
	clkB			=> clk_data_i,
	SignalIn_clkA	=> enable_i,
	SignalOut_clkB	=> internal_trig_en);

	xCOINCREQ : for i in 0 to 4 generate
		xCOINCREQSYNC : signal_sync
			port map(
			clkA			=> clk_reg_i,
			clkB			=> clk_data_i,
			SignalIn_clkA	=> num_coinc_i(i),
			SignalOut_clkB	=> coinc_require_int(i));
	end generate;

	xCOINCWIN : for i in 0 to 4 generate
		xCOINCWINSYNC : signal_sync
			port map(
			clkA			=> clk_reg_i,
			clkB			=> clk_data_i,
			SignalIn_clkA	=> coinc_window_i(i),
			SignalOut_clkB	=> coinc_window_int(i));
	end generate;

	xVPPMODESYNC : signal_sync
		port map(
		clkA			=> clk_reg_i,
		clkB			=> clk_data_i,
		SignalIn_clkA	=> vpp_mode_i,
		SignalOut_clkB	=> vppmode_int);

	ChanMask : for i in 0 to NUM_CHANNELS-1 generate
		xCHANMASK : signal_sync
		port map(
			clkA 			=> clk_reg_i,
			clkB			=> clk_data_i,
			SignalIn_clkA	=> ch_mask_i(i),
			SignalOut_clkB	=> channel_mask(i));
	end generate;

	/*
	-- sync threshold buses. these do change during run time and 'could' have timing issues between bits causing false triggers
	-- use handshake syncs to sync the full bus to be safer
	trig_threshold_sync : for i in 0 to NUM_CHANNELS-1 generate
		trig_ch_thresh_sync : entity work.handshake_sync(rtl)
			generic map(
				port_width=>trig_threshold_int(i)'length
				)
			port map(
				rst_i => rst_i,
				clk_a => clk_reg_i,
				clk_a_data => trig_thresholds_i((i+1)*8 downto i*i),
				clk_b => clk_data_i,
				clk_b_data => trig_threshold_int(i)
			);
	end generate;

	servo_threshold_sync : for i in 0 to NUM_CHANNELS-1 generate
		servo_ch_thresh_sync : entity work.handshake_sync(rtl)
			generic map(
				port_width=>servo_threshold_int(i)'length
				)
			port map(
				rst_i => rst_i,
				clk_a => clk_reg_i,
				clk_a_data => servo_thresholds_i((i+1)*8 downto i*i),
				clk_b => clk_data_i,
				clk_b_data => servo_threshold_int(i)
			);
	end generate;
	*/
	
	TRIG_THRESHOLDS : for ch in 0 to NUM_CHANNELS-1 generate
		INDIV_TRIG_BITS : for i in 0 to 7 generate
			-- reg to be like (scaler_thresh 1, trigger_thresh_1, servo_thresh_0, trigger_thresh_0), can be all continguously all trigs or all servos too
			xTRIGTHRESHSYNC0 : signal_sync
			port map(
			clkA			=> clk_reg_i,
			clkB			=> clk_data_i,
			SignalIn_clkA	=> trig_thresholds_i(8*ch+i),
			SignalOut_clkB	=> trig_threshold_int(ch)(i));

			xSERVOTHRESHSYNC0 : signal_sync
			port map(
			clkA			=> clk_reg_i,
			clkB			=> clk_data_i,
			SignalIn_clkA	=> servo_thresholds_i(8*ch+i),
			SignalOut_clkB	=> servo_threshold_int(ch)(i));
		end generate;
	end generate;
	
	--------------

end rtl;