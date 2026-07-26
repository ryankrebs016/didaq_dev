-- taken from the flower pa trig, which did 472MHz->1888MHz upsampling, x4
-- for the didaq, we can resuse the filter since its cutoff should be f_s/8, sampling rate from 1000MHZ to 2000MHz so cutoff of 250MHz
-- it does the double duty of low passing the high f image produced from zero stuffing
-- and low-passing the final bandwidth to 250MHz for trigger performance
library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.defs.all;


entity upsampling is
    generic(
		SAMPLE_LENGTH   : integer := 8;
		NUM_SAMPLES     : integer := 4;
		NUM_PA_CHANNELS : integer := 4;
		INTERP_FACTOR   : integer := 2);
    port(
            rst_i       : in std_logic;
            clk_data_i  : in std_logic;
            enable_i    : in std_logic;
            ch_data_i   : in std_logic_vector(SAMPLE_LENGTH*NUM_SAMPLES*NUM_PA_CHANNELS -1 downto 0);
            ch_data_o   : out std_logic_vector(SAMPLE_LENGTH*NUM_SAMPLES*NUM_PA_CHANNELS*INTERP_FACTOR -1 downto 0)
            );
    end upsampling;
    
architecture rtl of upsampling is

    constant upsample_filter_length: integer:=37;
    type upsample_coeffs_t is array (upsample_filter_length-1 downto 0) of integer range -128 to 127;
    constant upsample_coeffs: upsample_coeffs_t:=(1, 1, 0, -1, -2, -2, 0, 3, 5, 4, 0, -6, -11, -10, 0, 
                                                    18, 40, 57, 64, 57, 40, 18, 0, -10, -11, -6, 0, 4,
                                                    5, 3, 0, -2, -2, -1, 0, 1, 1);
    --*256
    --2,6,10,14,22,26.30,34 are zero

    --short streaming buffer
    type streaming_data_array is array(NUM_PA_CHANNELS-1 downto 0, NUM_SAMPLES-1 downto 0) of signed(SAMPLE_LENGTH-1 downto 0);
    signal streaming_data : streaming_data_array := (others=>(others=>(others=>'0'))); --pipeline data

    --buffer to store the interpolated sample for being pulled when doing the beamforming / summation
    type interpolated_data_array is array(NUM_PA_CHANNELS-1 downto 0, NUM_SAMPLES*INTERP_FACTOR-1 downto 0) of signed(SAMPLE_LENGTH-1 downto 0);
    signal interp_data: interpolated_data_array:= (others=>(others=>(others=>'0')));

    type padded_t is array(NUM_PA_CHANNELS-1 downto 0, NUM_SAMPLES*INTERP_FACTOR-1+upsample_filter_length downto 0) of signed(SAMPLE_LENGTH-1 downto 0);
    signal padded_sig: padded_t:=(others=>(others=>(others=>'0')));

    type fir_temp is array(14 downto 0, NUM_PA_CHANNELS-1 downto 0, NUM_SAMPLES*INTERP_FACTOR+upsample_filter_length-1 downto 0) of signed(2*SAMPLE_LENGTH-1 downto 0);
    signal int_up: fir_temp:=(others=>(others=>(others=>(others=>'0'))));

    type fir_temp_big is array(NUM_PA_CHANNELS-1 downto 0, NUM_SAMPLES*INTERP_FACTOR-1 downto 0) of signed(2*SAMPLE_LENGTH-1 downto 0);
    signal int_up_final: fir_temp_big := (others=>(others=>(others=>'0')));
    signal int_up_first: fir_temp_big := (others=>(others=>(others=>'0')));
    signal int_up_second: fir_temp_big := (others=>(others=>(others=>'0')));
    signal int_up_third: fir_temp_big := (others=>(others=>(others=>'0')));

    -- for generality these are the same sizes, but could be optimized on a per coefficient basis since coefficients are 
    -- either close (near the center coeff so less delay needed when reused) or far (early coeff so need to wait a longer time to be used)
    signal int_up_1: fir_temp_big := (others=>(others=>(others=>'0')));
    signal int_up_m1: fir_temp_big := (others=>(others=>(others=>'0')));
    signal int_up_m2: fir_temp_big := (others=>(others=>(others=>'0')));
    signal int_up_3: fir_temp_big := (others=>(others=>(others=>'0')));
    signal int_up_5: fir_temp_big := (others=>(others=>(others=>'0')));
    signal int_up_4: fir_temp_big := (others=>(others=>(others=>'0')));
    signal int_up_m6: fir_temp_big := (others=>(others=>(others=>'0')));
    signal int_up_m11: fir_temp_big := (others=>(others=>(others=>'0')));
    signal int_up_m10: fir_temp_big := (others=>(others=>(others=>'0')));
    signal int_up_18: fir_temp_big := (others=>(others=>(others=>'0')));
    signal int_up_40: fir_temp_big := (others=>(others=>(others=>'0')));
    signal int_up_57: fir_temp_big := (others=>(others=>(others=>'0')));

