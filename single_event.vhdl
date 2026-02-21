-- event structure = header info, event timing, trigger metadata, waveforms
-- event is array ()
-- waveforms are going to be mapped uto waveform mem blocks using the starting write addresses per channel 
-- header_length = header info (run number, event number, event timing)
--      run_number = 2 bytes (2^16-1 numbers)
--      event_number = 3 bytes (2^24-1 numbers) - 2 bytes may not be enough for noisy runs
--      event_pps_count = 2 bytes for run specific counter (4 bytes if longer running pps counter from start up)
--      event_clk_count = 4 bytes
--      event_clk_on_last_pps = 4 bytes
--      event_clk_on_last_last_pps = 4 bytes
--      test: event_unix_time_s = 4 bytes
--      test: event_unix_time_ns = 4 bytes
--
-- metadata_length = trigger specific metadata (triggering channels or triggering beams) + any computed quantities(digital makes this less important)
--      which_trigger 1 byte
--      rf_trig_0: triggering_channels = 3 bytes
--      rf_trig_1: triggering_channels = 3 bytes
--      pa_trig: triggering_beams = 2 bytes
--
--
-- waveform length = num_channels*buffer_length/4*num_sample_per_block*sample_length
--      1 channel = 2048 samples or 2048/4=512 mem addresses
--      8 bit samples is 512*24*1 = 12288 bytes
--      9 bit samples is if packed without empty space is 13824 bytes
--      waveforms should already be correctly time sequential in the waveform storage (ie byte 0 here should point to the oldest data stored)
--

library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.defs.all;

