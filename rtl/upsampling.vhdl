-- taken from the flower pa trig, which did 472MHz->1888MHz upsampling, x4
-- for the didaq, we can resuse the filter since its cutoff should be f_s/8, sampling rate from 1000MHZ to 2000MHz so cutoff of 250MHz
-- it does the double duty of low passing the high f image produced from zero stuffing
-- and low-passing the final bandwidth to 250MHz for trigger performance
library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.defs.all;

entity upsampling is
    generic();
    
    port(
            rst_i       : in std_logic;
            clk_data_i  : in std_logic;
            enable      : in std_logic;
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
    type streaming_data_array is array(3 downto 0, 3 downto 0) of signed(7 downto 0);
    signal streaming_data : streaming_data_array := (others=>(others=>(others=>'0'))); --pipeline data

    --buffer to store the interpolated sample for being pulled when doing the beamforming / summation
    type interpolated_data_array is array(3 downto 0, NUM_SAMPLES*INTERP_FACTOR-1 downto 0) of signed(7 downto 0);
    signal interp_data: interpolated_data_array:= (others=>(others=>(others=>'0')));

    type padded_t is array(3 downto 0, NUM_SAMPLES*INTERP_FACTOR-1+upsample_filter_length downto 0) of signed(7 downto 0);
    signal padded_sig: padded_t:=(others=>(others=>x"00"));

    type fir_temp is array(3 downto 0, NUM_SAMPLES*INTERP_FACTOR-1 downto 0) of signed(15 downto 0);
    signal int_up0: fir_temp:=(others=>(others=>x"0000"));
    signal int_up1: fir_temp:=(others=>(others=>x"0000"));
    signal int_up2: fir_temp:=(others=>(others=>x"0000"));
    signal int_up3: fir_temp:=(others=>(others=>x"0000"));
    signal int_up4: fir_temp:=(others=>(others=>x"0000"));
    signal int_up5: fir_temp:=(others=>(others=>x"0000"));
    signal int_up6: fir_temp:=(others=>(others=>x"0000"));
    signal int_up7: fir_temp:=(others=>(others=>x"0000"));
    signal int_up8: fir_temp:=(others=>(others=>x"0000"));
    signal int_up9: fir_temp:=(others=>(others=>x"0000"));
    signal int_up10: fir_temp:=(others=>(others=>x"0000"));
    signal int_up11: fir_temp:=(others=>(others=>x"0000"));
    signal int_up12: fir_temp:=(others=>(others=>x"0000"));
    signal int_up13: fir_temp:=(others=>(others=>x"0000"));
    signal int_up14: fir_temp:=(others=>(others=>x"0000"));
    signal int_up15: fir_temp:=(others=>(others=>x"0000"));

    type fir_temp_big is array(3 downto 0, NUM_SAMPLES*INTERP_FACTOR-1 downto 0) of signed(15 downto 0);
    signal int_up: fir_temp_big:=(others=>(others=>x"0000"));
    signal int_up_first: fir_temp_big:=(others=>(others=>x"0000"));
    signal int_up_second: fir_temp_big:=(others=>(others=>x"0000"));

begin

    --assign inputs
    assign_channels_in: for ch in 0 to 3 generate
        assign_samples: for sam in 0 to NUM_SAMPLES-1 generate
            streaming_data(ch,sam)<=signed(ch_data_i(SAMPLE_LENGTH*(sam+1)+ch*NUM_SAMPLES*SAMPLE_LENGTH-1 downto ch*NUM_SAMPLES*SAMPLE_LENGTH+8*sam));
        end generate;
    end generate;

    --assign ouputs
    assign_channels_out: for ch in 0 to 3 generate
        assign_samples_o: for sam in 0 to NUM_SAMPLES*INTERP_FACTOR-1 generate
            ch_data_o(SAMPLE_LENGTH*(sam+1)+ch*SAMPLE_LENGTH*NUM_SAMPLES*INTERP_FACTOR-1 downto ch*SAMPLE_LENGTH*NUM_SAMPLES*INTERP_FACTOR+8*sam)<=std_logic_vector(interp_data(ch,sam));
        end generate;
    end generate;

    -- do the upsampling
    proc_upsample_by_hand:process(clk_data_i, rst_i, enable)
    begin
        for ch in 0 to 3 loop
            -- assign the real sample values
            padded_sig(ch,0)<=streaming_data(ch,0);
            padded_sig(ch,2)<=streaming_data(ch,1);
            padded_sig(ch,4)<=streaming_data(ch,2);
            padded_sig(ch,6)<=streaming_data(ch,3);

            -- explicitely assign zeros (default to 0 and are never updated, but good to be clear)
            padded_sig(ch,1) <= (others=>'0');
            padded_sig(ch,3) <= (others=>'0');
            padded_sig(ch,5) <= (others=>'0');
            padded_sig(ch,7) <= (others=>'0');

        end loop;

        if rising_edge(clk_data_i) and (enable='1')then
            for  ch in 0 to 3 loop
                for sam in 0 to NUM_SAMPLES*INTERP_FACTOR-1 loop

                    --convolve with filter in parts
                    ---2,6,10,14,22,26.30,34 zero
                    int_up0(ch,sam)<=upsample_coeffs(0)*padded_sig(ch,0+sam)+upsample_coeffs(1)*padded_sig(ch,1+sam);
                    int_up1(ch,sam)<=upsample_coeffs(3)*padded_sig(ch,3+sam)+upsample_coeffs(4)*padded_sig(ch,4+sam);
                    int_up2(ch,sam)<=upsample_coeffs(5)*padded_sig(ch,5+sam)+upsample_coeffs(7)*padded_sig(ch,7+sam);
                    int_up3(ch,sam)<=upsample_coeffs(8)*padded_sig(ch,8+sam)+upsample_coeffs(9)*padded_sig(ch,9+sam);
                    int_up4(ch,sam)<=upsample_coeffs(11)*padded_sig(ch,11+sam)+upsample_coeffs(12)*padded_sig(ch,12+sam);
                    int_up5(ch,sam)<=upsample_coeffs(13)*padded_sig(ch,13+sam)+upsample_coeffs(15)*padded_sig(ch,15+sam);
                    int_up6(ch,sam)<=upsample_coeffs(16)*padded_sig(ch,16+sam)+upsample_coeffs(17)*padded_sig(ch,17+sam);
                    int_up7(ch,sam)<=upsample_coeffs(18)*padded_sig(ch,18+sam)+upsample_coeffs(19)*padded_sig(ch,19+sam);
                    int_up8(ch,sam)<=upsample_coeffs(20)*padded_sig(ch,20+sam)+upsample_coeffs(21)*padded_sig(ch,21+sam);
                    int_up9(ch,sam)<=upsample_coeffs(23)*padded_sig(ch,23+sam)+upsample_coeffs(24)*padded_sig(ch,24+sam);
                    int_up10(ch,sam)<=upsample_coeffs(25)*padded_sig(ch,25+sam)+upsample_coeffs(27)*padded_sig(ch,27+sam);
                    int_up11(ch,sam)<=upsample_coeffs(28)*padded_sig(ch,28+sam)+upsample_coeffs(29)*padded_sig(ch,29+sam);
                    int_up12(ch,sam)<=upsample_coeffs(31)*padded_sig(ch,31+sam)+upsample_coeffs(32)*padded_sig(ch,32+sam);
                    int_up13(ch,sam)<=upsample_coeffs(33)*padded_sig(ch,33+sam)+upsample_coeffs(35)*padded_sig(ch,35+sam);
                    int_up14(ch,sam)<=upsample_coeffs(36)*padded_sig(ch,36+sam);

                    --sum parts first stage
                    int_up_first(ch,sam)<=int_up0(ch,sam)+int_up1(ch,sam)+int_up2(ch,sam)+int_up3(ch,sam)+int_up4(ch,sam)+int_up5(ch,sam)+int_up6(ch,sam);
                    int_up_second(ch,sam)<=int_up7(ch,sam)+int_up8(ch,sam)+int_up9(ch,sam)+int_up10(ch,sam)+int_up11(ch,sam)+int_up12(ch,sam)+int_up13(ch,sam)+int_up14(ch,sam);

                    --sum parts second stage
                    int_up(ch,sam)<=int_up_first(ch,sam)+int_up_second(ch,sam);

                    --do division (bit shifting) with rounding
                    if unsigned(int_up(ch,sam)(5 downto 0)) > x"20" then
                        interp_data(ch,sam)<=resize(signed(int_up(ch,sam)(15 downto 6)),8)+1;
                    elsif unsigned(int_up(ch,sam)(5 downto 0)) = x"20" and int_up(ch,sam)(6) = '0' then
                        interp_data(ch,sam)<=resize(signed(int_up(ch,sam)(15 downto 6)),8);
                    elsif unsigned(int_up(ch,sam)(5 downto 0)) = x"20" and int_up(ch,sam)(6) = '1' then
                        interp_data(ch,sam)<=resize(signed(int_up(ch,sam)(15 downto 6)),8) + 1;
                    else --unsigned(int_up(ch,sam)(5 downto 0))<x"20" then
                        interp_data(ch,sam)<=resize(signed(int_up(ch,sam)(15 downto 6)),8);

                    end if;
                end loop;

                --shift padded sig for future clock cycles
                for j in NUM_SAMPLES*INTERP_FACTOR to NUM_SAMPLES*INTERP_FACTOR+upsample_filter_length-1 loop
                    padded_sig(ch,j)<=padded_sig(ch,j-NUM_SAMPLES*INTERP_FACTOR);
                end loop;

            end loop;
        end if;
    end process;
end rtl;