--
--
--
--
-- Input is mapped like Bm11 data (S7, S6, S5, S4, S3, S2, S1, S0) -> Bm0 (S7, S6, S5, S4, S3, S2, S1, S0), at 8-bit samples each
-- Output is mapped like Bm11 data (Avg 1, Avg 0) -> Bm0 data (Avg 1, Avg 0) at 16-bit samples each
--
--
--
--
--
--



library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.defs.all;

entity power_integration is    
    generic(
		SAMPLE_LENGTH   : integer := 8;
		NUM_SAMPLES     : integer := 4;
		NUM_PA_CHANNELS : integer := 4;
		INTERP_FACTOR   : integer := 2;
        NUM_POWERS      : integer := 2;
        POWER_LENGTH    : integer := 16);
    port(
            rst_i		: in std_logic;
            clk_data_i	: in std_logic; --data clock
            enable_i    : in std_logic;
            beam_data_i : in std_logic_vector(NUM_BEAMS*SAMPLE_LENGTH*NUM_SAMPLES*INTERP_FACTOR-1 downto 0);
            power_o     : out std_logic_vector(POWER_LENGTH*NUM_POWERS*NUM_BEAMS-1 downto 0)
    
            );
    end power_integration;
    
architecture rtl of power_integration is

    constant phased_sum_bits: integer := 8;
    constant phased_sum_length: integer := 32; -- actual window determined by addition. This is the divisor since /2^n is easy
    constant phased_sum_power_bits: integer := 16;--16 with calc. trying 7-> 14 lut
    constant num_power_bits: integer := 18;
    constant power_sum_bits:	integer := 18; --actually 25 but this fits into the io regs
    constant num_div: integer := 5;--can be calculated using -> integer(log2(real(phased_sum_length)));

    type phased_arr is array (NUM_BEAMS-1 downto 0,phased_sum_length-1 downto 0) of signed(phased_sum_bits-1 downto 0);-- range 0 to 2**phased_sum_bits-1; --phased sum... log2(16*8)=7bits
    signal phased_beam_waves: phased_arr:= (others=>(others=>(others=>'0')));
    
    --instantaneous power
    type square_waveform is array (NUM_BEAMS-1 downto 0,phased_sum_length-1 downto 0) of unsigned(phased_sum_power_bits-1 downto 0);-- range 0 to 2**phased_sum_power_bits-1;--std_logic_vector(phased_sum_power_bits-1 downto 0);
    signal phased_power : square_waveform:= (others=>(others=>(others=>'0')));
    
    --big arrays for thresholds/ average power
    type power_array is array (NUM_BEAMS-1 downto 0) of unsigned(17 downto 0);-- range 0 to 2**num_power_bits-1;--std_logic_vector(num_power_bits-1 downto 0); --log2(6*(16*6)^2) max power possible
    signal power_sum_0 : power_array:=(others=>(others=>'0')); --partial power integration (samples 0-3)
    signal power_sum_1 : power_array:=(others=>(others=>'0')); --partial power integration (samples 4-7)
    signal power_sum_2 : power_array:=(others=>(others=>'0')); --partial power integration (samples 8-11)
    signal power_sum_3 : power_array:=(others=>(others=>'0')); --partial power integration (samples 12-15)
    signal power_sum_4 : power_array:=(others=>(others=>'0')); --partial power integration (samples 16-19)
    signal power_sum_5 : power_array:=(others=>(others=>'0')); --partial power integration (samples 20-23)
    signal power_sum_6 : power_array:=(others=>(others=>'0')); --partial power integration (samples 24-27)
    signal power_sum_7 : power_array:=(others=>(others=>'0')); --partial power integration (samples 28-31)
    signal power_sum_8 : power_array:=(others=>(others=>'0')); --partial power integration (samples 32-35)
    signal power_sum_9 : power_array:=(others=>(others=>'0')); --partial power integration (samples 36-39)
    signal power_sum_10 : power_array:=(others=>(others=>'0')); --partial power integration (samples 40-43)
    signal power_sum_11 : power_array:=(others=>(others=>'0')); --partial power integration (samples 44-47)
    signal power_sum_12 : power_array:=(others=>(others=>'0')); --partial power integration (samples 48-51)

    type bigger_power_array is array (NUM_BEAMS-1 downto 0) of unsigned(19 downto 0);

    signal running_sum_a: bigger_power_array:=(others=>(others=>'0'));
    signal running_sum_b : bigger_power_array:=(others=>(others=>'0'));
    signal running_sum_c : bigger_power_array:=(others=>(others=>'0'));
    signal running_sum_d : bigger_power_array:=(others=>(others=>'0'));


    --signal power_sum_a : bigger_power_array:=(others=>(others=>'0')); --partial power integration (zero offset)
    --signal power_sum_b : bigger_power_array:=(others=>(others=>'0')); --partial power integration (zero offset)

    --add two more overlap to having a single sample sliding window. seems to be better
    type avg_power_array is array (NUM_BEAMS-1 downto 0, NUM_POWERS-1 downto 0) of unsigned(15 downto 0);
    signal avg_power: avg_power_array:=(others=>(others=>(others=>'0'))); --average power (power_sum shifted down)

    component power_lut_8 is --8 bit lut for calculating power
    port(
            clk_i   : in std_logic;
            a       : in	std_logic_vector(7 downto 0);
            z       : out	unsigned(15 downto 0));
    end component;
