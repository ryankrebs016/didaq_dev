library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
--use ieee.std_logic_textio.all;

use work.defs.all;
--use work.register_map.all;
use work.all;

entity simple_beamformed_trigger_tb is
end simple_beamformed_trigger_tb;

architecture behave of simple_beamformed_trigger_tb is
-----------------------------------------------------------------------------
-- Declare the Component Under Test
-----------------------------------------------------------------------------

component simple_beamformed_trigger
    generic(
            ENABLE : std_logic := '1';
            TRIG_PARAM_ADDRESS : std_logic_vector(7 downto 0) := x"00";
            THRESHOLD_BASE_ADDRESS : std_logic_vector(7 downto 0) := x"01";
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
            trig_o: 	out	std_logic; --trigger
            trig_metadata_o: out std_logic_vector(num_beams-1 downto 0) --for triggering beams

            );
end component;

-----------------------------------------------------------------------------
-- Testbench Internal Signals
-----------------------------------------------------------------------------
signal  clock : std_logic := '1';
signal slow_clk:std_logic:='0';

type thresholds_t is array(num_beams-1 downto 0) of std_logic_vector(7 downto 0);
signal enable: std_logic:='1';
--type input_samples_t is unsigned(31 downto 0);
type output_samples_t is array(15 downto 0) of std_logic_vector(31 downto 0);
signal thresholds:thresholds_t:=(others=>"00100000");
signal registers: register_array_type:=(others=>(others=>'0'));

signal ch0_samples:std_logic_vector(31 downto 0):=(others=>'0');
signal ch1_samples:std_logic_vector(31 downto 0):=(others=>'0');
signal ch2_samples:std_logic_vector(31 downto 0):=(others=>'0');
signal ch3_samples:std_logic_vector(31 downto 0):=(others=>'0');

signal meta:std_logic_vector(11 downto 0):=x"000";
signal temp_power:std_logic_vector(22 downto 0):=(others=>'0');
signal trig: std_logic:='0';
signal temp_sample:std_logic_vector(7 downto 0):=(others=>'0');
signal is_enable:std_logic:='0';

begin

    clock <= not clock after 2 ns;
    slow_clk <= not slow_clk after 8 ns; -- don't make it so long that it takes 100 ns to move thresholds into the trigger

    -----------------------------------------------------------------------------
    -- Instantiate and Map UUT
    -----------------------------------------------------------------------------

    simple_beamformed_trigger_inst: simple_beamformed_trigger
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
        trig_o           => trig,
        trig_metadata_o  => meta
        );


    process


    variable thresholds_tmp:thresholds_t:=(others=>"00100000");
    variable registers_tmp: register_array_type;

    variable ch0_samples_tmp:std_logic_vector(31 downto 0):=x"80808080";
    variable ch1_samples_tmp:std_logic_vector(31 downto 0):=x"80808080";
    variable ch2_samples_tmp:std_logic_vector(31 downto 0):=x"80808080";
    variable ch3_samples_tmp:std_logic_vector(31 downto 0):=x"80808080";

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
            file_open(file_THRESHOLDS, "data/input_pa_thresholds.txt", read_mode);
            file_open(file_TRIGGERS, "data/output_pa_trigger.txt", write_mode);

            --read in thresholds and assign to regs

            readline(file_THRESHOLDS,v_ILINE);
            for i in 0 to NUM_BEAMS/2-1 loop
                read(v_ILINE,thresholds_tmp(2*i));
                read(v_ILINE, v_SPACE);
                registers(1+i)(7 downto 0)<=thresholds_tmp(2*i); --make to correct reg location
                
                read(v_ILINE,thresholds_tmp(2*i+1));
                read(v_ILINE, v_SPACE);
                registers(1+i)(23 downto 16)<=thresholds_tmp(2*i+1);
            end loop;
            --ch mask beam mask enable
            registers(0)<=x"0f0fff01"; --beam mask
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
                write(v_OLINE,meta,right,12);
                writeline(output,v_OLINE);

                --write(v_OLINE,temp_sample,right,8);
                --writeline(output,v_OLINE);

                
                write(v_OLINE,trig,right,1);
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