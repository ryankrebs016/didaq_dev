-- module to wrap the single channel dual port ram with maybe different write and read clocks
--
-- write side
-- state machine to handle writing to the buffers
--      writes to a RAM starting at addr 0, until a trigger signal is recieved, then the post trigger counts will be written and the
--      final write address is stored so that the first read block is final addr + 1 (keeps time ordered)
--      
--      RAM is a simple dual port. separate wr and rd clock to allow for fast write but slow read
--
--      wr state functions as follows:
--      if trigger happens before a buffer is partially written, it will continue writing until the full buffer is complete
--      if trigger happens after a buffer is partially filled but before the buffer is filled, it will write until the post trigger counts are complete
--      if trigger happens after the buffer is written to, it will continue writing the post trigger counts and stop
--      once buffer is filled and written, it will become idle until wr enable is reasserted.
--
--      wr_enable starts the wr, trigger will cause the final blocks to be written. here, wr enable needs to be deasserted by the parent
--          module to keep flow of the state machine
--      rd happens in the wr idle state. rd enable is assumed to happen after some time due to being initiated by sbc
--
-- read side
--      rd is initiated by the read enable signal, which channel should be read, and which memory "address" to be used.
--          the ram indexed read address is the last written address + 1 + chosen read address.
--          parent module should loop read address from 0 to 511
--
--      output samples are 32 bits of data, 4 samples of 8 or 9 bits and are accompanied by a data valid signal
--      note: it may take an extra clock cycle to access ram as written, some signals could be moved to async assign, but it still takes
--          one clock to move rd address, enable, and channel address in, and another clock cycle for the correct data to appear
--
--      once read is finished the wr clk read done signal should go high to tell the wr side to clear data and wait for new wr enable

--


-- want wr_clk_rd_done_i to be low and wr_finished_o to be low before wr_en_i can go back high. as in event control should be controlling


library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.defs.all;

entity waveform_storage is
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
        soft_reset_i : std_logic;
        data_i      : in std_logic_vector(NUM_CHANNELS*NUM_SAMPLES*SAMPLE_LENGTH-1 downto 0); -- input data 24channels*4samples*8/9bits
        post_trigger_wait_clks_i : in std_logic_vector(NUM_CHANNELS*10-1 downto 0); -- configurable, trigger dependent, post trigger hold off
        wr_clk_rd_done_i : in std_logic;
        wr_finished_o   : out std_logic; --write finished signal from dma or read control higher up

        --read clocked stuff
        rd_clk_i        : in std_logic; -- rd clock, doesn't have to be wr_clk
        rd_en_i         : in std_logic; -- rd enable to know when to pass samples out
        rd_channel_i    : in std_logic_vector(4 downto 0); -- same time as rd_en_i
        rd_block_i      : in std_logic_vector(8 downto 0); -- same time as rd_en_i

        rd_clk_wr_finished_o : out std_logic;
        rd_data_valid_o : out std_logic; -- data valid signal
        data_o          : out std_logic_vector(NUM_SAMPLES*SAMPLE_LENGTH-1 downto 0) -- output data 32 bits to match reg size, may need update with 9 bits
        --test : out std_logic_vector(31 downto 0)
    );
end waveform_storage;

