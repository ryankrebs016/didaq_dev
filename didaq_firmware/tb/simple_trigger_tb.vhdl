library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
--use ieee.std_logic_textio.all;

use work.defs.all;
use work.all;

entity simple_trigger_tb is
end simple_trigger_tb;

architecture behave of simple_trigger_tb is
-----------------------------------------------------------------------------
-- Declare the Component Under Test
-----------------------------------------------------------------------------

component simple_trigger

    
    generic(
            ENABLE_TRIG : std_logic := '1';
            TRIGGER_PARAM_ADDRESS : std_logic_vector(7 downto 0) := x"00";
            TRIGGER_MASK_ADDRESS : std_logic_vector(7 downto 0) := x"01";
            TRIGGER_THRESHOLD_START_ADDRESS : std_logic_vector(7 downto 0) := x"02"
            );
    
    port(
            rst_i			:	in		std_logic;
            clk_i			:	in		std_logic; --register clock 
            clk_data_i	    :	in		std_logic; --data clock
            registers_i	    :	in		register_array_type;
            ch_data_i	    : 	in		std_logic_vector(NUM_SAMPLES*NUM_CHANNELS*SAMPLE_LENGTH-1 downto 0);

            trig_bits_o     : 	out	std_logic_vector(NUM_CHANNELS*2+2 -1 downto 0); --24 trig scaler, 24 servo scaler, total trig scaler, total servo scaler
            trig_o          : 	out	std_logic; --trigger output
            trig_metadata_o : out std_logic_vector(NUM_CHANNELS-1 downto 0) --triggering channels causing trig_o, synced to trig_o
            );
end component;

-----------------------------------------------------------------------------
-- Testbench Internal Signals
-----------------------------------------------------------------------------
signal  clock : std_logic := '1';
signal slow_clk:std_logic:='0';

type thresholds_t is array(NUM_CHANNELS-1 downto 0) of std_logic_vector(7 downto 0);
signal enable: std_logic:='1';
--type input_samples_t is unsigned(31 downto 0);
signal thresholds:thresholds_t:=(others=>"01000000");
signal registers: register_array_type:=(others=>(others=>'0'));

signal ch_samples:std_logic_vector(NUM_CHANNELS*NUM_SAMPLES*SAMPLE_LENGTH-1 downto 0):=(others=>'0');

--signal ch0_samples:std_logic_vector(31 downto 0):=(others=>'0');
--signal ch1_samples:std_logic_vector(31 downto 0):=(others=>'0');
--signal ch2_samples:std_logic_vector(31 downto 0):=(others=>'0');
--signal ch3_samples:std_logic_vector(31 downto 0):=(others=>'0');

signal temp_power:std_logic_vector(22 downto 0):=(others=>'0');
signal trig: std_logic:='0';
signal triggering_channels: std_logic_vector(NUM_CHANNELS-1 downto 0) := (others=>'0');
signal temp_sample:std_logic_vector(7 downto 0):=(others=>'0');
signal is_enable:std_logic:='0';

