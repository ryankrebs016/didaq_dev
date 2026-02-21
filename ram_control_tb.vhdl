library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
--use ieee.std_logic_textio.all;

use work.defs.all;
use work.all;

entity ram_control_tb is
end ram_control_tb;

architecture behave of ram_control_tb is
-----------------------------------------------------------------------------
-- Declare the Component Under Test
-----------------------------------------------------------------------------
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
        soft_reset_i : in std_logic;

        wr_clk_rd_done_i : in std_logic; -- signal to reset the state machine
        wr_en_o : out std_logic; -- output signal to pass to the ram to control active writing
        wr_finished_o   : out std_logic -- write finished signal when write is complete

    );
end component;

-----------------------------------------------------------------------------
-- Testbench Internal Signals
-----------------------------------------------------------------------------
signal clock : std_logic := '1';
signal rst : std_logic := '0';
signal soft_reset : std_logic := '0';
type thresholds_t is array(NUM_CHANNELS-1 downto 0) of std_logic_vector(7 downto 0);
signal enable: std_logic := '0';
signal trigger : std_logic := '0';
signal post_trigger_wait_clks : std_logic_vector(9 downto 0) := "0010000000"; --(others=>'0');
signal wr_clk_rd_done : std_logic := '0';
signal ram_enable : std_logic := '0';
signal wr_finished : std_logic := '0';
signal clock_counter : unsigned(31 downto 0) := (others=>'0');
--signal wait_rd_counter : unsigned(31 downto 0) := x"00000200";
signal wait_rd_counter : unsigned(31 downto 0) := x"00000001";

constant where_trigger : integer := 600;
signal do_loop : std_logic := '1';

constant header : string :=  "clk_counter enable_i trigger_i ram_enable wr_finished_o wr_clk_rd_done_i";


begin

    clock <= not clock after 2 ns;
    -----------------------------------------------------------------------------
    -- Instantiate and Map UUT
    -----------------------------------------------------------------------------
    ram_control_inst : ram_control
    port map(
        rst_i => rst,
        wr_clk_i => clock,
        wr_en_i => enable,
        trigger_i => trigger,
        soft_reset_i => soft_reset,
        post_trigger_wait_clks_i => post_trigger_wait_clks,
        wr_clk_rd_done_i => wr_clk_rd_done,
        wr_en_o => ram_enable,
        wr_finished_o => wr_finished
    );


    process

        --variable v_ILINE     : line;
        variable v_OLINE     : line;
        variable v_SPACE     : character;

        --file file_INPUT : text;-- open read_mode is "input_waveforms.txt";
        --file file_THRESHOLDS : text;-- open read_mode is "input_thresholds.txt";
        --file file_TRIGGERS : text;-- open write_mode is "output_trigger.txt";

        file file_output : text;

        begin

            file_open(file_output, "data/ram_tb.txt", write_mode);
            write(v_OLINE,header, right, header'length);
            writeline(file_output,v_OLINE);
            while do_loop loop
                wait for 4 ns; --about 1/118e6 ns, one full clock cycle


                clock_counter <= clock_counter +1;

                if clock_counter >50 and clock_counter<where_trigger then
                    enable <='1';
                elsif clock_counter >= where_trigger+1 then
                    enable <= '0';
                else
                    enable <= '0';
                end if;

                if clock_counter = where_trigger then
                    trigger <= '1';
                else
                    trigger <= '0';
                end if;

                if clock_counter = 1000 then
                    wr_clk_rd_done <= '1';
                else
                    wr_clk_rd_done <= '0';
                end if;

                --io files
                --file_open(file_INPUT, "data/input_waveforms.txt", read_mode);
                --file_open(file_THRESHOLDS, "data/input_channel_thresholds.txt", read_mode);
                --file_open(file_TRIGGERS, "data/output_trigger.txt", write_mode);

                

                --write(v_OLINE,ch_samples(31 downto 0),right,32);
                --writeline(output,v_OLINE);

                write(v_OLINE,clock_counter,right,32);
                write(v_OLINE,' ');

                write(v_OLINE,enable,right,1);
                write(v_OLINE,' ');

                write(v_OLINE,trigger,right,1);
                write(v_OLINE, ' ');

                write(v_OLINE,ram_enable,right,1);
                write(v_OLINE, ' ');

                write(v_OLINE,wr_finished,right,1);
                write(v_OLINE, ' ');

                write(v_OLINE,wr_clk_rd_done,right,1);
                write(v_OLINE, ' ');





                writeline(file_output,v_OLINE);

                --write(v_OLINE,trig,right,1);
                --writeline(file_TRIGGERS, v_OLINE);

            end loop;

            file_close(file_output);

            wait;

        end process;

end behave;