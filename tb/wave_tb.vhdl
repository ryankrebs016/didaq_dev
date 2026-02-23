library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
--use ieee.std_logic_textio.all;

use work.defs.all;
use work.register_map.all;
use work.all;

entity wave_tb is
end wave_tb;

architecture behave of wave_tb is
---------------------------------------------------------------------------
-- Declare the Component Under Test
-----------------------------------------------------------------------------
component upsampling is 
    port(
            rst_i			:	in		std_logic;
            clk_data_i	:	in		std_logic; --data clock
            enable : in std_logic;
            ch_data_i : in std_logic_vector(8*step_size*num_channels -1 downto 0);
            ch_data_o : out std_logic_vector(8*step_size*num_channels*interp_factor -1 downto 0)
    
            );
    end component;
    
    signal upsampling_i : std_logic_vector(8*step_size*num_channels -1 downto 0):=(others=>'0');
    signal upsampling_o : std_logic_vector(8*step_size*num_channels*interp_factor -1 downto 0):=(others=>'0');
    
    
    component beamforming is 
        generic
        (
            station_number_i : in std_logic_vector(7 downto 0)
        );
        port(
                rst_i			:	in		std_logic;
                clk_data_i	:	in		std_logic; --data clock
                enable : in std_logic;
                ch_data_i : in std_logic_vector(8*step_size*num_channels*interp_factor -1 downto 0);
                beam_data_o : out std_logic_vector(num_beams*step_size*interp_factor*8-1 downto 0)
    
                );
        end component;
    
    signal beaming_i : std_logic_vector(8*step_size*num_channels*interp_factor -1 downto 0):=(others=>'0');
    signal beaming_o : std_logic_vector(num_beams*8*step_size*interp_factor-1 downto 0):=(others=>'0');
    
    
    component power_integration is 
        port(
                rst_i			:	in		std_logic;
                clk_data_i	:	in		std_logic; --data clock
                enable : in std_logic;
                beam_data_i : in std_logic_vector(num_beams*step_size*interp_factor*8-1 downto 0);
                power_o : out std_logic_vector(14*4*num_beams-1 downto 0)
    
                );
        end component;
    
    signal power_integration_i : std_logic_vector(num_beams*step_size*interp_factor*8-1 downto 0):=(others=>'0');
    signal power_integration_o : std_logic_vector(14*4*num_beams-1 downto 0):=(others=>'0');
    
-----------------------------------------------------------------------------
-- Testbench Internal Signals
-----------------------------------------------------------------------------
signal  clock : std_logic := '1';
signal rst_i: std_logic:='0';
signal enable: std_logic:='1';
--type input_samples_t is unsigned(31 downto 0);

signal ch0_samples:std_logic_vector(31 downto 0):=x"80808080";
signal ch1_samples:std_logic_vector(31 downto 0):=x"80808080";
signal ch2_samples:std_logic_vector(31 downto 0):=x"80808080";
signal ch3_samples:std_logic_vector(31 downto 0):=x"80808080";


