library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package defs is
	constant NUM_BEAMS : integer:=12;
	constant NUM_CHANNELS : integer:=24;
	constant NUM_PA_CHANNELS : integer:=4;
	constant SAMPLE_LENGTH : integer:=8;
	constant NUM_SAMPLES : integer :=4;
	constant NUM_EVENTS : integer := 2;
	constant INTERP_FACTOR : interger := 2;
end defs;
