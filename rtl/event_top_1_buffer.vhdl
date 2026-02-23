-- event top but for only 1 event buffer
-- simplifies the control interface for testing
-- two buffers better to reduce deadtime
-- TODO:
--      multiple event control, write and read, with predefined trigger deadtime to not trigger next event buffer
--      write side should start writing waveforms on the next event once the first buffer gets a trigger signal to eliminate deadtime
--      but ignore triggers coming in after the first, but before the waveform is finished writing

-- some of the control signals in the different modules could be moved higher, as in which trigger holdoff, which trigger, etc to higher but
-- it makes the higher level files more larger (harder to follow?)

library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.defs.all;

entity single_event_top is
    generic(
        SAMPLE_LENGTH : integer := 8; -- n bit samples
        NUM_SAMPLES : integer := 4; -- samples per clock
        ADDR_DEPTH : integer := 9; --2^9 - 1 deep ram
    );
    port(
        rst_i : in std_logic;

        -- write clocked stuff, data and triggers
        wr_clk_i    : in std_logic; -- write data clock
        data_i      : in std_logic_vector(NUM_CHANNELS*NUM_SAMPLES*SAMPLE_LENGTH-1 downto 0); -- from adc receivers, input data 24channels*4samples*8/9bits
        event_enable_i : in std_logic; -- from regs
        soft_reset_i : in std_logic; -- from regs
        run_number_i : in std_logic_vector(15 downto 0); -- pull from regs


        rf_trig_0_i : in std_logic; -- from rf trig 0
        rf_trig_0_meta_i: in std_logic_vector(NUM_CHANNELS_1 downto 0); -- from rf trig 0

        rf_trig_1_i : in std_logic; -- from rf trig 1
        rf_trig_1_meta_i: in std_logic_vector(NUM_CHANNELS-1 downto 0); -- from rf trig 1

        pa_trig_i : in std_logic; -- from pa trig
        pa_trig_meta_i: in std_logic_vector(NUM_BEAMS-1 downto 0); -- from pa trig

        ext_trigger_i : in std_logic; -- raw ext trigger, needs sync chain

        -- to gpio
        event_ready_o : out std_logic; -- if any read ready signals, send to gpio output

        -- from pps block, might be on different clock so may need cdc's to data clock
        pps_clk_i : in std_logic; -- if on diff clock
        pps_i : in std_logic; -- single clock wide pps pulse, not raw
        pps_trig_holoff_i : in std_logic_vector(31 downto 0); -- from regs

        -- read side clock. things are either manual which go through registers
        -- or with automatic event control which reads out 1 event at a time with a 
        -- pop data signal
        rd_clk_i : in std_logic; -- read clock, avalon/spi clock
        --need register signals!!!!!!!!!!


        -- register sized data out
        data_valid_o : out std_logic;
        data_o : out std_logic_vector(31 downto 0); -- TODO: 9 bits requires a rework if going through regs, ignore for now, but once spi is decoupled sending 5 (n) bytes should be easy
        data_ready_rd_clk_o : out std_logic -- cdc using data ready o? maybe from reg module
    );
end single_event_top;