begin
    --registers(0)<=x"00020803" after 40 ns; --trigger params
    clock <= not clock after 2 ns; -- 4ns clock period
    slow_clk <= not slow_clk after 8 ns; -- don't make it so long that it takes 100 ns to move thresholds into the trigger

    -----------------------------------------------------------------------------
    -- Instantiate and Map UUT
    -----------------------------------------------------------------------------

    simple_trigger_inst: simple_trigger
    port map(
        rst_i               => '0',
        clk_i               => slow_clk,
        clk_data_i          => clock,
        registers_i         => registers,
        ch_data_i           => ch_samples,

		trig_bits_o         => open,
        trig_o              => trig,
		trig_metadata_o     => triggering_channels
        );


    process


    variable thresholds_tmp:thresholds_t;
    variable registers_tmp: register_array_type;

    variable ch0_samples_tmp:std_logic_vector(31 downto 0);
    variable ch1_samples_tmp:std_logic_vector(31 downto 0);
    variable ch2_samples_tmp:std_logic_vector(31 downto 0);
    variable ch3_samples_tmp:std_logic_vector(31 downto 0);
    variable ch4_samples_tmp:std_logic_vector(31 downto 0);
    variable ch5_samples_tmp:std_logic_vector(31 downto 0);
    variable ch6_samples_tmp:std_logic_vector(31 downto 0);
    variable ch7_samples_tmp:std_logic_vector(31 downto 0);
    variable ch8_samples_tmp:std_logic_vector(31 downto 0);
    variable ch9_samples_tmp:std_logic_vector(31 downto 0);
    variable ch10_samples_tmp:std_logic_vector(31 downto 0);
    variable ch11_samples_tmp:std_logic_vector(31 downto 0);

    variable ch12_samples_tmp:std_logic_vector(31 downto 0);
    variable ch13_samples_tmp:std_logic_vector(31 downto 0);
    variable ch14_samples_tmp:std_logic_vector(31 downto 0);
    variable ch15_samples_tmp:std_logic_vector(31 downto 0);
    variable ch16_samples_tmp:std_logic_vector(31 downto 0);
    variable ch17_samples_tmp:std_logic_vector(31 downto 0);
    variable ch18_samples_tmp:std_logic_vector(31 downto 0);
    variable ch19_samples_tmp:std_logic_vector(31 downto 0);
    variable ch20_samples_tmp:std_logic_vector(31 downto 0);
    variable ch21_samples_tmp:std_logic_vector(31 downto 0);
    variable ch22_samples_tmp:std_logic_vector(31 downto 0);
    variable ch23_samples_tmp:std_logic_vector(31 downto 0);

    variable trig_tmp: std_logic:='0';

    variable v_ILINE     : line;
    variable v_OLINE     : line;
    variable v_SPACE     : character;

    file file_INPUT : text;-- open read_mode is "input_waveforms.txt";
    file file_THRESHOLDS : text;-- open read_mode is "input_thresholds.txt";
    file file_TRIGGERS : text;-- open write_mode is "output_trigger.txt";

        begin

            --io files
            file_open(file_INPUT, "data/input_waveforms.txt", read_mode);
            file_open(file_THRESHOLDS, "data/input_channel_thresholds.txt", read_mode);
            file_open(file_TRIGGERS, "data/output_trigger.txt", write_mode);

            --read in thresholds and assign to regs

            readline(file_THRESHOLDS,v_ILINE);
            for i in 0 to 11 loop
                read(v_ILINE,thresholds_tmp(2*i));
                read(v_ILINE, v_SPACE);
                registers(2+i)(7 downto 0)<=thresholds_tmp(2*i);
                
                read(v_ILINE,thresholds_tmp(2*i+1));
                read(v_ILINE, v_SPACE);
                registers(2+i)(23 downto 16)<=thresholds_tmp(2*i+1);
            end loop;

            registers(0)<=x"00020803"; --trigger params
            registers(1)<=x"00ffffff"; --channel mask
            --registers(81)<=x"000000"; --threshold offset

            --read in samples in sets of 4
            while not endfile(file_INPUT) loop
                readline(file_INPUT, v_ILINE);
                read(v_ILINE, ch0_samples_tmp);
                read(v_ILINE, v_SPACE);
                read(v_ILINE, ch1_samples_tmp);
                read(v_ILINE, v_SPACE);
                read(v_ILINE, ch2_samples_tmp);
                read(v_ILINE, v_SPACE);
                read(v_ILINE, ch3_samples_tmp);
                read(v_ILINE, v_SPACE);

                read(v_ILINE, ch4_samples_tmp);
                read(v_ILINE, v_SPACE);
                read(v_ILINE, ch5_samples_tmp);
                read(v_ILINE, v_SPACE);
                read(v_ILINE, ch6_samples_tmp);
                read(v_ILINE, v_SPACE);
                read(v_ILINE, ch7_samples_tmp);
                read(v_ILINE, v_SPACE);
                
                read(v_ILINE, ch8_samples_tmp);
                read(v_ILINE, v_SPACE);
                read(v_ILINE, ch9_samples_tmp);
                read(v_ILINE, v_SPACE);
                read(v_ILINE, ch10_samples_tmp);
                read(v_ILINE, v_SPACE);
                read(v_ILINE, ch11_samples_tmp);
                read(v_ILINE, v_SPACE);
                
                read(v_ILINE, ch12_samples_tmp);
                read(v_ILINE, v_SPACE);
                read(v_ILINE, ch13_samples_tmp);
                read(v_ILINE, v_SPACE);
                read(v_ILINE, ch14_samples_tmp);
                read(v_ILINE, v_SPACE);
                read(v_ILINE, ch15_samples_tmp);
                read(v_ILINE, v_SPACE);
                
                read(v_ILINE, ch16_samples_tmp);
                read(v_ILINE, v_SPACE);
                read(v_ILINE, ch17_samples_tmp);
                read(v_ILINE, v_SPACE);
                read(v_ILINE, ch18_samples_tmp);
                read(v_ILINE, v_SPACE);
                read(v_ILINE, ch19_samples_tmp);
                read(v_ILINE, v_SPACE);
                
                read(v_ILINE, ch20_samples_tmp);
                read(v_ILINE, v_SPACE);
                read(v_ILINE, ch21_samples_tmp);
                read(v_ILINE, v_SPACE);
                read(v_ILINE, ch22_samples_tmp);
                read(v_ILINE, v_SPACE);
                read(v_ILINE, ch23_samples_tmp);
                --read(v_ILINE, v_SPACE);

                --assign data

                ch_samples((0+1)*NUM_SAMPLES*SAMPLE_LENGTH-1 downto 0*NUM_SAMPLES*SAMPLE_LENGTH) <= ch0_samples_tmp;
                ch_samples((1+1)*NUM_SAMPLES*SAMPLE_LENGTH-1 downto 1*NUM_SAMPLES*SAMPLE_LENGTH) <= ch1_samples_tmp; 
                ch_samples((2+1)*NUM_SAMPLES*SAMPLE_LENGTH-1 downto 2*NUM_SAMPLES*SAMPLE_LENGTH) <= ch2_samples_tmp;
                ch_samples((3+1)*NUM_SAMPLES*SAMPLE_LENGTH-1 downto 3*NUM_SAMPLES*SAMPLE_LENGTH) <= ch3_samples_tmp;
                
                ch_samples((4+1)*NUM_SAMPLES*SAMPLE_LENGTH-1 downto 4*NUM_SAMPLES*SAMPLE_LENGTH) <= ch4_samples_tmp;
                ch_samples((5+1)*NUM_SAMPLES*SAMPLE_LENGTH-1 downto 5*NUM_SAMPLES*SAMPLE_LENGTH) <= ch5_samples_tmp;
                ch_samples((6+1)*NUM_SAMPLES*SAMPLE_LENGTH-1 downto 6*NUM_SAMPLES*SAMPLE_LENGTH) <= ch6_samples_tmp;
                ch_samples((7+1)*NUM_SAMPLES*SAMPLE_LENGTH-1 downto 7*NUM_SAMPLES*SAMPLE_LENGTH) <= ch7_samples_tmp;

                ch_samples((8+1)*NUM_SAMPLES*SAMPLE_LENGTH-1 downto 8*NUM_SAMPLES*SAMPLE_LENGTH) <= ch8_samples_tmp;
                ch_samples((9+1)*NUM_SAMPLES*SAMPLE_LENGTH-1 downto 9*NUM_SAMPLES*SAMPLE_LENGTH) <= ch9_samples_tmp;
                ch_samples((10+1)*NUM_SAMPLES*SAMPLE_LENGTH-1 downto 10*NUM_SAMPLES*SAMPLE_LENGTH) <= ch10_samples_tmp;
                ch_samples((11+1)*NUM_SAMPLES*SAMPLE_LENGTH-1 downto 11*NUM_SAMPLES*SAMPLE_LENGTH) <= ch11_samples_tmp;

                ch_samples((12+1)*NUM_SAMPLES*SAMPLE_LENGTH-1 downto 12*NUM_SAMPLES*SAMPLE_LENGTH) <= ch12_samples_tmp;
                ch_samples((13+1)*NUM_SAMPLES*SAMPLE_LENGTH-1 downto 13*NUM_SAMPLES*SAMPLE_LENGTH) <= ch13_samples_tmp;
                ch_samples((14+1)*NUM_SAMPLES*SAMPLE_LENGTH-1 downto 14*NUM_SAMPLES*SAMPLE_LENGTH) <= ch14_samples_tmp;
                ch_samples((15+1)*NUM_SAMPLES*SAMPLE_LENGTH-1 downto 15*NUM_SAMPLES*SAMPLE_LENGTH) <= ch15_samples_tmp;

                ch_samples((16+1)*NUM_SAMPLES*SAMPLE_LENGTH-1 downto 16*NUM_SAMPLES*SAMPLE_LENGTH) <= ch16_samples_tmp;
                ch_samples((17+1)*NUM_SAMPLES*SAMPLE_LENGTH-1 downto 17*NUM_SAMPLES*SAMPLE_LENGTH) <= ch17_samples_tmp;
                ch_samples((18+1)*NUM_SAMPLES*SAMPLE_LENGTH-1 downto 18*NUM_SAMPLES*SAMPLE_LENGTH) <= ch18_samples_tmp;
                ch_samples((19+1)*NUM_SAMPLES*SAMPLE_LENGTH-1 downto 19*NUM_SAMPLES*SAMPLE_LENGTH) <= ch19_samples_tmp;

                ch_samples((20+1)*NUM_SAMPLES*SAMPLE_LENGTH-1 downto 20*NUM_SAMPLES*SAMPLE_LENGTH) <= ch20_samples_tmp;
                ch_samples((21+1)*NUM_SAMPLES*SAMPLE_LENGTH-1 downto 21*NUM_SAMPLES*SAMPLE_LENGTH) <= ch21_samples_tmp;
                ch_samples((22+1)*NUM_SAMPLES*SAMPLE_LENGTH-1 downto 22*NUM_SAMPLES*SAMPLE_LENGTH) <= ch22_samples_tmp;
                ch_samples((23+1)*NUM_SAMPLES*SAMPLE_LENGTH-1 downto 23*NUM_SAMPLES*SAMPLE_LENGTH) <= ch23_samples_tmp;

                
                
                --ch0_samples<=ch0_samples_tmp;
                --ch1_samples<=ch1_samples_tmp;
                --ch2_samples<=ch2_samples_tmp;
                --ch3_samples<=ch3_samples_tmp;


                
                wait for 4 ns; --about 1/118e6 ns, one full clock cycle
                --write(v_OLINE,ch_samples(31 downto 0),right,32);
                --writeline(output,v_OLINE);

                --write(v_OLINE,temp_sample,right,8);
                --writeline(output,v_OLINE);

                --write(v_OLINE,registers(3)(31 downto 0),right,32);
                --writeline(output,v_OLINE);

                write(v_OLINE,trig,right,1);
                writeline(output,v_OLINE);

                write(v_OLINE,triggering_channels,right,24);
                writeline(output,v_OLINE);

                --write(v_OLINE,is_enable,right,1);
                --writeline(output,v_OLINE);
                --write output trigger state
                write(v_OLINE,trig,right,1);
                writeline(file_TRIGGERS, v_OLINE);


            end loop;

            file_close(file_INPUT);
            file_close(file_THRESHOLDS);
            file_close(file_TRIGGERS);

            wait;

        end process;

end behave;