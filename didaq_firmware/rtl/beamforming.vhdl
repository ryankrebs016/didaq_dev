library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.defs.all;

entity beamforming is
    generic(
            ENABLE_PHASED_TRIG : std_logic := '1';
            station_number_i : in std_logic_vector(7 downto 0)
            );
    
    port(
            rst_i : in std_logic:='0';
            clk_data_i : in	std_logic:='0'; --data clock
            enable : in std_logic:='0';
            ch_data_i : in std_logic_vector(NUM_PA_CHANNELS*NUM_SAMPLES*SAMPLE_LENGTH-1 downto 0):=(others=>'0');
            beam_data_o : out std_logic_vector(NUM_BEAMS*NUM_SAMPLES*SAMPLE_LENGTH-1 downto 0):=(others=>'0')
            );
    end beamforming;
    
architecture rtl of beamforming is

constant interp_data_length: integer := 64; -- atleast 16 larger than highest delay
constant baseline: unsigned(7 downto 0) := x"80";
constant phased_sum_bits: integer := 8; --8. trying 7 bit lut
constant phased_sum_length: integer := NUM_SAMPLES;
constant num_stations: integer:=8;

--buffer to store the interpolated sample for being pulled when doing the beamforming / summation
type interpolated_data_array is array(NUM_PA_CHANNELS-1 downto 0, interp_data_length-1 downto 0) of signed(SAMPLE_LENGTH-1 downto 0);
signal interp_data: interpolated_data_array:= (others=>(others=>(others=>'0')));

--temp buffer to calculate coherent sum waveforms to check for saturation
type phased_arr_buff is array (NUM_BEAMS-1 downto 0,phased_sum_length-1 downto 0) of signed(9 downto 0);-- range 0 to 2**phased_sum_bits-1; --phased sum... log2(16*8)=7bits
signal phased_beam_waves_buff: phased_arr_buff:= (others=>(others=>"0000000000"));

--7 bit limited coherent sum for power LUT
type phased_arr is array (NUM_BEAMS-1 downto 0, phased_sum_length-1 downto 0) of signed(phased_sum_bits-1 downto 0);-- range 0 to 2**phased_sum_bits-1; --phased sum... log2(16*8)=7bits
signal phased_beam_waves: phased_arr:= (others=>(others=>(others=>'0')));

type antenna_delays is array (num_stations-1 downto 0, NUM_BEAMS-1 downto 0, NUM_PA_CHANNELS-1 downto 0) of integer range 0 to 127;
--12 beams equally spaced between -60 and 60 generated with make_beams.py


function convert_station_to_index(number:std_logic_vector)
    return integer is
    begin
        if number = x"0b" then return 0;
        elsif number = x"0c" then return 1;
        elsif number = x"0d" then return 2;
        elsif number = x"0e" then return 3;
        elsif number = x"15" then return 4;
        elsif number = x"16" then return 5;
        elsif number = x"17" then return 6;
        elsif number = x"18" then return 7;
        else return -1;
        end if;
    end function;

constant station_index: integer :=convert_station_to_index(station_number_i);
--station indexed in this order = [24 (7 ind), 23, 22, 21, 14, 13, 12, 11 (0 ind)]
--beams 11 to 0 w/ beam 11 pointing down, and 0 pointing up

--v0p18
--using db detector with group delays. the lab-measured signal chain keeps the cal pulser at most within 0.5ns when comparing to measured events
--beam delays for all stations will be station 11 delays =>  ie firmware will be tagged with 11 but used on XX
constant beam_delays: antenna_delays :=
    (((0,0,0,1),(2,1,0,0),(5,3,1,0),(7,5,2,0),(10,7,3,0),(13,9,4,0),(16,11,5,0),(19,12,6,0),(21,14,7,0),(24,16,8,0),(27,18,9,0),(30,20,10,0)),
    ((0,1,1,1),(2,2,1,0),(5,3,2,0),(7,5,2,0),(10,7,3,0),(13,9,4,0),(16,11,5,0),(18,13,6,0),(21,14,7,0),(24,16,8,0),(27,18,9,0),(29,20,10,0)),
    ((0,1,1,1),(2,2,1,0),(5,4,1,0),(7,5,2,0),(10,7,3,0),(13,9,4,0),(16,11,5,0),(18,13,6,0),(21,15,7,0),(24,16,8,0),(27,18,9,0),(29,20,10,0)),
    ((0,1,1,1),(2,2,0,0),(4,4,1,0),(7,5,2,0),(10,7,3,0),(13,9,4,0),(16,11,5,0),(18,13,6,0),(21,15,7,0),(24,17,8,0),(27,18,9,0),(29,20,10,0)),
    ((0,0,0,1),(2,1,0,0),(5,3,1,0),(7,5,2,0),(10,7,3,0),(13,9,4,0),(16,10,5,0),(19,12,6,0),(22,14,7,0),(24,16,8,0),(27,18,9,0),(30,20,9,0)),
    ((0,1,1,1),(2,2,0,0),(4,3,1,0),(7,5,2,0),(10,7,3,0),(13,9,4,0),(16,11,5,0),(18,13,6,0),(21,14,7,0),(24,16,8,0),(27,18,9,0),(30,20,10,0)),
    ((0,1,2,1),(2,2,2,0),(5,4,3,0),(7,6,4,0),(10,7,5,0),(13,9,6,0),(16,11,7,0),(18,13,7,0),(21,15,8,0),(24,16,9,0),(26,18,10,0),(29,20,11,0)),
    ((0,1,1,1),(1,1,0,0),(4,3,1,0),(7,5,2,0),(10,7,3,0),(13,9,4,0),(15,11,5,0),(18,13,6,0),(21,14,7,0),(24,16,8,0),(27,18,9,0),(30,20,10,0)));

