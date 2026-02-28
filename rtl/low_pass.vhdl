-- half-band low pass filter. 500MHz -> 250MHz for PA trigger if no upsampling
-- coefficients generated with scipy with float->int rescaling of 256

library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.defs.all;

entity low_pass_filter is
    generic();
    
    port(
            rst_i			:	in	    std_logic;
            clk_data_i	    :   in	    std_logic;
            enable          :   in      std_logic;
            ch_data_i       :   in      std_logic_vector(NUM_PA_CHANNELS*NUM_SAMPLES*SAMPLE_LENGTH -1 downto 0);
            ch_data_o       :   out     std_logic_vector(NUM_PA_CHANNELS*NUM_SAMPLES*SAMPLE_LENGTH -1 downto 0)
            );
    end low_pass_filter;
    
architecture rtl of low_pass_filter is

    constant low_pass_filter_length: integer:=27;
    type low_pass_coeffs_t is array (low_pass_filter_length-1 downto 0) of integer range -128 to 127;
    constant low_pass_coeffs: low_pass_coeffs_t:=(1,  -0,  -2,   0,   4,  -0,  -7,   0,  13,  -0, -25,   0,
                                                    81, 128,  81,   0, -25,  -0,  13,   0,  -7,  -0,   4,   0,  -2,  -0, 1, ); --cutoff at f_s/2

    -- short streaming buffer
    type streaming_data_array is array(NUM_PA_CHANNELS-1 downto 0, 35 downto 0) of signed(SAMPLE_LENGTH-1 downto 0);
    signal streaming_data : streaming_data_array := (others=>(others=>(others=>'0'))); --pipeline data

    -- buffer to store the interpolated sample for being pulled when doing the beamforming / summation
    -- ignore the interp naming here. it's just a temp array
    type interpolated_data_array is array(NUM_PA_CHANNELS downto 0, NUM_SAMPLES-1 downto 0) of signed(7 downto 0);
    signal interp_data: interpolated_data_array:= (others=>(others=>(others=>'0')));

    type fir_temp is array(NUM_PA_CHANNELS downto 0, NUM_SAMPLES-1 downto 0) of signed(15 downto 0);
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

    type fir_temp_big is array(NUM_PA_CHANNELS downto 0, NUM_SAMPLES-1 downto 0) of signed(15 downto 0);
    signal int_up: fir_temp_big:=(others=>(others=>x"0000"));
    signal int_up_first: fir_temp_big:=(others=>(others=>x"0000"));
    signal int_up_second: fir_temp_big:=(others=>(others=>x"0000"));

