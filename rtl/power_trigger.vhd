---------------------------------------------------------------------------------
-- Penn State  
-- Dept. of Physics
--
-- PROJECT:      RNO-G lowthresh
-- FILE:         phased_trigger.vhd
-- AUTHOR:       Ryan Krebs
-- EMAIL         rjk5416@psu.edu
-- DATE:         3/10/2025
--
-- DESCRIPTION:  phased_trigger
-- Data is streamed into the module and is then ported to the (dedispersion), 4x upsampling,
-- beamforming, and power integration modules, then finally the output of the power integration 
-- is compared to thresholds. The trigger is passed out, and the triggering beams is sent to the 
-- data manager. The code is broken up into modules to ease testbenching
--
---------------------------------------------------------------------------------
library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.defs.all;

entity power_trigger is
generic(
        ENABLE_PHASED_TRIG : std_logic := '1';
        trigger_enable_reg_adr : std_logic_vector(7 downto 0) := x"3D";
        phased_trig_reg_base	: std_logic_vector(7 downto 0):= x"50";
        address_reg_pps_delay: std_logic_vector(7 downto 0) := x"5E";
        phased_trig_param_reg	: std_logic_vector(7 downto 0):= x"80";
        station_number : std_logic_vector(7 downto 0):=x"0b"
        );

port(
        rst_i :	in std_logic;
        clk_i :	in std_logic; --register clock 
        clk_data_i:	in std_logic; --data clock
        registers_i	: in register_array_type;
        ch0_data_i : in	std_logic_vector(31 downto 0);
        ch1_data_i : in	std_logic_vector(31 downto 0);
        ch2_data_i : in	std_logic_vector(31 downto 0);
        ch3_data_i : in	std_logic_vector(31 downto 0);
        
        trig_bits_o : out	std_logic_vector(2*(num_beams+1)-1 downto 0); --for scalers
        phased_trig_o : out	std_logic; --trigger
        phased_trig_metadata_o : out std_logic_vector(num_beams-1 downto 0) --for triggering beams
        --power_o: out std_logic_vector(22 downto 0) --test avg power for debugging located in metadata
        );
end power_trigger;

architecture rtl of power_trigger is

--definitions + constants -- I realize I can now just use 'length too
constant streaming_buffer_length: integer := 8;
constant interp_data_length: integer := interp_factor*(24)+1;--interp_factor*(streaming_buffer_length-1)+1;
constant sample_bit_length: integer:=8;
constant baseline: unsigned(7 downto 0) := x"80";
constant phased_sum_bits: integer := 8; --8. trying 7 bit lut
constant phased_sum_length: integer := 32; --8 real samples ... not sure if it should be 8 or 16. longer windows smooths things. shorter window gives higher peak
constant phased_sum_power_bits: integer := 16;--16 with calc. trying 7-> 14 lut
constant num_power_bits: integer := 18;
constant power_sum_bits: integer := 18; --actually 25 but this fits into the io regs
constant input_power_thesh_bits:	integer := 12;
constant power_length: integer := 12;
constant num_div: integer := 5;--can be calculated using -> integer(log2(real(phased_sum_length)));
constant pad_zeros: std_logic_vector(num_div-1 downto 0):=(others=>'0');
constant num_channels:integer:=4;
                                    
--short streaming regs to ease timing (if needed at all)
type streaming_data_array is array(3 downto 0, step_size-1 downto 0) of signed(7 downto 0);
signal streaming_data : streaming_data_array := (others=>(others=>(others=>'0'))); --pipeline data

--big arrays for thresholds/ average power
type power_array is array (num_beams-1 downto 0) of unsigned(13 downto 0);-- range 0 to 2**num_power_bits-1;--std_logic_vector(num_power_bits-1 downto 0); --log2(6*(16*6)^2) max power possible
signal trig_beam_thresh : power_array:=(others=>(others=>'0')) ; --trigger thresholds for all beams
signal servo_beam_thresh : power_array:=(others=>(others=>'0')) ;--(others=>(others=>'0')) --servo thresholds for all beams
--signal power_sum : power_array:=(others=>(others=>'0')); --power integration using all 32 samples
--signal power_sum_overlap : power_array:=(others=>(others=>'0')); --power integration using all 32 samples

