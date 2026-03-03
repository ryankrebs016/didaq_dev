echo "running beamformed power trigger testbench, hiding stdout"
ghdl -r --std=08 trigger_tb --stop-time=8192ns #> /dev/null