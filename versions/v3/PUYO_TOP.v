// Puyo Puyo Placement Solver - v3: v2 pipeline + probe filter.
// Every candidate only touches 12 fixed spots (lowest empty cell of each column and the one above).
// Before evaluating candidates, 4 (A!=B) or 5 (A==B) "probe boards" - one piece per column, adjacent
// columns in different colours - go through the same Soft IP.  A candidate whose piece cell is erased
// in a probe may chain (false positives are possible, false negatives are not, because adding pieces
// can only grow groups).  Only flagged candidates are run through the full chain evaluation; every other
// legal candidate has chain = erased = 0, so the lowest legal id is the default answer.
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
reg           run;

wire last_cell = in_valid && ring[W-1] && (rcnt == 4'd11);
wire fin;
wire fin_idle;

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
        if (fin || fin_idle) begin
            first_cell <= 1'b1;
            for (ci = 0; ci < W; ci = ci + 1) hgt[ci] <= 4'd0;
        end
    end
end

// ------------------------------------------------------------ legality
wire        same = (pa == pb);
reg [21:0]  legal;
always @(*) begin
    for (ci = 0; ci < W; ci = ci + 1) begin
        legal[ci]    = (hgt[ci] <= 4'd10);
        legal[ci+6]  = (hgt[ci] <= 4'd10);
    end
    for (ci = 0; ci < W-1; ci = ci + 1) begin
        legal[ci+12] = (hgt[ci] != 4'd12) && (hgt[ci+1] != 4'd12);
        legal[ci+17] = (hgt[ci] != 4'd12) && (hgt[ci+1] != 4'd12);
    end
    // A == B: "B above A" and "B left of A" duplicate "A above B" / "A left of B"
    if (same) legal = legal & 22'h1F03F;
end

// lowest legal id: default answer (chain 0, erased 0)
reg [4:0] low_id;
integer qi;
always @(*) begin
    low_id = 5'd0;
    for (qi = 21; qi >= 0; qi = qi - 1)
        if (legal[qi]) low_id = qi[4:0];
end

// ------------------------------------------------------------ job issue (probe or candidate)
reg [21:0] fl;          // candidates flagged by probes
reg [21:0] issued;
reg [2:0]  pcnt;        // probes issued so far
wire [2:0] npb = same ? 3'd5 : 3'd4;

wire [21:0] avail = fl & legal & ~issued;
wire        has_avail = |avail;
reg  [4:0]  nid;
always @(*) begin
    nid = 5'd0;
    for (qi = 21; qi >= 0; qi = qi - 1)
        if (avail[qi]) nid = qi[4:0];
end

wire        probes_left = (pcnt != npb);
wire        job_is_probe = !has_avail;                 // candidates first, probes fill the gaps
wire [4:0]  job_idx = job_is_probe ? {2'b00, pcnt} : nid;

// placement descriptor: per column a piece on the lowest empty cell (lo) and/or the one above (hi)
reg [2:0]   lo_val [0:W-1];
reg [2:0]   hi_val [0:W-1];
reg [W-1:0] lo_en, hi_en;
reg [4:0]   lcol;
reg [2:0]   pcol;
reg [N*3-1:0] placed;
integer pc, pj;
always @(*) begin
    lo_en = 6'd0; hi_en = 6'd0;
    for (pc = 0; pc < W; pc = pc + 1) begin lo_val[pc] = 3'd0; hi_val[pc] = 3'd0; end
    lcol = 5'd0; pcol = 3'd0;
    if (job_is_probe) begin
        if (!same) begin
            for (pc = 0; pc < W; pc = pc + 1) begin
                pcol = (pc[0] ^ job_idx[0]) ? pb : pa;
                lo_en[pc]  = !job_idx[1];  lo_val[pc] = pcol;
                hi_en[pc]  =  job_idx[1];  hi_val[pc] = pcol;
            end
        end else begin
            for (pc = 0; pc < W; pc = pc + 1) begin
                lo_val[pc] = pa; hi_val[pc] = pa;
                case (job_idx[2:0])
                    3'd0: begin lo_en[pc] = !pc[0]; hi_en[pc] = !pc[0]; end
                    3'd1: begin lo_en[pc] =  pc[0]; hi_en[pc] =  pc[0]; end
                    3'd2: lo_en[pc] = (pc == 0) || (pc == 1) || (pc == 3) || (pc == 4);
                    3'd3: lo_en[pc] = (pc == 1) || (pc == 2) || (pc == 4) || (pc == 5);
                    default: lo_en[pc] = (pc == 2) || (pc == 3);
                endcase
            end
        end
    end else if (nid < 5'd6) begin
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
reg           vA, vB, pA, pB_;           // valid, is-probe
reg [4:0]     cA, cB, chA, chB;
reg [4*W-1:0] ecA, ecB;
reg [14:0]    sB;

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

wire anyB   = |mB;
wire contB  = vB && !pB_ && anyB;
wire candB  = vB && !pB_ && !anyB;       // candidate finished
wire probeB = vB && pB_;

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

// ---- probe result extraction: was the piece on spot lo / hi of column c erased?
reg [W-1:0] e_lo, e_hi;
integer ej;
always @(*) begin
    for (ci = 0; ci < W; ci = ci + 1) begin
        e_lo[ci] = 1'b0; e_hi[ci] = 1'b0;
        for (ej = 0; ej < H; ej = ej + 1) begin
            if (hgt[ci] == ej)                e_lo[ci] = e_lo[ci] | mB[(H-1-ej)*W + ci];
            if ((hgt[ci] + 4'd1) == ej)       e_hi[ci] = e_hi[ci] | mB[(H-1-ej)*W + ci];
        end
    end
end

reg [21:0] fl_set;
integer fc;
always @(*) begin
    fl_set = 22'd0;
    if (!same) begin
        // probes 0/1: lo spots, 2/3: hi spots; bit 0 swaps the colour phase of the columns
        for (fc = 0; fc < W; fc = fc + 1) begin
            // piece colour at column fc in this probe: A if (fc[0] ^ swap) == 0
            if (!cB[1]) begin   // lo probes
                if ((fc[0] ^ cB[0]) == 1'b1) fl_set[fc]   = fl_set[fc]   | e_lo[fc];   // lo piece is B: A-above-B
                else                         fl_set[6+fc] = fl_set[6+fc] | e_lo[fc];   // lo piece is A: B-above-A
            end else begin      // hi probes
                if ((fc[0] ^ cB[0]) == 1'b0) fl_set[fc]   = fl_set[fc]   | e_hi[fc];   // hi piece is A
                else                         fl_set[6+fc] = fl_set[6+fc] | e_hi[fc];   // hi piece is B
            end
        end
        for (fc = 0; fc < W-1; fc = fc + 1) if (!cB[1]) begin
            if ((fc[0] ^ cB[0]) == 1'b0) fl_set[12+fc] = fl_set[12+fc] | e_lo[fc] | e_lo[fc+1];  // A left of B
            else                         fl_set[17+fc] = fl_set[17+fc] | e_lo[fc] | e_lo[fc+1];  // B left of A
        end
    end else begin
        case (cB[2:0])
            3'd0: begin fl_set[0] = e_lo[0] | e_hi[0]; fl_set[2] = e_lo[2] | e_hi[2]; fl_set[4] = e_lo[4] | e_hi[4]; end
            3'd1: begin fl_set[1] = e_lo[1] | e_hi[1]; fl_set[3] = e_lo[3] | e_hi[3]; fl_set[5] = e_lo[5] | e_hi[5]; end
            3'd2: begin fl_set[12] = e_lo[0] | e_lo[1]; fl_set[15] = e_lo[3] | e_lo[4]; end
            3'd3: begin fl_set[13] = e_lo[1] | e_lo[2]; fl_set[16] = e_lo[4] | e_lo[5]; end
            default: fl_set[14] = e_lo[2] | e_lo[3];
        endcase
    end
end

wire go      = start || run;
wire issue   = go && !contB && (has_avail || probes_left);
wire done_all = (pcnt == npb) && !has_avail && !vA;
assign fin   = candB && done_all;                      // last candidate finished
assign fin_idle = go && !vA && !vB && (pcnt == npb) && !has_avail;   // nothing was flagged at all

// best-candidate compare (candidates finish out of order, so the id breaks ties)
reg        r_vld, r_last;
reg [4:0]  r_ch, r_id;
reg [6:0]  r_tot;
wire better = (r_ch > out_chain) ||
              (r_ch == out_chain && r_tot > out_erased) ||
              (r_ch == out_chain && r_tot == out_erased && r_id < out_best_candidate);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        run <= 1'b0;
        fl <= 22'd0; issued <= 22'd0; pcnt <= 3'd0;
        bA <= {N*3{1'b0}}; bB <= {N*3{1'b0}}; mB <= {N{1'b0}};
        vA <= 1'b0; vB <= 1'b0; pA <= 1'b0; pB_ <= 1'b0;
        cA <= 5'd0; cB <= 5'd0; chA <= 5'd0; chB <= 5'd0; ecA <= {4*W{1'b0}}; ecB <= {4*W{1'b0}}; sB <= 15'd0;
        r_vld <= 1'b0; r_last <= 1'b0; r_ch <= 5'd0; r_id <= 5'd0; r_tot <= 7'd0;
        out_valid <= 1'b0; out_best_candidate <= 5'd0; out_chain <= 5'd0; out_erased <= 7'd0;
    end else begin
        out_valid <= 1'b0;
        // stage A -> B
        bB <= bA; mB <= mA; vB <= vA; pB_ <= pA; cB <= cA; chB <= chA; ecB <= ecA; sB <= {sA2, sA1, sA0};
        // stage B -> A: next round of the same candidate, or a newly issued job
        if (contB) begin
            bA <= gB; vA <= 1'b1; pA <= 1'b0; cA <= cB; chA <= chB + 5'd1; ecA <= ecN;
        end else if (issue) begin
            bA <= placed; vA <= 1'b1; pA <= job_is_probe; cA <= job_idx; chA <= 5'd0; ecA <= {4*W{1'b0}};
            if (job_is_probe) pcnt <= pcnt + 3'd1;
            else issued[nid] <= 1'b1;
        end else begin
            vA <= 1'b0;
        end
        if (probeB) fl <= fl | fl_set;
        if (start) begin
            run <= 1'b1;
            out_best_candidate <= low_id; out_chain <= 5'd0; out_erased <= 7'd0;
        end
        // result stage: total erased, then compare
        r_vld <= candB; r_last <= fin; r_ch <= chB; r_id <= cB; r_tot <= totB;
        if (r_vld && better) begin
            out_best_candidate <= r_id;
            out_chain <= r_ch;
            out_erased <= r_tot;
        end
        if (r_vld && r_last) out_valid <= 1'b1;
        if (fin_idle) out_valid <= 1'b1;
        if (fin || fin_idle) begin
            run <= 1'b0;
            fl <= 22'd0; issued <= 22'd0; pcnt <= 3'd0;
        end
    end
end

endmodule
