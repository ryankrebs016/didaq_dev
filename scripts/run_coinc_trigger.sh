echo "running trigger testbench, hiding stdout"
ghdl -r --std=08 coinc_trigger_tb --stop-time=8192ns #> /dev/null