begin


assign_beam_i: for bm in 0 to NUM_BEAMS-1 generate
    assign_sams_i: for sam in 0 to NUM_SAMPLES*INTERP_FACTOR-1 generate
        phased_beam_waves(bm,sam)<= signed(beam_data_i(bm*NUM_SAMPLES*INTERP_FACTOR*SAMPLE_LENGTH+SAMPLE_LENGTH*(sam+1)-1 downto bm*NUM_SAMPLES*INTERP_FACTOR*SAMPLE_LENGTH+SAMPLE_LENGTH*sam));
    end generate;
end generate;

assign_power_o: for bm in 0 to NUM_BEAMS-1 generate
    assign_powers_o: for pow in 0 to NUM_POWERS-1 generate
        power_o(POWER_LENGTH*NUM_POWERS*bm+POWER_LENGTH*(pow+1)-1 downto POWER_LENGTH*NUM_POWERS*bm+POWER_LENGTH*pow) <= std_logic_vector(avg_power(bm,pow));
    end generate;

    --power_o(2*16*bm+16-1 downto 2*16*bm) <= std_logic_vector(avg_power(bm,0));
    --power_o(2*16*bm+32-1 downto 2*16*bm+16) <= std_logic_vector(avg_power(bm,1));
    --power_o(4*14*bm+42-1 downto 4*14*bm+28) <= (others=>'0'); -- std_logic_vector(avg_power2(bm));
    --power_o(4*14*bm+56-1 downto 4*14*bm+42) <= (others=>'0'); -- std_logic_vector(avg_power3(bm));
end generate;


--calculate the power
--this just uses a LUT in logic to find the power from a signed value. 8 bits synth as bram, 7 bits as norm luts

DO_POWER_BEAM : for i in 0 to NUM_BEAMS-1 generate
    DO_POWER_SAMPLE : for j in 0 to NUM_SAMPLES*INTERP_FACTOR-1 generate --for j in 0 to phased_sum_length-1 generate
        xPOWERLUT : power_lut_8
        port map(
        clk_i => clk_data_i,
        a => std_logic_vector(phased_beam_waves(i,j)),
        z => phased_power(i,j));
    end generate;
end generate;


/*
proc_move_power:process(clk_data_i, enable_i)
begin
    if rising_edge(clk_data_i) and enable_i='1' then
    --sample_o<=std_logic_vector(phased_beam_waves(0,0));

        for i in 0 to NUM_BEAMS-1 loop --loop over beams
            for j in 0 to NUM_SAMPLES*INTERP_FACTOR-1 loop --for j in 16 to phased_sum_length-1 loop
                --phased_power(i,j)<=unsigned(phased_beam_waves(i,j)*phased_beam_waves(i,j)); --for mult
                --phased_power(i,j+NUM_SAMPLES*INTERP_FACTOR)<=phased_power(i,j); --for power sum >16 but not factor of 2
            end loop;
        end loop;

    end if;
end process;
*/

