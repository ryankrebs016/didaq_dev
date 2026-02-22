library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
--use ieee.std_logic_textio.all;

use work.defs.all;
use work.all;

entity waveform_tb is
end waveform_tb;

architecture behave of waveform_tb is
-----------------------------------------------------------------------------
-- Declare the Component Under Test
-----------------------------------------------------------------------------
component waveform_storage is
    generic(
        SAMPLE_LENGTH : integer := 8; -- n bit samples
        NUM_SAMPLES : integer := 4; -- samples per clock
        ADDR_DEPTH : integer := 9 --2^9 - 1 deep ram
    );
    port(
        rst_i : in std_logic;

        -- write clocked stuff
        wr_clk_i    : in std_logic; -- write data clock
        wr_en_i     : in std_logic; --write enable, de assert when rd_en_i is high and de assert after trigger_i is high
        trigger_i   : in std_logic; -- trigger pulse for post trigger sample holdoff
        data_i      : in std_logic_vector(NUM_CHANNELS*NUM_SAMPLES*SAMPLE_LENGTH-1 downto 0); -- input data 24channels*4samples*8/9bits
        post_trigger_wait_clks_i : in std_logic_vector(NUM_CHANNELS*10-1 downto 0); -- configurable, trigger dependent, post trigger hold off
        wr_clk_rd_done_i : in std_logic;
        soft_reset_i : std_logic;
        wr_finished_o   : out std_logic; --write finished signal from dma or read control higher up

        --read clocked stuff
        rd_clk_i        : in std_logic; -- rd clock, doesn't have to be wr_clk
        rd_en_i         : in std_logic; -- rd enable to know when to pass samples out
        rd_channel_i    : in std_logic_vector(4 downto 0); -- same time as rd_en_i
        rd_block_i      : in std_logic_vector(8 downto 0); -- same time as rd_en_i

        rd_data_valid_o : out std_logic; -- data valid signal
        data_o          : out std_logic_vector(NUM_SAMPLES*SAMPLE_LENGTH-1 downto 0) -- output data 32 bits to match reg size, may need update with 9 bits
        --test : out std_logic_vector(31 downto 0)
    );
end component;

-----------------------------------------------------------------------------
-- Testbench Internal Signals
-----------------------------------------------------------------------------
signal clock : std_logic := '1';
signal clock_counter : unsigned(31 downto 0) := (others=>'0');

signal rst : std_logic := '0';
signal soft_reset : std_logic := '0';

signal wr_enable: std_logic := '0';
signal trigger : std_logic := '0';
signal samples_in : std_logic_vector(NUM_CHANNELS*NUM_SAMPLES*SAMPLE_LENGTH-1 downto 0) := (others=>'0');
type waveform_t is array(NUM_CHANNELS-1 downto 0) of unsigned(31 downto 0);
signal int_samples : waveform_t := (others=>(others=>'0'));

--constant wait_clks : std_logic_vector(9 downto 0) := "0000001000";
constant wait_clks : std_logic_vector(9 downto 0) := "0000000000";

type post_trig_t is array(NUM_CHANNELS-1 downto 0) of std_logic_vector(9 downto 0);
signal post_trigger_wait_clks : post_trig_t := (others=>wait_clks);
signal send_post_trigger_wait_clks : std_logic_vector(NUM_CHANNELS*10-1 downto 0) := (others=>'0');

signal wr_clk_rd_done : std_logic := '0';
signal ram_enable : std_logic := '0';
signal wr_finished : std_logic := '0';

signal slow_clock : std_logic := '1';
signal read_enable : std_logic := '0';
signal read_channel : std_logic_vector (4 downto 0) := (others=>'0');
signal read_block : std_logic_vector (8 downto 0) := (others=>'0');
signal read_valid : std_logic := '0';
signal samples_out: std_logic_vector(NUM_SAMPLES*SAMPLE_LENGTH-1 downto 0) := (others=>'0');

signal read_start : unsigned(31 downto 0) := (others=>'0');
signal read_counter : unsigned(13 downto 0) := (others=> '0');

--signal wait_rd_counter : unsigned(31 downto 0) := x"00000200";
signal wait_rd_counter : unsigned(31 downto 0) := x"00000007";
signal test : std_logic_vector(31 downto 0) := (others=>'0');
constant where_trigger : integer := 600;
signal do_loop : std_logic := '1';

constant header : string := "clk wr_enable trigger wr_finished read_enable read_channel read_block read_valid samples";

begin
    clock <= not clock after 2 ns;
    slow_clock <= clock; -- same clock between wr and read for now
    -----------------------------------------------------------------------------
    -- Instantiate and Map UUT
    -----------------------------------------------------------------------------
    waveform_inst : waveform_storage
    port map(
        rst_i => rst,

        wr_clk_i => clock,
        wr_en_i => wr_enable,
        trigger_i => trigger,
        soft_reset_i => soft_reset,
        data_i => samples_in,
        post_trigger_wait_clks_i => send_post_trigger_wait_clks,
        wr_clk_rd_done_i => wr_clk_rd_done,
        wr_finished_o => wr_finished,

        rd_clk_i => clock,
        rd_en_i => read_enable,
        rd_channel_i => read_channel,
        rd_block_i => read_block,
        rd_data_valid_o => read_valid,
        data_o => samples_out
        --test => test
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

            file_open(file_output, "data/waveform_tb.txt", write_mode);

            write(v_OLINE,header, right, header'length);
            writeline(file_output,v_OLINE);
            while do_loop loop
                wait for 4 ns;


                for i in 0 to NUM_CHANNELS-1 loop
                    int_samples(i) <= clock_counter + i*256*4;
                    --if i =0 then
                    --    int_samples(i)<=clock_counter;
                    --elsif i =1 then
                    --    int_samples(i) <= clock_counter + 256*4;
                    --end if;
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
                elsif clock_counter > 4000 then
                    read_enable <= '0';
                    soft_reset <= '1';
                elsif clock_counter > 1000 and wr_finished='1' then
                    read_enable <= '1';
                else
                    read_enable <= '0'; -- need something to off read enable and then pulse wr_clk_rd_done
                end if;

                -- in single event I just need to queue up the first samples of channel 0 early and then the rest should be ok
                if wr_finished and not read_enable then
                    read_channel <= "00000";
                    read_block <= (others=>'0');
                elsif read_enable = '1' then
                    read_counter <= read_counter + 1;
                    read_block <= std_logic_vector(unsigned(read_block) + 1);
                    if unsigned(read_block) = 511 then
                        read_channel <= std_logic_vector(unsigned(read_channel)+1);
                    end if;
                    
                else
                    --read_block <= (others=>'0');
                    --read_channel <= (others=>'0');

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

                writeline(file_output,v_OLINE);

                --write(v_OLINE,trig,right,1);
                --writeline(file_TRIGGERS, v_OLINE);

            end loop;

            file_close(file_output);

            wait;

        end process;

end behave;