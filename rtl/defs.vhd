library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package defs is

	-- firmware registers defines:
	constant define_address_size	:	integer := 8;
	constant define_register_size	:	integer := 32;

	-- global register type
	type register_array_type is array (255 downto 0) 
		of std_logic_vector(define_register_size-1 downto 0);

	constant NUM_BEAMS : integer:=12;
	constant NUM_CHANNELS : integer:=24;
	constant NUM_PA_CHANNELS : integer:=4;
	constant SAMPLE_LENGTH : integer:=8;
	constant NUM_SAMPLES : integer :=4;
	constant NUM_EVENTS : integer := 2;
end defs;