begin

    clock <= not clock after 4.237 ns;

    -----------------------------------------------------------------------------
    -- Instantiate and Map UUT
    -----------------------------------------------------------------------------
    xUpsampling : upsampling 
    port map (
        rst_i => rst_i,
        clk_data_i => clock,
        enable => enable,
        ch_data_i => upsampling_i,
        ch_data_o => upsampling_o
    );

    sim_sams:for i in 0 to 3 generate
        upsampling_i(8*(i+1)-1 downto 8*i)<=std_logic_vector(unsigned(ch0_samples(8*(i+1)-1 downto 8*i))-128);
        upsampling_i(4*1*8+8*(i+1)-1 downto 4*1*8+8*i)<=std_logic_vector(unsigned(ch1_samples(8*(i+1)-1 downto 8*i))-128);
        upsampling_i(4*2*8+8*(i+1)-1 downto 4*2*8+8*i)<=std_logic_vector(unsigned(ch2_samples(8*(i+1)-1 downto 8*i))-128);
        upsampling_i(4*3*8+8*(i+1)-1 downto 4*3*8+8*i)<=std_logic_vector(unsigned(ch3_samples(8*(i+1)-1 downto 8*i))-128);
    end generate;

    beaming_i<=upsampling_o;
    power_integration_i<=beaming_o;
    
    
    --connect upsampling to beamforming

    
    xBeamforming: beamforming
    generic map (station_number_i=>x"0b")
    port map (
        rst_i => rst_i,
        clk_data_i => clock,
        enable => enable,
        ch_data_i => beaming_i,
        beam_data_o => beaming_o
    );

    
    xPower: power_integration
    port map (
        rst_i => rst_i,
        clk_data_i => clock,
        enable => enable,
        beam_data_i => power_integration_i,
        power_o =>  power_integration_o
    );
    
    --connect output of power
    --assing_power_o: for bm in 0 to num_beams-1 generate
    --    avg_power(bm)<=unsigned(power_integration_o(2*18*(bm+1)-18 downto 2*18*bm));
    --    avg_power_overlap(bm)<=unsigned(power_integration_o(2*18*(bm+1) downto 2*18*bm+18));
    --end generate;

    process


    variable ch0_samples_tmp:std_logic_vector(31 downto 0):=x"80808080";
    variable ch1_samples_tmp:std_logic_vector(31 downto 0):=x"80808080";
    variable ch2_samples_tmp:std_logic_vector(31 downto 0):=x"80808080";
    variable ch3_samples_tmp:std_logic_vector(31 downto 0):=x"80808080";

    variable trig_tmp: std_logic:='0';

    variable v_ILINE     : line;
    variable v_OLINE     : line;
    variable v_SPACE     : character;

    file file_INPUT : text;
    file file_UPSAMPLING : text;
    file file_BEAMFORMING : text;
    file file_POWER : text;

        begin

            --io files
            file_open(file_INPUT, "tb/data/input_waveforms.txt", read_mode);
            file_open(file_UPSAMPLING, "tb/data/output_upsampled.txt", write_mode);
            file_open(file_BEAMFORMING, "tb/data/output_beamformed.txt", write_mode);
            file_open(file_POWER, "tb/data/output_power.txt", write_mode);


            --read in thresholds and assign to regs

            --read in samples in sets of 4
            while not endfile(file_INPUT) loop
                wait for 8.474 ns; --about 1/118e6 ns, one full clock cycle

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

                writeline(output,v_OLINE);
                writeline(output,v_OLINE);
                writeline(output,v_OLINE);

                --write(v_OLINE,upsampling_i(31 downto 0),right,32);--4*4*8);
                write(v_OLINE,upsampling_i(7 downto 0),right,8);--4*4*8);
                writeline(output,v_OLINE);

                write(v_OLINE,upsampling_i(15 downto 8),right,8);--4*4*8);
                writeline(output,v_OLINE);

                write(v_OLINE,upsampling_i(23 downto 16),right,8);--4*4*8);
                writeline(output,v_OLINE);

                write(v_OLINE,upsampling_i(31 downto 24),right,8);--4*4*8);
                writeline(output,v_OLINE);

                writeline(output,v_OLINE);

                write(v_OLINE,upsampling_o,right,4*16*8);
                writeline(output,v_OLINE);
                writeline(output,v_OLINE);

                write(v_OLINE,beaming_o,right,12*16*8);
                writeline(output,v_OLINE);
                writeline(output,v_OLINE);

                write(v_OLINE,power_integration_o,right,12*14*4);
                writeline(output,v_OLINE);
                --write(v_OLINE,ch0_output,right,32*4);
                --writeline(output,v_OLINE);
                --write(v_OLINE,temp_sample,right,8);
                --writeline(output,v_OLINE);


                --write upsampled waveforms
                for ch in 0 to 3 loop
                    for i in 0 to 15 loop
                        write(v_OLINE,unsigned(upsampling_o(16*8*ch+8*(i+1)-1 downto 16*8*ch+8*i))+128,right,8);
                        write(v_OLINE, v_SPACE);
                    end loop;
                end loop;
                writeline(file_UPSAMPLING, v_OLINE);

                --write beamformed waveforms
                for bm in 0 to 11 loop
                    for i in 0 to 15 loop
                        write(v_OLINE,unsigned(beaming_o(16*8*bm+8*(i+1)-1 downto 16*8*bm+8*i))+128,right,8);
                        write(v_OLINE, v_SPACE);
                    end loop;
                end loop;
                writeline(file_BEAMFORMING, v_OLINE);

                --write averaged power
                for bm in 0 to 11 loop
                    for i in 0 to 3 loop
                        write(v_OLINE,unsigned(power_integration_o(14*4*bm+14*(i+1)-1 downto 14*4*bm+14*i)),right,14);
                        write(v_OLINE, v_SPACE);
                    end loop;
                end loop;
                writeline(file_POWER, v_OLINE);


            end loop;

            file_close(file_INPUT);
            file_close(file_UPSAMPLING);
            file_close(file_BEAMFORMING);
            file_close(file_POWER);


            wait;

        end process;

end behave;