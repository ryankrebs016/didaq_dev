
rm work-obj08.cf
echo "compiliing defs"
ghdl -a --std=08 rtl/defs.vhd

echo "compiling signal sync"
ghdl -a --std=08 rtl/signal_sync.vhdl

echo "compiling handshake sync"
ghdl -a --std=08 rtl/handshake_sync.vhdl

echo "compiliing beamforming"
ghdl -a --std=08 rtl/beamforming.vhdl

#echo "compiling power lut"
#ghdl -a --std=08 power_lut_8.vhdl

#echo "compiling power integration"
#ghdl -a --std=08 power_integration.vhdl

#echo "compiling power trigger"
#ghdl -a --std=08 power_trigger.vhd

echo "compiling surface trigger"
ghdl -a --std=08 rtl/simple_trigger.vhd

echo "compiling simple beamformed trigger"
ghdl -a --std=08 rtl/simple_beamformed_trigger.vhd

#echo "compiliing wave tb"
#ghdl -a --std=08 wave_tb.vhdl
#ghdl -e --std=08 wave_tb

echo "compiling trigger testbench, scalers not implemented"
ghdl -a --std=08 tb/simple_trigger_tb.vhdl
ghdl -e --std=08 simple_trigger_tb

echo "compiling simple beamformed trigger tesbench"
ghdl -a --std=08 tb/simple_beamformed_trigger_tb.vhdl
ghdl -e --std=08 simple_beamformed_trigger_tb

#echo "compiliing trigger testbench, scalers not implemented"
#ghdl -a --std=08 trigger_tb.vhdl
#ghdl -e --std=08 trigger_tb