architecture rtl of waveform_storage is

    component ram_control is
    generic(
        ADDR_DEPTH : integer := 9
    );
    port(
        rst_i : in std_logic;

        -- write clocked stuff
        wr_clk_i    : in std_logic; -- write data clock
        wr_en_i     : in std_logic; --write enable, de assert when wr_finished_o goes high
        trigger_i   : in std_logic; -- trigger pulse for post trigger sample holdoff
        post_trigger_wait_clks_i : in std_logic_vector(9 downto 0); -- configurable, trigger dependent, post trigger hold off
        wr_clk_rd_done_i : in std_logic; -- signal to reset the state machine
        soft_reset_i : in std_logic; -- signal to force clocked reset
        wr_en_o : out std_logic; -- output signal to pass to the ram to control active writing
        wr_finished_o   : out std_logic -- write finished signal when write is complete

    );
    end component;

    -- simple dual port ram
    component single_channel_ram is
    generic(
        SAMPLE_LENGTH : integer := SAMPLE_LENGTH;
        NUM_SAMPLES : integer := NUM_SAMPLES;
        ADDR_DEPTH : integer := ADDR_DEPTH
    );
    port(
        rst_i : in std_logic;

        A_clk_i : in std_logic;
        A_en_i : in std_logic;
        A_addr_i : in std_logic_vector(ADDR_DEPTH-1 downto 0);
        A_data_i : in std_logic_vector(SAMPLE_LENGTH*NUM_SAMPLES-1 downto 0);

        B_clk_i : in std_logic;
        B_en_i : in std_logic;
        B_addr_i : in std_logic_vector(ADDR_DEPTH-1 downto 0);
        B_valid_o : out std_logic;
        B_data_o : out std_logic_vector(SAMPLE_LENGTH*NUM_SAMPLES-1 downto 0)
    );
    end component;

    component signal_sync is
    port(
        clkA			: in	std_logic;
        clkB			: in	std_logic;
        SignalIn_clkA	: in	std_logic;
        SignalOut_clkB	: out	std_logic);
    end component;

    -- write  clock stuff
    constant NULL_DATA : std_logic_vector(NUM_SAMPLES*SAMPLE_LENGTH-1 downto 0) := x"10101010";

    type mapped_data is array(NUM_CHANNELS-1 downto 0) of std_logic_vector(NUM_SAMPLES*SAMPLE_LENGTH-1 downto 0);
    signal internal_input_data : mapped_data := (others=>(others=>'0'));

    signal wr_ens : std_logic_vector(NUM_CHANNELS-1 downto 0) := (others=>'0');
    signal ram_ens : std_logic_vector(NUM_CHANNELS-1 downto 0) := (others=>'0');
    --signal wr_busy : std_logic_vector(NUM_CHANNELS-1 downto 0):=(others=>'0'); --unused
    signal wrs_done : std_logic_vector(NUM_CHANNELS-1 downto 0):=(others=>'0');
    signal last_wrs_done : std_logic_vector(NUM_CHANNELS-1 downto 0):=(others=>'0');


    type addrs is array(NUM_CHANNELS-1 downto 0) of unsigned(ADDR_DEPTH-1 downto 0);
    signal wr_addrs: addrs := (others=>(others=>'0'));
    signal rd_addrs: addrs := (others=>(others=>'0'));
    signal final_wr_addrs: addrs := (others=>(others=>'0'));


    type count_post_trigger is array(NUM_CHANNELS -1 downto 0) of std_logic_vector(9 downto 0);
    signal post_trigger_wait_clks : count_post_trigger := (others=>"0100000000"); --read in from regs, maybe trig dep so need to port in

    signal reads_done : std_logic_vector(NUM_CHANNELS-1 downto 0) := (others=>'0');

    -- read clock stuff
    signal rd_ens : std_logic_vector(NUM_CHANNELS-1 downto 0) := (others=>'0');
    signal ram_data_valid : std_logic_vector(NUM_CHANNELS-1 downto 0):=(others=>'0');
    
    signal internal_output_data : mapped_data := (others=>(others=>'0'));
    signal internal_read_channel : std_logic_vector(4 downto 0) := (others=>'0');
    signal internal_read_block : std_logic_vector(8 downto 0):=(others=>'0');
    signal reg_out_data : std_logic_vector(NUM_SAMPLES*SAMPLE_LENGTH-1 downto 0) := (others=>'0');

    type count_addrs is array(NUM_CHANNELS-1 downto 0) of unsigned(32 downto 0);

    signal rd_clk_wr_finished : std_logic_vector(1 downto 0) := (others=>'0');
    signal rd_clk_wr_addrs: addrs := (others=>(others=>'0'));
    signal end_wr_addrs: addrs := (others=>(others=>'0'));
    signal count_rd_addrs: count_addrs := (others=>(others=>'0'));

    signal rd_done : std_logic := '0';
    signal wr_clk_rd_done : std_logic := '0';
    signal last_wr_clk_rd_done : std_logic := '0';

    signal queue_data : std_logic_vector(NUM_SAMPLES*SAMPLE_LENGTH-1 downto 0) := (others=>'0');