--block to do the power integration
proc_avg_beam_power : process(rst_i, clk_data_i, enable_i)
begin		

    if rst_i = '1' or enable_i = '0' then
        power_sum_0 <= (others=>(others=>'0'));
        power_sum_1 <= (others=>(others=>'0'));
        power_sum_2 <= (others=>(others=>'0'));
        power_sum_3 <= (others=>(others=>'0'));
        power_sum_4 <= (others=>(others=>'0'));
        power_sum_5 <= (others=>(others=>'0'));
        power_sum_6 <= (others=>(others=>'0'));
        power_sum_7 <= (others=>(others=>'0'));
        power_sum_8 <= (others=>(others=>'0'));
        power_sum_10 <= (others=>(others=>'0'));
        power_sum_11 <= (others=>(others=>'0'));
        power_sum_12 <= (others=>(others=>'0'));

        --power_sum_a <= (others=>(others=>'0'));
        --power_sum_b <= (others=>(others=>'0'));
        --power_sum_11 <= (others=>(others=>'0'));
        --power_sum_12 <= (others=>(others=>'0'));
        --power_sum_13 <= (others=>(others=>'0'));

        running_sum_a <= (others=>(others=>'0'));
        running_sum_b <= (others=>(others=>'0'));
        running_sum_c <= (others=>(others=>'0'));
        running_sum_d <= (others=>(others=>'0'));


        --avg_power0 <= (others=>(others=>'0'));
        --avg_power1 <= (others=>(others=>'0'));
        --avg_power2 <= (others=>(others=>'0'));
        --avg_power3 <= (others=>(others=>'0'));

        avg_power <= (others=>(others=>(others=>'0')));
    elsif rising_edge(clk_data_i) and (enable_i='1') then
        for i in 0 to NUM_BEAMS-1 loop


            -- create sliding window of 4 samples (at 2GHz = 2ns step) TODO: refactor for timing, num samples = 4 interp factor = 2
            power_sum_0(i)<=resize(phased_power(i,0),num_power_bits)+resize(phased_power(i,1),num_power_bits)+resize(phased_power(i,2),num_power_bits)+resize(phased_power(i,3),num_power_bits);
            power_sum_1(i)<=resize(phased_power(i,4),num_power_bits)+resize(phased_power(i,5),num_power_bits)+resize(phased_power(i,6),num_power_bits)+resize(phased_power(i,7),num_power_bits);
            
            if NUM_SAMPLES*INTERP_FACTOR = 16 then
                power_sum_2(i)<=resize(phased_power(i,8),num_power_bits)+resize(phased_power(i,9),num_power_bits)+resize(phased_power(i,10),num_power_bits)+resize(phased_power(i,11),num_power_bits);
                power_sum_3(i)<=resize(phased_power(i,12),num_power_bits)+resize(phased_power(i,13),num_power_bits)+resize(phased_power(i,14),num_power_bits)+resize(phased_power(i,15),num_power_bits);
            else
                power_sum_2(i) <= power_sum_0(i);
                power_sum_3(i) <= power_sum_1(i);
            end if;
            -- num_samples=8 and interp_factor=2
            --power_sum_2(i)<=resize(phased_power(i,8),num_power_bits)+resize(phased_power(i,9),num_power_bits)+resize(phased_power(i,10),num_power_bits)+resize(phased_power(i,11),num_power_bits);
            --power_sum_3(i)<=resize(phased_power(i,12),num_power_bits)+resize(phased_power(i,13),num_power_bits)+resize(phased_power(i,14),num_power_bits)+resize(phased_power(i,15),num_power_bits);

            
            --power_sum_2(i)<=resize(phased_power(i,4),num_power_bits)+resize(phased_power(i,5),num_power_bits);
            --power_sum_3(i)<=resize(phased_power(i,6),num_power_bits)+resize(phased_power(i,7),num_power_bits);

            --shift smaller sums along

            power_sum_4(i) <= power_sum_2(i);
            power_sum_5(i) <= power_sum_3(i);
            power_sum_6(i) <= power_sum_4(i);
            power_sum_7(i) <= power_sum_5(i);
            power_sum_8(i) <= power_sum_6(i);
            power_sum_9(i) <= power_sum_7(i);
            power_sum_10(i) <= power_sum_8(i);
            power_sum_11(i) <= power_sum_9(i);
            power_sum_12(i) <= power_sum_10(i);

            running_sum_a(i) <= running_sum_a(i) + power_sum_0(i) + power_sum_1(i) - power_sum_8(i) - power_sum_9(i);
            running_sum_b(i) <= running_sum_b(i) + power_sum_1(i) + power_sum_2(i) - power_sum_9(i) - power_sum_10(i);


            --add together powers in the 32 samples (at 2GHz = 16 ns integration windows) TODO: refactor for timing
            --power_sum_a(i)<=resize(power_sum_0(i),20)+power_sum_1(i)+power_sum_2(i)+power_sum_3(i)+power_sum_4(i)+power_sum_5(i)+power_sum_6(i)+power_sum_7(i);
            --power_sum_b(i)<=resize(power_sum_1(i),20)+power_sum_2(i)+power_sum_3(i)+power_sum_4(i)+power_sum_5(i)+power_sum_6(i)+power_sum_7(i)+power_sum_8(i);

            --power_sum_12(i)<=resize(power_sum_2(i),20)+power_sum_3(i)+power_sum_4(i)+power_sum_5(i);
            --power_sum_13(i)<=resize(power_sum_3(i),20)+power_sum_4(i)+power_sum_5(i)+power_sum_6(i);


            if (running_sum_a(i)(4 downto 0))>=x"10" then
                avg_power(i,0)<=resize(unsigned(running_sum_a(i)(running_sum_a(0)'length-1 downto 5)),avg_power(0,0)'length)+1;
            else
                avg_power(i,0)<=resize(unsigned(running_sum_a(i)(running_sum_a(0)'length-1 downto 5)),avg_power(0,0)'length);
            end if;

            if (running_sum_b(i)(4 downto 0))>=x"10" then
                avg_power(i,1)<=resize(unsigned(running_sum_b(i)(running_sum_b(0)'length-1 downto 5)),avg_power(0,0)'length)+1;
            else
                avg_power(i,1)<=resize(unsigned(running_sum_b(i)(running_sum_b(0)'length-1 downto 5)),avg_power(0,0)'length);
            end if;


            if NUM_POWERS = 4 then
                running_sum_c(i) <= running_sum_c(i) + power_sum_2(i) + power_sum_3(i) - power_sum_10(i) - power_sum_11(i);
                running_sum_d(i) <= running_sum_d(i) + power_sum_3(i) + power_sum_4(i) - power_sum_11(i) - power_sum_12(i);


                if (running_sum_c(i)(4 downto 0))>=x"10" then
                    avg_power(i,2)<=resize(unsigned(running_sum_c(i)(running_sum_c(0)'length-1 downto 5)),avg_power(0,0)'length)+1;
                else
                    avg_power(i,2)<=resize(unsigned(running_sum_c(i)(running_sum_c(0)'length-1 downto 5)),avg_power(0,0)'length);
                end if;

                if (running_sum_d(i)(4 downto 0))>=x"10" then
                    avg_power(i,3)<=resize(unsigned(running_sum_d(i)(running_sum_d(0)'length-1 downto 5)),avg_power(0,0)'length)+1;
                else
                    avg_power(i,3)<=resize(unsigned(running_sum_d(i)(running_sum_d(0)'length-1 downto 5)),avg_power(0,0)'length);
                end if;
            end if;

        end loop;
    end if;
end process;


end rtl;