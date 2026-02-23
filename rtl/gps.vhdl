library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.defs.all;

entity pps_handler is
    generic(
            -- these will need moved to reg constants file
            PPS_CONTROL_ADDR : integer := 0;
            PPS_COUNTER_ADDR : integer := 1;
            CLK_COUNTER_ADDR : integer := 2;
            UNIX_TIMESTAMP_S_ADDR : integer := 3;
            UNIX_TIMESTAMP_NS_ADDR : integer := 4
            );
    
    port(
            rst_i           : in std_logic:='0';
            clk_i           : in std_logic:='0'; --figure out which clock to use. data clock is 250 MHz or can do 125 MHz - events discretized in 4ns or 8 ns or slower multiple
            pps_i           : in std_logic:='0'; -- raw pps pin input
            registers_i     : in register_array_type;

            -- 'old' style clock counters
            clk_on_pps_o        : out std_logic_vector(31 downto 0); -- clk count of long counter latest pps
            clk_on_last_pps_o   : out std_logic_vector(31 downto 0); -- clk count of long counter last pps

            pps_o               : out std_logic :='0'; -- single clock cycle wide pps signal, for scaler refresh

            data_valid_o    : out std_logic :='0'; -- single clock wide pulse to signal when data is valid and should be saved. if valid then latch data. event handler wait for valid signal on trig
            -- current counter states if needed
            pps_counter_o   : out std_logic_vector(31 downto 0); --current pps counter
            clk_counter_o   : out std_logic_vector(31 downto 0) -- current clk counter

            );
    end pps_handler;
    
architecture rtl of pps_handler is

    -- reg enable, last state for latching time stamp
    signal enable : std_logic :='0';
    signal enable_last : std_logic :='0';

    -- internal pps signal (long pulse width) and sync chain for raw input
    signal pps_int : std_logic := '0';
    signal pps_int_last : std_logic := '0';
    signal pps_sync : std_logic_vector(2 downto 0) := "000";

    -- counter enable and counters
    signal pps_counter_enable : std_logic := '0';
    signal pps_counter : unsigned(31 downto 0) := (others=>'0');
    signal clk_counter : unsigned(31 downto 0) := (others=>'0');
    signal long_clk_counter : unsigned(31 downto 0) := (others=>'0');

    -- latched clk counter states for pps and event info
    signal clk_on_pps : unsigned(31 downto 0) := (others=>'0');
    signal clk_on_last_pps : unsigned(31 downto 0) := (others=>'0');
    signal clk_on_event : unsigned(31 downto 0) := (others=>'0');
    signal pps_on_event : unsigned(31 downto 0) := (others=>'0');
    signal data_valid : std_logic := '0';

    -- trigger sigs
    signal trigger : std_logic := '0';
    signal trigger_last: std_logic := '0';

    -- for global time sync
    signal unix_s : unsigned(31 downto 0) := (others=>'0');
    signal unix_ns : unsigned(31 downto 0) := (others=>'0');
    signal event_time_s : unsigned(31 downto 0) := (others=>'0');
    signal event_time_ns : unsigned(31 downto 0) := (others=>'0');

begin

    -- assumes regs are okay to use with data clock, if not put in signal sync
    proc_pull_regs: process(rst_i, clk_i)
    begin
        if rst_i='1' then
            enable <= '0';
        elsif rising_edge(clk_i) then
            enable <= registers_i(PPS_CONTROL_ADDR)(0);
            enable_last <= enable;
            -- capture rising edge of enable. assumes timestamp regs are filled first, then the pps enable can try to tag
            -- events with a unix time. latch the first pps timestamp
            if enable and (not enable_last) then
                unix_s <= unsigned(registers_i(UNIX_TIMESTAMP_S_ADDR));
                unix_ns <= unsigned(registers_i(UNIX_TIMESTAMP_NS_ADDR));
            end if;
        end if;
    end process;

    proc_pps_counter: process(rst_i, clk_i)
    begin
        if rst_i = '1' or enable='0' then
            pps_counter <= (others=>'0');
            clk_counter <= (others=>'0');
            long_clk_counter <= (others=>'0');


        elsif rising_edge(clk_i) then
            pps_sync(2 downto 0) <= pps_sync(1 downto 0) & pps_i; 

            --may need debounce?
            
            --for now pps_int ~4 clocks after physical pps_in going high 
            pps_int <= pps_sync(2); 
            pps_int_last <= pps_int;

            long_clk_counter <= long_clk_counter + 1;
            clk_on_last_pps <= clk_on_pps;

            if pps_int and (not pps_int_last) then
                pps_counter <= pps_counter + 1;
                clk_counter <= (others=>'0');
                clk_on_pps <= long_clk_counter;
                pps_o <= '1'; --for now ~5 clock cycles after physical pps_in going high

            --elsif to_integer(clk_counter) = (250000000-1) then
            --    clk_counter <= (others=>'0');

            else
                clk_counter <= clk_counter + 1;
                pps_o <= '0';
            end if;

        end if;
    end process;

    proc_trigger_timestamp: process(rst_i, clk_i)
    begin
        if rst_i ='1' or enable ='0' then
            event_time_s <= (others=>'0');
            event_time_ns <= (others=>'0');
            trigger<='0';
            trigger_last<='0';
            clk_on_event <= (others=>'0');
            pps_on_event <= (others=>'0');


        elsif rising_edge(clk_i) and enable ='1' then


            if to_integer(unix_ns + clk_counter * 4) > 1e9 then -- hard code 4 for a 250MHz clock count to ns. if statement only needed for pps jitter/ timestamp jitter? 
                event_time_s <= unix_s + pps_counter + 1;
                event_time_ns <= unix_ns + clk_counter*4 - to_unsigned(1e9, 32); -- from capping counter to 10^9 ns
            else -- base event time assuming nice pps unix timestamps
                event_time_s <= unix_s + pps_counter;
                event_time_ns <= unix_ns + clk_counter*4;
            end if;

        end if;
    end process;

    pps_counter_o <= std_logic_vector(pps_counter);
    clk_counter_o <= std_logic_vector(clk_counter); --maybe long clk counter?

    data_valid_o <= data_valid;
    clk_on_pps_o <= std_logic_vector(clk_on_pps);
    clk_on_last_pps_o <= std_logic_vector(clk_on_last_pps);

    --event_time_s_o <= std_logic_vector(event_time_s);
    --event_time_ns_o <= std_logic_vector(event_time_ns);
    
end rtl;