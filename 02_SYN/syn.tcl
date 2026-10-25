#======================================================
#
# Synopsys Synthesis Scripts (Design Vision dctcl mode)
#
#======================================================

#======================================================
#  Global Parameters
#======================================================
sh mkdir -p Netlist
set DESIGN       "PUYO_TOP"
set CYCLE        3.0
set INPUT_DLY    [expr 0.5 * $CYCLE]
set OUTPUT_DLY   [expr 0.5 * $CYCLE]
set OUTPUT_LOAD  0.05

#======================================================
#  Read RTL Code
#======================================================
analyze -format verilog { ../01_RTL/PUYO_SOFT_IP.v ../01_RTL/PUYO_TOP.v }
elaborate $DESIGN
current_design $DESIGN
link

#======================================================
#  Global Setting
#======================================================
set_wire_load_mode top

#======================================================
#  Set Design Constraints
#======================================================
create_clock -name clk -period $CYCLE [get_ports clk]
set_dont_touch_network [get_clocks clk]
set_ideal_network      [get_ports clk]
set_clock_uncertainty  0.1 [get_clocks clk]

set_input_delay  0 -clock clk [get_ports {clk rst_n}]
set_input_delay  $INPUT_DLY -clock clk [remove_from_collection [all_inputs] [get_ports {clk rst_n}]]
set_output_delay $OUTPUT_DLY -clock clk [all_outputs]
set_load         $OUTPUT_LOAD [all_outputs]

#======================================================
#  Optimization
#======================================================
check_design
compile_ultra

#======================================================
#  Output Reports
#======================================================
report_area   > ${DESIGN}.area
report_timing > ${DESIGN}.timing
report_qor    > ${DESIGN}.qor

#======================================================
#  Change Naming Rule
#======================================================
set bus_inference_style {%s[%d]}
set bus_naming_style {%s[%d]}
set hdlout_internal_busses true
change_names -hierarchy -rule verilog
define_name_rules name_rule -allowed {a-z A-Z 0-9 _} -max_length 255 -type cell
define_name_rules name_rule -allowed {a-z A-Z 0-9 _[]} -max_length 255 -type net
define_name_rules name_rule -map {{"\\*cell\\*" "cell"}}
change_names -hierarchy -rules name_rule

#======================================================
#  Output Results
#======================================================
set verilogout_no_tri true
write -format verilog -hierarchy -output Netlist/${DESIGN}_SYN.v
write_sdf -version 3.0 -context verilog Netlist/${DESIGN}_SYN.sdf

#======================================================
#  Finish and Quit
#======================================================
exit
