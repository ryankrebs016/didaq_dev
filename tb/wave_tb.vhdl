library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
--use ieee.std_logic_textio.all;

use work.defs.all;
use work.all;

entity wave_tb is
end wave_tb;

architecture behave of wave_tb is
---------------------------------------------------------------------------
-- Declare the Component Under Test
-----------------------------------------------------------------------------
constant NUM_SAMPLES : integer := 8;
constant SAMPLE_LENGTH : integer := 8;
constant NUM_PA_CHANNELS : integer := 4;
constant INTERP_FACTOR : integer := 2;
constant POWER_LENGTH : integer := 16;
constant NUM_POWERS : integer := 4;
constant NUM_BEAMS : integer := 12;




signal upsampling_i : std_logic_vector(SAMPLE_LENGTH*NUM_SAMPLES*NUM_PA_CHANNELS -1 downto 0):=(others=>'0');
signal upsampling_o : std_logic_vector(SAMPLE_LENGTH*NUM_SAMPLES*NUM_PA_CHANNELS*INTERP_FACTOR -1 downto 0):=(others=>'0');

signal beaming_i : std_logic_vector(SAMPLE_LENGTH*NUM_SAMPLES*NUM_PA_CHANNELS*INTERP_FACTOR -1 downto 0):=(others=>'0');
signal beaming_o : std_logic_vector(SAMPLE_LENGTH*NUM_BEAMS*NUM_SAMPLES*INTERP_FACTOR-1 downto 0):=(others=>'0');

signal power_integration_i : std_logic_vector(NUM_BEAMS*NUM_SAMPLES*INTERP_FACTOR*SAMPLE_LENGTH-1 downto 0):=(others=>'0');
signal power_integration_o : std_logic_vector(POWER_LENGTH*NUM_POWERS*NUM_BEAMS-1 downto 0):=(others=>'0');
    
-----------------------------------------------------------------------------
-- Testbench Internal Signals
-----------------------------------------------------------------------------
signal  clock : std_logic := '1';
signal rst_i: std_logic:='0';
signal enable: std_logic:='0';
--type input_samples_t is unsigned(31 downto 0);

-- HARDCODED DEFAULTS FOR 4 SAMPLES
signal ch0_samples:std_logic_vector(NUM_SAMPLES*SAMPLE_LENGTH-1 downto 0):=x"8080808080808080"; --x"80808080";
signal ch1_samples:std_logic_vector(NUM_SAMPLES*SAMPLE_LENGTH-1 downto 0):=x"8080808080808080";--:=x"80808080";
signal ch2_samples:std_logic_vector(NUM_SAMPLES*SAMPLE_LENGTH-1 downto 0):=x"8080808080808080";--:=x"80808080";
signal ch3_samples:std_logic_vector(NUM_SAMPLES*SAMPLE_LENGTH-1 downto 0):=x"8080808080808080";--:=x"80808080";


