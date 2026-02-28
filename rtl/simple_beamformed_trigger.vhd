---------------------------------------------------------------------------------
-- Penn State  
-- Dept. of Physics
--
-- PROJECT:      DiDAQ
-- FILE:         phased_trigger.vhd
-- AUTHOR:       Ryan Krebs
-- EMAIL         rjk5416@psu.edu
-- DATE:         1/2026
--
-- DESCRIPTION:  phased_trigger
-- data is streamed into the trigger block. low-pass filter or upsampling are not implemented (could be).
-- then beams are created and then only the amplitude of the beamformed traces are used to find a trigger
--
---------------------------------------------------------------------------------
library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.defs.all;

entity simple_beamformed_trigger is
generic(

		-- placeholder to be filled with project level constants
		NUM_PA_CHANNELS : integer := 4;
		NUM_SAMPLES : integer := 4;
		SAMPLE_LENGTH : integer:= 8;
        NUM_BEAMS : integer := 12;

        station_number : std_logic_vector(7 downto 0):=x"0b" -- to know which beam delays to use. geometry of st 11 is used by default unless things go wrong in station deployment
        );

port(
        rst_i           : in std_logic;

        -- adc samples
        clk_data_i      : in std_logic; --data clock
        ch0_data_i      : in	std_logic_vector(NUM_SAMPLES*SAMPLE_LENGTH-1 downto 0);
        ch1_data_i      : in	std_logic_vector(NUM_SAMPLES*SAMPLE_LENGTH-1 downto 0);
        ch2_data_i      : in	std_logic_vector(NUM_SAMPLES*SAMPLE_LENGTH-1 downto 0);
        ch3_data_i      : in	std_logic_vector(NUM_SAMPLES*SAMPLE_LENGTH-1 downto 0);

        -- register things
        clk_reg_i           : in std_logic := '0'; --register clock 
        enable_i            : in std_logic;
        beam_mask_i         : in std_logic_vector(NUM_BEAMS-1 downto 0);
        channel_mask_i      : in std_logic_vector(NUM_PA_CHANNELS-1 downto 0);
        trig_thresholds_i   : in std_logic_vector(NUM_BEAMS*SAMPLE_LENGTH-1 downto 0);
        servo_thresholds_i  : in std_logic_vector(NUM_BEAMS*SAMPLE_LENGTH-1 downto 0);


        -- output
        trig_bits_o     : out	std_logic_vector(2*(NUM_BEAMS+1)-1 downto 0) := (others=>'0'); --for scalers
        trig_o          : out	std_logic := '0'; --trigger
        trig_metadata_o : out std_logic_vector(NUM_BEAMS-1 downto 0) := (others=>'0') --for triggering beams
        --power_o: out std_logic_vector(22 downto 0) --test avg power for debugging located in metadata
        
        );
end simple_beamformed_trigger;

