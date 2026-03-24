library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
--use ieee.std_logic_textio.all;

use work.defs.all;
use work.all;

entity coinc_trigger_tb is
end coinc_trigger_tb;

architecture behave of coinc_trigger_tb is
-----------------------------------------------------------------------------
-- Declare the Component Under Test
-----------------------------------------------------------------------------

-----------------------------------------------------------------------------
-- Testbench Internal Signals
-----------------------------------------------------------------------------
signal  clock : std_logic := '1';
signal slow_clk:std_logic:='0';

type thresholds_t is array(NUM_CHANNELS-1 downto 0) of std_logic_vector(7 downto 0);
signal enable: std_logic:='1';
--type input_samples_t is unsigned(31 downto 0);
signal thresholds:thresholds_t:=(others=>"01000000");
signal trig_thresholds : std_logic_vector(8*NUM_CHANNELS-1 downto 0) := (others=>'0');
signal servo_thresholds : std_logic_vector(8*NUM_CHANNELS-1 downto 0) := (others=>'0');

signal ch_samples:std_logic_vector(NUM_CHANNELS*NUM_SAMPLES*SAMPLE_LENGTH-1 downto 0):=(others=>'0');
signal data_valid : std_logic_vector(NUM_CHANNELS-1 downto 0) := (others=>'1');

--signal ch0_samples:std_logic_vector(31 downto 0):=(others=>'0');
--signal ch1_samples:std_logic_vector(31 downto 0):=(others=>'0');
--signal ch2_samples:std_logic_vector(31 downto 0):=(others=>'0');
--signal ch3_samples:std_logic_vector(31 downto 0):=(others=>'0');

signal trig_0: std_logic:='0';
signal trig_1: std_logic:='0';

signal triggering_channels_0: std_logic_vector(NUM_CHANNELS-1 downto 0) := (others=>'0');
signal triggering_channels_1: std_logic_vector(NUM_CHANNELS-1 downto 0) := (others=>'0');

signal temp_sample:std_logic_vector(7 downto 0):=(others=>'0');
signal is_enable:std_logic:='0';

begin
    --registers(0)<=x"00020803" after 40 ns; --trigger params
    clock <= not clock after 2 ns; -- 4ns clock period
    slow_clk <= not slow_clk after 4 ns; -- don't make it so long that it takes 100 ns to move thresholds into the trigger

    -----------------------------------------------------------------------------
    -- Instantiate and Map UUT
    -----------------------------------------------------------------------------

    simple_trigger_inst: entity work.coinc_trigger_24_ch
    port map(
        rst_i               => '0',
        clk_data_i          => clock,
        ch_data_i           => ch_samples,
        ch_data_valid_i     => data_valid,

        clk_reg_i           => slow_clk,

        trig_0_enable_i            => enable,
        trig_0_ch_mask_i           => x"000001",

        trig_1_enable_i => enable,
        trig_1_ch_mask_i => x"000002",

        vpp_mode_i          => '1',
        coinc_window_i      => "01010",
        num_coinc_i         => "00001",
        trig_thresholds_i   => trig_thresholds,
        servo_thresholds_i   => servo_thresholds,

		trig_bits_o         => open,
        trig_0_o              => trig_0,
		trig_0_metadata_o     => triggering_channels_0,
        trig_1_o              => trig_1,
		trig_1_metadata_o     => triggering_channels_1
        );


    process


    variable thresholds_tmp:thresholds_t;

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
            file_open(file_TRIGGERS, "data/coinc_trigger.txt", write_mode);

            --read in thresholds and assign to regs

            readline(file_THRESHOLDS,v_ILINE);
            for i in 0 to NUM_CHANNELS-1 loop
                read(v_ILINE,thresholds_tmp(i));
                read(v_ILINE, v_SPACE);
                trig_thresholds(8*(i+1) -1 downto 8*i)<=thresholds_tmp(i);
                
            end loop;

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

                write(v_OLINE,ch_samples(31 downto 0),right,32);
                write(v_OLINE, v_SPACE);

                write(v_OLINE,trig_thresholds(7 downto 0),right,8);
                write(v_OLINE, v_SPACE);

                --writeline(file_TRIGGERS,v_OLINE);

                write(v_OLINE,trig_0,right,1);
                write(v_OLINE, v_SPACE);

                write(v_OLINE,triggering_channels_0,right,24);
                write(v_OLINE, v_SPACE);

                write(v_OLINE,trig_1,right,1);
                write(v_OLINE, v_SPACE);

                --writeline(file_TRIGGERS,v_OLINE);

                write(v_OLINE,triggering_channels_1,right,24);
                writeline(file_TRIGGERS,v_OLINE);

                --write(v_OLINE,is_enable,right,1);
                --writeline(output,v_OLINE);
                --write output trigger state
                --write(v_OLINE,trig,right,1);
                --writeline(file_TRIGGERS, v_OLINE);


            end loop;

            file_close(file_INPUT);
            file_close(file_THRESHOLDS);
            file_close(file_TRIGGERS);

            wait;

        end process;

end behave;