entity single_event is
    generic(
        SAMPLE_LENGTH : integer := 8; -- or 9
        NUM_SAMPLES : integer := 4;
        ADDR_DEPTH : integer := 9;
        OUTPUT_LENGTH : integer := 32 -- tbd map 24 ch out to 4 byte reg interface or port 24 ch to 24 regs? fit to reg size or packet size. TODO: update for 9 bits
    );
    port(
        rst_i : in std_logic;

        -- write side clock things
        -- some of these may not be on the wr clock and instead the 100MHz or slower, so be careful
        wr_clk_i : in std_logic;
        wr_en_i : in std_logic; -- to enable waveform writing and meta data storage
        clear_i : in std_logic; -- to clear the contents of the event in order to restart data collection
        soft_reset_i :in std_logic; -- may be be duplicate functionality to clear_i?
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
        pps_count_i : in std_logic_vector(31 downto 0);
        clk_count_i : in std_logic_vector(31 downto 0);
        clk_on_last_pps_i : in std_logic_vector(31 downto 0);
        clk_on_last_last_pps_i : in std_logic_vector(31 downto 0);
        pps_trig_i : in std_logic; -- pps trig from pps holdoff
        -- pps trig i may need cdc?
        -- from rf triggers. the specific rf trigger input should serve as the enable 
        --      in order to latch the metadata (although already latched inside the trigger modules)
        rf_trig_0_i : in std_logic;
        rf_trig_0_meta_i: in std_logic_vector(NUM_CHANNELS-1 downto 0);

        rf_trig_1_i : in std_logic;
        rf_trig_1_meta_i: in std_logic_vector(NUM_CHANNELS-1 downto 0);

        pa_trig_i : in std_logic;
        pa_trig_meta_i: in std_logic_vector(NUM_BEAMS-1 downto 0);

        soft_trig_i : in std_logic;
        ext_trig_i : in std_logic;

        -- data ready signal output to higher up event handler. which should look like a big mux between event storage modules
        wr_busy_o : out std_logic := '0';
        data_ready_o : out std_logic := '0'; --same as data written

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
end single_event;
 
architecture rtl of single_event is

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
        trigger_i   : in std_logic; -- trigger strobe for post trigger sample holdoff
        soft_reset_i: in std_logic;
        data_i      : in std_logic_vector(NUM_CHANNELS*NUM_SAMPLES*SAMPLE_LENGTH-1 downto 0); -- input data 24channels*4samples*8/9bits
        post_trigger_wait_clks_i : in std_logic_vector(NUM_CHANNELS*10-1 downto 0); -- configurable, trigger dependent, post trigger hold off
        wr_clk_rd_done_i : in std_logic;
        --wr_busy_o : out std_logic;
        wr_finished_o   : out std_logic; --write finished signal from dma or read control higher up

        --read clocked stuff
        rd_clk_i        : in std_logic; -- rd clock, doesn't have to be wr_clk
        rd_en_i         : in std_logic; -- rd enable to know when to pass samples out
        rd_channel_i    : in std_logic_vector(4 downto 0); -- same time as rd_en_i
        rd_block_i      : in std_logic_vector(8 downto 0); -- same time as rd_en_i


        rd_data_valid_o : out std_logic; -- data valid signal
        data_o          : out std_logic_vector(NUM_SAMPLES*SAMPLE_LENGTH-1 downto 0):= (others=>'0') -- output data 32 bits to match reg size, may need update with 9 bits

    );
    end component;

    component signal_sync is
    port(
        clkA			: in	std_logic;
        clkB			: in	std_logic;
        SignalIn_clkA	: in	std_logic;
        SignalOut_clkB	: out	std_logic);
    end component;

    -- total bytes for header, metadata, and waveform. might not be needed if mapping individually
    constant EVENT_HEADER_LENGTH : integer := 27;
    constant EVENT_HEADER_BLOCKS : integer := 6;
    constant EVENT_META_LENGTH : integer := 8;
    constant EVENT_META_BLOCKS : integer := 4;
    constant EVENT_WAVEFORM_LENGTH : integer := 12288;
    constant EVENT_WAVEFORM_BLOCKS : integer := NUM_CHANNELS*2**ADDR_DEPTH;
    constant HEAD : integer := EVENT_HEADER_BLOCKS+EVENT_META_BLOCKS;
    -- ############################################
    -- data clock side

    -- wavefrom control signals
    signal wr_clk_rd_done : std_logic := '0';
    signal internal_wr_en : std_logic := '0';
    signal buffers_filled : std_logic := '0';
    signal post_trigger_wait_clks : std_logic_vector(NUM_CHANNELS*10-1 downto 0) := (others=>'0');
    signal internal_input_data : std_logic_vector(NUM_CHANNELS*NUM_SAMPLES*SAMPLE_LENGTH -1 downto 0);

    type post_trigger_waits_t is array(NUM_CHANNELS-1 downto 0) of std_logic_vector(9 downto 0);
    constant forced_waits : post_trigger_waits_t := (others=>"0000000000"); -- port outside to regs?
    constant rf_waits : post_trigger_waits_t := (others=>"0000000000");

    signal trigger_hold: std_logic := '0';
    signal trigger_to_ram: std_logic := '0';

    -- data inputs to latch on a trigger
    -- from higher up module
    signal run_number : std_logic_vector(15 downto 0) := (others=>'0');
    signal event_number : std_logic_vector(23 downto 0) := (others=>'0');

    -- TODO: decide pps counter clock
    signal event_pps_count : std_logic_vector(31 downto 0) := (others=>'0');
    signal event_clk_count : std_logic_vector(31 downto 0) := (others=>'0');
    signal event_clk_on_last_pps : std_logic_vector(31 downto 0) := (others=>'0');
    signal event_clk_on_last_last_pps : std_logic_vector(31 downto 0) := (others=>'0');
    
    signal which_trigger : std_logic_vector(7 downto 0) := (others=>'0');
    signal rf_trig_0_meta : std_logic_vector(NUM_CHANNELS-1 downto 0) := (others=>'0');
    signal rf_trig_1_meta : std_logic_vector(NUM_CHANNELS-1 downto 0) := (others=>'0');
    signal pa_trig_meta : std_logic_vector(NUM_BEAMS-1 downto 0) := (others=>'0');
    signal any_trig : std_logic := '0';


    -- #####################################
    -- read side stuff
    signal read_counter : unsigned(15 downto 0) := (others=> '0');
    signal read_side_buffers_filled : std_logic_vector(1 downto 0) := (others=>'0');
    signal delayed_read_address : std_logic_vector(15 downto 0) := (others=>'0');
    signal ram_rd_en : std_logic := '0';
    signal ram_read_address : std_logic_vector(8 downto 0) := (others=>'0'); --hardcode 512 depth of 32 bit words for now
    signal waveform_read_counter : unsigned(8 downto 0) := (others=>'0');
    signal channel_to_read : std_logic_vector(4 downto 0) := (others=>'0');
    signal waveform_read_valid : std_logic := '0';
    signal waveform_read_data : std_logic_vector(NUM_SAMPLES*SAMPLE_LENGTH-1 downto 0) := (others=>'0');
    signal rd_clk_data_ready : std_logic := '0';