begin

    assign_in : for i in 0 to NUM_CHANNELS-1 generate
        post_trigger_wait_clks(i) <= post_trigger_wait_clks_i((i+1)*10-1 downto i*10);
    end generate;

    xRamControl: for i in 0 to NUM_CHANNELS-1 generate
        chan_ram_control : ram_control
        port map(
            rst_i => rst_i,
            wr_clk_i => wr_clk_i,
            wr_en_i => wr_ens(i),
            trigger_i => trigger_i,
            post_trigger_wait_clks_i => post_trigger_wait_clks(i),
            wr_clk_rd_done_i => wr_clk_rd_done_i,
            soft_reset_i => soft_reset_i,
            wr_en_o => ram_ens(i),
            wr_finished_o => wrs_done(i)
        );
    end generate;

    xChannelRAM: for i in 0 to NUM_CHANNELS-1 generate
        chan_ram : single_channel_ram
        port map(
            rst_i => rst_i,
            A_clk_i => wr_clk_i,
            A_en_i => ram_ens(i),
            A_addr_i => std_logic_vector(wr_addrs(i)),
            A_data_i => internal_input_data(i),

            B_clk_i => rd_clk_i,
            B_en_i => rd_ens(i),
            B_addr_i => std_logic_vector(rd_addrs(i)),
            B_valid_o => ram_data_valid(i),
            B_data_o => internal_output_data(i)
        );
    end generate;

    proc_write_ram : process(rst_i, wr_clk_i)
    begin
        if rst_i = '1' then
            for i in 0 to NUM_CHANNELS-1 loop
                wr_ens(i) <= '0';
                internal_input_data(i) <= NULL_DATA;
                wr_addrs(i) <= (others=>'0'); -- tools complain about async reset of ram control signal
                final_wr_addrs(i) <= (others=>'0');
            end loop;
            wr_finished_o <= '0';
            
        elsif rising_edge(wr_clk_i) then
            if soft_reset_i then
                wr_ens <= (others=>'0');
                internal_input_data <= (others=>NULL_DATA);
                wr_addrs <= (others=>(others=>'0'));
                final_wr_addrs <= (others=>(others=>'0'));
                wr_finished_o <= '0';

            else
                for i in 0 to NUM_CHANNELS-1 loop
                    last_wrs_done(i)<=wrs_done(i);
                    if (wr_en_i='1') and (wrs_done(i)='0')  then
                        wr_ens(i) <= '1';
                        internal_input_data(i) <= data_i((i+1)*NUM_SAMPLES*SAMPLE_LENGTH-1 downto i*NUM_SAMPLES*SAMPLE_LENGTH);
                        if ram_ens(i) then 
                            wr_addrs(i) <= wr_addrs(i) + 1;
                        else
                            wr_addrs(i) <= (others=>'0');
                        end if;
                    --triggers passed to the ram controller will intitiate the final write of the ram and raise wrs done
                    elsif (wr_en_i='1') and (wrs_done(i)='1') then
                        wr_ens(i) <= '0';
                        internal_input_data(i) <= data_i((i+1)*NUM_SAMPLES*SAMPLE_LENGTH-1 downto i*NUM_SAMPLES*SAMPLE_LENGTH);

                        if wrs_done(i)='1' and last_wrs_done(i)='0' then
                            final_wr_addrs(i) <= wr_addrs(i); --might need to add 1 if it takes a beat to stop writing
                        end if;
                    else
                        -- ram enable is low so no new data will be written. things can be reset too?
                        wr_ens(i) <= '0';
                        internal_input_data(i) <= NULL_DATA;
                        wr_addrs(i) <= (others=>'0');
                    end if;
                end loop;

                if (not (wrs_done=x"ffffff")) then -- had wr_en_i = '1' and
                    wr_finished_o <= '0';

                elsif (wrs_done=x"ffffff") then
                    wr_finished_o <= '1';

                else
                    -- pulsing wr clk rd done should also pulse the ram controller to lower wrs done.
                    
                    --if wr_clk_rd_done_i='1' then
                    --    wr_finished_o <= '0';
                    --end if;
                end if;
            end if;
        end if;
    end process;


    rd_clk_wr_finished_o <= rd_clk_wr_finished(1);

    proc_read_ram : process(rst_i, rd_clk_i)
    begin

        -- maps 24 ch data down to 1 ch data ouput. better to leave all available?
        -- do block incrementing in higher level

        -- async assign into the ram block where inputs and ram block is already clocked. can add regs for timing if needed. 
        -- normally outside of a process but I need some logic to translate here

        --test(8 downto 0) <= std_logic_vector(unsigned(rd_addrs(0)));

        -- CHANNEL SWITCHING POINTS TO THE NEW CHANNEL DATA BEFORE IT IS GRABBED, CAUSING DUPLICATE DATA, NEED TO WAIT FOR LAST CHANNEL SAMPLE
        -- BEFORE SWAPPING, DO HERE OR HIGH LEVEL?
        if  rd_clk_wr_finished(1) then
            rd_ens <= (others=>'1');
            for i in 0 to NUM_CHANNELS-1 loop
                --rd_ens(i) <= '0';
                --rd_addrs(i) <= rd_clk_wr_addrs(i);

                if to_integer(unsigned(rd_channel_i)) = i then
                    --rd_ens(i) <= '1';
                    rd_addrs(i) <= rd_clk_wr_addrs(i) + unsigned(rd_block_i); -- can roll over but that's ok
                    --if i /= 23 then
                    --    rd_ens(i+1) <= '1'; -- enable the next channel block or we just get an invalid data packet between channels
                    --    rd_addrs(i+1) <= rd_clk_wr_addrs(i+1);
                    --end if;
                else
                --    rd_ens(i) <= '0';
                    rd_addrs(i) <= rd_clk_wr_addrs(i);
                end if;
            end loop;
            rd_data_valid_o <= ram_data_valid(to_integer(unsigned(internal_read_channel)));
            data_o <= internal_output_data(to_integer(unsigned(internal_read_channel)));
        else
            rd_ens <= (others=>'0');
            rd_data_valid_o <= '0';
            data_o <= (others=>'1');
            for i in 0 to NUM_CHANNELS-1 loop
                rd_addrs(i) <= rd_clk_wr_addrs(i);
            end loop;
        end if;
        
        if rising_edge(rd_clk_i) then
            internal_read_channel <= rd_channel_i;

            rd_clk_wr_finished(0) <= wr_finished_o;
            rd_clk_wr_finished(1) <= rd_clk_wr_finished(0);
            
        end if;
        
        /*
         --clocked output data is not the way since it incurs a clock cycle of delay to move through modules. as long as the assigns above meet timing we don't need to do this
        if rst_i = '1' then
            rd_ens <= (others=>'0');
            internal_read_channel <= (others=>'0');
            internal_read_block <= (others=>'0');

            rd_addrs <= (others=>(others=>'0'));
            rd_data_valid_o <= '0';
            data_o <= (others=>'0');
            internal_output_data <= (others=>(others=>'0'));

        elsif rising_edge(rd_clk_i) then
            
            -- some of these should be unclocked if I'm just passing already clocked signals
            internal_read_block <= rd_block_i;
            if rd_en_i='1' and unsigned(rd_channel_i)>=0 and unsigned(rd_channel_i)<=23 then
                internal_read_channel <= rd_channel_i;
                rd_ens(to_integer(unsigned(rd_channel_i))) <= '1';
                rd_addrs(to_integer(unsigned(rd_channel_i))) <= rd_clk_wr_addrs(to_integer(unsigned(rd_channel_i))) + unsigned(internal_read_block); -- can roll over but that's ok

            else
                rd_ens <= (others=> '0');
                rd_addrs <= (others=>(others=>'0'));
            end if;

            if ram_data_valid(to_integer(unsigned(internal_read_channel)))='1' then
                rd_data_valid_o <= '1';
                data_o <= internal_output_data(to_integer(unsigned(rd_channel_i)));
            else
                rd_data_valid_o <= '0';
                data_o <= NULL_DATA;
            end if;

        end if;
        */

    end process;

    -- cdc signal sync for where the first block of reads happen. rd addr should be held long enough before readout that a simple ff sync from fast to slow is ok
    SYNC_WR_ADDR : for ch in 0 to NUM_CHANNELS-1 generate
        SYNC_WR_ADDR_BITS : for i in 0 to ADDR_DEPTH-1 generate
            ADDR_SYNC : signal_sync
            port map(
                clkA	=> wr_clk_i,
                clkB	=> rd_clk_i,
                SignalIn_clkA	=> final_wr_addrs(ch)(i),
                SignalOut_clkB	=> rd_clk_wr_addrs(ch)(i)
            );
        end generate;
    end generate;

end rtl;

