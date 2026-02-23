-- simple dual port ram to store a single channel's data
-- exclusive write in, read out --- single clock write, single clock read
--
-- a single M20k should be able to fit a single channel's buffer
-- 8bit*4samples*512depth = 16384 bits < 20kbits
-- 9bit*4samples*512depth = 18432 bits < 20kbits
--
--
-- 512 depth is 2us buffer length
-- 32 bit words or 36 bit words should be allowed with the M20k
-- depths of up to 512 are allowed for both
-- I think data sheet says so?

-- https://www.mouser.com/datasheet/2/612/Intel_Corporation_ug_762191_762192_1-3441117.pdf
-- from agilex 5 e series datasheet pg 23 "512x40 (or x32)"


library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.defs.all;

entity single_channel_ram is
    generic(
        SAMPLE_LENGTH : integer := 8; -- or 9
        NUM_SAMPLES : integer := 4;
        ADDR_DEPTH : integer := 9 -- (2^9-1)*num_samples length buffer, default 2048 samples
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
end single_channel_ram;
 
architecture rtl of single_channel_ram is
    type mem is array(2**ADDR_DEPTH-1 downto 0) of std_logic_vector(SAMPLE_LENGTH*NUM_SAMPLES-1 downto 0);
    signal mem_blk : mem := (others=>(others=>'0'));

-- this is basically a behavioral template for simple dual port ram. verify this synthesizes as BRAM
begin
    a_side : process(A_clk_i) begin
        if rising_edge(A_clk_i) then
            if A_en_i = '1' then 
                mem_blk(to_integer(unsigned(A_addr_i))) <= A_data_i;
            end if;
        end if;
    end process;

    b_side : process(B_clk_i, rst_i) begin
        if rst_i = '1' then
            B_data_o <= (others=>'0');
            B_valid_o <= '0';

        elsif rising_edge(B_clk_i) then
            if B_en_i = '1' then
                B_valid_o <= '1';
                B_data_o <= mem_blk(to_integer(unsigned(B_addr_i)));
            else
                B_valid_o <= '0';
                B_data_o <= (others=>'0');
            end if;
        end if;
    end process;
end rtl;