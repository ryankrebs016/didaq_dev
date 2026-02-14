echo "running beamformed trigger testbench, hiding stdout"
ghdl -r --std=08 simple_beamformed_trigger_tb --stop-time=8192ns #> /dev/null