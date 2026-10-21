// Puyo Puyo Placement Solver - v2: two-stage pipeline, two candidates in flight.
//   stage A : PUYO_SOFT_IP on the board in bA          -> registers (bB, mB)
//   stage B : erase + gravity, accumulate, compare     -> bA (next round) or a freshly issued candidate
// The two contexts swap A <-> B every cycle, so both stages are busy every cycle.
module PUYO_TOP (
    input        clk,
    input        rst_n,
    input        in_valid,
    input  [2:0] in_cell,
    input  [2:0] in_puyo_a,
    input  [2:0] in_puyo_b,
    output reg       out_valid,
    output reg [4:0] out_best_candidate,
    output reg [4:0] out_chain,
    output reg [6:0] out_erased
);

localparam W = 6;
localparam H = 12;
localparam N = W * H;

// ------------------------------------------------------------ load
reg [N*3-1:0] base;
reg [3:0]     hgt [0:W-1];
reg [W-1:0]   ring;
reg [3:0]     rcnt;
reg [2:0]     pa, pb;
reg           first_cell;
reg           start;
reg           run;           // candidates are being evaluated

wire last_cell = in_valid && ring[W-1] && (rcnt == 4'd11);
wire fin;

integer ci;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        base <= {N*3{1'b0}};
        ring <= 6'b000001;
        rcnt <= 4'd0;
        pa <= 3'd0; pb <= 3'd0;
        first_cell <= 1'b1;
        start <= 1'b0;
        for (ci = 0; ci < W; ci = ci + 1) hgt[ci] <= 4'd0;
    end else begin
        start <= 1'b0;
        if (in_valid) begin
            base <= {in_cell, base[N*3-1:3]};
            if (first_cell) begin
                pa <= in_puyo_a;
                pb <= in_puyo_b;
                first_cell <= 1'b0;
            end
            ring <= {ring[W-2:0], ring[W-1]};
            if (ring[W-1]) rcnt <= (rcnt == 4'd11) ? 4'd0 : rcnt + 4'd1;
            for (ci = 0; ci < W; ci = ci + 1)
                if (ring[ci] && in_cell != 3'd0) hgt[ci] <= hgt[ci] + 4'd1;
            if (last_cell) start <= 1'b1;
        end
        if (fin) begin
            first_cell <= 1'b1;
            for (ci = 0; ci < W; ci = ci + 1) hgt[ci] <= 4'd0;
        end
    end
end

// ------------------------------------------------------------ candidate selection
reg [21:0] pend;
reg [21:0] legal;
always @(*) begin
    for (ci = 0; ci < W; ci = ci + 1) begin
        legal[ci]    = (hgt[ci] <= 4'd10);
        legal[ci+6]  = (hgt[ci] <= 4'd10);
    end
    for (ci = 0; ci < W-1; ci = ci + 1) begin
        legal[ci+12] = (hgt[ci] != 4'd12) && (hgt[ci+1] != 4'd12);
        legal[ci+17] = (hgt[ci] != 4'd12) && (hgt[ci+1] != 4'd12);
    end
end

wire [21:0] sel_vec  = start ? legal : pend;
wire [21:0] sel_rest = sel_vec & (sel_vec - 22'd1);
reg  [4:0]  nid;
integer qi;
always @(*) begin
    nid = 5'd0;
    for (qi = 21; qi >= 0; qi = qi - 1)
        if (sel_vec[qi]) nid = qi[4:0];
end

// ------------------------------------------------------------ placement of candidate nid
reg [2:0] lo_val [0:W-1];
reg [2:0] hi_val [0:W-1];
reg [W-1:0] lo_en, hi_en;
reg [4:0] lcol;
reg [N*3-1:0] placed;
integer pc, pj;
always @(*) begin
    lo_en = 6'd0; hi_en = 6'd0;
    for (pc = 0; pc < W; pc = pc + 1) begin lo_val[pc] = 3'd0; hi_val[pc] = 3'd0; end
    lcol = 5'd0;
    if (nid < 5'd6) begin
        lo_en[nid[2:0]] = 1'b1; lo_val[nid[2:0]] = pb;
        hi_en[nid[2:0]] = 1'b1; hi_val[nid[2:0]] = pa;
    end else if (nid < 5'd12) begin
        lcol = nid - 5'd6;
        lo_en[lcol[2:0]] = 1'b1; lo_val[lcol[2:0]] = pa;
        hi_en[lcol[2:0]] = 1'b1; hi_val[lcol[2:0]] = pb;
    end else if (nid < 5'd17) begin
        lcol = nid - 5'd12;
        lo_en[lcol[2:0]] = 1'b1;        lo_val[lcol[2:0]]        = pa;
        lo_en[lcol[2:0] + 3'd1] = 1'b1; lo_val[lcol[2:0] + 3'd1] = pb;
    end else begin
        lcol = nid - 5'd17;
        lo_en[lcol[2:0]] = 1'b1;        lo_val[lcol[2:0]]        = pb;
        lo_en[lcol[2:0] + 3'd1] = 1'b1; lo_val[lcol[2:0] + 3'd1] = pa;
    end
    for (pc = 0; pc < W; pc = pc + 1)
        for (pj = 0; pj < H; pj = pj + 1) begin
            if (lo_en[pc] && hgt[pc] == pj)
                placed[3*((H-1-pj)*W + pc) +: 3] = lo_val[pc];
            else if (hi_en[pc] && (hgt[pc] + 4'd1) == pj)
                placed[3*((H-1-pj)*W + pc) +: 3] = hi_val[pc];
            else
                placed[3*((H-1-pj)*W + pc) +: 3] = base[3*((H-1-pj)*W + pc) +: 3];
        end
end

// ------------------------------------------------------------ pipeline
reg [N*3-1:0] bA, bB;
reg [N-1:0]   mB;
reg           vA, vB;
reg [4:0]     cA, cB, chA, chB;
reg [4*W-1:0] ecA, ecB;          // erased so far, per column
reg [14:0]    sB;                // pair sums of ecA, formed in stage A

wire [N-1:0]   mA;
wire [N*3-1:0] gB;
wire [6:0]     unused_num;
wire [4*W-1:0] ccB;

PUYO_SOFT_IP #(.WIDTH(W), .HEIGHT(H), .COUNT_EN(0)) u_soft_ip (
    .board_in  (bA),
    .erase_mask(mA),
    .erase_num (unused_num)
);

PUYO_GRAV #(.W(W), .H(H)) u_grav (
    .board  (bB),
    .mask   (mB),
    .board_n(gB),
    .cc     (ccB)
);

wire anyB  = |mB;
wire contB = vB && anyB;
wire doneB = vB && !anyB;

wire [4:0] sA0 = ecA[3:0]   + ecA[7:4];
wire [4:0] sA1 = ecA[11:8]  + ecA[15:12];
wire [4:0] sA2 = ecA[19:16] + ecA[23:20];
wire [6:0] totB = sB[4:0] + sB[9:5] + sB[14:10];
wire [4*W-1:0] ecN;
genvar gq;
generate
    for (gq = 0; gq < W; gq = gq + 1) begin : g_ec
        assign ecN[4*gq +: 4] = ecB[4*gq +: 4] + ccB[4*gq +: 4];
    end
endgenerate

wire more   = |sel_vec;
wire issue  = (start || run) && !contB && more;
assign fin  = doneB && !more && !vA;

// best-candidate compare (candidates finish out of order, so the id breaks ties)
reg        have_best;
reg        r_vld, r_last;
reg [4:0]  r_ch, r_id;
reg [6:0]  r_tot;
wire better = !have_best || (r_ch > out_chain) ||
              (r_ch == out_chain && r_tot > out_erased) ||
              (r_ch == out_chain && r_tot == out_erased && r_id < out_best_candidate);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        run <= 1'b0;
        pend <= 22'd0;
        bA <= {N*3{1'b0}}; bB <= {N*3{1'b0}}; mB <= {N{1'b0}};
        vA <= 1'b0; vB <= 1'b0;
        cA <= 5'd0; cB <= 5'd0; chA <= 5'd0; chB <= 5'd0; ecA <= {4*W{1'b0}}; ecB <= {4*W{1'b0}}; sB <= 15'd0;
        r_vld <= 1'b0; r_last <= 1'b0; r_ch <= 5'd0; r_id <= 5'd0; r_tot <= 7'd0;
        have_best <= 1'b0;
        out_valid <= 1'b0; out_best_candidate <= 5'd0; out_chain <= 5'd0; out_erased <= 7'd0;
    end else begin
        out_valid <= 1'b0;
        // stage A -> B
        bB <= bA; mB <= mA; vB <= vA; cB <= cA; chB <= chA; ecB <= ecA; sB <= {sA2, sA1, sA0};
        // stage B -> A (next round of the same candidate, or a newly issued one)
        if (contB) begin
            bA <= gB; vA <= 1'b1; cA <= cB; chA <= chB + 5'd1; ecA <= ecN;
        end else if (issue) begin
            bA <= placed; vA <= 1'b1; cA <= nid; chA <= 5'd0; ecA <= {4*W{1'b0}};
            pend <= sel_rest;
        end else begin
            vA <= 1'b0;
        end
        if (start) begin
            run <= 1'b1;
            have_best <= 1'b0;
            out_best_candidate <= 5'd0; out_chain <= 5'd0; out_erased <= 7'd0;
        end
        // result stage: total erased, then compare
        r_vld <= doneB; r_last <= fin; r_ch <= chB; r_id <= cB; r_tot <= totB;
        if (r_vld) begin
            if (better) begin
                have_best <= 1'b1;
                out_best_candidate <= r_id;
                out_chain <= r_ch;
                out_erased <= r_tot;
            end
            if (r_last) out_valid <= 1'b1;
        end
        if (fin) run <= 1'b0;
    end
end

endmodule