begin

    --assign inputs
    assign_channels_in: for ch in 0 to NUM_PA_CHANNELS-1 generate
        assign_samples: for sam in 0 to NUM_SAMPLES-1 generate
            streaming_data(ch,sam)<=signed(ch_data_i(SAMPLE_LENGTH*(sam+1)+ch*NUM_SAMPLES*SAMPLE_LENGTH-1 downto ch*NUM_SAMPLES*SAMPLE_LENGTH+8*sam));
        end generate;
    end generate;

    --assign ouputs
    assign_channels_out: for ch in 0 to NUM_PA_CHANNELS-1 generate
        assign_samples_o: for sam in 0 to NUM_SAMPLES*INTERP_FACTOR-1 generate
            ch_data_o(SAMPLE_LENGTH*(sam+1)+ch*SAMPLE_LENGTH*NUM_SAMPLES*INTERP_FACTOR-1 
                      downto ch*SAMPLE_LENGTH*NUM_SAMPLES*INTERP_FACTOR+SAMPLE_LENGTH*sam)
                      <= std_logic_vector(interp_data(ch,sam));
        end generate;
    end generate;

    -- do the upsampling
    proc_upsample_by_hand:process(clk_data_i, rst_i, enable_i)
    begin
        for ch in 0 to NUM_PA_CHANNELS-1 loop
            -- assign the real sample values
            for sam in 0 to NUM_SAMPLES-1 loop
                    -- real samples are located at multiples of INTERP_FACTOR, others default to 0 and are never assigned
                    padded_sig(ch,INTERP_FACTOR*sam) <= streaming_data(ch,sam);
            end loop;
        end loop;

        if rising_edge(clk_data_i) and (enable_i='1')then
            for  ch in 0 to NUM_PA_CHANNELS-1 loop
                for sam in 0 to NUM_SAMPLES*INTERP_FACTOR-1 loop

                    --convolve with filter in parts, bit shifts and adds
                    ---2,6,10,14,22,26.30,34 zero
                    if (sam mod 2) = 0 then
                        -- even + even = even -> real sample
                        int_up(0,ch,sam) <= resize(padded_sig(ch,0+sam),2*SAMPLE_LENGTH); -- c0
                        int_up(3,ch,sam) <= - (resize(padded_sig(ch,4+sam),2*SAMPLE_LENGTH-1)&'0'); -- c4
                        int_up(6,ch,sam) <= (resize(padded_sig(ch,8+sam),2*SAMPLE_LENGTH-2)&"00") + padded_sig(ch,8+sam); -- c8
                        int_up(9,ch,sam) <= - (resize(padded_sig(ch,12+sam),2*SAMPLE_LENGTH-4)&"0000") + (resize(padded_sig(ch,12+sam),2*SAMPLE_LENGTH-2)&"00") + padded_sig(ch,12+sam); -- c12
                        int_up(12,ch,sam) <= (resize(padded_sig(ch,16+sam),2*SAMPLE_LENGTH-5)&"00000")+(resize(padded_sig(ch,16+sam),2*SAMPLE_LENGTH-3)&"000"); -- 16
                        int_up(14,ch,sam) <= (resize(padded_sig(ch,18+sam),2*SAMPLE_LENGTH-6)&"000000"); -- c18

                        -- even + odd = odd -> zero sample
                        int_up(1,ch,sam) <= (others=>'0');
                        int_up(2,ch,sam) <= (others=>'0');
                        int_up(4,ch,sam) <= (others=>'0');
                        int_up(5,ch,sam) <= (others=>'0');
                        int_up(7,ch,sam) <= (others=>'0');
                        int_up(8,ch,sam) <= (others=>'0');
                        int_up(10,ch,sam) <= (others=>'0');
                        int_up(11,ch,sam) <= (others=>'0');
                        int_up(13,ch,sam) <= (others=>'0');

                    else
                        -- odd + odd = even -> real sample

                        int_up(1,ch,sam) <= resize(padded_sig(ch,1+sam),2*SAMPLE_LENGTH); -- c1
                        int_up(2,ch,sam) <= - resize(padded_sig(ch,3+sam),2*SAMPLE_LENGTH);-- c3
                        int_up(4,ch,sam) <= -(resize(padded_sig(ch,5+sam),2*SAMPLE_LENGTH-1)&"0"); -- c5
                        int_up(5,ch,sam) <= (resize(padded_sig(ch,7+sam),2*SAMPLE_LENGTH-1)&'0') + padded_sig(ch,7+sam); -- c7
                        int_up(7,ch,sam) <= (resize(padded_sig(ch,9+sam),2*SAMPLE_LENGTH-2)&"00"); -- c9
                        int_up(8,ch,sam) <= - (resize(padded_sig(ch,11+sam),2*SAMPLE_LENGTH-2)&"00") - (resize(padded_sig(ch,11+sam),2*SAMPLE_LENGTH-1)&'0'); -- c11
                        int_up(10,ch,sam) <= - (resize(padded_sig(ch,13+sam),2*SAMPLE_LENGTH-3)&"000") - (resize(padded_sig(ch,13+sam),2*SAMPLE_LENGTH-1)&'0'); -- c13
                        int_up(11,ch,sam) <= (resize(padded_sig(ch,15+sam),2*SAMPLE_LENGTH-4)&"0000") + (resize(padded_sig(ch,15+sam),2*SAMPLE_LENGTH-2)&"00"); -- c15
                        int_up(13,ch,sam) <= (resize(padded_sig(ch,17+sam),2*SAMPLE_LENGTH-6)&"000000") - (resize(padded_sig(ch,17+sam),2*SAMPLE_LENGTH-3)&"000") + padded_sig(ch,17+sam); -- c17

                        -- odd + even = off => zero sample
                        int_up(0,ch,sam) <= (others=>'0');
                        int_up(3,ch,sam) <= (others=>'0');
                        int_up(6,ch,sam) <= (others=>'0');
                        int_up(9,ch,sam) <= (others=>'0');
                        int_up(12,ch,sam) <= (others=>'0');
                        int_up(14,ch,sam) <= (others=>'0');

                    end if;

                    -- polyphase
                    int_up_1(ch,sam) <= int_up(0,ch,sam) + int_up(0,ch,sam+1) + int_up(0,ch,sam+36) + int_up(0,ch,sam+35);
                    int_up_m1(ch,sam) <= int_up(2,ch,sam) + int_up(2,ch,sam+30);
                    int_up_m2(ch,sam) <= int_up(3,ch,sam) + int_up(3,ch,sam+1) + int_up(3,ch,sam+27) + int_up(3,ch,sam+28);
                    int_up_3(ch,sam) <= int_up(5,ch,sam) +int_up(5,ch,sam+22);
                    int_up_5(ch,sam) <=  int_up(6,ch,sam) + int_up(6,ch,sam+20);
                    int_up_4(ch,sam) <= int_up(7,ch,sam) + int_up(7,ch,sam+18);
                    int_up_m6(ch,sam) <= int_up(8,ch,sam) + int_up(8,ch,sam+14);
                    int_up_m11(ch,sam) <= int_up(9,ch,sam) + int_up(9,ch,sam+12);
                    int_up_m10(ch,sam) <= int_up(10,ch,sam) + int_up(10,ch,sam+10);
                    int_up_18(ch,sam) <= int_up(11,ch,sam) + int_up(11,ch,sam+6);
                    int_up_40(ch,sam) <= int_up(12,ch,sam) + int_up(12,ch,sam+4);
                    int_up_57(ch,sam) <= int_up(13,ch,sam) + int_up(13,ch,sam+2) + int_up(14,ch,sam); --throw 64 here


                    --sum parts first stage
                    int_up_first(ch,sam) <= int_up_1(ch,sam) + int_up_m1(ch,sam) + int_up_m2(ch,sam) + int_up_3(ch,sam) + int_up_5(ch,sam) + int_up_4(ch,sam);
                    int_up_second(ch,sam) <= int_up_m6(ch,sam) + int_up_m11(ch,sam) + int_up_m10(ch,sam) + int_up_18(ch,sam) + int_up_40(ch,sam) + int_up_57(ch,sam);

                    --sum parts second stage
                    int_up_final(ch,sam)<=int_up_first(ch,sam) + int_up_second(ch,sam);

                    --do division (bit shifting) with rounding
                    if unsigned(int_up_final(ch,sam)(5 downto 0)) > x"20" then
                        interp_data(ch,sam) <= resize( signed(int_up_final(ch,sam)(2*SAMPLE_LENGTH-1 downto 6)) , SAMPLE_LENGTH) + 1;
                    elsif unsigned(int_up_final(ch,sam)(5 downto 0)) = x"20" and int_up_final(ch,sam)(6) = '0' then
                        interp_data(ch,sam) <= resize( signed(int_up_final(ch,sam)(2*SAMPLE_LENGTH-1 downto 6)) , SAMPLE_LENGTH);
                    elsif unsigned(int_up_final(ch,sam)(5 downto 0)) = x"20" and int_up_final(ch,sam)(6) = '1' then
                        interp_data(ch,sam) <= resize( signed(int_up_final(ch,sam)(2*SAMPLE_LENGTH-1 downto 6)) , SAMPLE_LENGTH) + 1;
                    else --unsigned(int_up(ch,sam)(5 downto 0))<x"20" then
                        interp_data(ch,sam) <= resize( signed(int_up_final(ch,sam)(2*SAMPLE_LENGTH-1 downto 6)) , SAMPLE_LENGTH);

                    end if;
                end loop;

                --shift padded sig for future clock cycles
                for j in NUM_SAMPLES*INTERP_FACTOR to NUM_SAMPLES*INTERP_FACTOR+upsample_filter_length-1 loop
                    padded_sig(ch,j)<=padded_sig(ch,j-NUM_SAMPLES*INTERP_FACTOR);

                    for fil in 0 to 14 loop
                        int_up(fil,ch,j) <= int_up(fil,ch,j-NUM_SAMPLES*INTERP_FACTOR);
                    end loop;
                end loop;

            end loop;
        end if;
    end process;
end rtl;