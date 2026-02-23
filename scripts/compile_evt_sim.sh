
rm work-obj08.cf
echo "compiling defs"
ghdl -a --std=08 rtl/defs.vhd

echo "compiling signal sync"
ghdl -a --std=08 rtl/signal_sync.vhdl

echo "compiling gps"
ghdl -a --std=08 rtl/gps.vhdl

echo "compiling ram"
ghdl -a --std=08 rtl/single_channel_ram.vhdl

echo "compiling ram controller"
ghdl -a --std=08 rtl/ram_control.vhdl

echo "compiling ram controller tb"
ghdl -a --std=08 tb/ram_control_tb.vhdl
ghdl -e --std=08 ram_control_tb

echo "compiling waveform storage"
ghdl -a --std=08 rtl/waveform_storage.vhdl

echo "compiling waveform tb"
ghdl -a --std=08 tb/waveform_tb.vhdl
ghdl -e --std=08 waveform_tb

echo "compiling single event"
ghdl -a --std=08 rtl/single_event.vhdl

echo "compiling single event tb"
ghdl -a --std=08 tb/single_event_tb.vhdl
ghdl -e --std=08 single_event_tb

echo "compiling event top"
ghdl -a --std=08 rtl/event_top.vhdl

echo "compiling event top tb"
ghdl -a --std=08 tb/event_top_tb.vhdl
ghdl -e --std=08 event_top_tb