begin

    proc_pipeline_data: process(clk_data_i,enable)
    begin
            if rst_i = '1' or enable='0' then
                for ch in 0 to NUM_PA_CHANNELS-1 loop
                        for sam in 0 to interp_data_length-1 loop
                            interp_data(ch,sam) <= x"00";
                    end loop;
                end loop;

            elsif rising_edge(clk_data_i) then
                    for ch in 0 to NUM_PA_CHANNELS-1 loop
                            -- recieve new samples
                            for sam in 0 to NUM_SAMPLES-1 loop
                                    interp_data(ch,sam)<=signed(ch_data_i(ch*NUM_SAMPLES*SAMPLE_LENGTH+(sam+1)*SAMPLE_LENGTH-1 downto ch*NUM_SAMPLES*SAMPLE_LENGTH+sam*SAMPLE_LENGTH));
                            end loop;
                            -- shift sample along buffer
                            for sam in NUM_SAMPLES to interp_data_length-1 loop
                                    interp_data(ch,sam)<=interp_data(ch,sam-NUM_SAMPLES);
                            end loop;
                    end loop;
            end if;
    end process;

    --do phasing to calculate the coherently summed waveforms
    proc_phasing: process(clk_data_i,enable)
    begin

        for i in 0 to NUM_BEAMS-1 loop --loop over beams
            for j in 0 to NUM_SAMPLES-1 loop
            
                --async add then clock saturation. adjustable station specific delays - keeping in case
                --phased_beam_waves_buff(i,j)<=resize(interp_data(0,beam_delays(STATION_INDEX,i,0)+(j)+to_integer(specific_dels(i,0))),10)
                --+resize(interp_data(1,beam_delays(STATION_INDEX,i,1)+(j)+to_integer(specific_dels(i,1))),10)
                --+resize(interp_data(2,beam_delays(STATION_INDEX,i,2)+(j)+to_integer(specific_dels(i,2))),10)
                --+resize(interp_data(3,beam_delays(STATION_INDEX,i,3)+(j)+to_integer(specific_dels(i,3))),10);

                phased_beam_waves_buff(i,j)<=resize(interp_data(0,beam_delays(station_index,i,0)+(j)),10)
                                            +resize(interp_data(1,beam_delays(station_index,i,1)+(j)),10)
                                            +resize(interp_data(2,beam_delays(station_index,i,2)+(j)),10)
                                            +resize(interp_data(3,beam_delays(station_index,i,3)+(j)),10);

                if rst_i ='1' or enable='0' then
                    phased_beam_waves(i,j) <= x"00";

                elsif rising_edge(clk_data_i) then 

                    --saturate low and high for 8 bit LUT. max=2^(8-1)-1, min=-2^(8-1), might be able to go up in bit length with simple threshold instead of power
                    if((phased_beam_waves_buff(i,j))>127) then
                        phased_beam_waves(i,j)<=b"01111111";--saturate max
                    elsif((phased_beam_waves_buff(i,j))<-128) then
                        phased_beam_waves(i,j)<=b"10000000"; --saturate min
                    else
                        phased_beam_waves(i,j)<=resize(phased_beam_waves_buff(i,j),8);
                    end if;

                end if;
            end loop;
        end loop;
    end process;

    assign_beams_o: for bm in 0 to NUM_BEAMS-1 generate
            assign_samples_o: for sam in 0 to NUM_SAMPLES-1 generate
                    beam_data_o(bm*NUM_SAMPLES*SAMPLE_LENGTH+(sam+1)*SAMPLE_LENGTH-1 downto bm*NUM_SAMPLES*SAMPLE_LENGTH+sam*SAMPLE_LENGTH)<=std_logic_vector(phased_beam_waves(bm,sam));
            end generate;
    end generate;

end rtl;