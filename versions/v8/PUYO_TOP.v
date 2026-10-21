// Puyo Puyo Placement Solver - v4: compact board representation.
// A gravity-stable board is stored as 2-bit colour codes plus one 4-bit height per column
// (empties are derived from the heights), which shrinks every board register and the gravity
// network.  Each in-flight candidate carries its column heights; the number of puyos left on the
// board (sum of heights) replaces the erase counters because every candidate starts from the same
// total, so "most erased" == "fewest left".
// Candidate filtering is the probe scheme of v3 (see there).
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
reg [N*2-1:0] base;          // colour code = cell value[1:0] (4 -> 0); empties are don't-care
reg [3:0]     hgt [0:W-1];
reg [6:0]     ktot;          // puyos on the input board + the 2 new ones
reg [W-1:0]   ring;
reg [3:0]     rcnt;
reg [1:0]     pa2, pb2;
reg           same;
reg           first_cell;
reg           start;
reg           run;

wire last_cell = in_valid && ring[W-1] && (rcnt == 4'd11);
wire fin;
wire fin_idle;
wire upd_last;

integer ci;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        base <= {N*2{1'b0}};
        ktot <= 7'd2;
        ring <= 6'b000001;
        rcnt <= 4'd0;
        pa2 <= 2'd0; pb2 <= 2'd0; same <= 1'b0;
        first_cell <= 1'b1;
        start <= 1'b0;
        for (ci = 0; ci < W; ci = ci + 1) hgt[ci] <= 4'd0;
    end else begin
        start <= 1'b0;
        if (in_valid) begin
            base <= {in_cell[1:0], base[N*2-1:2]};
            if (first_cell) begin
                pa2 <= in_puyo_a[1:0];
                pb2 <= in_puyo_b[1:0];
                same <= (in_puyo_a == in_puyo_b);
                first_cell <= 1'b0;
            end
            ring <= {ring[W-2:0], ring[W-1]};
            if (ring[W-1]) rcnt <= (rcnt == 4'd11) ? 4'd0 : rcnt + 4'd1;
            if (in_cell != 3'd0) ktot <= ktot + 7'd1;
            for (ci = 0; ci < W; ci = ci + 1)
                if (ring[ci] && in_cell != 3'd0) hgt[ci] <= hgt[ci] + 4'd1;
            if (last_cell) start <= 1'b1;
        end
        if (fin || fin_idle) begin
            first_cell <= 1'b1;
            for (ci = 0; ci < W; ci = ci + 1) hgt[ci] <= 4'd0;
        end
        if (upd_last || fin_idle) ktot <= 7'd2;
    end
end

// ------------------------------------------------------------ legality
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

reg [4:0] low_id;
integer qi;
always @(*) begin
    low_id = 5'd0;
    for (qi = 21; qi >= 0; qi = qi - 1)
        if (legal[qi]) low_id = qi[4:0];
end

// colour that differs from both new puyos: padding under a floating probe piece
wire [1:0] dummy = (pa2 != 2'd0 && pb2 != 2'd0) ? 2'd0 :
                   (pa2 != 2'd1 && pb2 != 2'd1) ? 2'd1 :
                   (pa2 != 2'd2 && pb2 != 2'd2) ? 2'd2 : 2'd3;

// ------------------------------------------------------------ job issue (probe or candidate)
reg [21:0] pend;        // flagged, legal, not yet issued candidates
reg [21:0] issued;
reg [2:0]  pcnt;
wire [2:0] npb = same ? 3'd5 : 3'd4;

wire        has_avail    = |pend;
wire [21:0] sel1h        = pend & (~pend + 22'd1);          // lowest pending candidate, one-hot
wire        probes_left  = (pcnt != npb);
wire        job_is_probe = !has_avail;

// candidate id (only needed to tag the context)
reg [4:0] nid;
always @(*) begin
    nid = 5'd0;
    for (qi = 0; qi < 22; qi = qi + 1)
        if (sel1h[qi]) nid = nid | qi[4:0];
end
wire [4:0] job_idx = job_is_probe ? {2'b00, pcnt} : nid;

// placement descriptor per column: a piece on the lowest empty cell (lo) and/or the one above (hi)
reg [W-1:0] lo_en, hi_en;
reg [1:0]   lo_val [0:W-1];
reg [1:0]   hi_val [0:W-1];
reg         c_loA, c_loB, c_hiA, c_hiB, c_lo, c_hi;
reg [1:0]   pcol;
integer pc, pj;
always @(*) begin
    for (pc = 0; pc < W; pc = pc + 1) begin
        // candidate side (from the one-hot selection)
        c_hiA = sel1h[pc];                               // A above B: hi = A, lo = B
        c_hiB = sel1h[6+pc];                             // B above A: hi = B, lo = A
        c_loA = sel1h[6+pc]  | ((pc <= 4) ? sel1h[12+pc] : 1'b0) | ((pc >= 1) ? sel1h[16+pc] : 1'b0);
        c_loB = sel1h[pc]    | ((pc >= 1) ? sel1h[11+pc] : 1'b0) | ((pc <= 4) ? sel1h[17+pc] : 1'b0);
        c_hi  = c_hiA | c_hiB;
        c_lo  = c_loA | c_loB;
        // probe side
        lo_en[pc]  = c_lo;
        hi_en[pc]  = c_hi;
        lo_val[pc] = ({2{c_loA}} & pa2) | ({2{c_loB}} & pb2);
        hi_val[pc] = ({2{c_hiA}} & pa2) | ({2{c_hiB}} & pb2);
        if (job_is_probe) begin
            pcol = (pc[0] ^ pcnt[0]) ? pb2 : pa2;
            if (!same) begin
                lo_en[pc]  = !pcnt[1];  lo_val[pc] = pcol;
                hi_en[pc]  =  pcnt[1];  hi_val[pc] = pcol;
            end else begin
                lo_val[pc] = pa2; hi_val[pc] = pa2;
                case (pcnt)
                    3'd0: begin lo_en[pc] = !pc[0]; hi_en[pc] = !pc[0]; end
                    3'd1: begin lo_en[pc] =  pc[0]; hi_en[pc] =  pc[0]; end
                    3'd2: begin lo_en[pc] = (pc == 0) || (pc == 1) || (pc == 3) || (pc == 4); hi_en[pc] = 1'b0; end
                    3'd3: begin lo_en[pc] = (pc == 1) || (pc == 2) || (pc == 4) || (pc == 5); hi_en[pc] = 1'b0; end
                    default: begin lo_en[pc] = (pc == 2) || (pc == 3); hi_en[pc] = 1'b0; end
                endcase
            end
        end
    end
end

// effective pieces (spots that fall off the top of the board are dropped)
reg [W-1:0]   lo_eff, hi_eff;
wire [21:0]   iss1h = (issue && !job_is_probe) ? sel1h : 22'd0;
reg [N*2-1:0] placed;
reg [4*W-1:0] hplaced;
always @(*) begin
    for (pc = 0; pc < W; pc = pc + 1) begin
        hi_eff[pc] = hi_en[pc] && (hgt[pc] < 4'd11);
        lo_eff[pc] = (lo_en[pc] && (hgt[pc] < 4'd12)) || hi_eff[pc];
        hplaced[4*pc +: 4] = hi_eff[pc] ? (hgt[pc] + 4'd2) : (lo_eff[pc] ? (hgt[pc] + 4'd1) : hgt[pc]);   // increments depend on static heights only
    end
    for (pc = 0; pc < W; pc = pc + 1)
        for (pj = 0; pj < H; pj = pj + 1) begin
            if (lo_eff[pc] && hgt[pc] == pj)
                placed[2*((H-1-pj)*W + pc) +: 2] = lo_en[pc] ? lo_val[pc] : dummy;
            else if (hi_eff[pc] && (hgt[pc] + 4'd1) == pj)
                placed[2*((H-1-pj)*W + pc) +: 2] = hi_val[pc];
            else
                placed[2*((H-1-pj)*W + pc) +: 2] = base[2*((H-1-pj)*W + pc) +: 2];
        end
end

// ------------------------------------------------------------ pipeline
reg [N*2-1:0] bA, bB;
reg [4*W-1:0] hA, hB;
reg [N-1:0]   mB;
reg           vA, vB, pA, pB_;
reg [4:0]     cA, cB, chA, chB;
reg [14:0]    sB;                // pair sums of hA, formed in stage A

// rebuild the 3-bit cell encoding of the Soft IP from colour code + height
reg [N*3-1:0] sip_in;
integer dj, dc;
reg dv;
reg [1:0] dcol;
always @(*) begin
    for (dc = 0; dc < W; dc = dc + 1)
        for (dj = 0; dj < H; dj = dj + 1) begin
            dv   = (dj < hA[4*dc +: 4]);
            dcol = bA[2*((H-1-dj)*W + dc) +: 2];
            sip_in[3*((H-1-dj)*W + dc) +: 3] = {dv & ~dcol[1] & ~dcol[0], dv & dcol[1], dv & dcol[0]};
        end
end

wire [N-1:0]   mA;
wire [N*2-1:0] gB;
wire [6:0]     unused_num;
wire [4*W-1:0] hgtN;

PUYO_SOFT_IP #(.WIDTH(W), .HEIGHT(H), .COUNT_EN(0)) u_soft_ip (
    .board_in  (sip_in),
    .erase_mask(mA),
    .erase_num (unused_num)
);

PUYO_GRAV #(.W(W), .H(H)) u_grav (
    .board  (bB),
    .mask   (mB),
    .hgt    (hB),
    .board_n(gB),
    .hgt_n  (hgtN)
);

wire anyB   = |mB;
wire contB  = vB && !pB_ && anyB;
wire candB  = vB && !pB_ && !anyB;
wire probeB = vB && pB_;

wire [4:0] sA0 = hA[3:0]   + hA[7:4];
wire [4:0] sA1 = hA[11:8]  + hA[15:12];
wire [4:0] sA2 = hA[19:16] + hA[23:20];
wire [6:0] remB = sB[4:0] + sB[9:5] + sB[14:10];

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
        for (fc = 0; fc < W; fc = fc + 1) begin
            if (!cB[1]) begin
                if ((fc[0] ^ cB[0]) == 1'b1) fl_set[fc]   = fl_set[fc]   | e_lo[fc];
                else                         fl_set[6+fc] = fl_set[6+fc] | e_lo[fc];
            end else begin
                if ((fc[0] ^ cB[0]) == 1'b0) fl_set[fc]   = fl_set[fc]   | e_hi[fc];
                else                         fl_set[6+fc] = fl_set[6+fc] | e_hi[fc];
            end
        end
        for (fc = 0; fc < W-1; fc = fc + 1) if (!cB[1]) begin
            if ((fc[0] ^ cB[0]) == 1'b0) fl_set[12+fc] = fl_set[12+fc] | e_lo[fc] | e_lo[fc+1];
            else                         fl_set[17+fc] = fl_set[17+fc] | e_lo[fc] | e_lo[fc+1];
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

wire go       = start || run;
wire iss_pulse_unused = 1'b0;
wire issue    = go && !contB && (has_avail || probes_left);
wire done_all = (pcnt == npb) && !has_avail && !vA;
assign fin      = candB && done_all;
assign fin_idle = go && !vA && !vB && (pcnt == npb) && !has_avail;

// best-candidate compare (candidates finish out of order, so the id breaks ties)
reg        r_vld, r_last;
reg [4:0]  r_ch, r_id;
reg [6:0]  r_rem;
reg [6:0]  best_rem;
assign upd_last = r_vld && r_last;
wire better = (r_ch > out_chain) ||
              (r_ch == out_chain && r_rem < best_rem) ||
              (r_ch == out_chain && r_rem == best_rem && r_id < out_best_candidate);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        run <= 1'b0;
        pend <= 22'd0; issued <= 22'd0; pcnt <= 3'd0;
        bA <= {N*2{1'b0}}; bB <= {N*2{1'b0}}; mB <= {N{1'b0}};
        hA <= {4*W{1'b0}}; hB <= {4*W{1'b0}};
        vA <= 1'b0; vB <= 1'b0; pA <= 1'b0; pB_ <= 1'b0;
        cA <= 5'd0; cB <= 5'd0; chA <= 5'd0; chB <= 5'd0; sB <= 15'd0;
        r_vld <= 1'b0; r_last <= 1'b0; r_ch <= 5'd0; r_id <= 5'd0; r_rem <= 7'd0; best_rem <= 7'd0;
        out_valid <= 1'b0; out_best_candidate <= 5'd0; out_chain <= 5'd0; out_erased <= 7'd0;
    end else begin
        out_valid <= 1'b0;
        // stage A -> B
        bB <= bA; hB <= hA; mB <= mA; vB <= vA; pB_ <= pA; cB <= cA; chB <= chA; sB <= {sA2, sA1, sA0};
        // stage B -> A: next round of the same candidate, or a newly issued job
        if (contB) begin
            bA <= gB; hA <= hgtN; vA <= 1'b1; pA <= 1'b0; cA <= cB; chA <= chB + 5'd1;
        end else if (issue) begin
            bA <= placed; hA <= hplaced; vA <= 1'b1; pA <= job_is_probe; cA <= job_idx; chA <= 5'd0;
            if (job_is_probe) pcnt <= pcnt + 3'd1;
        end else begin
            vA <= 1'b0;
        end
        issued <= issued | iss1h;
        pend   <= (pend & ~iss1h) | (probeB ? (fl_set & legal & ~(issued | iss1h)) : 22'd0);
        if (start) begin
            run <= 1'b1;
            out_best_candidate <= low_id; out_chain <= 5'd0; out_erased <= 7'd0; best_rem <= ktot;
        end
        // result stage: remaining puyos, then compare
        r_vld <= candB; r_last <= fin; r_ch <= chB; r_id <= cB; r_rem <= remB;
        if (r_vld && better) begin
            out_best_candidate <= r_id;
            out_chain <= r_ch;
            out_erased <= ktot - r_rem;
            best_rem <= r_rem;
        end
        if (r_vld && r_last) out_valid <= 1'b1;
        if (fin_idle) out_valid <= 1'b1;
        if (fin || fin_idle) begin
            run <= 1'b0;
            pend <= 22'd0; issued <= 22'd0; pcnt <= 3'd0;
        end
    end
end

endmodule