signal avg_power0: power_array:=(others=>(others=>'0')); --average power (power_sum shifted down by log2(32)=5 bits)
signal avg_power1: power_array:=(others=>(others=>'0')); --average power (power_sum shifted down by log2(32)=5 bits)
signal avg_power2: power_array:=(others=>(others=>'0')); --average power (power_sum shifted down by log2(32)=5 bits)
signal avg_power3: power_array:=(others=>(others=>'0')); --average power (power_sum shifted down by log2(32)=5 bits)

signal avg_power_overlap: power_array:=(others=>(others=>'0')); --average power (power_sum shifted down by log2(32)=5 bits)
signal latched_power_out: power_array:=(others=>(others=>'0')); 

--input thresholds, 12 bits from registers then increased to ~16 by the threshold offset 
type thresh_input is array (num_beams-1 downto 0) of unsigned(input_power_thesh_bits-1 downto 0);
signal input_trig_thresh : thresh_input:=(others=>(others=>'0'));
signal input_servo_thresh : thresh_input:=(others=>(others=>'0'));

--threshold offset in case thresholds saturate over 4095 (they shouldn't)
signal threshold_offset: unsigned(11 downto 0):=x"000";

--mask of which beam triggers/servos to use in the trigger
signal triggering_beam: std_logic_vector(num_beams-1 downto 0):=(others=>'0');
signal servoing_beam: std_logic_vector(num_beams-1 downto 0):=(others=>'0');

--signal bits_for_trigger : std_logic_vector(num_beams-1 downto 0);

--actual output from the phased trigger and servo
signal phased_trigger : std_logic:='0';
signal phased_trigger_reg : std_logic_vector(1 downto 0):=(others=>'0');
signal phased_servo : std_logic:='0';
signal phased_servo_reg : std_logic_vector(1 downto 0):=(others=>'0');

--copy of simple trigger channel regs (probably not needed)
type trigger_regs is array(num_beams-1 downto 0) of std_logic_vector(1 downto 0);
signal beam_trigger_reg : trigger_regs:= (others=>(others=>'0'));
signal beam_servo_reg : trigger_regs:= (others=>(others=>'0'));
type trigger_counter is array (num_beams-1 downto 0) of unsigned(15 downto 0);
signal trig_clear : std_logic_vector(num_beams-1 downto 0):= (others=>'0');
signal servo_clear : std_logic_vector(num_beams-1 downto 0):= (others=>'0');
signal trig_counter : trigger_counter:= (others=>(others=>'0'));
signal servo_counter : trigger_counter:= (others=>(others=>'0'));

--previous trig beam bits
signal last_trig_bits_latched : std_logic_vector(num_beams-1 downto 0):=(others=>'0');
signal trig_array_for_scalers : std_logic_vector(2*(num_beams+1) downto 0):=(others=>'0'); --//on clk_data_i

--enables+input masks
signal internal_phased_trig_en : std_logic := '0'; --enable this trigger block from sw
--signal internal_trigger_channel_mask : std_logic_vector(num_channels-1 downto 0); if masking channel from coh sum (not implemented)
signal internal_trigger_beam_mask : std_logic_vector(num_beams-1 downto 0):=(others=>'0');

--full regs for ouput to scalers
signal trig_array_for_scalars : std_logic_vector (2*(num_beams+1)-1 downto 0):=(others=>'0');

--output for triggering beams for metadata
signal trig_bits_metadata: std_logic_vector(num_beams-1 downto 0):=(others=>'0');

signal phased_trig_metadata: std_logic_vector(num_beams-1 downto 0):=(others=>'0'); --for triggering beams

signal dedispersion_i : std_logic_vector(8*step_size*num_channels -1 downto 0):=(others=>'0');
signal dedispersion_o : std_logic_vector(8*step_size*num_channels -1 downto 0):=(others=>'0');
signal upsampling_i : std_logic_vector(8*step_size*num_channels -1 downto 0):=(others=>'0');
signal upsampling_o : std_logic_vector(8*step_size*num_channels*interp_factor -1 downto 0):=(others=>'0');	
signal beaming_i : std_logic_vector(8*step_size*num_channels*interp_factor -1 downto 0):=(others=>'0');
signal beaming_o : std_logic_vector(num_beams*8*step_size*interp_factor-1 downto 0):=(others=>'0');
signal power_integration_i : std_logic_vector(num_beams*step_size*interp_factor*8-1 downto 0):=(others=>'0');
signal power_integration_o : std_logic_vector(14*4*num_beams-1 downto 0):=(others=>'0');


--signal specific_delays: specific_delays_t;--std_logic_vector(2*12-1 downto 0);
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
--begin rtl

begin

--buffer samples into the phased trigger module
--streaming data should really be used much other than storing the latest 4 sample locally
proc_pipeline_data: process(clk_data_i,internal_phased_trig_en)
begin
    if rising_edge(clk_data_i) and (internal_phased_trig_en='1') then

        --pull new data in
        for i in 0 to step_size-1 loop
                streaming_data(0,i)<=signed(unsigned(ch0_data_i(8*(i+1)-1 downto 8*(i)))-baseline);
                streaming_data(1,i)<=signed(unsigned(ch1_data_i(8*(i+1)-1 downto 8*(i)))-baseline);
                streaming_data(2,i)<=signed(unsigned(ch2_data_i(8*(i+1)-1 downto 8*(i)))-baseline);
                streaming_data(3,i)<=signed(unsigned(ch3_data_i(8*(i+1)-1 downto 8*(i)))-baseline);
        end loop;

    end if;
end process;



--uncomment for dedisperion
/*
-- connect streaming data to dedispersion
assign_upsampling_io: for ch in 0 to 3 generate
    assign_sams_i: for i in 0 to 3 generate
        dedispersion_i(ch*8*4+8*(i+1)-1 downto ch*8*4+8*i)<=std_logic_vector(streaming_data(ch,i));
    end generate;
end generate;
--
xDedispersion : entity work.dedispersion
port map (
    rst_i => rst_i,
    clk_data_i => clk_data_i,
    enable => internal_phased_trig_en,
    ch_data_i => dedispersion_i,
    ch_data_o => dedispersion_o
);
--connect dedispersion output to upsampling input
upsampling_i<=dedispersion_o;
*/

xUpsampling : entity work.upsampling
port map (
    rst_i => rst_i,
    clk_data_i => clk_data_i,
    enable => internal_phased_trig_en,
    ch_data_i => upsampling_i,
    ch_data_o => upsampling_o
);

--comment these generates if using dedispersion
assign_upsampling_io: for ch in 0 to 3 generate
    assign_sams_i: for i in 0 to 3 generate
        upsampling_i(ch*8*4+8*(i+1)-1 downto ch*8*4+8*i)<=std_logic_vector(streaming_data(ch,i));
    end generate;
end generate;

--connect upsampling to beamforming
beaming_i<=upsampling_o;

xBeamforming: entity work.beamforming
generic map (station_number_i => station_number)
port map (
    rst_i => rst_i,
    clk_data_i => clk_data_i,
    enable => internal_phased_trig_en,
    ch_data_i => beaming_i,
    beam_data_o => beaming_o
    --specific_dels => specific_delays
);

--connect beamforming output to power integration
power_integration_i<=beaming_o;

xPower: entity work.power_integration
port map (
    rst_i => rst_i,
    clk_data_i => clk_data_i,
    enable => internal_phased_trig_en,
    beam_data_i => power_integration_i,
    power_o =>  power_integration_o
);

--connect output of power
assing_power_o: for bm in 0 to num_beams-1 generate

    avg_power0(bm)<=unsigned(power_integration_o(4*14*bm+14-1 downto 4*14*bm));
    avg_power1(bm)<=unsigned(power_integration_o(4*14*bm+28-1 downto 4*14*bm+14));
    avg_power2(bm)<=unsigned(power_integration_o(4*14*bm+42-1 downto 4*14*bm+28));
    avg_power3(bm)<=unsigned(power_integration_o(4*14*bm+56-1 downto 4*14*bm+42));
    
end generate;


--compare calculated powers and compare to masks and thresholds for the actual trigger
proc_get_triggering_beams : process(clk_data_i,rst_i)
begin
    if rst_i = '1' then
        phased_trigger_reg <= "00";
        phased_trigger <= '0'; -- the trigger

        phased_servo_reg <= "00";
        phased_servo <= '0';  --the servo trigger

        triggering_beam<= (others=>'0');
        servoing_beam<= (others=>'0');
        
    elsif rising_edge(clk_data_i) then
        --loop over the beams and this is a big mess
        for i in 0 to num_beams-1 loop

            --calculate if a beam is triggering or seroing
            if avg_power0(i)>trig_beam_thresh(i) or avg_power1(i)>trig_beam_thresh(i) or
                avg_power2(i)>trig_beam_thresh(i) or avg_power3(i)>trig_beam_thresh(i) then
                triggering_beam(i)<='1';
                beam_trigger_reg(i)(0)<='1';
                --latched_power_out(i)<=avg_power(i);
            else
                triggering_beam(i)<='0';
                beam_trigger_reg(i)(0)<='0';
            end if;

            beam_trigger_reg(i)(1)<=beam_trigger_reg(i)(0);
            if avg_power0(i)>servo_beam_thresh(i) or avg_power1(i)>servo_beam_thresh(i) or
                avg_power2(i)>servo_beam_thresh(i) or avg_power3(i)>servo_beam_thresh(i) then
                servoing_beam(i)<='1';
                beam_servo_reg(i)(0)<='1';
            else
                servoing_beam(i)<='0';
                beam_servo_reg(i)(0)<='0';
            end if;
            beam_servo_reg(i)(1)<=beam_servo_reg(i)(0);

        end loop;

        --this is the core of figuring out if a trigger needs to happen
        if (to_integer(unsigned(triggering_beam AND internal_trigger_beam_mask))>0) and (internal_phased_trig_en='1') then
            phased_trigger_reg(0)<='1';
            --power_o(num_power_bits-1 downto 0)<=std_logic_vector(latched_power_out(0)(num_power_bits-1 downto 0));
            phased_trig_metadata<=triggering_beam AND internal_trigger_beam_mask; --latches on a trigger
        else
            phased_trigger_reg(0)<='0';
        end if;
        if (to_integer(unsigned(servoing_beam AND internal_trigger_beam_mask))>0) and (internal_phased_trig_en='1') then
            phased_servo_reg(0)<='1';
        else
            phased_servo_reg(0)<='0';
        end if;

        phased_trigger_reg(1)<=phased_trigger_reg(0);
        phased_servo_reg(1)<=phased_servo_reg(0);

        if phased_trigger_reg="01" then
            phased_trigger<='1';

        else
            phased_trigger<='0';
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

--enable for the entire trigger block to start running (consuming power)
xTRIGENABLESYNC : signal_sync --phased trig enable bit
    port map(
    clkA			=> clk_i,
    clkB			=> clk_data_i,
    SignalIn_clkA	=> registers_i(to_integer(unsigned(trigger_enable_reg_adr)))(9), --overall phased trig enable bit
    SignalOut_clkB	=> internal_phased_trig_en);
    
    
--sync the trigger thresholds to clk_data_i from slow reg clock
TRIG_THRESHOLDS : for bm in 0 to num_beams-1 generate
    INDIV_TRIG_BITS : for i in 0 to input_power_thesh_bits-1 generate
        xTRIGTHRESHSYNC : signal_sync
        port map(
        clkA			=> clk_i,
        clkB			=> clk_data_i,
        SignalIn_clkA	=> registers_i(to_integer(unsigned(phased_trig_param_reg))+bm)(i), --threshold from software
        SignalOut_clkB	=> input_trig_thresh(bm)(i));
    end generate;
end generate;


--sync the servo thresholds to clk_data_i from slow reg clock
SERVO_THRESHOLDS : for bm in 0 to num_beams-1 generate
    INDIV_SERVO_BITS : for i in 0 to input_power_thesh_bits-1 generate
        xSERVOTHRESHSYNC : signal_sync
        port map(
        clkA			=> clk_i,
        clkB			=> clk_data_i,
        SignalIn_clkA	=> registers_i(to_integer(unsigned(phased_trig_param_reg))+bm)(i+12), --threshold from software
        SignalOut_clkB	=> input_servo_thresh(bm)(i));
    end generate;
end generate;


--sync the threhsold offset (like a prescaler) to clk_data_i from slow reg clock
THRESH_OFFSET: for i in 0 to 11 generate
    xTHRESHOFFSETSYNC : signal_sync
        port map(
        clkA => clk_i,   
        clkB => clk_data_i,
        SignalIn_clkA => registers_i(to_integer(unsigned(phased_trig_reg_base))+1)(i), --phased threshold offset
        SignalOut_clkB => threshold_offset(i));
end generate;


--process 12 bit input thresholds with some threshold offset (defined in software) if needed (likely not needed)
proc_threshold_set:process(clk_data_i)
begin
   if rising_edge(clk_data_i) then
        for i in 0 to num_beams-1 loop
            trig_beam_thresh(i)<=resize(input_trig_thresh(i),14)+threshold_offset;
            servo_beam_thresh(i)<=resize(input_servo_thresh(i),14)+threshold_offset;
        end loop;
    end if;
end process;

/*
--specific delays for channels/stations. shifts up to 3, which works for the stations, took up ~20% and 0.5W
SPECDELAYS : for bm in 0 to num_beams-1 generate
    SPECDELAYSCHANNELS: for ch in 0 to 3 generate
        SPECDELAYSBITS : for b in 0 to 1 generate
            xSPECDELAYS : signal_sync
            port map(
            clkA				=> clk_i,
            clkB				=> clk_data_i,
            SignalIn_clkA	=> registers_i(140+bm)(b+2*ch), --threshold from software
            SignalOut_clkB	=> specific_delays(bm,ch)(b));
        end generate;
    end generate;
end generate;
*/

--sync the trigger beam mask to clk_data_i from slow reg clock
TRIGBEAMMASK : for bm in 0 to num_beams-1 generate --beam masks. 1 == on
    xTRIGBEAMMASKSYNC : signal_sync
    port map(
    clkA	=> clk_i,   clkB	=> clk_data_i,
    SignalIn_clkA	=> registers_i(to_integer(unsigned(phased_trig_reg_base)))(bm), --trig channel mask
    SignalOut_clkB	=> internal_trigger_beam_mask(bm));
end generate;


-------------------------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------------------------

--send/sync things from the fast clk_data_i clock to the slow reg clock

----ASYNCTRIGGER OUT!!W
phased_trig_o <= phased_trigger;-- phased trigger for 0->1 transition. phased_trigger_reg(0) for any trigger condition
phased_trig_metadata_o<=phased_trig_metadata;

--phased trigger scaler
trigscaler: flag_sync
    port map(
        clkA 		=> clk_data_i,
        clkB		=> clk_i,
        in_clkA		=> phased_trigger,
        busy_clkA	=> open,
        out_clkB	=> trig_bits_o(0));

        
--beam trigger scalers
TrigToScalers	:	 for bm in 0 to num_beams-1 generate 
    xTRIGSYNC : flag_sync
    port map(
        clkA 		=> clk_data_i,
        clkB		=> clk_i,
        in_clkA		=> triggering_beam(bm),-- and internal_trigger_beam_mask(i),
        busy_clkA	=> open,
        out_clkB	=> trig_bits_o(bm+1));
end generate TrigToScalers;


--phased servo scaler
servoscaler: flag_sync
    port map(
        clkA 		=> clk_data_i,
        clkB		=> clk_i,
        in_clkA		=> phased_servo,
        busy_clkA	=> open,
        out_clkB	=> trig_bits_o(num_beams+1));

        
--beam servo scalers
ServoToScalers	:	 for bm in 0 to num_beams-1 generate 
    xSERVOSYNC : flag_sync
    port map(
        clkA 		=> clk_data_i,
        clkB		=> clk_i,
        in_clkA		=> servoing_beam(bm),-- and internal_trigger_beam_mask(i),
        busy_clkA	=> open,
        out_clkB	=> trig_bits_o(bm+num_beams+2));
end generate ServoToScalers;


--only needed if running at a clock different than 1/4 fs
--meta_bits	:	 for i in 0 to num_beams-1 generate 
--	xPHASEDMETA : flag_sync
--	port map(
--		clkA 			=> clk_data_i,
--		clkB			=> clk_data_i, -- to 1/4 fs
--		in_clkA		=> phased_trig_metadata(i),
--		busy_clkA	=> open,
--		out_clkB		=> phased_trig_metadata_o(i));
--end generate meta_bits;

end rtl;