`timescale 1ns/1ps
// Self-checking testbench for PUYO_TOP. Stimulus/golden from dat/*.dat (tools/gen_pattern.py).
module PATTERN (
    output reg       clk,
    output reg       rst_n,
    output reg       in_valid,
    output reg [2:0] in_cell,
    output reg [2:0] in_puyo_a,
    output reg [2:0] in_puyo_b,
    input            out_valid,
    input      [4:0] out_best_candidate,
    input      [4:0] out_chain,
    input      [6:0] out_erased
);
parameter CYCLE = 20.0;
parameter MAX_LAT = 200;
integer NPAT;

reg [2:0] in_mem   [0:100000];
reg [7:0] gold_mem [0:100000];

integer p, i, lat, maxlat, errs, gap, fd;
reg [4:0] g_cand, g_chain;
reg [6:0] g_erased;

always #(CYCLE/2.0) clk = ~clk;

initial begin
    fd = $fopen("dat/ntop.txt", "r");
    if (fd == 0) fd = $fopen("01_RTL/dat/ntop.txt", "r");
    i = $fscanf(fd, "%d", NPAT);
    $fclose(fd);
    $readmemh("dat/top_in.dat",   in_mem);
    $readmemh("dat/top_gold.dat", gold_mem);
    clk = 0; rst_n = 1; in_valid = 0;
    in_cell = 3'bx; in_puyo_a = 3'bx; in_puyo_b = 3'bx;
    errs = 0; maxlat = 0;
    #(CYCLE*0.7) rst_n = 0;
    #(CYCLE*2.3);
    if (out_valid !== 0 || out_best_candidate !== 0 || out_chain !== 0 || out_erased !== 0) begin
        $display("FAIL: outputs not zero after reset"); errs = errs + 1;
    end
    rst_n = 1;
    repeat (2) @(negedge clk);

    for (p = 0; p < NPAT; p = p + 1) begin
        // stream 72 cells, applied on negedge
        for (i = 0; i < 72; i = i + 1) begin
            in_valid  = 1;
            in_cell   = in_mem[p*74 + 2 + i];
            in_puyo_a = (i == 0) ? in_mem[p*74]     : 3'bx;
            in_puyo_b = (i == 0) ? in_mem[p*74 + 1] : 3'bx;
            @(negedge clk);
        end
        in_valid = 0; in_cell = 3'bx; in_puyo_a = 3'bx; in_puyo_b = 3'bx;
        // wait for out_valid, count latency
        lat = 0;
        while (out_valid !== 1'b1 && lat <= MAX_LAT) begin
            @(negedge clk);
            lat = lat + 1;
        end
        if (out_valid !== 1'b1) begin
            $display("FAIL pattern %0d: latency exceeds %0d", p, MAX_LAT); $finish;
        end
        if (lat > maxlat) maxlat = lat;
        g_cand = gold_mem[p*3]; g_chain = gold_mem[p*3+1]; g_erased = gold_mem[p*3+2];
        if (out_best_candidate !== g_cand || out_chain !== g_chain || out_erased !== g_erased) begin
            errs = errs + 1;
            $display("FAIL pattern %0d: got cand=%0d chain=%0d erased=%0d, expected cand=%0d chain=%0d erased=%0d",
                     p, out_best_candidate, out_chain, out_erased, g_cand, g_chain, g_erased);
            if (errs > 5) $finish;
        end
        @(negedge clk);
        if (out_valid !== 1'b0) begin
            $display("FAIL pattern %0d: out_valid longer than one cycle", p); errs = errs + 1;
        end
        gap = 2 + (p % 5);
        repeat (gap) @(negedge clk);
    end
    if (errs == 0) begin
        $display("==================================================");
        $display(" TOP PASS: %0d patterns, max latency = %0d cycles", NPAT, maxlat);
        $display("==================================================");
    end else $display("TOP FAILED with %0d errors", errs);
    $finish;
end

// out_valid must never be high while in_valid is high
always @(posedge clk) if (in_valid && out_valid === 1'b1) begin
    $display("FAIL: out_valid asserted while in_valid is high"); errs = errs + 1;
end
endmodule
