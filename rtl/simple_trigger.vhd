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

use work.defs.all; --rename to constants

entity simple_trigger is
generic(
		-- placeholder to be filled with project level constants
		--NUM_CHANNELS : integer := 24;
		--NUM_SAMPLES : integer := 4;
		--SAMPLE_LENGTH : integer:= 8;

		-- Firmware compile level enable
		ENABLE_TRIG : std_logic := '1';

		-- Trigger number label (unused)
		RF_TRIGGER_NUM : std_logic_vector(1 downto 0) := "00";

		-- Trigger channel masks (24 bits in 32 bit reg), pass address for RF_TRIGGER_NUM
		-- (00000000{23}->{0})
		TRIGGER_MASK_ADDRESS : std_logic_vector(7 downto 0) := x"00";

		-- Trigger paramteters (coincidence num, window length), pass address for RF_TRIGGER_NUM
		-- (00000000-000{coinc_num}-000{window}-000000{vpp_mode}{enable})
		TRIGGER_PARAM_ADDRESS : std_logic_vector(7 downto 0) := x"00";

		-- Start of threshold register address (8-bit, 2 scaler thresholds, 2 trigger thresholds in each reg)
		-- pass address for RF_TRIGGER_NUM
		-- (scaler_thresh 1 - trigger_thresh_1 - servo_thresh_0 - trigger_thresh_0)
		TRIGGER_THRESHOLD_START_ADDRESS : std_logic_vector(7 downto 0) := x"00"

		);