begin

    --assign inputs
    assign_channels_in: for ch in 0 to NUM_PA_CHANNELS-1 generate
        assign_samples: for sam in 0 to NUM_SAMPLES-1 generate
            streaming_data(ch,sam)<=signed(ch_data_i(SAMPLE_LENGTH*(sam+1)+ch*NUM_SAMPLES*SAMPLE_LENGTH-1 downto ch*NUM_SAMPLES*SAMPLE_LENGTH+SAMPLE_LENGTH*sam));
        end generate;
    end generate;

    --assign ouputs
    assign_channels_out: for ch in 0 to NUM_PA_CHANNELS-1 generate
        assign_samples_o: for sam in 0 to NUM_SAMPLES-1 generate
            ch_data_o(8*(sam+1)+ch*NUM_SAMPLES*SAMPLE_LENGTH-1 downto ch*NUM_SAMPLES*SAMPLE_LENGTH+8*sam)<=std_logic_vector(interp_data(ch,sam));
        end generate;
    end generate;

    -- do the upsampling
    proc_upsample_by_hand:process(clk_data_i, rst_i, enable)
    begin
        if rst_i = '1' then
            streaming_data <= (others=>(others=>'0'));
            int_up0 <= (others=>(others=>'0'));
            int_up1 <= (others=>(others='0'>));
            int_up2 <= (others=>(others=>'0'));
            int_up3 <= (others=>(others=>'0'));
            int_up4 <= (others=>(others=>'0'));
            int_up5 <= (others=>(others=>'0'));
            int_up6 <= (others=>(others=>'0'));
            int_up7 <= (others=>(others=>'0'));
            int_up8 <= (others=>(others=>'0'));
            int_up9 <= (others=>(others=>'0'));
            int_up10 <= (others=>(others=>'0'));
            int_up11 <= (others=>(others=>'0'));
            int_up12 <= (others=>(others=>'0'));
            int_up13 <= (others=>(others=>'0'));
            int_up14 <= (others=>(others=>'0'));
            int_up15 <= (others=>(others=>'0'));

            int_up_first <= (others=>(others=>'0'));
            int_up_second <= (others=>(others=>'0'));
            int_up <= (others=>(others=>'0'));
            interp_data <= (others=>(others=>'0'))

        elsif rising_edge(clk_data_i) and (enable='1')then
            for ch in 0 to 3 loop

                --shift sig for full filter mult
                for j in 4 to 35 loop
                    streaming_data(ch,j)<=streaming_data(ch,j-4);
                end loop;

                -- first stage mutl and add. including the 0 coefficients bc lazy. this could be optimized by removing those, and 
                -- having the multiplactions be bit shifts and add. most coefficients are 2^n +/- c with small c. 
                for sam in 0 to NUM_SAMPLES-1 loop
                    int_up0(ch,sam)<=upsample_coeffs(0)*streaming_data(ch,0+sam)+upsample_coeffs(1)*streaming_data(ch,1+sam);
                    int_up1(ch,sam)<=upsample_coeffs(2)*streaming_data(ch,2+sam)+upsample_coeffs(3)*streaming_data(ch,3+sam);
                    int_up2(ch,sam)<=upsample_coeffs(4)*streaming_data(ch,4+sam)+upsample_coeffs(5)*streaming_data(ch,5+sam);
                    int_up3(ch,sam)<=upsample_coeffs(6)*streaming_data(ch,6+sam)+upsample_coeffs(7)*streaming_data(ch,7+sam);
                    int_up4(ch,sam)<=upsample_coeffs(8)*streaming_data(ch,8+sam)+upsample_coeffs(9)*streaming_data(ch,9+sam);
                    int_up5(ch,sam)<=upsample_coeffs(10)*streaming_data(ch,10+sam)+upsample_coeffs(11)*streaming_data(ch,11+sam);
                    int_up6(ch,sam)<=upsample_coeffs(12)*streaming_data(ch,12+sam)+upsample_coeffs(13)*streaming_data(ch,13+sam);
                    int_up7(ch,sam)<=upsample_coeffs(14)*streaming_data(ch,14+sam)+upsample_coeffs(15)*streaming_data(ch,15+sam);
                    int_up8(ch,sam)<=upsample_coeffs(16)*streaming_data(ch,16+sam)+upsample_coeffs(17)*streaming_data(ch,17+sam);
                    int_up9(ch,sam)<=upsample_coeffs(18)*streaming_data(ch,18+sam)+upsample_coeffs(19)*streaming_data(ch,19+sam);
                    int_up10(ch,sam)<=upsample_coeffs(20)*streaming_data(ch,20+sam)+upsample_coeffs(21)*streaming_data(ch,21+sam);
                    int_up11(ch,sam)<=upsample_coeffs(22)*streaming_data(ch,22+sam)+upsample_coeffs(23)*streaming_data(ch,23+sam);
                    int_up12(ch,sam)<=upsample_coeffs(24)*streaming_data(ch,24+sam)+upsample_coeffs(25)*streaming_data(ch,25+sam);
                    int_up12(ch,sam)<=upsample_coeffs(26)*streaming_data(ch,26+sam)+upsample_coeffs(27)*streaming_data(ch,27+sam);
                    int_up14(ch,sam)<=upsample_coeffs(28)*streaming_data(ch,28+sam)+upsample_coeffs(29)*streaming_data(ch,29+sam);
                    int_up15(ch,sam)<=upsample_coeffs(30)*streaming_data(ch,30+sam)+upsample_coeffs(31)*streaming_data(ch,31+sam);

                    --second stage add, adjust to meet timing on didaq clock. worked on flower at 118.
                    int_up_first(ch,sam)<=int_up0(ch,sam)+int_up1(ch,sam)+int_up2(ch,sam)+int_up3(ch,sam)+int_up4(ch,sam)+int_up5(ch,sam)+int_up6(ch,sam)+int_up7(ch,sam);
                    int_up_second(ch,sam)<=int_up8(ch,sam)+int_up9(ch,sam)+int_up10(ch,sam)+int_up11(ch,sam)+int_up12(ch,sam)+int_up13(ch,sam)+int_up14(ch,sam)+int_up15(ch,sam);

                    --final third stage add
                    int_up(ch,sam)<=int_up_first(ch,sam)+int_up_second(ch,sam);

                    --do division (bit shifting) to remove x256 scaling on coefficients and do rounding on the output
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
            end loop;
        end if;
    end process;
end rtl;