begin
    waveform_ram : waveform_storage
    port map(
        rst_i => rst_i,

        -- write clocked stuff
        wr_clk_i => wr_clk_i, --figure out logic
        wr_en_i => internal_wr_en, -- figure out logic
        trigger_i => trigger_to_ram, -- figure out logic, inside single pulse will push the state machine
        soft_reset_i => soft_reset_i or clear_i,
        data_i => internal_input_data,
        post_trigger_wait_clks_i => post_trigger_wait_clks,
        wr_clk_rd_done_i =>  wr_clk_rd_done,

        wr_finished_o => buffers_filled, -- figure out logic

        --read clocked stuff
        rd_clk_i => rd_clk_i,
        rd_en_i => ram_rd_en,
        rd_channel_i => channel_to_read,
        rd_block_i => ram_read_address,
        
        rd_data_valid_o => waveform_read_valid, -- figure out clock delay and logic
        data_o => waveform_read_data

    );

    -- REFACTOR
    proc_fill_event_on_trig : process(rst_i, wr_clk_i)
    begin
        if rst_i = '1' then
            --resets
            internal_wr_en <= '0';
            trigger_hold <= '0';
            trigger_to_ram <= '0';
            any_trig <='0';
            data_ready_o <= '0'; -- super needs to record which event is filled and know when it has been read out
            event_pps_count <= (others=>'0');
            event_clk_count <= (others=>'0');
            event_clk_on_last_pps <= (others=>'0');
            event_clk_on_last_last_pps <= (others=>'0');
            run_number <= (others=>'0');
            event_number <= (others=>'0');
            internal_input_data <= (others=>'0');

        elsif rising_edge(wr_clk_i) then

            --clear manually rather than clearing when wr_enable goes low eg wr_en high wait for wr finished, do readout, then pulse clear_i to reset data

            if clear_i or soft_reset_i then
                internal_wr_en <= '0';
                trigger_hold <= '0';
                trigger_to_ram <= '0';
                any_trig <='0';
                data_ready_o <= '0'; -- super needs to record which event is filled and know when it has been read out
                event_pps_count <= (others=>'0');
                event_clk_count <= (others=>'0');
                event_clk_on_last_pps <= (others=>'0');
                event_clk_on_last_last_pps <= (others=>'0');
                run_number <= (others=>'0');
                event_number <= (others=>'0');
                internal_input_data <= (others=>'0');

            -- remember to assert wr_en_i after readout has happened
            -- write waveforms to buffer and wait for trigger signal to latch meta data
            elsif wr_en_i then

                --internal_wr_en <= '1';
                
                internal_input_data <= waveform_data_i;
                -- fill trigger meta data on a trigger input
                if rf_trig_0_i and (not trigger_hold) then
                    rf_trig_0_meta <= rf_trig_0_meta_i;
                end if;

                if rf_trig_1_i and (not trigger_hold) then
                    rf_trig_1_meta <= rf_trig_1_meta_i;
                end if;

                if pa_trig_i and (not trigger_hold) then
                    pa_trig_meta <= pa_trig_meta_i;
                end if;
                
                if not trigger_hold then
                    any_trig <= rf_trig_0_i or rf_trig_1_i or pa_trig_i or soft_trig_i or ext_trig_i or pps_trig_i;
                end if;

                -- first instance of a trigger
                if (rf_trig_0_i or rf_trig_1_i or pa_trig_i or soft_trig_i or ext_trig_i or pps_trig_i) and (not trigger_hold) then
                    which_trigger <= "00" & pa_trig_i & rf_trig_1_i & rf_trig_0_i & pps_trig_i & ext_trig_i & soft_trig_i;
                    trigger_hold <= '1'; -- trigger hold once we get a trigger and is only dropped is wr_en_i is low, ie has filled event and upper module de asserts
                    wr_busy_o <= '0'; --same as trigger hold
                    for i in 0 to NUM_CHANNELS-1 loop
                        if rf_trig_0_i or rf_trig_1_i or pa_trig_i then
                            post_trigger_wait_clks((i+1)*10 -1 downto i*10) <= rf_waits(i);
                        else 
                            post_trigger_wait_clks((i+1)*10 -1 downto i*10) <= forced_waits(i);
                        end if;
                    end loop;


                    -- need some work
                    trigger_to_ram <= '1'; -- send trigger to waveform storage to know when to stop

                    event_pps_count <= pps_count_i;
                    event_clk_count <= clk_count_i;
                    event_clk_on_last_pps <= clk_on_last_pps_i;
                    event_clk_on_last_last_pps <= clk_on_last_last_pps_i;

                    run_number <= run_number_i;
                    event_number <= event_number_i;

                else
                    trigger_to_ram <= '0';
                end if;

                if buffers_filled then
                    internal_wr_en <= '0';
                    data_ready_o <= '1';
                    wr_busy_o <= '0';
                else
                    internal_wr_en <= '1';
                    data_ready_o <= '0';
                    wr_busy_o <= '1';
                end if;

            end if;

        end if;
    end process;

    --read_address_o <= std_logic_vector(read_counter);


    -- REFACTOR!!!!
    proc_map_sbc_read_addr : process(rst_i, rd_clk_i)
    begin
    read_address_o <= channel_to_read & "00" & ram_read_address;

        if rst_i = '1' then
            data_o <= (others=>'0');
            data_valid_o <= '0';
            read_done_o <= '0';
            read_counter <= (others=>'0');
            rd_clk_data_ready <= '0';
            channel_to_read <= (others=>'0');
            ram_read_address <= (others=>'0');

    
        elsif rising_edge(rd_clk_i) then
            read_side_buffers_filled(0) <= buffers_filled;
            read_side_buffers_filled(1) <= read_side_buffers_filled(0);

            -- cdc not working from wr side buffers_filled. held long enough, maybe just ignore?
            if read_side_buffers_filled(1) = '0' then-- and rd_en_i='0' then
                -- reset some signals?
                ram_rd_en <= '0';
                data_o <= (others=>'1');
                data_valid_o <= '0';
                read_counter <= (others=>'0');
                read_done_o <= '0';
                channel_to_read <= (others=>'0');
                ram_read_address <= (others=>'0');

                
            elsif read_side_buffers_filled(1) = '1' then
                -- assign data out so rd enable pulses new data to the output
                -- need to do a look ahead so if writing is done the first block is already there
                -- then each read updates the read address

                -- once event complete queue up waveform buffers by enabling
                data_valid_o <= '1';

                if rd_en_i and not rd_manual_i then
                    -- update a read address
                    read_counter <= read_counter + 1;
                else
                    -- dont
                end if;

                if rd_manual_i then
                    channel_to_read <= rd_channel_i;
                    ram_read_address <= rd_block_i;
                    data_o <= waveform_read_data;

                else

                    -- map event data out
                    if unsigned(read_counter)=0 then
                        data_o <= x"0000" & run_number;
                    elsif unsigned(read_counter)=1 then
                        data_o <= x"00" & event_number;
                    elsif unsigned(read_counter)=2 then
                        data_o <= event_pps_count;
                    elsif unsigned(read_counter)=3 then
                        data_o <= event_clk_count;
                    elsif unsigned(read_counter)=4 then
                        data_o <= event_clk_on_last_pps;
                    elsif unsigned(read_counter)=5 then
                        data_o <= event_clk_on_last_last_pps;
                    elsif unsigned(read_counter)=6 then
                        data_o <= x"000000" & which_trigger;
                    elsif unsigned(read_counter)=7 then
                        data_o <= x"00" & rf_trig_0_meta;
                    elsif unsigned(read_counter)=8 then
                        data_o <= x"00" & rf_trig_1_meta;
                        ram_rd_en <= '1';
                        ram_read_address <= (others=>'0');
                        channel_to_read <= (others=>'0');
                    elsif unsigned(read_counter)=9 then
                        data_o <= x"00000" & pa_trig_meta;
                        ram_rd_en <= '1';
                        ram_read_address <= (others=>'0');
                        channel_to_read <= (others=>'0');
                        --ram_read_address <= std_logic_vector(unsigned(ram_read_address) + 1);

                    elsif unsigned(read_counter) >= HEAD and unsigned(read_counter) < HEAD+EVENT_WAVEFORM_BLOCKS then
                        ram_rd_en <= '1';

                        --waveform_read_counter <= waveform_read_counter + 1;
                        ram_read_address <= std_logic_vector(unsigned(ram_read_address) + 1);
                        if waveform_read_valid then
                            data_o <= waveform_read_data;
                        else
                            data_o <= x"ffffffff";
                        end if;
                    else
                        data_o <= (others=>'1');
                        data_valid_o <= '0';
                    end if;

                    if unsigned(ram_read_address) = 511 then
                        if unsigned(channel_to_read) + 1 > 23 then
                            channel_to_read <= "00000";
                        else
                            channel_to_read <= std_logic_vector(unsigned(channel_to_read) + 1);
                        end if;
                    end if;

                    if unsigned(read_counter) >= HEAD+EVENT_WAVEFORM_BLOCKS-1 then
                        read_done_o <= '1';
                        ram_rd_en <= '0';
                    else
                        read_done_o <= '0';
                    end if;
                end if;

            else

            end if;

        end if;
    end process;

    --ADDR_SYNC : signal_sync
    --port map(
    --    clkA	=> wr_clk_i,
    --    clkB	=> rd_clk_i,
    --    SignalIn_clkA	=> buffers_filled,
    --    SignalOut_clkB	=> rd_clk_data_ready 
    --);

end rtl;