begin

    clock <= not clock after 4 ns;
    enable <= '1' after 32 ns;
    -----------------------------------------------------------------------------
    -- Instantiate and Map UUT
    -----------------------------------------------------------------------------
    xUpsampling : entity work.upsampling 
    generic map(
        SAMPLE_LENGTH   => SAMPLE_LENGTH,
		NUM_SAMPLES     => NUM_SAMPLES,
		NUM_PA_CHANNELS => NUM_PA_CHANNELS,
		INTERP_FACTOR   => INTERP_FACTOR
    )
    port map (
        rst_i => rst_i,
        clk_data_i => clock,
        enable_i => enable,
        ch_data_i => upsampling_i,
        ch_data_o => upsampling_o
    );

    sim_sams:for i in 0 to NUM_SAMPLES-1 generate
        upsampling_i(SAMPLE_LENGTH*(i+1)-1 downto SAMPLE_LENGTH*i)
            <= std_logic_vector(unsigned(ch0_samples(SAMPLE_LENGTH*(i+1)-1 downto SAMPLE_LENGTH*i))-128);

        upsampling_i(NUM_SAMPLES*1*SAMPLE_LENGTH+SAMPLE_LENGTH*(i+1)-1 downto NUM_SAMPLES*1*SAMPLE_LENGTH+SAMPLE_LENGTH*i)
            <= std_logic_vector(unsigned(ch1_samples(SAMPLE_LENGTH*(i+1)-1 downto SAMPLE_LENGTH*i))-128);

        upsampling_i(NUM_SAMPLES*2*SAMPLE_LENGTH+SAMPLE_LENGTH*(i+1)-1 downto NUM_SAMPLES*2*SAMPLE_LENGTH+SAMPLE_LENGTH*i)
            <= std_logic_vector(unsigned(ch2_samples(SAMPLE_LENGTH*(i+1)-1 downto SAMPLE_LENGTH*i))-128);
    
        upsampling_i(NUM_SAMPLES*3*SAMPLE_LENGTH+SAMPLE_LENGTH*(i+1)-1 downto NUM_SAMPLES*3*SAMPLE_LENGTH+SAMPLE_LENGTH*i)
            <= std_logic_vector(unsigned(ch3_samples(SAMPLE_LENGTH*(i+1)-1 downto SAMPLE_LENGTH*i))-128);
    end generate;

    beaming_i<=upsampling_o;
    power_integration_i<=beaming_o;
    
    
    --connect upsampling to beamforming

    
    xBeamforming: entity work.beamforming
    generic map (
        station_number_i=>x"0b",
        SAMPLE_LENGTH   => SAMPLE_LENGTH,
		NUM_SAMPLES     => NUM_SAMPLES,
		NUM_PA_CHANNELS => NUM_PA_CHANNELS,
		INTERP_FACTOR   => INTERP_FACTOR
    )
    port map (
        rst_i => rst_i,
        clk_data_i => clock,
        enable_i => enable,
        ch_data_i => beaming_i,
        beam_data_o => beaming_o
    );

    
    xPower: entity work.power_integration
    generic map(
		SAMPLE_LENGTH   => SAMPLE_LENGTH,
		NUM_SAMPLES     => NUM_SAMPLES,
		NUM_PA_CHANNELS => NUM_PA_CHANNELS,
		INTERP_FACTOR   => INTERP_FACTOR,
        NUM_POWERS      => NUM_POWERS,
        POWER_LENGTH    => POWER_LENGTH
    )
    port map (
        rst_i => rst_i,
        clk_data_i => clock,
        enable_i => enable,
        beam_data_i => power_integration_i,
        power_o =>  power_integration_o
    );
    
    --connect output of power
    --assing_power_o: for bm in 0 to NUM_BEAMS-1 generate
    --    avg_power(bm)<=unsigned(power_integration_o(2*18*(bm+1)-18 downto 2*18*bm));
    --    avg_power_overlap(bm)<=unsigned(power_integration_o(2*18*(bm+1) downto 2*18*bm+18));
    --end generate;

    process

    -- HARDCODED DEFAULTS FOR 4 SAMPLES
    variable ch0_samples_tmp:std_logic_vector(NUM_SAMPLES*SAMPLE_LENGTH-1 downto 0):=x"8080808080808080";--:=x"80808080";
    variable ch1_samples_tmp:std_logic_vector(NUM_SAMPLES*SAMPLE_LENGTH-1 downto 0):=x"8080808080808080";--:=x"80808080";
    variable ch2_samples_tmp:std_logic_vector(NUM_SAMPLES*SAMPLE_LENGTH-1 downto 0):=x"8080808080808080";--:=x"80808080";
    variable ch3_samples_tmp:std_logic_vector(NUM_SAMPLES*SAMPLE_LENGTH-1 downto 0):=x"8080808080808080";--:=x"80808080";

    variable trig_tmp: std_logic:='0';

    variable v_ILINE     : line;
    variable v_OLINE     : line;
    variable v_SPACE     : character;

    file file_INPUT : text;
    file file_OUTPUT : text;
    file file_UPSAMPLING : text;
    file file_BEAMFORMING : text;
    file file_POWER : text;

        begin

            --io files
            file_open(file_INPUT, "data/input_pa_waveforms.txt", read_mode);
            file_open(file_OUTPUT, "data/output_pa_waveforms.txt", write_mode);
            file_open(file_UPSAMPLING, "data/output_upsampled.txt", write_mode);
            file_open(file_BEAMFORMING, "data/output_beamformed.txt", write_mode);
            file_open(file_POWER, "data/output_power.txt", write_mode);


            --read in thresholds and assign to regs

            --read in samples in sets of 4
            while not endfile(file_INPUT) loop
                wait for 8 ns; --about 1/118e6 ns, one full clock cycle

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

                --write(v_OLINE,upsampling_i(31 downto 0),right,32);--4*4*8;
                write(v_OLINE,upsampling_i(SAMPLE_LENGTH-1 downto 0),right,SAMPLE_LENGTH);--4*4*8);
                writeline(output,v_OLINE);

                write(v_OLINE,upsampling_i(2*SAMPLE_LENGTH-1 downto SAMPLE_LENGTH),right,SAMPLE_LENGTH);--4*4*8);
                writeline(output,v_OLINE);

                write(v_OLINE,upsampling_i(3*SAMPLE_LENGTH-1 downto 2*SAMPLE_LENGTH),right,SAMPLE_LENGTH);--4*4*8);
                writeline(output,v_OLINE);

                write(v_OLINE,upsampling_i(4*SAMPLE_LENGTH-1 downto 3*SAMPLE_LENGTH),right,SAMPLE_LENGTH);--4*4*8);
                writeline(output,v_OLINE);

                writeline(output,v_OLINE);

                write(v_OLINE,upsampling_o,right,NUM_PA_CHANNELS*SAMPLE_LENGTH*NUM_SAMPLES*INTERP_FACTOR);
                writeline(output,v_OLINE);
                writeline(output,v_OLINE);

                write(v_OLINE,beaming_o,right,NUM_BEAMS*SAMPLE_LENGTH*NUM_SAMPLES*INTERP_FACTOR);
                writeline(output,v_OLINE);
                writeline(output,v_OLINE);

                write(v_OLINE,power_integration_o,right,NUM_BEAMS*NUM_POWERS*POWER_LENGTH);
                writeline(output,v_OLINE);
                --write(v_OLINE,ch0_output,right,32*4);
                --writeline(output,v_OLINE);
                --write(v_OLINE,temp_sample,right,8);
                --writeline(output,v_OLINE);

                --write upsampled waveforms
                for ch in 0 to NUM_PA_CHANNELS-1 loop
                    for i in 0 to NUM_SAMPLES-1 loop
                        write(v_OLINE,unsigned(upsampling_i(SAMPLE_LENGTH*NUM_SAMPLES*ch+SAMPLE_LENGTH*(i+1)-1 downto SAMPLE_LENGTH*NUM_SAMPLES*ch+SAMPLE_LENGTH*i))+128,right,SAMPLE_LENGTH);
                        write(v_OLINE, v_SPACE);
                    end loop;
                end loop;
                writeline(file_OUTPUT, v_OLINE);

                --write upsampled waveforms
                for ch in 0 to NUM_PA_CHANNELS-1 loop
                    for i in 0 to NUM_SAMPLES*INTERP_FACTOR-1 loop
                        write(v_OLINE,unsigned(upsampling_o(SAMPLE_LENGTH*NUM_SAMPLES*INTERP_FACTOR*ch+SAMPLE_LENGTH*(i+1)-1 downto SAMPLE_LENGTH*NUM_SAMPLES*INTERP_FACTOR*ch+SAMPLE_LENGTH*i))+128,right,SAMPLE_LENGTH);
                        write(v_OLINE, v_SPACE);
                    end loop;
                end loop;
                writeline(file_UPSAMPLING, v_OLINE);

                --write beamformed waveforms
                for bm in 0 to NUM_BEAMS-1 loop
                    for i in 0 to NUM_SAMPLES*INTERP_FACTOR-1 loop
                        write(v_OLINE,unsigned(beaming_o(SAMPLE_LENGTH*NUM_SAMPLES*INTERP_FACTOR*bm+SAMPLE_LENGTH*(i+1)-1 downto SAMPLE_LENGTH*NUM_SAMPLES*INTERP_FACTOR*bm+SAMPLE_LENGTH*i))+128,right,SAMPLE_LENGTH);
                        write(v_OLINE, v_SPACE);
                    end loop;
                end loop;
                writeline(file_BEAMFORMING, v_OLINE);

                --write averaged power
                for bm in 0 to NUM_BEAMS-1 loop
                    for i in 0 to NUM_POWERS-1 loop
                        write(v_OLINE,unsigned(power_integration_o(POWER_LENGTH*NUM_POWERS*bm+POWER_LENGTH*(i+1)-1 downto POWER_LENGTH*NUM_POWERS*bm+POWER_LENGTH*i)),right,POWER_LENGTH);
                        write(v_OLINE, v_SPACE);
                    end loop;
                end loop;
                writeline(file_POWER, v_OLINE);


            end loop;

            file_close(file_INPUT);
            file_close(file_OUTPUT);
            file_close(file_UPSAMPLING);
            file_close(file_BEAMFORMING);
            file_close(file_POWER);


            wait;

        end process;

end behave;