architecture rtl of single_event_top is

    component single_event is
    generic(
        SAMPLE_LENGTH : integer := 8; -- or 9
        NUM_SAMPLES : integer := 4;
        ADDR_DEPTH : integer := 9;
        OUTPUT_LENGTH : integer := 32
    );
    port(
        rst_i : in std_logic;

        -- write side clock things
        -- some of these may not be on the wr clock and instead the 100MHz or slower, so be careful
        wr_clk_i : in std_logic; -- fast clock 250 MHz
        waveform_data_i : in std_logic_vector(NUM_CHANNELS*NUM_SAMPLES*SAMPLE_LENGTH -1 downto 0);
        -- I think going into here these values might be latched
        -- the idea is this block just maps what the sbc wants, address
        -- in a single register, and internally maps out what is needed
        -- the single clock waveforms may need to be mapped in so that the ram is here
        -- and then once the event is completed the readout can happen?

        run_number_i : in std_logic_vector(15 downto 0);
        event_number_i : in std_logic_vector(23 downto 0);

        -- from gps pps and event timing module. this interface needs some work otherwise is becomes clunky
        -- ie move the counters to the super event control rather than from pps, which then keeps trigger only from trigger
        -- modules to the event controller
        pps_clk_i : std_logic;
        event_timing_enable_i : in std_logic;
        event_pps_count_i : in std_logic_vector(31 downto 0);
        event_clk_count_i : in std_logic_vector(31 downto 0);
        event_clk_on_last_pps_i : in std_logic_vector(31 downto 0);
        event_clk_on_last_last_pps_i : in std_logic_vector(31 downto 0);
        pps_trig_i : in std_logic; -- pps trig from pps holdoff
        -- pps trig i may need cdc?
        -- from rf triggers. the specific rf trigger input should serve as the enable 
        --      in order to latch the metadata (although already latched inside the trigger modules)
        rf_trig_0_i : in std_logic;
        rf_trig_0_meta_i: in std_logic_vector(NUM_CHANNELS_1 downto 0);

        rf_trig_1_i : in std_logic;
        rf_trig_1_meta_i: in std_logic_vector(NUM_CHANNELS-1 downto 0);

        pa_trig_i : in std_logic;
        pa_trig_meta_i: in std_logic_vector(NUM_BEAMS-1 downto 0);

        soft_trig_i : in std_logic;
        ext_trig_i : in std_logic;

        -- data ready signal output to higher up event handler. which should look like a big mux between event storage modules
        wr_busy_o : out std_logic;
        data_ready_o : out std_logic;

        --read side clock and enable
        rd_clk_i : in std_logic; -- slow clock, 125MHz
        rd_en_i : in std_logic;
        rd_address_i : in std_logic_vector(15 downto 0);

        -- register sized data out
        data_valid_o : out std_logic;
        data_o : out std_logic_vector(31 downto 0);
        data_ready_rd_clk_o : out std_logic -- cdc using data ready o?

    );
    end component;


    signal global_enable : std_logic := '0'; -- read from regs
    signal soft_reset : std_logic := '0'; -- global soft reset read from regs, should reset all event buffers on a run start
    signal soft_resets : std_logic := (others=>'0'); -- event specific soft reset
    signal reg_soft_reset : std_logic := '0'; -- from register soft reset, redundant with soft reset?
    
    -- these were in the gps pps block, but maybe it makes it eaiser if they're here? event timing stuff
    signal pps_counter : unsigned(31 downto 0) := (others=>'0');
    signal clk_counter : unsigned(31 downto 0) := (others=>'0');
    signal clk_counter_last_pps : unsigned(31 downto 0) := (others=>'0');
    signal clk_counter_last_last_pps : unsigned(31 downto 0) := (others=>'0');

    -- write controls
    signal wr_events : std_logic := '0'; --std_logic_vector(NUM_EVENTS-1 downto 0) := (others=>'0'); -- wr event enable. only 1 at a time
    signal wr_busy : std_logic := '0';
    signal trig_deadtime : unsigned(9 downto 0) := (others=>'0');
    constant trig_deadtime_counter : integer := 256; -- deadtime to block second triggers during a wr busy
    signal full_events : std_logic := '0'; --: std_logic_vector(NUM_EVENTS-1 downto 0) := (others=>'0'); -- signal full events need to be readout

    -- read controls
    signal rd_events : std_logic := '0'; --: std_logic_vector(NUM_EVENTS-1 downto 0) := (others=>'0'); -- rd event enable. only 1 at a time
    signal rd_clk_event_ready : std_logic := '0'; --: std_logic_vector(NUM_EVENTS-1 downto 0) := (others=>'0');
    signal manual_events : std_logic := '0'; -- from regs, manual event mode to record signals for calibration
    signal read_channel : std_logic_vector(4 downto 0) := (others=>'0'); -- from regs, pick channel
    signal read_block : std_logic_vector(8 downto 0) := (others=>'0'); -- from regs, pick buffer address

    --type event_data_t is array(NUM_EVENTS-1 downto 0) of std_logic_vector(NUM_SMAPLES*SAMPLE_LENGTH-1 downto 0);
    --signal event_data : event_data_t := (others=>(others=>'0')); 
    signal event_data : std_logic_vector(NUM_SMAPLES*SAMPLE_LENGTH-1 downto 0) := (others=>'0'); 


    -- event and run numbers
    --type event_counters_t is array(NUM_EVENTS-1 downto 0) of unsigned(15 downto 0);
    signal event_counter : unsigned(15 downto 0) := (others=>'0'); --event_counters_t := (others=>(others=>'0')); -- count after new wr enabled, reset on run start
    signal run_number : unsigned(15 downto 0) := (others=>'0'); -- pull from regs
    
    -- trigger data to be multiplexed to single events
    signal any_trig : std_logic := '0';
    signal which_trigger : std_logic_vector(7 downto 0) := (others=>'0');
    --signal rf_trig_0_meta : std_logic_vector(NUM_CHANNELS-1 downto 0) := (others=>'0');
    --signal rf_trig_1_meta : std_logic_vector(NUM_CHANNELS-1 downto 0) := (others=>'0');
    --signal pa_trig_meta : std_logic_vector(NUM_BEAMS-1 downto 0) := (others=>'0');
    signal soft_trig : std_logic := '0'; -- pull from regs
    signal ext_trig : std_logic_vector(1 downto 0) := (others=>'0'); -- vector for sync chain

    -- pps trigger generators
    signal pps_trig : std_logic := '0'; -- pull from regs, write to reg, then pull low to queue the next one while perfroming the pps trig
    signal pps_trig_hold : std_logic := '0';
    signal pps_trig_holdoff : unsigned(31 downto 0) := (others=>'0'); -- pull in from regs
    signal pps_trig_counter : unsigned(31 downto 0) := (others=>'0');

    -- things to check for trigger deadtime to complete an event if multiple trigger while filling a buffer
    signal any_trig : std_logic := '0';
    signal trig_deadtime : unsigned(8 downto 0) := (others=>'0'); -- deadtime for when we have a writing event with a trigger, and if we get a second trigger before the buffer is written we ignore it.

    begin

    pps_trig_holdoff <= pps_trig_holdoff_i;
    global_enable <= event_enable_i;
    soft_reset <= soft_reset_i;
    run_number <= run_number_i;

    --for evt in 0 to NUM_EVENTS-1 generate
        xEvent : single_event
        port map(
            rst_i => rst,
            wr_clk_i => clock,
            wr_en_i => wr_events,
            clear_i => evt_clears,
            soft_reset_i => soft_resets,
            waveform_data_i => samples_in,
            
            run_number_i => run_number,
            event_number_i => event_number,
            
            pps_clk_i => pps_clk_i,
            event_timing_enable_i => open,
            clk_count_i => clk_counter,
            pps_count_i => pps_counter,
            clk_on_last_pps_i => clk_on_last_pps,
            clk_on_last_last_pps_i => clk_on_last_last_pps,
            
            pps_trig_i => pps_trig,
            rf_trig_0_i => rf_trig_0_i,
            rf_trig_0_meta_i => rf_trig_0_meta_i,
            rf_trig_1_i => rf_trig_1_i,
            rf_trig_1_meta_i => rf_trig_1_meta_i,
            soft_trig_i => soft_trig,
            ext_trig_i => ext_trig,

            wr_busy_o => wr_busy,
            data_ready_o => full_events,

            rd_clk_i => rd_clk_i,
            rf_en_i => rd_events,
            rd_address_i => read_address,
            
            rd_manual_i => read_manual,
            rd_channel_i => read_channel,
            rd_block_i => read_block,

            read_done_o => read_done,
            data_valid_o => read_valid,
            data_o => event_data,
            data_ready_rd_clk_o => read_ready
        );
    --end generate;

    -- clock counter and pps counter, pps trig generator -- NEED TO PULL IN REGS -- OTHERWISE DONE
    proc_clk_counter_and_pps_trig : process(rst_i, pps_clk_i)
    begin
        if rst_i = '1' then
            pps_counter <= (others=>'0');
            clk_counter <= (others=>'0');
            clk_counter_last_pps <= (others=>'0');
            clk_counter_last_last_pps <= (others=>'0');
            
        elsif rising_edge(pps_clk_i) then
            -- event timing stuff
            clk_counter <= clk_counter + 1;
            if pps_i = '1' then
                pps_counter <= pps_counter + 1;
                clk_counter_last_pps <= pps_counter;
                clk_counter_last_last_pps <= clk_counter_last_pps;
            end if;

            -- pps trigger stuff
            if pps_trig'event and pps_trig='1' and not pps_trig_hold then
                pps_trig_hold <= '1';
                pps_trig_counter <= (others=>'0');
            end if;

            if pps_trig_hold then
                pps_trig_counter <= pps_trig_counter + 1;
                if pps_trig_counter >= pps_trig_holdoff then
                    pps_trig_hold <= '0';
                    pps_trig <= '1';
                else 
                    pps_trig <= '0';
                end if;
            end if;
        end if;
    end process;

    proc_wr_event_control : process(rst_i, clk_wr_i)
    begin
        if rst_i then
            wr_events <= '0'; --(others=>'0');
            rd_events <= '0'; --(others=>'0');
            full_events <='0'; -- (others=>'0');


        elsif rising_edge(clk_wr_i) then
            if global_enable then
                -- new event every time wr events is restarted. wr_events, go low during, read finished, enable wr events
                if wr_events'event and wr_events='1' then
                    event_number = event_number + 1;
                elsif soft_reset
                    event_number <= (others=>'0');
                end if;


                -- done should stay high until it is deasserted after a complete read. might eed more conditions
                if not done then
                    wr_events <= '1';
                else
                    wr_events <= '0';
                end if;

                -- event has a trig and is filling the buffer
                if wr_busy then
                    trig_deadtime_counter <= trig_deadtime_counter + 1;
                    -- and also queue up the next event buffer to eliminate deadtime
                end if;

                -- TODO for 2+ event buffers. if another trig while an event is currently filling a buffer
                if trig_deadtime_counter < trig_deadtime and any_trig then
                    --ignore it
                elsif trig_deadtime_counter > trig_deadtime and any_trig then
                    -- send make sure other event buffer is recording
                end if;

                if rd_done then
                    soft_resets <= '1';
                else
                    soft_resets <= '0';
                end if;

                    -- this might get messy?
                    --if wr_events(0) = '0' and wr_events(1) ='0' then
                    --    if wr_enable then
                    --        wr_events(0) <= '1';
                    --    end if;
                    --elsif wr_events(0) = '1' and wr_events(1) = '0' then

            end if;
        end if;
    end process;

    proc_trigs : process(rst_i, clk_wr_i)
    begin
        if rst_i = '1' then
            -- resets
            any_trig <= '0';
            trig_deadtime <= (others=>'0');
            ext_trig <= (others=>'0');

        elsif rising_edge(clk_wr_i) then
            -- idk if it's easier to process the triggers here or if we should do it in the individual events?
            
            any_trig <= rf_trig_0_i or rf_trig_1_i or pa_trig_i or soft_trig_i or ext_trig(1) or pps_trig_i;

            -- sync raw ext trig in to wr clk
            ext_trig(0) <= ext_trig_i;
            ext_trig(1) <= ext_trig(0);


            -- no reason to do this if the events already latch on a trigger, just need to track any trigger for trigger deadtime
            --if (rf_trig_0_i or rf_trig_1_i or pa_trig_i or soft_trig_i or ext_trig_i or pps_trig_i) then
            --    which_trigger <= "00" & pa_trig_i & rf_trig_1_i & rf_trig_0_i & pps_trig & ext_trig_i & soft_trig_i;
            --    evt_pps_counter <= pps_counter;
            --    evt_clk_counter <= clk_counter;
            --    evt_clk_counter_last_pps <= ck_counter_last_pps;
            --    evt_pps_counter <= clk_counter_last_pps;
            --    -- post_trigger_holdoff <= to feed in any post trigger holdoff per trigger type?
            --
            --end if;


        end if;

    proc_rd_event_control : process(rst_i, clk_rd_i)
    begin
        -- TODO 2+ event buffers. assign data out
        --if rd_events(0) then
        --    data_o <= event_data(0);
        --elsif rd_events(1) then
        --    data_o <= event_data(1);
        --else
        --    data_o <= (others=>'0');
        --end if;

        if rst_i then
        
        elsif rising_edge(clk_rd_i)

        end if;
    end process;


    end rtl;