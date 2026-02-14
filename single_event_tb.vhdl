library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
--use ieee.std_logic_textio.all;

use work.defs.all;
use work.all;

entity single_event_tb is
end single_event_tb;

architecture behave of single_event_tb is
-----------------------------------------------------------------------------
-- Declare the Component Under Test
-----------------------------------------------------------------------------
component single_event is
    generic(
        SAMPLE_LENGTH : integer := 8; -- n bit samples
        NUM_SAMPLES : integer := 4; -- samples per clock
        ADDR_DEPTH : integer := 9 --2^9 - 1 deep ram
    );
    port(
        rst_i : in std_logic;
        wr_clk_i : in std_logic;
        wr_en_i : in std_logic; -- to enable waveform writing and meta data storage
        clear_i : in std_logic; -- to clear the contents of the event in order to restart data collection
        soft_reset_i :in std_logic; -- may be be duplicate functionality to clear_i?
        waveform_data_i : in std_logic_vector(NUM_CHANNELS*NUM_SAMPLES*SAMPLE_LENGTH -1 downto 0);

        run_number_i : in std_logic_vector(15 downto 0);
        event_number_i : in std_logic_vector(23 downto 0);

        pps_clk_i : std_logic;
        event_timing_enable_i : in std_logic;
        pps_count_i : in std_logic_vector(31 downto 0);
        clk_count_i : in std_logic_vector(31 downto 0);
        clk_on_last_pps_i : in std_logic_vector(31 downto 0);
        clk_on_last_last_pps_i : in std_logic_vector(31 downto 0);
        
        pps_trig_i : in std_logic; -- pps trig from pps holdoff
        rf_trig_0_i : in std_logic;
        rf_trig_0_meta_i: in std_logic_vector(NUM_CHANNELS-1 downto 0);
        rf_trig_1_i : in std_logic;
        rf_trig_1_meta_i: in std_logic_vector(NUM_CHANNELS-1 downto 0);
        pa_trig_i : in std_logic;
        pa_trig_meta_i: in std_logic_vector(NUM_BEAMS-1 downto 0);
        soft_trig_i : in std_logic;
        ext_trig_i : in std_logic;

        -- data ready signal output to higher up event handler. which should look like a big mux between event storage modules
        data_ready_o : out std_logic; --same as data written

        --read side clock and enable
        rd_clk_i : in std_logic;
        rd_en_i : in std_logic;
        rd_address_i : in std_logic_vector(15 downto 0);

        rd_manual_i : in std_logic;
        rd_channel_i : in std_logic_vector(4 downto 0);
        rd_block_i : in std_logic_vector(8 downto 0);

        -- register sized data out
        read_done_o : std_logic;
        data_valid_o : out std_logic;
        data_o : out std_logic_vector(31 downto 0);
        data_ready_rd_clk_o : out std_logic -- cdc using data ready o?

    );
end component;

-----------------------------------------------------------------------------
-- Testbench Internal Signals
-----------------------------------------------------------------------------
signal clock : std_logic := '1';
signal clock_counter : unsigned(31 downto 0) := (others=>'0');

signal rst : std_logic := '0';
signal soft_reset : std_logic := '0';
signal clear : std_logic := '0';

signal wr_enable: std_logic := '0';
signal trigger : std_logic := '0';
signal samples_in : std_logic_vector(NUM_CHANNELS*NUM_SAMPLES*SAMPLE_LENGTH-1 downto 0) := (others=>'0');
type waveform_t is array(NUM_CHANNELS-1 downto 0) of unsigned(31 downto 0);
signal int_samples : waveform_t := (others=>(others=>'0'));

signal rf_trig_0 : std_logic := '0';
signal rf_trig_1 : std_logic := '0';
signal pa_trig : std_logic := '0';
signal soft_trig : std_logic := '0';
signal pps_trig : std_logic := '0';
signal ext_trig : std_logic := '0';

