`timescale 1ns/1ps
module TESTBED;
wire clk, rst_n, in_valid, out_valid;
wire [2:0] in_cell, in_puyo_a, in_puyo_b;
wire [4:0] out_best_candidate, out_chain;
wire [6:0] out_erased;
PUYO_TOP u_dut (.clk(clk), .rst_n(rst_n), .in_valid(in_valid), .in_cell(in_cell),
    .in_puyo_a(in_puyo_a), .in_puyo_b(in_puyo_b), .out_valid(out_valid),
    .out_best_candidate(out_best_candidate), .out_chain(out_chain), .out_erased(out_erased));
PATTERN u_pat (.clk(clk), .rst_n(rst_n), .in_valid(in_valid), .in_cell(in_cell),
    .in_puyo_a(in_puyo_a), .in_puyo_b(in_puyo_b), .out_valid(out_valid),
    .out_best_candidate(out_best_candidate), .out_chain(out_chain), .out_erased(out_erased));
endmodule
