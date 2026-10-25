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
wire issue;

integer ci;
// control: reset
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ktot <= 7'd2;
        ring <= 6'b000001;
        rcnt <= 4'd0;
        first_cell <= 1'b1;
        start <= 1'b0;
        for (ci = 0; ci < W; ci = ci + 1) hgt[ci] <= 4'd0;
    end else begin
        start <= 1'b0;
        if (in_valid) begin
            first_cell <= 1'b0;
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

// data: loaded before use, no reset needed
always @(posedge clk) begin
    if (in_valid) begin
        base <= {in_cell[1:0], base[N*2-1:2]};
        if (first_cell) begin
            pa2  <= in_puyo_a[1:0];
            pb2  <= in_puyo_b[1:0];
            same <= (in_puyo_a == in_puyo_b);
        end
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
assign issue  = go && !contB && (has_avail || probes_left);
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

// control: reset
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        run <= 1'b0;
        pend <= 22'd0; issued <= 22'd0; pcnt <= 3'd0;
        vA <= 1'b0; vB <= 1'b0; pA <= 1'b0; pB_ <= 1'b0;
        r_vld <= 1'b0; r_last <= 1'b0;
        out_valid <= 1'b0; out_best_candidate <= 5'd0; out_chain <= 5'd0; out_erased <= 7'd0;
    end else begin
        out_valid <= 1'b0;
        vB <= vA; pB_ <= pA;
        // stage B -> A: next round of the same candidate, or a newly issued job
        if (contB) begin
            vA <= 1'b1; pA <= 1'b0;
        end else if (issue) begin
            vA <= 1'b1; pA <= job_is_probe;
            if (job_is_probe) pcnt <= pcnt + 3'd1;
        end else begin
            vA <= 1'b0;
        end
        issued <= issued | iss1h;
        pend   <= (pend & ~iss1h) | (probeB ? (fl_set & legal & ~(issued | iss1h)) : 22'd0);
        if (start) begin
            run <= 1'b1;
            out_best_candidate <= low_id; out_chain <= 5'd0; out_erased <= 7'd0;
        end
        // result stage: remaining puyos, then compare
        r_vld <= candB; r_last <= fin;
        if (r_vld && better) begin
            out_best_candidate <= r_id;
            out_chain <= r_ch;
            out_erased <= ktot - r_rem;
        end
        if (r_vld && r_last) out_valid <= 1'b1;
        if (fin_idle) out_valid <= 1'b1;
        if (fin || fin_idle) begin
            run <= 1'b0;
            pend <= 22'd0; issued <= 22'd0; pcnt <= 3'd0;
        end
    end
end

// data: written before it is read, no reset needed
always @(posedge clk) begin
    // stage A -> B
    bB <= bA; hB <= hA; mB <= mA; cB <= cA; chB <= chA; sB <= {sA2, sA1, sA0};
    if (contB) begin
        bA <= gB; hA <= hgtN; cA <= cB; chA <= chB + 5'd1;
    end else begin
        bA <= placed; hA <= hplaced; cA <= job_idx; chA <= 5'd0;
    end
    if (start) best_rem <= ktot;
    r_ch <= chB; r_id <= cB; r_rem <= remB;
    if (r_vld && better) best_rem <= r_rem;
end

endmodule

module PUYO_GRAV_COL (input [23:0] cv, input [11:0] keep, output [23:0] out, output [3:0] total);
wire c1 = ((1'b1) & ~keep[0]) | ((1'b0) & keep[0]);
wire c2 = ((1'b0) & ~keep[0]) | ((1'b1) & keep[0]);
wire c3 = ((1'b0) & ~keep[0]) | ((1'b0) & keep[0]);
wire c4 = ((c1) & ~keep[1]) | ((1'b0) & keep[1]);
wire c5 = ((c2) & ~keep[1]) | ((c1) & keep[1]);
wire c6 = ((c3) & ~keep[1]) | ((c2) & keep[1]);
wire [1:0] v7 = ({2{keep[0] & 1'b1}} & cv[1:0]) | ({2{keep[1] & c1}} & cv[3:2]);
wire [1:0] v8 = ({2{keep[1] & c2}} & cv[3:2]);
wire c9 = ((1'b1) & ~keep[2]) | ((1'b0) & keep[2]);
wire c10 = ((1'b0) & ~keep[2]) | ((1'b1) & keep[2]);
wire c11 = ((1'b0) & ~keep[2]) | ((1'b0) & keep[2]);
wire c12 = ((c9) & ~keep[3]) | ((1'b0) & keep[3]);
wire c13 = ((c10) & ~keep[3]) | ((c9) & keep[3]);
wire c14 = ((c11) & ~keep[3]) | ((c10) & keep[3]);
wire [1:0] v15 = ({2{keep[2] & 1'b1}} & cv[5:4]) | ({2{keep[3] & c9}} & cv[7:6]);
wire [1:0] v16 = ({2{keep[3] & c10}} & cv[7:6]);
wire c17 = ((1'b1) & ~keep[4]) | ((1'b0) & keep[4]);
wire c18 = ((1'b0) & ~keep[4]) | ((1'b1) & keep[4]);
wire c19 = ((1'b0) & ~keep[4]) | ((1'b0) & keep[4]);
wire c20 = ((c17) & ~keep[5]) | ((1'b0) & keep[5]);
wire c21 = ((c18) & ~keep[5]) | ((c17) & keep[5]);
wire c22 = ((c19) & ~keep[5]) | ((c18) & keep[5]);
wire [1:0] v23 = ({2{keep[4] & 1'b1}} & cv[9:8]) | ({2{keep[5] & c17}} & cv[11:10]);
wire [1:0] v24 = ({2{keep[5] & c18}} & cv[11:10]);
wire c25 = ((1'b1) & ~keep[6]) | ((1'b0) & keep[6]);
wire c26 = ((1'b0) & ~keep[6]) | ((1'b1) & keep[6]);
wire c27 = ((1'b0) & ~keep[6]) | ((1'b0) & keep[6]);
wire c28 = ((c25) & ~keep[7]) | ((1'b0) & keep[7]);
wire c29 = ((c26) & ~keep[7]) | ((c25) & keep[7]);
wire c30 = ((c27) & ~keep[7]) | ((c26) & keep[7]);
wire [1:0] v31 = ({2{keep[6] & 1'b1}} & cv[13:12]) | ({2{keep[7] & c25}} & cv[15:14]);
wire [1:0] v32 = ({2{keep[7] & c26}} & cv[15:14]);
wire c33 = ((1'b1) & ~keep[8]) | ((1'b0) & keep[8]);
wire c34 = ((1'b0) & ~keep[8]) | ((1'b1) & keep[8]);
wire c35 = ((1'b0) & ~keep[8]) | ((1'b0) & keep[8]);
wire c36 = ((c33) & ~keep[9]) | ((1'b0) & keep[9]);
wire c37 = ((c34) & ~keep[9]) | ((c33) & keep[9]);
wire c38 = ((c35) & ~keep[9]) | ((c34) & keep[9]);
wire [1:0] v39 = ({2{keep[8] & 1'b1}} & cv[17:16]) | ({2{keep[9] & c33}} & cv[19:18]);
wire [1:0] v40 = ({2{keep[9] & c34}} & cv[19:18]);
wire c41 = ((1'b1) & ~keep[10]) | ((1'b0) & keep[10]);
wire c42 = ((1'b0) & ~keep[10]) | ((1'b1) & keep[10]);
wire c43 = ((1'b0) & ~keep[10]) | ((1'b0) & keep[10]);
wire c44 = ((c41) & ~keep[11]) | ((1'b0) & keep[11]);
wire c45 = ((c42) & ~keep[11]) | ((c41) & keep[11]);
wire c46 = ((c43) & ~keep[11]) | ((c42) & keep[11]);
wire [1:0] v47 = ({2{keep[10] & 1'b1}} & cv[21:20]) | ({2{keep[11] & c41}} & cv[23:22]);
wire [1:0] v48 = ({2{keep[11] & c42}} & cv[23:22]);
wire g49 = c6 | 1'b0;
wire g50 = c5 | g49;
wire g51 = c4 | g50;
wire [1:0] m52 = ({2{g50}} & v7) | ({2{c4}} & v15);
wire [1:0] m53 = ({2{g49}} & v8) | ({2{c4}} & v16) | ({2{c5}} & v15);
wire [1:0] m54 = ({2{c5}} & v16) | ({2{c6}} & v15);
wire [1:0] m55 = ({2{c6}} & v16);
wire o56 = (c4 & c12);
wire o57 = (c4 & c13) | (c5 & c12);
wire o58 = (c4 & c14) | (c5 & c13) | (c6 & c12);
wire o59 = (c5 & c14) | (c6 & c13);
wire o60 = (c6 & c14);
wire g61 = c22 | 1'b0;
wire g62 = c21 | g61;
wire g63 = c20 | g62;
wire [1:0] m64 = ({2{g62}} & v23) | ({2{c20}} & v31);
wire [1:0] m65 = ({2{g61}} & v24) | ({2{c20}} & v32) | ({2{c21}} & v31);
wire [1:0] m66 = ({2{c21}} & v32) | ({2{c22}} & v31);
wire [1:0] m67 = ({2{c22}} & v32);
wire o68 = (c20 & c28);
wire o69 = (c20 & c29) | (c21 & c28);
wire o70 = (c20 & c30) | (c21 & c29) | (c22 & c28);
wire o71 = (c21 & c30) | (c22 & c29);
wire o72 = (c22 & c30);
wire g73 = c38 | 1'b0;
wire g74 = c37 | g73;
wire g75 = c36 | g74;
wire [1:0] m76 = ({2{g74}} & v39) | ({2{c36}} & v47);
wire [1:0] m77 = ({2{g73}} & v40) | ({2{c36}} & v48) | ({2{c37}} & v47);
wire [1:0] m78 = ({2{c37}} & v48) | ({2{c38}} & v47);
wire [1:0] m79 = ({2{c38}} & v48);
wire o80 = (c36 & c44);
wire o81 = (c36 & c45) | (c37 & c44);
wire o82 = (c36 & c46) | (c37 & c45) | (c38 & c44);
wire o83 = (c37 & c46) | (c38 & c45);
wire o84 = (c38 & c46);
wire g85 = o60 | 1'b0;
wire g86 = o59 | g85;
wire g87 = o58 | g86;
wire g88 = o57 | g87;
wire g89 = o56 | g88;
wire [1:0] m90 = ({2{g88}} & m52) | ({2{o56}} & m64);
wire [1:0] m91 = ({2{g87}} & m53) | ({2{o56}} & m65) | ({2{o57}} & m64);
wire [1:0] m92 = ({2{g86}} & m54) | ({2{o56}} & m66) | ({2{o57}} & m65) | ({2{o58}} & m64);
wire [1:0] m93 = ({2{g85}} & m55) | ({2{o56}} & m67) | ({2{o57}} & m66) | ({2{o58}} & m65) | ({2{o59}} & m64);
wire [1:0] m94 = ({2{o57}} & m67) | ({2{o58}} & m66) | ({2{o59}} & m65) | ({2{o60}} & m64);
wire [1:0] m95 = ({2{o58}} & m67) | ({2{o59}} & m66) | ({2{o60}} & m65);
wire [1:0] m96 = ({2{o59}} & m67) | ({2{o60}} & m66);
wire [1:0] m97 = ({2{o60}} & m67);
wire o98 = (o56 & o68);
wire o99 = (o56 & o69) | (o57 & o68);
wire o100 = (o56 & o70) | (o57 & o69) | (o58 & o68);
wire o101 = (o56 & o71) | (o57 & o70) | (o58 & o69) | (o59 & o68);
wire o102 = (o56 & o72) | (o57 & o71) | (o58 & o70) | (o59 & o69) | (o60 & o68);
wire o103 = (o57 & o72) | (o58 & o71) | (o59 & o70) | (o60 & o69);
wire o104 = (o58 & o72) | (o59 & o71) | (o60 & o70);
wire o105 = (o59 & o72) | (o60 & o71);
wire o106 = (o60 & o72);
wire g107 = o106 | 1'b0;
wire g108 = o105 | g107;
wire g109 = o104 | g108;
wire g110 = o103 | g109;
wire g111 = o102 | g110;
wire g112 = o101 | g111;
wire g113 = o100 | g112;
wire g114 = o99 | g113;
wire g115 = o98 | g114;
wire [1:0] m116 = ({2{g114}} & m90) | ({2{o98}} & m76);
wire [1:0] m117 = ({2{g113}} & m91) | ({2{o98}} & m77) | ({2{o99}} & m76);
wire [1:0] m118 = ({2{g112}} & m92) | ({2{o98}} & m78) | ({2{o99}} & m77) | ({2{o100}} & m76);
wire [1:0] m119 = ({2{g111}} & m93) | ({2{o98}} & m79) | ({2{o99}} & m78) | ({2{o100}} & m77) | ({2{o101}} & m76);
wire [1:0] m120 = ({2{g110}} & m94) | ({2{o99}} & m79) | ({2{o100}} & m78) | ({2{o101}} & m77) | ({2{o102}} & m76);
wire [1:0] m121 = ({2{g109}} & m95) | ({2{o100}} & m79) | ({2{o101}} & m78) | ({2{o102}} & m77) | ({2{o103}} & m76);
wire [1:0] m122 = ({2{g108}} & m96) | ({2{o101}} & m79) | ({2{o102}} & m78) | ({2{o103}} & m77) | ({2{o104}} & m76);
wire [1:0] m123 = ({2{g107}} & m97) | ({2{o102}} & m79) | ({2{o103}} & m78) | ({2{o104}} & m77) | ({2{o105}} & m76);
wire [1:0] m124 = ({2{o103}} & m79) | ({2{o104}} & m78) | ({2{o105}} & m77) | ({2{o106}} & m76);
wire [1:0] m125 = ({2{o104}} & m79) | ({2{o105}} & m78) | ({2{o106}} & m77);
wire [1:0] m126 = ({2{o105}} & m79) | ({2{o106}} & m78);
wire [1:0] m127 = ({2{o106}} & m79);
wire o128 = (o98 & o80);
wire o129 = (o98 & o81) | (o99 & o80);
wire o130 = (o98 & o82) | (o99 & o81) | (o100 & o80);
wire o131 = (o98 & o83) | (o99 & o82) | (o100 & o81) | (o101 & o80);
wire o132 = (o98 & o84) | (o99 & o83) | (o100 & o82) | (o101 & o81) | (o102 & o80);
wire o133 = (o99 & o84) | (o100 & o83) | (o101 & o82) | (o102 & o81) | (o103 & o80);
wire o134 = (o100 & o84) | (o101 & o83) | (o102 & o82) | (o103 & o81) | (o104 & o80);
wire o135 = (o101 & o84) | (o102 & o83) | (o103 & o82) | (o104 & o81) | (o105 & o80);
wire o136 = (o102 & o84) | (o103 & o83) | (o104 & o82) | (o105 & o81) | (o106 & o80);
wire o137 = (o103 & o84) | (o104 & o83) | (o105 & o82) | (o106 & o81);
wire o138 = (o104 & o84) | (o105 & o83) | (o106 & o82);
wire o139 = (o105 & o84) | (o106 & o83);
wire o140 = (o106 & o84);
assign out[1:0] = m116;
assign out[3:2] = m117;
assign out[5:4] = m118;
assign out[7:6] = m119;
assign out[9:8] = m120;
assign out[11:10] = m121;
assign out[13:12] = m122;
assign out[15:14] = m123;
assign out[17:16] = m124;
assign out[19:18] = m125;
assign out[21:20] = m126;
assign out[23:22] = m127;
assign total[0] = o129 | o131 | o133 | o135 | o137 | o139;
assign total[1] = o130 | o131 | o134 | o135 | o138 | o139;
assign total[2] = o132 | o133 | o134 | o135 | o140;
assign total[3] = o136 | o137 | o138 | o139 | o140;
endmodule

module PUYO_GRAV #(parameter W = 6, parameter H = 12)(
    input  [W*H*2-1:0] board,
    input  [W*H-1:0]   mask,
    input  [4*W-1:0]   hgt,
    output [W*H*2-1:0] board_n,
    output [4*W-1:0]   hgt_n
);
genvar c, j;
generate
    for (c = 0; c < W; c = c + 1) begin : g_col
        wire [23:0] cv;
        wire [11:0] keep;
        wire [23:0] o;
        for (j = 0; j < H; j = j + 1) begin : g_v
            assign cv[2*j +: 2] = board[2*((H-1-j)*W + c) +: 2];
            assign keep[j]      = ~mask[(H-1-j)*W + c] && (j < hgt[4*c +: 4]);   // padding never survives
            assign board_n[2*((H-1-j)*W + c) +: 2] = o[2*j +: 2];
        end
        PUYO_GRAV_COL u_col (.cv(cv), .keep(keep), .out(o), .total(hgt_n[4*c +: 4]));
    end
endgenerate
endmodule