signal rf_trig_0_meta : std_logic_vector(NUM_CHANNELS-1 downto 0) := (others=>'0');
signal rf_trig_1_meta : std_logic_vector(NUM_CHANNELS-1 downto 0) := (others=>'0');
signal pa_trig_meta : std_logic_vector(NUM_BEAMS-1 downto 0) := (others=>'0');

signal pps : std_logic := '0'; -- prob going to be unused given time scale
signal pps_counter : std_logic_vector(31 downto 0) := (others=>'0');
signal clk_on_last_pps : std_logic_vector(31 downto 0):= (others=>'0');
signal clk_on_last_last_pps : std_logic_vector(31 downto 0):= (others=>'0');

signal run_number : std_logic_vector(15 downto 0);
signal event_number : std_logic_vector(23 downto 0);


--constant wait_clks : std_logic_vector(9 downto 0) := "0000001000";
constant wait_clks : std_logic_vector(9 downto 0) := "0000000001";

type post_trig_t is array(NUM_CHANNELS-1 downto 0) of std_logic_vector(9 downto 0);
signal post_trigger_wait_clks : post_trig_t := (others=>wait_clks);
signal send_post_trigger_wait_clks : std_logic_vector(NUM_CHANNELS*10-1 downto 0) := (others=>'0');

signal wr_clk_rd_done : std_logic := '0';
signal ram_enable : std_logic := '0';
signal wr_finished : std_logic := '0';

signal slow_clock : std_logic := '1';
signal read_enable : std_logic := '0';
signal read_address : std_logic_vector(15 downto 0) := (others=>'0');

signal read_manual : std_logic := '0';
signal read_channel : std_logic_vector(4 downto 0) := (others=>'0');
signal read_block : std_logic_vector(8 downto 0) := (others=>'0');
signal read_valid : std_logic := '0';
signal samples_out: std_logic_vector(NUM_SAMPLES*SAMPLE_LENGTH-1 downto 0) := (others=>'0');
signal read_done : std_logic := '0';
signal read_ready : std_logic := '0';

signal read_start : unsigned(31 downto 0) := (others=>'0');
signal read_counter : unsigned(13 downto 0) := (others=> '0');

--signal wait_rd_counter : unsigned(31 downto 0) := x"00000200";
signal wait_rd_counter : unsigned(31 downto 0) := x"00000007";
signal test : std_logic_vector(31 downto 0) := (others=>'0');
constant where_trigger : integer := 600;
signal do_loop : std_logic := '1';

begin
    clock <= not clock after 2 ns;
    slow_clock <= clock; -- same clock between wr and read for now
    -----------------------------------------------------------------------------
    -- Instantiate and Map UUT
    -----------------------------------------------------------------------------
    waveform_inst : single_event
    port map(
        rst_i => rst,
        wr_clk_i => clock,
        wr_en_i => wr_enable,
        clear_i => clear,
        soft_reset_i => soft_reset,
        waveform_data_i => samples_in,
        
        run_number_i => run_number,
        event_number_i => event_number,
        
        pps_clk_i => clock,
        event_timing_enable_i => '1',
        clk_count_i => std_logic_vector(clock_counter),
        pps_count_i => pps_counter,
        clk_on_last_pps_i => clk_on_last_pps,
        clk_on_last_last_pps_i => clk_on_last_last_pps,
        
        pps_trig_i => pps_trig,
        rf_trig_0_i => rf_trig_0,
        rf_trig_0_meta_i => rf_trig_0_meta,
        rf_trig_1_i => rf_trig_1,
        rf_trig_1_meta_i => rf_trig_1_meta,
        pa_trig_i => pa_trig,
        pa_trig_meta_i => pa_trig_meta,
        soft_trig_i => soft_trig,
        ext_trig_i => ext_trig,

        data_ready_o => wr_finished,

        rd_clk_i => clock,
        rd_en_i => read_enable,
        rd_address_i => read_address,
        
        rd_manual_i => read_manual,
        rd_channel_i => read_channel,
        rd_block_i => read_block,

        read_done_o => read_done,
        data_valid_o => read_valid,
        data_o => samples_out,
        data_ready_rd_clk_o => read_ready
        );

    map_sig : for i in 0 to NUM_CHANNELS-1 generate
        samples_in((i+1)*NUM_SAMPLES*SAMPLE_LENGTH-1 downto i*NUM_SAMPLES*SAMPLE_LENGTH) <= std_logic_vector(int_samples(i));
        --send_post_trigger_wait_clks((i+1)*9-1 downto i*9) <= wait_clks; --std_logic_vector(post_trigger_wait_clks(i));
    end generate;
    

    process

        --variable v_ILINE     : line;
        variable v_OLINE     : line;
        variable v_SPACE     : character;

        --file file_INPUT : text;-- open read_mode is "input_waveforms.txt";
        --file file_THRESHOLDS : text;-- open read_mode is "input_thresholds.txt";
        --file file_TRIGGERS : text;-- open write_mode is "output_trigger.txt";

        file file_output : text;


        begin

            file_open(file_output, "data/single_event_tb.txt", write_mode);

            while do_loop loop
                wait for 4 ns;