architecture rtl of simple_beamformed_trigger is

    --enables+input masks
    signal internal_phased_trig_en : std_logic := '0'; --enable this trigger block from sw
    signal internal_channel_mask : std_logic_vector(NUM_PA_CHANNELS-1 downto 0):=x"f"; -- if masking channel from beamforming (actually broken channels)
    signal internal_beam_mask : std_logic_vector(NUM_BEAMS-1 downto 0):=(others=>'0'); -- trigger mask

    --definitions + constants -- I realize I can now just use 'length too
    constant streaming_buffer_length: integer := 8;
    constant baseline: unsigned(7 downto 0) := x"80";

    --short streaming regs to ease timing (if needed at all)
    type streaming_data_array is array(NUM_PA_CHANNELS-1 downto 0, NUM_SAMPLES-1 downto 0) of signed(SAMPLE_LENGTH-1 downto 0);
    signal streaming_data : streaming_data_array := (others=>(others=>x"00")); --pipeline data

    type threshold_type is array(NUM_BEAMS-1 downto 0) of signed(7 downto 0);
    signal trig_thresh : threshold_type := (others=>"00100000");
    signal servo_thresh : threshold_type := (others=>"00100000");

    -- if downsamppling change length of this
    type beamformed_samples_t is array(NUM_BEAMS-1 downto 0, NUM_SAMPLES-1 downto 0) of signed(7 downto 0);
    signal beamformed_samples : beamformed_samples_t := (others=>(others=>x"00"));

    --big arrays for thresholds/ average power
    --type power_array is array (NUM_BEAMS-1 downto 0) of unsigned(13 downto 0);-- range 0 to 2**num_power_bits-1;--std_logic_vector(num_power_bits-1 downto 0); --log2(6*(16*6)^2) max power possible
    --signal trig_beam_thresh : power_array:=(others=>(others=>'0')) ; --trigger thresholds for all beams
    --signal servo_beam_thresh : power_array:=(others=>(others=>'0')) ;--(others=>(others=>'0')) --servo thresholds for all beams

    --which beam triggers/servos to use in the trigger
    signal triggering_beam: std_logic_vector(NUM_BEAMS-1 downto 0):=(others=>'0');
    signal triggering_beam_last: std_logic_vector(NUM_BEAMS-1 downto 0):=(others=>'0');
    signal triggering_beam_last_last: std_logic_vector(NUM_BEAMS-1 downto 0):=(others=>'0');
    signal servoing_beam: std_logic_vector(NUM_BEAMS-1 downto 0):=(others=>'0');

    --actual output from the phased trigger and servo
    signal phased_trigger : std_logic:='0';
    signal phased_trigger_reg : std_logic_vector(1 downto 0):=(others=>'0');
    signal phased_servo : std_logic:='0';
    signal phased_servo_reg : std_logic_vector(1 downto 0):=(others=>'0');

    --copy of simple trigger channel regs (probably not needed)
    type trigger_regs is array(NUM_BEAMS-1 downto 0) of std_logic_vector(1 downto 0);
    signal beam_trigger_reg : trigger_regs:= (others=>(others=>'0'));
    signal beam_servo_reg : trigger_regs:= (others=>(others=>'0'));

    --full regs for ouput to scalers
    signal trig_array_for_scalars : std_logic_vector (2*(num_beams+1)-1 downto 0):=(others=>'0');

    -- if downsampling change length of this
    signal beaming_i : std_logic_vector(NUM_PA_CHANNELS*NUM_SAMPLES*SAMPLE_LENGTH -1 downto 0):=(others=>'0');
    signal beaming_o : std_logic_vector(NUM_BEAMS*NUM_SAMPLES*SAMPLE_LENGTH-1 downto 0):=(others=>'0');

    /*
    -- low pass with half band filter (down to 250MHz bandwidth)
    -- if using just uncomment and assign the downsampling_i with streaming_data and downsampling_o to beaming_i
    signal downsampling_i : std_logic_vector(NUM_PA_CHANNELS*NUM_SAMPLES*SAMPLE_LENGTH-1 downto 0);
    signal downsampling_o : std_logic_vector(NUM_PA_CHANNELS*NUM_SAMPLES*SAMPLE_LENGTH-1 downto 0);

    -- this component isn't needed since I'm using the entity rather than component and instatiation
    component low_pass_filter is 
        generic(
            ENABLE : std_logic := '1'
            );
        port(
                rst_i			:	in	    std_logic;
                clk_data_i	    :   in	    std_logic;
                enable          :   in      std_logic;
                ch_data_i       :   in      std_logic_vector(NUM_PA_CHANNELS*NUM_SAMPLES*SAMPLE_LENGTH -1 downto 0);
                ch_data_o       :   out     std_logic_vector(NUM_PA_CHANNELS*NUM_SAMPLES*SAMPLE_LENGTH -1 downto 0)
                );
    end component;
    */


    -------------------------------------------------------------------------------------------------------------------------------
    -------------------------------------------------------------------------------------------------------------------------------
    --components, modules, etc


    --cdc slow to fast
    component signal_sync is
    port(
        clkA			: in	std_logic;
        clkB			: in	std_logic;
        SignalIn_clkA	: in	std_logic;
        SignalOut_clkB	: out	std_logic);
    end component;

    --cdc fast to slow
    component flag_sync is
    port(
        clkA		: in	std_logic;
        clkB		: in	std_logic;
        in_clkA		: in	std_logic;
        busy_clkA	: out	std_logic;
        out_clkB	: out	std_logic);
    end component;
