-- simple handshake syncronizer for one directional input data that is held for a long time (only occasionally changes)
-- so we won't care about data changing while transaction happens. thinking this should be used for thresholds and other
-- trigger control bus signals?

library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.defs.all;

entity handshake_sync is
generic(
        port_width : integer := 8
		);

port(
        rst_i : in std_logic;
        clk_a : in std_logic;
        clk_a_data : in std_logic_vector(port_width-1 downto 0);

        clk_b : in std_logic;
        clk_b_data : out std_logic_vector(port_width-1 downto 0)

		);
end handshake_sync;

architecture rtl of handshake_sync is

    signal last_req : std_logic := '0';
    signal req : std_logic_vector(2 downto 0) := (others=>'0');
    signal ack : std_logic_vector(2 downto 0) := (others=>'0');
    signal in_data : std_logic_vector(port_width-1 downto 0) := (others=>'0');

begin

    process(rst_i, clk_a)
    begin
        if rst_i = '1' then
            req(0) <= '0';
            last_req <= '0';
            ack(2 downto 1) <= "00";
            in_data <= (others=>'0');

        elsif rising_edge(clk_a) then
            last_req <= req(0);
            ack(1) <= ack(0);
            ack(2) <= ack(1);

            -- if transaction finished drop req
            if ack(2) = '1' then
                req(0) <= '0';

            -- if new data or req has started, keep holding req
            elsif clk_a_data /= in_data or req(0) = '1' then
                req(0) <= '1';

                -- hold data from when data first changed
                if last_req = '0' then
                    in_data <= clk_a_data;
                end if;
            end if;

        end if;
    end process;

    process(rst_i, clk_b)
    begin
        if rst_i = '1' then
            ack(0) <= '0';
            req(2 downto 1) <= "00";
            clk_b_data <= (others=>'0');

        elsif rising_edge(clk_b) then
            req(1) <= req(0);
            req(2) <= req(1);

            -- good data so grab it and send ack
            if req(2) = '1' then
                clk_b_data <= in_data;
                ack(0) <= '1';
            else
                ack(0) <= '0';
            end if;
        end if;
    end process;
end rtl;