--updsatteeeeeeeeeeeeeeeeee ssssssssssttttttttttttttkiiiiiiiiiiiiiiiimmmmmmmmmmmmmmmm
                for i in 0 to NUM_CHANNELS-1 loop
                    if i =0 then
                        int_samples(i)<=clock_counter;
                    elsif i =1 then
                        int_samples(i) <= clock_counter + 256*4;
                    end if;
                end loop;

                if clock_counter >20 then
                    --wr_enable <= '1';
                    if wr_finished = '1' then
                        wr_enable <='0';
                    else
                        wr_enable <= '1';
                    end if;
                end if;

                if clock_counter = where_trigger then
                    trigger <= '1';
                else
                    trigger <= '0';
                end if;

                if read_counter >= 512*24-1 then
                    read_enable <= '0';
                elsif clock_counter > 1000 and wr_finished='1' then
                    read_enable <= '1';
                else
                    read_enable <= '0'; -- need something to off read enable and then pulse wr_clk_rd_done
                end if;

                if read_enable = '1' then
                    read_counter <= read_counter + 1;
                    read_block <= std_logic_vector(unsigned(read_block) + 1);
                    if read_counter < 511 then
                        read_channel <= "00000";
                    elsif read_counter < 1023 then
                        read_channel <= "00001";
                    else
                        read_channel <= "00010";
                    end if;
                else
                    read_block <= (others=>'0');
                    read_channel <= (others=>'0');

                end if;

                --io files
                --file_open(file_INPUT, "data/input_waveforms.txt", read_mode);
                --file_open(file_THRESHOLDS, "data/input_channel_thresholds.txt", read_mode);
                --file_open(file_TRIGGERS, "data/output_trigger.txt", write_mode);

                
                clock_counter <= clock_counter +1;


                --write(v_OLINE,ch_samples(31 downto 0),right,32);
                --writeline(output,v_OLINE);

                write(v_OLINE,clock_counter,right,32);
                write(v_OLINE,' ');

                write(v_OLINE,wr_enable,right,1);
                write(v_OLINE,' ');

                write(v_OLINE,trigger,right,1);
                write(v_OLINE, ' ');

                write(v_OLINE,wr_finished,right,1);
                write(v_OLINE, ' ');

                write(v_OLINE,read_enable,right,1);
                write(v_OLINE, ' ');

                write(v_OLINE,read_channel,right,5);
                write(v_OLINE, ' ');

                write(v_OLINE,read_block,right,9);
                write(v_OLINE, ' ');

                write(v_OLINE,read_valid,right,1);
                write(v_OLINE, ' ');

                write(v_OLINE,samples_out,right,32);
                write(v_OLINE, ' ');

                write(v_OLINE,test,right,32);
                write(v_OLINE, ' ');

                writeline(file_output,v_OLINE);

                --write(v_OLINE,trig,right,1);
                --writeline(file_TRIGGERS, v_OLINE);

            end loop;

            file_close(file_output);

            wait;

        end process;

end behave;