-------------------------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------------------------

begin

    --buffer samples into the phased trigger module
    --streaming data should really be used much other than storing the latest 4 sample locally
    proc_pipeline_data: process(clk_data_i,internal_phased_trig_en)
    begin
        if rst_i='1' or internal_phased_trig_en='0' then
            for i in 0 to NUM_PA_CHANNELS-1 loop
                for j in 0 to NUM_SAMPLES-1 loop
                    streaming_data(i,j)<=x"00";
                end loop;
            end loop;

        elsif rising_edge(clk_data_i) then

            --pull new data in, mask channels here
            for i in 0 to NUM_SAMPLES-1 loop
                if internal_channel_mask(0) = '1' then
                    streaming_data(0,i)<=signed(unsigned(ch0_data_i(8*(i+1)-1 downto 8*(i)))-baseline);
                else
                    streaming_data(0,i)<=x"00";
                end if;

                if internal_channel_mask(1) = '1' then
                    streaming_data(1,i)<=signed(unsigned(ch1_data_i(8*(i+1)-1 downto 8*(i)))-baseline);
                else
                    streaming_data(1,i)<=x"00";
                end if;

                if internal_channel_mask(2) = '1' then
                    streaming_data(2,i)<=signed(unsigned(ch2_data_i(8*(i+1)-1 downto 8*(i)))-baseline);
                else
                    streaming_data(2,i)<=x"00";
                end if;

                if internal_channel_mask(3) = '1' then
                    streaming_data(3,i)<=signed(unsigned(ch3_data_i(8*(i+1)-1 downto 8*(i)))-baseline);
                else
                    streaming_data(3,i)<=x"00";
                end if;
            end loop;

        end if;
    end process;

    /*
    -- uncomment for low pass filtering. would need to update beamforming module to know interp factor and update the beam delays
    for ch in 0 to NUM_PA_CHANNELS-1 generate
        for s in 0 to NUM_SAMPLES-1 generate
            downsampling_i((ch+1)*NUM_PA_CHANNELS*NUM_SAMPLES*SAMPLE_LENGTH + (s+1)*SAMPLE_LENGTH - 1
                            downto ch*NUM_PA_CHANNELS*NUM_SAMPLES*8 + s*SAMPLE_LENGTH) <= streaming_data(ch,s)(7 downto 0);
        end generate;
    end generate;

    beamiing_i <= downsampling_o

    xLowPass: entity work.low_pass_filter
    generic map ()
    port map (
        rst_i => rst_i,
        clk_data_i => clk_data_i,
        enable => internal_phased_trig_en,
        ch_data_i => downsampling_i,
        ch_data_o => downsampling_o
    );

    */

    -- connect input to beamforming assuming no pre beamforming upsampling or filtering
    xBUFFERCH: for ch in 0 to NUM_PA_CHANNELS-1 generate
        xBUFFERSAM: for s in 0 to NUM_SAMPLES-1 generate
            beaming_i(ch*NUM_SAMPLES*SAMPLE_LENGTH + (s+1)*SAMPLE_LENGTH - 1
                        downto ch*NUM_SAMPLES*SAMPLE_LENGTH + s*SAMPLE_LENGTH) <= std_logic_vector(streaming_data(ch,s)(7 downto 0));
        end generate;
    end generate;

    -- beamforming module
    xBeamforming: entity work.beamforming
    generic map (station_number_i => station_number)
    port map (
        rst_i => rst_i,
        clk_data_i => clk_data_i,
        enable => internal_phased_trig_en,
        ch_data_i => beaming_i,
        beam_data_o => beaming_o
    );

    -- reformat output of beamforming for easier code
    xBUFFERBM : for bm in 0 to NUM_BEAMS-1 generate
        xBUFFERSAM : for s in 0 to NUM_SAMPLES-1 generate
            beamformed_samples(bm, s) <= signed(beaming_o(bm*NUM_SAMPLES*SAMPLE_LENGTH + (s+1)*SAMPLE_LENGTH - 1
                                                            downto bm*NUM_SAMPLES*SAMPLE_LENGTH + s*SAMPLE_LENGTH));
        end generate;
    end generate;

    --compare calculated powers and compare to masks and thresholds for the actual trigger
    proc_get_triggering_beams : process(clk_data_i,rst_i)
    begin
        if rst_i = '1' or internal_phased_trig_en='0' then
            phased_trigger_reg <= "00";
            phased_trigger <= '0'; -- the trigger

            phased_servo_reg <= "00";
            phased_servo <= '0';  --the servo trigger

            triggering_beam<= (others=>'0');
            servoing_beam<= (others=>'0');
            
        elsif rising_edge(clk_data_i) then
            --loop over the beams to compare to thresholds
            for i in 0 to NUM_BEAMS-1 loop

                if beamformed_samples(i,0)>=trig_thresh(i) or beamformed_samples(i,0)<=-trig_thresh(i)
                    or beamformed_samples(i,1)>=trig_thresh(i) or beamformed_samples(i,1)<=-trig_thresh(i)
                    or beamformed_samples(i,2)>=trig_thresh(i) or beamformed_samples(i,2)<=-trig_thresh(i)
                    or beamformed_samples(i,3)>=trig_thresh(i) or beamformed_samples(i,3)<=-trig_thresh(i) then
                    
                    triggering_beam(i)<='1';
                    beam_trigger_reg(i)(0)<='1';

                else
                    triggering_beam(i)<='0';
                    beam_trigger_reg(i)(0)<='0';

                end if;
                
                if beamformed_samples(i,0)>=servo_thresh(i) or beamformed_samples(i,0)<=-servo_thresh(i)
                    or beamformed_samples(i,1)>=servo_thresh(i) or beamformed_samples(i,1)<=-servo_thresh(i)
                    or beamformed_samples(i,2)>=servo_thresh(i) or beamformed_samples(i,2)<=-servo_thresh(i)
                    or beamformed_samples(i,3)>=servo_thresh(i) or beamformed_samples(i,3)<=-servo_thresh(i) then
                    
                    servoing_beam(i)<='1';
                    beam_servo_reg(i)(0)<='1';

                else
                    servoing_beam(i)<='0';
                    beam_servo_reg(i)(0)<='0';

                end if;

                beam_trigger_reg(i)(1)<=beam_trigger_reg(i)(0);
                beam_servo_reg(i)(1)<=beam_servo_reg(i)(0);

            end loop;

            triggering_beam_last <= triggering_beam;
            triggering_beam_last_last <= triggering_beam_last;

            --this is the core of figuring out if a trigger needs to happen
            if (to_integer(unsigned(triggering_beam AND internal_beam_mask))>0) and (internal_phased_trig_en='1') then
                phased_trigger_reg(0)<='1';
            else
                phased_trigger_reg(0)<='0';
            end if;

            if (to_integer(unsigned(servoing_beam AND internal_beam_mask))>0) and (internal_phased_trig_en='1') then
                phased_servo_reg(0)<='1';
            else
                phased_servo_reg(0)<='0';
            end if;

            phased_trigger_reg(1)<=phased_trigger_reg(0);
            phased_servo_reg(1)<=phased_servo_reg(0);
            --trig_metadata_o(7 downto 0) <= std_logic_vector(beamformed_samples(0,0));

            -- looks for 0 to 1 transition, phased_trigger_reg'event might work, and can look at single bit being high for saturation scalers
            if phased_trigger_reg="01" then
                phased_trigger<='1';
                trig_o<='1';
                trig_metadata_o <= triggering_beam_last AND internal_beam_mask;

            else
                phased_trigger<='0';
                trig_o<='0';
                --trig_metadata_o <= (other=>'0');

            end if;
            
            if phased_servo_reg="01" then
                phased_servo<='1';
            else
                phased_servo<='0';
            end if;

        end if;
    end process;

    -------------------------------------------------------------------------------------------------------------------------------
    -------------------------------------------------------------------------------------------------------------------------------

    --//sync some software commands from the slow reg clock to the data clock

    -- enable for the entire trigger block to start running (consuming power)
    xTRIGENABLESYNC : signal_sync --phased trig enable bit
        port map(
        clkA			=> clk_reg_i,
        clkB			=> clk_data_i,
        SignalIn_clkA	=> enable_i, --overall phased trig enable bit
        SignalOut_clkB	=> internal_phased_trig_en
        );

    -- sync the trigger beam mask to clk_data_i from slow reg clock
    TRIGBEAMMASK : for bm in 0 to NUM_BEAMS-1 generate --beam masks. 1 == on
        xTRIGBEAMMASKSYNC : signal_sync
        port map(
            clkA	=> clk_reg_i,
            clkB	=> clk_data_i,
            SignalIn_clkA	=> beam_mask_i(bm), -- trig beam mask
            SignalOut_clkB	=> internal_beam_mask(bm)
            );
    end generate;

    -- sync the trigger beam mask to clk_data_i from slow reg clock
    TRIGCHANNELMASK : for ch in 0 to NUM_PA_CHANNELS-1 generate --beam masks. 1 == on
        xTRIGBEAMMASKSYNC : signal_sync
        port map(
        clkA	=> clk_reg_i,
        clkB	=> clk_data_i,
        SignalIn_clkA	=> channel_mask_i(ch), --trig channel mask
        SignalOut_clkB	=> internal_channel_mask(ch)
        );
    end generate;

    -- sync the trigger thresholds to clk_data_i from slow reg clock
    -- TODO: update this to a handshake cdc to keep bus synced
    TRIG_THRESHOLDS : for bm in 0 to NUM_BEAMS-1 generate -- hardcode num_beams/2
        INDIV_TRIG_BITS : for i in 0 to SAMPLE_LENGTH-1 generate
            xTRIGTHRESHSYNC : signal_sync
            port map(
                clkA			=> clk_reg_i,
                clkB			=> clk_data_i,
                SignalIn_clkA	=> trig_thresholds_i(bm*SAMPLE_LENGTH + i), -- threshold from software
                SignalOut_clkB	=> trig_thresh(bm)(i)
                );

            xSERVOTHRESHSYNC0 : signal_sync
            port map(
                clkA			=> clk_reg_i,
                clkB			=> clk_data_i,
                SignalIn_clkA	=> servo_thresholds_i(bm*SAMPLE_LENGTH + i), --threshold from software
                SignalOut_clkB	=> servo_thresh(bm)(i)
                );
        end generate;
    end generate;

    -------------------------------------------------------------------------------------------------------------------------------
    -------------------------------------------------------------------------------------------------------------------------------

    --send/sync things from the fast clk_data_i clock to the slow reg clock
    /* --TODO FOR SCALERS
    -- phased trigger scaler
    trigscaler: flag_sync
        port map(
            clkA 		=> clk_data_i,
            clkB		=> clk_reg_i,
            in_clkA		=> phased_trigger,
            busy_clkA	=> open,
            out_clkB	=> trig_bits_o(0));

    -- beam trigger scalers
    TrigToScalers	:	 for bm in 0 to NUM_BEAMS-1 generate 
        xTRIGSYNC : flag_sync
        port map(
            clkA 		=> clk_data_i,
            clkB		=> clk_reg_i,
            in_clkA		=> triggering_beam(bm),-- and internal_trigger_beam_mask(i),
            busy_clkA	=> open,
            out_clkB	=> trig_bits_o(bm+1));
    end generate TrigToScalers;


    -- phased servo scaler
    servoscaler: flag_sync
        port map(
            clkA 		=> clk_data_i,
            clkB		=> clk_reg_i,
            in_clkA		=> phased_servo,
            busy_clkA	=> open,
            out_clkB	=> trig_bits_o(num_beams+1));

    -- beam servo scalers
    ServoToScalers	:	 for bm in 0 to NUM_BEAMS-1 generate 
        xSERVOSYNC : flag_sync
        port map(
            clkA 		=> clk_data_i,
            clkB		=> clk_reg_i,
            in_clkA		=> servoing_beam(bm),-- and internal_trigger_beam_mask(i),
            busy_clkA	=> open,
            out_clkB	=> trig_bits_o(bm+num_beams+2));
    end generate ServoToScalers;
    */
end rtl;