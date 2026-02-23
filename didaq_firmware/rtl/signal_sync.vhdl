library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity signal_sync is 
    port(
        clkA :in std_logic;
        clkB:in std_logic;
        signalIn_clkA:in std_logic;
        signalOut_clkB:out std_logic
    );
end signal_sync;

architecture rtl of signal_sync is
    signal regs: std_logic_vector(1 downto 0):="00";

begin

    signalOut_clkB<=regs(1);

    process(clkB)
    begin
        if rising_edge(clkB) then
            regs(0)<=signalIn_clkA;
            regs(1)<=regs(0);
        end if;
    end process;
end rtl;