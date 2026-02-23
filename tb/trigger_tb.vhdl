library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
--use ieee.std_logic_textio.all;

use work.defs.all;
use work.register_map.all;
use work.all;

entity trigger_tb is
end trigger_tb;

architecture behave of trigger_tb is
-----------------------------------------------------------------------------
-- Declare the Component Under Test
-----------------------------------------------------------------------------

component power_trigger

    
    generic(
            ENABLE_PHASED_TRIG : std_logic := '1';
            trigger_enable_reg_adr : std_logic_vector(7 downto 0) := x"3D";
            phased_trig_reg_base	: std_logic_vector(7 downto 0):= x"50";
            address_reg_pps_delay: std_logic_vector(7 downto 0) := x"5E";
            phased_trig_param_reg	: std_logic_vector(7 downto 0):= x"80";
            station_number : std_logic_vector(7 downto 0):=x"0b"
            );
    
    port(
            rst_i			:	in		std_logic;
            clk_i			:	in		std_logic; --register clock 
            clk_data_i	:	in		std_logic; --data clock
            registers_i	:	in		register_array_type;
            
            ch0_data_i	: 	in		std_logic_vector(31 downto 0);
            ch1_data_i	:	in		std_logic_vector(31 downto 0);
            ch2_data_i	:	in		std_logic_vector(31 downto 0);
            ch3_data_i	:	in		std_logic_vector(31 downto 0);
            
            trig_bits_o : 	out	std_logic_vector(2*(num_beams+1)-1 downto 0); --for scalers
            phased_trig_o: 	out	std_logic; --trigger
            phased_trig_metadata_o: out std_logic_vector(num_beams-1 downto 0) --for triggering beams

            );
end component;

-----------------------------------------------------------------------------
-- Testbench Internal Signals
-----------------------------------------------------------------------------
signal  clock : std_logic := '1';
signal slow_clk:std_logic:='0';

type thresholds_t is array(num_beams-1 downto 0) of std_logic_vector(11 downto 0);
signal enable: std_logic:='1';
--type input_samples_t is unsigned(31 downto 0);
type output_samples_t is array(15 downto 0) of std_logic_vector(31 downto 0);
signal thresholds:thresholds_t:=(others=>(others=>'0'));
signal registers: register_array_type:=(others=>(others=>'0'));

signal ch0_samples:std_logic_vector(31 downto 0):=(others=>'0');
signal ch1_samples:std_logic_vector(31 downto 0):=(others=>'0');
signal ch2_samples:std_logic_vector(31 downto 0):=(others=>'0');
signal ch3_samples:std_logic_vector(31 downto 0):=(others=>'0');


signal temp_power:std_logic_vector(22 downto 0):=(others=>'0');
signal trig: std_logic:='0';
signal temp_sample:std_logic_vector(7 downto 0):=(others=>'0');
signal is_enable:std_logic:='0';

begin

    clock <= not clock after 4.237 ns;
    slow_clk <= not slow_clk after 8.474 ns; -- don't make it so long that it takes 100 ns to move thresholds into the trigger

    -----------------------------------------------------------------------------
    -- Instantiate and Map UUT
    -----------------------------------------------------------------------------

    power: power_trigger
    port map(
        rst_i			        => '0',
        clk_i			        => slow_clk,
        clk_data_i	            => clock,
        registers_i	            => registers,
        ch0_data_i	            => ch0_samples,
        ch1_data_i  	        => ch1_samples, 
        ch2_data_i	            => ch2_samples, 
        ch3_data_i	            => ch3_samples,
        trig_bits_o             => open,
        phased_trig_o           => trig,
        phased_trig_metadata_o  => open
        );


    process


    variable thresholds_tmp:thresholds_t;
    variable registers_tmp: register_array_type;

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
            file_open(file_INPUT, "tb/data/input_waveforms.txt", read_mode);
            file_open(file_THRESHOLDS, "tb/data/input_thresholds.txt", read_mode);
            file_open(file_TRIGGERS, "tb/data/output_trigger.txt", write_mode);

            --read in thresholds and assign to regs

            readline(file_THRESHOLDS,v_ILINE);
            for i in 0 to 11 loop
                read(v_ILINE,thresholds_tmp(i));
                read(v_ILINE, v_SPACE);
                registers(128+i)(11 downto 0)<=thresholds_tmp(i); --make to correct reg location
            end loop;

            registers(80)<=x"000fff"; --beam mask
            registers(61)(9)<=enable; --phased trigger enable
            registers(81)<=x"000000"; --threshold offset
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


                
                wait for 8.474 ns; --about 1/118e6 ns, one full clock cycle
                --write(v_OLINE,ch0_samples(7 downto 0),right,8);
                --writeline(output,v_OLINE);

                --write(v_OLINE,temp_sample,right,8);
                --writeline(output,v_OLINE);

                
                --write(v_OLINE,trig,right,1);
                --writeline(output,v_OLINE);

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