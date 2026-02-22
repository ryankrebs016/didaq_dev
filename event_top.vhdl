-- Top level event controller

library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.defs.all;

entity event_top is
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
end event_top;

architecture rtl of event_top is

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
        wr_busy_o : out std_logic;
        data_ready_o : out std_logic; --same as data written

        --read side clock and enable
        rd_clk_i : in std_logic;
        rd_en_i : in std_logic; -- refresh new data if not rd manual

        rd_manual_i : in std_logic;
        rd_channel_i : in std_logic_vector(4 downto 0);
        rd_block_i : in std_logic_vector(8 downto 0);

        -- register sized data out
        read_address_o : out std_logic_vector(15 downto 0);
        read_done_o : out std_logic;
        data_valid_o : out std_logic;
        data_o : out std_logic_vector(31 downto 0);
        data_ready_rd_clk_o : out std_logic -- cdc using data ready o?

    );
    end component;


    signal global_enable : std_logic := '0'; -- read from regs
    signal soft_reset : std_logic := '0'; -- global soft reset
    signal soft_resets : std_logic_vector(NUM_EVENTS-1 downto 0) := (others=>'0'); -- event specific soft reset
    signal reg_soft_reset : std_logic := '0'; -- from register soft reset, redundant?
    
    signal manual_events : std_logic := '0'; -- from regs, manual event mode to record signals for calibration
    signal read_channel : std_logic_vector(4 downto 0) := (others=>'0'); -- from regs, pick channel
    signal read_block : std_logic_vector(8 downto 0) := (others=>'0'); -- from regs, pick buffer address


    -- these were in the gps pps block, but maybe it makes it eaiser if they're here? event timing stuff
    signal pps_counter : unsigned(31 downto 0) := (others=>'0');
    signal clk_counter : unsigned(31 downto 0) := (others=>'0');
    signal clk_counter_last_pps : unsigned(31 downto 0) := (others=>'0');
    signal clk_counter_last_last_pps : unsigned(31 downto 0) := (others=>'0');

    -- not needed
    --signal evt_pps_counter : unsigned(31 downto 0) := (others=>'0');
    --signal evt_clk_counter : unsigned(31 downto 0) := (others=>'0');
    --signal evt_clk_counter_last_pps : unsigned(31 downto 0) := (others=>'0');
    --signal evt_clk_counter_last_last_pps : unsigned(31 downto 0) := (others=>'0');

    -- wr, rd, and full event signals
    signal wr_enable : std_logic := '0';
    signal wr_busy : std_logic_vector(NUM_EVENTS-1 downto 0) := (others=>'0');
    signal wr_done : std_logic_vector(NUM_EVENTS-1 downto 0) := (others=>'0');
    signal event_free : std_logic_vector(NUM_EVENTS-1 downto 0) := (others=>'0');
    signal evt_busy : std_logic_vector(NUM_EVENTS-1 downto 0) := (others=>'0');

    signal wr_events : std_logic_vector(NUM_EVENTS-1 downto 0) := (others=>'0'); -- wr event enable. only 1 at a time
    signal rd_events : std_logic_vector(NUM_EVENTS-1 downto 0) := (others=>'0'); -- rd event enable. only 1 at a time
    signal full_events : std_logic_vector(NUM_EVENTS-1 downto 0) := (others=>'0'); -- signal full events need to be readout
    signal rd_clk_event_ready : std_logic_vector(NUM_EVENTS-1 downto 0) := (others=>'0');
    signal clear : std_logic_vector(NUM_EVENTS-1 downto 0) := (others=>'0');

    signal forced_reset : std_logic := '0'; -- pull from regs. should only need to be done on write side?

    signal trigger_deadtime : std_logic := '0';
    signal start_trigger_deadtime : std_logic := '0';
    signal trigger_deadtime_counter : unsigned(11 downto 0) := (others=>'0');
    signal trigger_deadtime_target : unsigned(11 downto 0) := x"100";

    type event_data_t is array(NUM_EVENTS-1 downto 0) of std_logic_vector(NUM_SAMPLES*SAMPLE_LENGTH-1 downto 0);
    signal event_data : event_data_t := (others=>(others=>'0')); 

    signal read_lock : std_logic := '0';
    signal rd_pulse : std_logic_vector(NUM_EVENTS-1 downto 0) := (others=>'0');
    signal read_done : std_logic_vector(NUM_EVENTS-1 downto 0) := (others=>'0');
    signal read_valid : std_logic_vector(NUM_EVENTS-1 downto 0) := (others=>'0');
    signal read_ready : std_logic_vector(NUM_EVENTS-1 downto 0) := (others=>'0');
    signal did_read : std_logic_vector(NUM_EVENTS-1 downto 0) := (others=>'0');
    -- event and run numbers
    type event_counters_t is array(NUM_EVENTS-1 downto 0) of unsigned(15 downto 0);
    --signal event_counter : event_counters_t := (others=>(others=>'0')); -- count after new wr enabled
    signal event_counter : std_logic_vector(23 downto 0) := (others=>'0');
    signal run_number : std_logic_vector(15 downto 0) := (others=>'0'); -- pull from regs
    
    -- trigger data to be multiplexed to single events
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

    forced_reset <= soft_reset_i; -- need cdc
    manual_events <= rd_manual_i; -- need cdc
    read_channel <= rd_channel_i;
    read_block <= rd_block_i;
    soft_trig <= soft_trig_i;

    GEN_EVENTS : for evt in 0 to NUM_EVENTS-1 generate
        xEvent : single_event
        port map(
            rst_i => rst_i,
            wr_clk_i => wr_clk_i,
            wr_en_i => wr_events(evt),
            clear_i => clear(evt),
            soft_reset_i => soft_resets(evt),
            waveform_data_i => data_i,
            
            run_number_i => run_number,
            event_number_i => event_counter,
            
            pps_clk_i => pps_clk_i,
            event_timing_enable_i => '1',
            clk_count_i => std_logic_vector(clk_counter),
            pps_count_i => std_logic_vector(pps_counter),
            clk_on_last_pps_i => std_logic_vector(clk_counter_last_pps),
            clk_on_last_last_pps_i => std_logic_vector(clk_counter_last_last_pps),
            
            pps_trig_i => pps_trig,
            rf_trig_0_i => rf_trig_0_i,
            rf_trig_0_meta_i => rf_trig_0_meta_i,
            rf_trig_1_i => rf_trig_1_i,
            rf_trig_1_meta_i => rf_trig_1_meta_i,
            pa_trig_i => pa_trig_i,
            pa_trig_meta_i => pa_trig_meta_i,
            soft_trig_i => soft_trig,
            ext_trig_i => ext_trig(1),

            wr_busy_o => wr_busy(evt),
            data_ready_o => wr_done(evt),

            rd_clk_i => rd_clk_i,
            rd_en_i => rd_pulse(evt), --rd_events(evt),
            
            rd_manual_i => manual_events,
            rd_channel_i => read_channel,
            rd_block_i => read_block,

            read_address_o => open,
            read_done_o => read_done(evt),
            data_valid_o => read_valid(evt),
            data_o => event_data(evt),
            data_ready_rd_clk_o => read_ready(evt)
        );
    end generate;


    wr_enable <= wr_enable_i;
    wr_pointer_o <= wr_events;
    wr_busy_o <= wr_busy;
    wr_done_o <= wr_done;

    proc_wr_event_control : process(rst_i, wr_clk_i)
    begin
        -- wr events is applied enable to event, should go low after wr_done
        -- wr busy is when there's a trigger hold on the event
        -- wr done is when the waveform has finished writing
        -- figure out which buffer is available to write, can be unclocked
        -- cdc wr done to read process
        if wr_events(0)='0' and wr_busy(0)='0' and wr_done(0)='0' then
            -- event buffer 0 ready
            event_free(0) <= '1';
        else
            -- event buffer 0 busy
            event_free(0) <= '0';
        end if;

        if wr_events(1)='0' and wr_busy(1)='0' and wr_done(1)='0' then
            -- event buffer 1 ready
            event_free(1) <= '1';
        else
            -- event buffer 0 busy
            event_free(1) <= '0';
        end if;

        if rst_i then
            --resets
        elsif rising_edge(wr_clk_i) then
            if wr_enable then
                if manual_events then
                    -- only use one buffer
                    if not wr_busy(0) and not wr_done(0) then
                        wr_events(0) <= '1';
                    else
                        wr_events(0) <= '0';
                    end if;

                    if wr_enable and (did_read(0) or forced_reset) then
                        clear(0) <= '1'; -- wr busy and wr done should be forced low
                    end if;
                    
                else
                    -- write control of multiple events and account for trigger deadtime between buffers TODO: figure out specific logic needed. close?


                    -- figure out valid triggers from trigger deadtime counter thing. both buffers shouldn't be in this same wr state. running extra trigger deadtime might not
                    -- be an issue otherwise as in if the other is full it doesn;t matter since it needs to readout. and if it's free it will start anyway
                    -- wr_busy goes high on a trigger, then wr done goes high until readout happens
                    if any_trig='1' and trigger_deadtime='0' and wr_events(0)='1' and wr_busy(0)='0' and wr_done(0)='0' then
                        -- send triggers and kick start trigger deadtime counter
                        start_trigger_deadtime <= '1';
                        event_counter <= std_logic_vector(unsigned(event_counter)+1);
                        -- I think I can just send trigger_deadtime as not trigger_valid to the events
                    elsif any_trig='1' and trigger_deadtime='0' and wr_events(1)='1' and wr_busy(1)='0' and wr_done(1)='0' then
                        -- send triggers and kick start trigger deadtime counter
                        start_trigger_deadtime <= '1';
                        event_counter <= std_logic_vector(unsigned(event_counter)+1);

                    else
                        start_trigger_deadtime <= '0';
                    end if;

                    -- trigger deadtime things (start counter=0, once kick start counter starts, then trigger deadtime goes high causing counter to continue, once counter exceeds target, deadtime goes low and counter should reset)
                    if trigger_deadtime_counter<trigger_deadtime_target and trigger_deadtime_counter /= 0 then
                        --block triggers
                        trigger_deadtime <= '1';
                    else
                        -- send triggers
                        trigger_deadtime <= '0';
                    end if;
                    -- trigger deadtime counter
                    if start_trigger_deadtime or trigger_deadtime then -- may cause extra count if another trigger happens right at the end of the counter, should be okay as long as trigger isn't stuck high
                        trigger_deadtime_counter <= trigger_deadtime_counter + 1;
                    elsif not trigger_deadtime then
                        trigger_deadtime_counter <= (others=>'0');
                    end if;


                    -- choose which events to start writing, first trigger in an event should start the next buffer
                    -- to start writing, but will initiate a deadtime to not trigger the next buffer while the first is still being written
                    -- may need to combine into larger conditional to not face collisions or breakout the wr events control to check if any went high?

                    -- if none busy/written, start event 0
                    if event_free(0)='1' and event_free(1)='1' then
                        --start event 0 buffer write
                        wr_events(0) <= '1';
                        wr_events(1) <= '0';
                    
                    -- if both busy wait
                    elsif event_free(0)='0' and event_free(1)='0' then
                        -- suffer and wait for readout
                        --wr_events(0) <= '0';
                        --wr_events(1) <= '0';

                    -- if both were full and 0 just finished read and cleared and 1 is waiting to read
                    elsif did_read(0)='1' and event_free(0)='1' and event_free(1)='0' then
                        wr_events(0) <= '1';
                    -- if both were full and 1 just finished read and cleared and 0 is waiting for read
                    elsif did_read(1)='1' and event_free(0)='0' and event_free(1)='1' then
                        wr_events(1) <= '1';

                    -- deadtime-less writing
                    -- if 0 is busy and get trigger, start event 1
                    elsif any_trig='1' and trigger_deadtime='0' and event_free(0)='0' and event_free(1)='1' then
                        -- start event 1 buffer write
                        wr_events(1) <= '1';
                    -- if 1 is busy and get trigger, start event 0
                    elsif any_trig='1' and trigger_deadtime='0' and event_free(0)='1' and event_free(1)='0' then
                        -- start event 0 buffer write
                        wr_events(0) <= '1';
                    end if;

                    if wr_done(0) = '1' or wr_done(1) = '1' then
                        event_ready_o <= '1';
                    else
                        event_ready_o <= '0';
                    end if;

                    -- did read should be single clock cycle pulse originating from read side process
                    -- signals to reset the event buffers
                    if did_read(0) or forced_reset then
                        clear(0) <= '1';
                    else 
                        clear(1) <= '0';
                    end if;
                    if did_read(1) or forced_reset then
                        clear(1) <= '1';
                    else
                        clear(1) <= '0';
                    end if;

                end if;
            end if;
        end if;
    end process;

    rd_pointer_o <= rd_events;
    --rd_pointer_o <= read_ready;

    rd_lock_o <= read_lock;

    proc_rd_event_control : process(rst_i, rd_clk_i)
    begin
        -- assign signals. lock should restrict only 1 bit of rd_events at a time
        if rd_events(0) then
            data_o <= event_data(0);
            rd_pulse(0) <= rd_pulse_i;
            data_valid_o <= read_valid(0);
        elsif rd_events(1) then
            data_o <= event_data(1);
            rd_pulse(1) <= rd_pulse_i;
            data_valid_o <= read_valid(1);

        else
            data_o <= (others=>'0');
            rd_pulse <= (others=>'0');
            data_valid_o <= '0';
        end if;

        if rst_i then
            rd_events <= (others=>'0');
            did_read <= (others=>'0');

        elsif rising_edge(rd_clk_i) then
            if manual_events then
                rd_events(0) <= '1'; -- only use first buffer so always point there
            
            else
                -- single event structure should take care of these control signals so we don't hit any weird behavior. tbd testing
                if read_ready(0) and not read_done(0) and not read_lock then
                    -- recognize available event and lock read pointer
                    rd_events(0) <= '1';
                    read_lock <= '1';
                elsif read_ready(1) and not read_done(1) and not read_lock then
                    -- recognize available event and lock read pointer
                    rd_events(1) <= '1';
                    read_lock <= '1';
                --else
                --    rd_events <= (others=>'0');
                end if;

                -- cdc this stuff, but once rd done goes high we unlock the readout pointer send the did read to the write side to reset the buffer
                if read_done(0) and read_lock then
                    rd_events(0) <= '0';
                    did_read(0) <= '1';
                    read_lock <= '0';
                else
                    did_read(0) <= '0';
                end if;

                if read_done(1) and read_lock then
                    rd_events(1) <= '0';
                    did_read(1) <= '1';
                    read_lock <= '0';
                else
                    did_read(1) <= '0';
                end if;
            end if;
            
        end if;
    end process;

    proc_trig_misc : process(rst_i, wr_clk_i)
    begin
        if rst_i = '1' then
            -- resets
            any_trig <= '0';
            ext_trig <= (others=>'0');

        elsif rising_edge(wr_clk_i) then
            -- idk if it's easier to process the triggers here or if we should do it in the individual events?
            
            -- know if we have any trigger at this level to use the trigger deadtime counter
            any_trig <= rf_trig_0_i or rf_trig_1_i or pa_trig_i or soft_trig or ext_trig(1) or pps_trig;

            -- sync raw ext trig in to wr clk
            ext_trig(0) <= ext_trig_i;
            ext_trig(1) <= ext_trig(0);

        end if;
    end process;

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
            if do_pps_trig_i='1' and pps_trig_hold='0' then
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
end rtl;