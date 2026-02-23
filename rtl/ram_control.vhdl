-- ram control for the write side state machine so writes are channel dependent with variable post trigger times
-- this replaces the first stage fifo for a fraction of the size
-- in the normal flow, enable goes high and then ram enable goes high, trigger happens, then ram enable goes low, then waits for the rd finished or reset signal to restart ram writing

library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.defs.all;

entity ram_control is
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
        
        soft_reset_i : in std_logic; -- force clear from software
        wr_clk_rd_done_i : in std_logic; -- signal to reset the state machine

        wr_en_o : out std_logic; -- output signal to pass to the ram to control active writing
        wr_finished_o   : out std_logic -- write finished signal when write is complete

    );
end ram_control;

architecture rtl of ram_control is

    -- write  clock stuff

    signal wr_en : std_logic := '0';
    signal wr_busy : std_logic := '0';

    signal count_wr_addrs : unsigned(32 downto 0) := (others=>'0');

    signal full_buffer_write : std_logic :='0';

    signal trigger : std_logic := '0';
    signal trigger_last : std_logic := '0';
    signal queue_trigger : std_logic := '0';

    signal post_trigger_clks : unsigned(9 downto 0) := (others=>'0');  
    signal post_trigger_wait_clks : unsigned(9 downto 0) := "0000000000"; --read in from regs, maybe trig dep so need to port in
   
    signal buffer_writing_counts : unsigned(9 downto 0) := (others=>'0');

    type wr_state_t is (wait_wr, wr, wr_to_end, rd_busy);
    signal data_state : wr_state_t := wait_wr;


begin

    proc_write_state_machine : process(rst_i, wr_clk_i)
    begin
        if rst_i = '1' then
            data_state <= wait_wr;
            trigger <= '0';
            trigger_last <= '0';
            count_wr_addrs <= (others=>'0');
            wr_finished_o <= '0';
            queue_trigger <= '0';
            wr_en <= '0';
            full_buffer_write <= '0';
            post_trigger_clks <= (others=>'0');

        elsif rising_edge(wr_clk_i) then
            
            -- this state machine needs to be done for each channel if we want channel specific holdoffs. otherwise global signals will
            -- wait until the last channel is written
            case data_state is 

                when wait_wr =>
                    -- do nothing until wr is enabled 
                    wr_finished_o <= '0';
                    queue_trigger <= '0';
                    trigger <= '0';
                    trigger_last <= '0';
                    count_wr_addrs <= (others=>'0');
                    wr_en<='0';
                    full_buffer_write <= '0';
                    post_trigger_clks<=(others=>'0'); -- reset post trigger counter on state buffer it's used
                    if wr_en_i then 
                        data_state <= wr;
                        wr_en <= '1'; -- astart writing here to reduce 1 clock state change

                    end if;

                when wr =>
                    if soft_reset_i then
                        data_state <= wait_wr;
                    else
                        -- start the write address counter once enables are on
                        if wr_en then
                            count_wr_addrs <= count_wr_addrs + 1;
                        end if;

                        -- only care about triggers now
                        trigger <= trigger_i;
                        --trigger_last <= trigger;

                        -- enable write
                        wr_en <= '1';

                        -- first instance of a trigger pulse -- this looks a lot like a another state machine => refactoring needed
                        if trigger_i and (not trigger) and (not queue_trigger) then
                            -- latch post trigger clks to first trigger instance of event make sure full buffer signal is low
                            -- and sync to the trigger signal coming in
                            post_trigger_wait_clks <= unsigned(post_trigger_wait_clks_i(9 downto 0));
                            queue_trigger <= '1';
                            full_buffer_write <= '0';

                        --  queued trigger so wait until ram is nearly finished so ram is filled with new data
                        elsif queue_trigger then

                            -- careful post_trigger_wait_clks doesn't become bigger than the trace length (lim to 511), but it latches so maybe ok
                            -- only check during a queued trigger so we know what the valid post trigger wait clks is, if it's const we can move outside queued triggered
                            if count_wr_addrs >= 2**ADDR_DEPTH-1-post_trigger_wait_clks-1 then
                                full_buffer_write <= '1';
                                data_state <= wr_to_end;
                            end if;

                        -- no trigger yet so keep full buffer low
                        else
                            full_buffer_write <= '0';
                        end if;
                    end if;

                when wr_to_end =>

                    if soft_reset_i then
                        data_state <= wait_wr;
                    else
                        -- write to addresses until write enable de asserted
                        if wr_en then
                            post_trigger_clks <= post_trigger_clks+1;
                        end if;

                        -- be careful here, this can overflow if post trigger clks is bigger than 512, shouldn't be an issue once wr_ens de asserted
                        if post_trigger_clks >= post_trigger_wait_clks then
                            data_state <= rd_busy;
                            wr_en <='0';
                            wr_finished_o <= '1';
                        end if;
                    end if;

                when rd_busy =>
                    if wr_clk_rd_done_i or soft_reset_i then
                        data_state <= wait_wr;
                    end if;
            end case;
        end if;
    end process;

    wr_en_o <= wr_en;
end rtl;

