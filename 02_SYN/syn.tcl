# Draft synthesis script for PUYO_TOP (spec items 17-26).
# NOTE: written without access to Design Compiler or the course library; it has NOT been run.
# Library / search-path setup is expected to come from the course .synopsys_dc.setup.

set DESIGN   "PUYO_TOP"
set CYCLE    1.4                       ;# clock period in ns, one decimal digit (spec: <= 20.0)
set INPUT_DLY  [expr 0.5 * $CYCLE]
set OUTPUT_DLY [expr 0.5 * $CYCLE]
set OUTPUT_LOAD 0.05

sh mkdir -p Netlist
sh mkdir -p Report

# ---- read the design with analyze + elaborate
analyze -format verilog { ../01_RTL/PUYO_SOFT_IP.v ../01_RTL/PUYO_TOP.v }
elaborate $DESIGN
current_design $DESIGN
link

# ---- wire load model: top
set_wire_load_mode top

# ---- constraints
create_clock -name clk -period $CYCLE [get_ports clk]
set_dont_touch_network [get_clocks clk]
set_ideal_network      [get_ports clk]
set_clock_uncertainty  0.1 [get_clocks clk]

set_input_delay 0 -clock clk [get_ports {clk rst_n}]
set_input_delay $INPUT_DLY -clock clk [remove_from_collection [all_inputs] [get_ports {clk rst_n}]]
set_output_delay $OUTPUT_DLY -clock clk [all_outputs]
set_load $OUTPUT_LOAD [all_outputs]

# ---- compile
compile_ultra

# ---- reports and netlist
report_area   > Report/${DESIGN}.area
report_timing > Report/${DESIGN}.timing
check_design  > Report/${DESIGN}.check
write -format verilog -hierarchy -output Netlist/${DESIGN}_SYN.v
write_sdf -version 3.0 Netlist/${DESIGN}_SYN.sdf
exit
