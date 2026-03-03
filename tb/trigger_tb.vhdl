library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
--use ieee.std_logic_textio.all;

use work.defs.all;
use work.all;

entity trigger_tb is
end trigger_tb;

architecture behave of trigger_tb is
-----------------------------------------------------------------------------
-- Declare the Component Under Test
-----------------------------------------------------------------------------

-----------------------------------------------------------------------------
-- Testbench Internal Signals
-----------------------------------------------------------------------------
signal  clock : std_logic := '1';
signal slow_clk:std_logic:='0';

signal enable: std_logic:='1';
--type input_samples_t is unsigned(31 downto 0);
type output_samples_t is array(15 downto 0) of std_logic_vector(31 downto 0);

type thresholds_t is array(NUM_BEAMS-1 downto 0) of std_logic_vector(11 downto 0);

signal trig_thresholds : std_logic_vector(NUM_BEAMS*12-1 downto 0) := (others=>'0');
signal servo_thresholds : std_logic_vector(NUM_BEAMS*12-1 downto 0) := (others=>'0');


signal ch0_samples:std_logic_vector(31 downto 0):=(others=>'0');
signal ch1_samples:std_logic_vector(31 downto 0):=(others=>'0');
signal ch2_samples:std_logic_vector(31 downto 0):=(others=>'0');
signal ch3_samples:std_logic_vector(31 downto 0):=(others=>'0');

signal meta : std_logic_vector(NUM_BEAMS-1 downto 0) := (others=>'0');
signal temp_power:std_logic_vector(22 downto 0):=(others=>'0');
signal trig: std_logic:='0';
signal temp_sample:std_logic_vector(7 downto 0):=(others=>'0');
signal is_enable:std_logic:='0';
signal test : std_logic_vector(13 downto 0) := (others=>'0');
begin

    clock <= not clock after 2 ns;
    slow_clk <= not slow_clk after 4 ns; -- don't make it so long that it takes 100 ns to move thresholds into the trigger

    -----------------------------------------------------------------------------
    -- Instantiate and Map UUT
    -----------------------------------------------------------------------------

    power : entity work.power_trigger
    generic map(
        station_number => x"0b"
    )
    port map(
            rst_i			        => '0',
        
            clk_data_i	            => clock,
            ch0_data_i	            => ch0_samples,
            ch1_data_i  	        => ch1_samples, 
            ch2_data_i	            => ch2_samples, 
            ch3_data_i	            => ch3_samples,

            clk_reg_i               => slow_clk,
            enable_i                => enable,
            beam_mask_i             => x"fff",
            channel_mask_i          => x"f",
            trig_thresholds_i       => trig_thresholds,
            servo_thresholds_i      => servo_thresholds,

            trig_bits_o             => open,
            trig_o                  => trig,
            trig_metadata_o         => meta,
            power_o => test
        );


    process


    variable thresholds_tmp:thresholds_t;

    variable ch0_samples_tmp:std_logic_vector(31 downto 0);
    variable ch1_samples_tmp:std_logic_vector(31 downto 0);
    variable ch2_samples_tmp:std_logic_vector(31 downto 0);
    variable ch3_samples_tmp:std_logic_vector(31 downto 0);

    variable ch0_output_tmp:output_samples_t;
    variable ch1_output_tmp:output_samples_t;
    variable ch2_output_tmp:output_samples_t;
    variable ch3_output_tmp:output_samples_t;

    variable trig_tmp: std_logic:='0';

    variable v_ILINE     : line;
    variable v_OLINE     : line;
    variable v_SPACE     : character;

    file file_INPUT : text;-- open read_mode is "input_waveforms.txt";
    file file_THRESHOLDS : text;-- open read_mode is "input_thresholds.txt";
    file file_TRIGGERS : text;-- open write_mode is "output_trigger.txt";

        begin

            --io files
            file_open(file_INPUT, "data/input_pa_waveforms.txt", read_mode);
            file_open(file_THRESHOLDS, "data/input_power_thresholds.txt", read_mode);
            file_open(file_TRIGGERS, "data/output_power_trigger.txt", write_mode);

            --read in thresholds and assign to regs

            readline(file_THRESHOLDS,v_ILINE);
            for i in 0 to NUM_BEAMS-1 loop
                read(v_ILINE,thresholds_tmp(i));
                read(v_ILINE, v_SPACE);
                trig_thresholds((i+1)*12-1 downto i*12)<=thresholds_tmp(i); --make to correct reg location
                servo_thresholds((i+1)*12-1 downto i*12)<=thresholds_tmp(i); --make to correct reg location
                
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

                --assign data
                ch0_samples<=ch0_samples_tmp;
                ch1_samples<=ch1_samples_tmp;
                ch2_samples<=ch2_samples_tmp;
                ch3_samples<=ch3_samples_tmp;


                
                wait for 4 ns; --about 1/118e6 ns, one full clock cycle
                --write(v_OLINE,ch0_samples(7 downto 0),right,8);
                --writeline(output,v_OLINE);

                --write(v_OLINE,temp_sample,right,8);
                --writeline(output,v_OLINE);

                
                --write(v_OLINE,trig,right,1);
                --writeline(output,v_OLINE);

                --write(v_OLINE,is_enable,right,1);
                --writeline(output,v_OLINE);
                --write output trigger state
                write(v_OLINE, ch3_samples, right, 32);
                write(v_OLINE, v_SPACE);

                write(v_OLINE, trig_thresholds(11 downto 0), right, 12);
                write(v_OLINE, v_SPACE);

                write(v_OLINE,trig,right,1);
                write(v_OLINE, v_SPACE);

                write(v_OLINE,meta,right,12);
                write(v_OLINE, v_SPACE);

                write(v_OLINE,test,right,14);
                --write(v_OLINE, v_SPACE);

                writeline(file_TRIGGERS, v_OLINE);


            end loop;

            file_close(file_INPUT);
            file_close(file_THRESHOLDS);
            file_close(file_TRIGGERS);

            wait;

        end process;

end behave;