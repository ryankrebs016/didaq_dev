library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
--use ieee.std_logic_textio.all;

use work.defs.all;
use work.all;

entity event_top_tb is
end event_top_tb;

architecture behave of event_top_tb is
-----------------------------------------------------------------------------
-- Declare the Component Under Test
-----------------------------------------------------------------------------
component event_top is
    generic(
        SAMPLE_LENGTH : integer := 8; -- n bit samples
        NUM_SAMPLES : integer := 4; -- samples per clock
        ADDR_DEPTH : integer := 9; --2^9 - 1 deep ram
        NUM_EVENTS : integer := 2 -- 2^num_events

    );
    port(
        rst_i : in std_logic;

        -- write clocked stuff, data and triggers
        wr_clk_i    : in std_logic; -- write data clock
        data_i      : in std_logic_vector(NUM_CHANNELS*NUM_SAMPLES*SAMPLE_LENGTH-1 downto 0); -- input data 24channels*4samples*8/9bits

        wr_enable_i : in std_logic; -- from reg
        soft_reset_i : in std_logic; -- from regs

        rf_trig_0_i : in std_logic;
        rf_trig_0_meta_i: in std_logic_vector(NUM_CHANNELS-1 downto 0);

        rf_trig_1_i : in std_logic;
        rf_trig_1_meta_i: in std_logic_vector(NUM_CHANNELS-1 downto 0);

        pa_trig_i : in std_logic;
        pa_trig_meta_i: in std_logic_vector(NUM_BEAMS-1 downto 0);

        soft_trig_i : in std_logic;
        ext_trig_i : in std_logic; -- raw ext trigger, needs sync chain

        -- to gpio
        event_ready_o : out std_logic; -- if any read ready signals

        -- from pps block, might be on different clock so may need cdc's to data clock
        pps_clk_i : in std_logic; -- if on diff clock
        pps_i : in std_logic; -- single clock wide pps pulse, not raw
        do_pps_trig_i : in std_logic; -- from regs

        -- read side clock. things are either manual which go through registers
        -- or with automatic event control which reads out 1 event at a time with a 
        -- pop data signal
        rd_clk_i : in std_logic;
        rd_pulse_i : in std_logic; -- single pulse from reg block, not a reg

        rd_manual_i : in std_logic; -- from regs
        rd_channel_i : in std_logic_vector(4 downto 0); -- from regs
        rd_block_i : in std_logic_vector(8 downto 0); -- from regs
    
        -- register sized data out
        data_valid_o : out std_logic;
        data_o : out std_logic_vector(31 downto 0);
        data_ready_rd_clk_o : out std_logic; -- cdc using data ready o?
        
        -- debug things
        wr_pointer_o : out std_logic_vector(NUM_EVENTS-1 downto 0);
        wr_busy_o : out std_logic_vector(NUM_EVENTS-1 downto 0);
        wr_done_o : out std_logic_vector(NUM_EVENTS-1 downto 0);

        rd_pointer_o : out std_logic_vector(NUM_EVENTS-1 downto 0);
        rd_lock_o : out std_logic

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

signal any_trig : std_logic := '0';
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
signal do_pps_trig : std_logic := '0';

signal run_number : std_logic_vector(15 downto 0) := x"0001";
signal event_number : std_logic_vector(23 downto 0) := x"000002";
signal event_ready : std_logic := '0';

--constant wait_clks : std_logic_vector(9 downto 0) := "0000001000";
constant wait_clks : std_logic_vector(9 downto 0) := "0000000100";

type post_trig_t is array(NUM_CHANNELS-1 downto 0) of std_logic_vector(9 downto 0);
signal post_trigger_wait_clks : post_trig_t := (others=>wait_clks);
signal send_post_trigger_wait_clks : std_logic_vector(NUM_CHANNELS*10-1 downto 0) := (others=>'0');

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
signal read_counter : unsigned(15 downto 0) := (others=> '0');
signal current_read_address : std_logic_vector(15 downto 0) := (others=>'0');
--signal wait_rd_counter : unsigned(31 downto 0) := x"00000200";
signal wait_rd_counter : unsigned(31 downto 0) := x"00000007";
signal test : std_logic_vector(31 downto 0) := (others=>'0');
constant where_trigger : integer := 600;
signal do_loop : std_logic := '1';
constant header : string :=  "clk_counter wr_enable";

signal wr_pointer : std_logic_vector(NUM_EVENTS-1 downto 0) := (others=>'0');
signal wr_busy : std_logic_vector(NUM_EVENTS-1 downto 0) := (others=>'0');
signal wr_done : std_logic_vector(NUM_EVENTS-1 downto 0) := (others=>'0');
signal rd_pointer : std_logic_vector(NUM_EVENTS-1 downto 0) := (others=>'0');
signal rd_lock : std_logic := '0';
begin
    clock <= not clock after 2 ns;
    slow_clock <= clock; -- same clock between wr and read for now
    -----------------------------------------------------------------------------
    -- Instantiate and Map UUT
    -----------------------------------------------------------------------------
    waveform_inst : event_top
    port map(
        rst_i => rst,
        wr_clk_i => clock,
        data_i => samples_in,

        wr_enable_i => wr_enable,
        soft_reset_i => soft_reset,

        rf_trig_0_i => rf_trig_0,
        rf_trig_0_meta_i => rf_trig_0_meta,
        rf_trig_1_i => rf_trig_1,
        rf_trig_1_meta_i => rf_trig_1_meta,
        pa_trig_i => pa_trig,
        pa_trig_meta_i => pa_trig_meta,
        soft_trig_i => soft_trig,
        ext_trig_i => ext_trig,

        event_ready_o => event_ready,

        pps_clk_i => clock,
        pps_i => pps,
        do_pps_trig_i => pps_trig,

        rd_clk_i => clock,
        rd_pulse_i => read_enable,
        
        rd_manual_i => read_manual,
        rd_channel_i => read_channel,
        rd_block_i => read_block,

        data_valid_o => read_valid,
        data_o => samples_out,
        data_ready_rd_clk_o => read_ready,

        wr_pointer_o => wr_pointer,
        wr_busy_o => wr_busy,
        wr_done_o => wr_done,

        rd_pointer_o => rd_pointer,
        rd_lock_o => rd_lock

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

            file_open(file_output, "data/event_top_tb.txt", write_mode);

        
            write(v_OLINE,header, right, header'length);
            writeline(file_output,v_OLINE);

            while do_loop loop
                wait for 4 ns;

                clock_counter <= clock_counter + 1;
                for i in 0 to NUM_CHANNELS-1 loop
                    int_samples(i) <= clock_counter + i*256*4;

                    --if i =0 then
                    --    int_samples(i)<=clock_counter;
                    --elsif i =1 then
                    --    ;
                    --else 
                    --    int_samples(i) <= to_unsigned(i,32);
                    --end if;
                end loop;

                if clock_counter >20 then
                    wr_enable <= '1';
                end if;

                if clock_counter = where_trigger then
                    -- pick one plus meta
                    --pps_trig <= '1';
                    --ext_trig <= '1';
                    rf_trig_0 <= '1';
                    rf_trig_0_meta <= x"00000f";
                    --rf_trig_1 <= '1';
                    --rf_trig_1_meta <= x"123000";
                    --pa_trig <= '1';
                    --pa_trig_meta <= x"89a";
                    --soft_trig <= '1';
                    any_trig <= '1';
                else
                    pps_trig <= '0';
                    ext_trig <= '0';
                    rf_trig_0 <= '0';
                    rf_trig_0_meta <= x"000000";
                    rf_trig_1 <= '0';
                    rf_trig_1_meta <= x"000000";
                    pa_trig <= '0';
                    pa_trig_meta <= x"000";
                    soft_trig <= '0';
                    any_trig <= '0';

                end if;


                if clock_counter > 1000 and event_ready='1' then
                    read_enable <= '1';
                else
                    read_enable <= '0'; -- need something to off read enable and then pulse wr_clk_rd_done
                end if;

                --io files
                --file_open(file_INPUT, "data/input_waveforms.txt", read_mode);
                --file_open(file_THRESHOLDS, "data/input_channel_thresholds.txt", read_mode);
                --file_open(file_TRIGGERS, "data/output_trigger.txt", write_mode);

                

                
                --write(v_OLINE,ch_samples(31 downto 0),right,32);
                --writeline(output,v_OLINE);

                write(v_OLINE,clock_counter,right,32);
                write(v_OLINE,' ');

                write(v_OLINE,wr_enable,right,1);
                write(v_OLINE,' ');

                write(v_OLINE,soft_trig,right,1);
                write(v_OLINE,pps_trig,right,1);
                write(v_OLINE,ext_trig,right,1);
                write(v_OLINE,rf_trig_0,right,1);
                write(v_OLINE,rf_trig_1,right,1);
                write(v_OLINE,pa_trig,right,1);
                write(v_OLINE, ' ');
    
                write(v_OLINE,wr_pointer,right,wr_pointer'length);
                write(v_OLINE,' ');
                write(v_OLINE,wr_busy,right,wr_busy'length);
                write(v_OLINE,' ');
                write(v_OLINE,wr_done,right,wr_done'length);
                write(v_OLINE,' ');

                write(v_OLINE,event_ready,right,1);
                write(v_OLINE,' ');
                
                write(v_OLINE,rd_pointer,right,2);
                write(v_OLINE,' ');

                write(v_OLINE,rd_lock,right,1);
                write(v_OLINE,' ');

                write(v_OLINE,read_enable,right,1);
                write(v_OLINE,' ');

                write(v_OLINE,read_valid,right,1);
                write(v_OLINE,' ');

                write(v_OLINE,samples_out,right,32);
                write(v_OLINE,' ');

                writeline(file_output, v_OLINE);



                --write(v_OLINE,test,right,32);
                --write(v_OLINE, ' ');

                --write(v_OLINE,trig,right,1);
                --writeline(file_TRIGGERS, v_OLINE);

            end loop;

            file_close(file_output);

            wait;

        end process;

end behave;