port(
		rst_i		:	in		std_logic := '1'; --global reset on start up
		clk_i		:	in		std_logic := '0'; --register clock
		clk_data_i	:	in		std_logic := '0'; --data clock, these might be the same on the didaq
		registers_i	:	in		register_array_type :=(others=>(others=>'0')); --redo for new reg structure
		ch_data_i	:	in		std_logic_vector(NUM_CHANNELS*NUM_SAMPLES*SAMPLE_LENGTH - 1 downto 0) := (others=>'0'); --formated where 4 samples of a channel are continuous


		trig_bits_o : 	out	std_logic_vector(NUM_CHANNELS*2+2 -1 downto 0) := (others=>'0'); --24 trig scaler, 24 servo scaler, total trig scaler, total servo scaler
		trig_o: 	out	std_logic := '0'; --trigger output
		trig_metadata_o: out std_logic_vector(NUM_CHANNELS-1 downto 0):= (others=>'0') --triggering channels causing trig_o, synced to trig_o
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

	type threshold_array is array (NUM_CHANNELS-1 downto 0) of unsigned(7 downto 0);
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
		if rst_i = '1' or ENABLE_TRIG = '0' then
			streaming_data_trig <= (others=>x"8080808080808080");
			streaming_data_servo <= (others=>x"8080808080808080");

		elsif rising_edge(clk_data_i) and internal_trig_en = '0' then
			streaming_data_trig <= (others=>x"8080808080808080");
			streaming_data_servo <= (others=>x"8080808080808080");

		elsif rising_edge(clk_data_i) then
			-- pipeline samples into 2x clock cycle buffer for trig and servo path. apply mask here to limit activity down the line or change to later
			for i in 0 to NUM_CHANNELS-1 loop
				if channel_mask(i)='1' then
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
			if rst_i = '1' or ENABLE_TRIG = '0' then
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
				if unsigned(streaming_data_trig(i)(6*SAMPLE_LENGTH-1 downto 5*SAMPLE_LENGTH)) <= (baseline - trig_threshold_int(i)) or 
					unsigned(streaming_data_trig(i)(5*SAMPLE_LENGTH-1 downto 4*SAMPLE_LENGTH)) <= (baseline - trig_threshold_int(i)) or 
					unsigned(streaming_data_trig(i)(4*SAMPLE_LENGTH-1 downto 3*SAMPLE_LENGTH)) <= (baseline - trig_threshold_int(i)) or 
					unsigned(streaming_data_trig(i)(3*SAMPLE_LENGTH-1 downto 2*SAMPLE_LENGTH)) <= (baseline - trig_threshold_int(i)) or
					unsigned(streaming_data_trig(i)(2*SAMPLE_LENGTH-1 downto SAMPLE_LENGTH)) <= (baseline - trig_threshold_int(i)) or
					unsigned(streaming_data_trig(i)(SAMPLE_LENGTH-1 downto 0)) <= (baseline - trig_threshold_int(i)) then
					--
					channel_trig_lo(i) <= '1';
				else
					channel_trig_lo(i) <= '0';
				end if;

				--same for hi
				if unsigned(streaming_data_trig(i)(6*SAMPLE_LENGTH-1 downto 5*SAMPLE_LENGTH)) >= (baseline + trig_threshold_int(i)) or 
					unsigned(streaming_data_trig(i)(5*SAMPLE_LENGTH-1 downto 4*SAMPLE_LENGTH)) >= (baseline + trig_threshold_int(i)) or 
					unsigned(streaming_data_trig(i)(4*SAMPLE_LENGTH-1 downto 3*SAMPLE_LENGTH)) >= (baseline + trig_threshold_int(i)) or 
					unsigned(streaming_data_trig(i)(3*SAMPLE_LENGTH-1 downto 2*SAMPLE_LENGTH)) >= (baseline + trig_threshold_int(i)) or
					unsigned(streaming_data_trig(i)(2*SAMPLE_LENGTH-1 downto SAMPLE_LENGTH)) >= (baseline + trig_threshold_int(i)) or
					unsigned(streaming_data_trig(i)(SAMPLE_LENGTH-1 downto 0)) >= (baseline + trig_threshold_int(i)) then
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
				if unsigned(streaming_data_servo(i)(6*SAMPLE_LENGTH-1 downto 5*SAMPLE_LENGTH)) <= (baseline - servo_threshold_int(i)) or 
					unsigned(streaming_data_servo(i)(5*SAMPLE_LENGTH-1 downto 4*SAMPLE_LENGTH)) <= (baseline - servo_threshold_int(i)) or 
					unsigned(streaming_data_servo(i)(4*SAMPLE_LENGTH-1 downto 3*SAMPLE_LENGTH)) <= (baseline - servo_threshold_int(i)) or 
					unsigned(streaming_data_servo(i)(3*SAMPLE_LENGTH-1 downto 2*SAMPLE_LENGTH))<= (baseline - servo_threshold_int(i)) or
					unsigned(streaming_data_servo(i)(2*SAMPLE_LENGTH-1 downto SAMPLE_LENGTH)) <= (baseline - servo_threshold_int(i)) or
					unsigned(streaming_data_servo(i)(SAMPLE_LENGTH-1 downto 0)) <= (baseline - servo_threshold_int(i)) then
					--
					channel_servo_lo(i) <= '1';
				else
					channel_servo_lo(i) <= '0';
				end if;

				--same for hi
				if unsigned(streaming_data_servo(i)(6*SAMPLE_LENGTH-1 downto 5*SAMPLE_LENGTH)) >= (baseline + servo_threshold_int(i)) or 
					unsigned(streaming_data_servo(i)(5*SAMPLE_LENGTH-1 downto 4*SAMPLE_LENGTH)) >= (baseline + servo_threshold_int(i)) or 
					unsigned(streaming_data_servo(i)(4*SAMPLE_LENGTH-1 downto 3*SAMPLE_LENGTH)) >= (baseline + servo_threshold_int(i)) or 
					unsigned(streaming_data_servo(i)(3*SAMPLE_LENGTH-1 downto 2*SAMPLE_LENGTH)) >= (baseline + servo_threshold_int(i)) or
					unsigned(streaming_data_servo(i)(2*SAMPLE_LENGTH-1 downto SAMPLE_LENGTH)) >= (baseline + servo_threshold_int(i)) or
					unsigned(streaming_data_servo(i)(SAMPLE_LENGTH-1 downto 0)) >= (baseline + servo_threshold_int(i)) then
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
		if rst_i = '1' or ENABLE_TRIG='0' then
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
	/*
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
	--//sync some software commands to the data clock

	xTRIGENABLESYNC : signal_sync
	port map(
	clkA			=> clk_i,
	clkB			=> clk_data_i,
	SignalIn_clkA	=> registers_i(to_integer(unsigned(TRIGGER_PARAM_ADDRESS)))(0),
	SignalOut_clkB	=> internal_trig_en);

	TRIG_THRESHOLDS : for ch in 0 to 11 generate
		INDIV_TRIG_BITS : for i in 0 to 7 generate
			-- reg to be like (scaler_thresh 1, trigger_thresh_1, servo_thresh_0, trigger_thresh_0), can be all continguously all trigs or all servos too
			xTRIGTHRESHSYNC0 : signal_sync
			port map(
			clkA			=> clk_i,
			clkB			=> clk_data_i,
			SignalIn_clkA	=> registers_i(to_integer(unsigned(TRIGGER_THRESHOLD_START_ADDRESS))+ch)(i),
			SignalOut_clkB	=> trig_threshold_int(2*ch)(i));

			xTRIGTHRESHSYNC1 : signal_sync
			port map(
			clkA			=> clk_i,
			clkB			=> clk_data_i,
			SignalIn_clkA	=> registers_i(to_integer(unsigned(TRIGGER_THRESHOLD_START_ADDRESS))+ch)(i+16),
			SignalOut_clkB	=> trig_threshold_int(2*ch+1)(i));


			xSERVOTHRESHSYNC0 : signal_sync
			port map(
			clkA			=> clk_i,
			clkB			=> clk_data_i,
			SignalIn_clkA	=> registers_i(to_integer(unsigned(TRIGGER_THRESHOLD_START_ADDRESS))+ch)(i+8),
			SignalOut_clkB	=> servo_threshold_int(2*ch)(i));

			xSERVOTHRESHSYNC1 : signal_sync
			port map(
			clkA			=> clk_i,
			clkB			=> clk_data_i,
			SignalIn_clkA	=> registers_i(to_integer(unsigned(TRIGGER_THRESHOLD_START_ADDRESS))+ch)(i+24),
			SignalOut_clkB	=> servo_threshold_int(2*ch+1)(i));

		end generate;
	end generate;
	--------------
	COINCREQ : for i in 0 to 4 generate
		xCOINCREQSYNC : signal_sync
			port map(
			clkA			=> clk_i,
			clkB			=> clk_data_i,
			SignalIn_clkA	=> registers_i(to_integer(unsigned(TRIGGER_PARAM_ADDRESS)))(i+16),
			SignalOut_clkB	=> coinc_require_int(i));
	end generate;

	COINCWIN : for i in 0 to 4 generate
		xCOINCWINSYNC : signal_sync
			port map(
			clkA			=> clk_i,
			clkB			=> clk_data_i,
			SignalIn_clkA	=> registers_i(to_integer(unsigned(TRIGGER_PARAM_ADDRESS)))(i+8),
			SignalOut_clkB	=> coinc_window_int(i));
	end generate;

	xVPPMODESYNC : signal_sync
		port map(
		clkA			=> clk_i,
		clkB			=> clk_data_i,
		SignalIn_clkA	=> registers_i(to_integer(unsigned(TRIGGER_PARAM_ADDRESS)))(1),
		SignalOut_clkB	=> vppmode_int);
	--------------

	ChanMask : for i in 0 to NUM_CHANNELS-1 generate
		xCHANMASK : signal_sync
		port map(
			clkA 			=> clk_i,
			clkB			=> clk_data_i,
			SignalIn_clkA	=> registers_i(to_integer(unsigned(TRIGGER_MASK_ADDRESS)))(i),
			SignalOut_clkB	=> channel_mask(i));
	end generate;

end rtl;