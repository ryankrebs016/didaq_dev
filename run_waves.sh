cd ..
echo "running wave testbench, hiding stdout"
echo "" > tb/data/output_trigger.txt

ghdl -r --std=08 wave_tb --stop-time=2170ns > /dev/null
cd tb
