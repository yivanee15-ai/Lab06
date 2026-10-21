// Puyo Puyo Placement Solver - v1: single-context loop, optimized control.
//  - input board is shifted in (no write decoder); column heights are tracked while streaming
//  - legal candidates are known from heights, illegal ones cost no cycle
//  - one {Soft IP -> erase -> gravity} round per cycle; erase counts are accumulated one cycle
//    late so no popcount sits in the loop; the best-candidate compare is a separate stage
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
reg [N*3-1:0] base;          // flat, cell 0 = top-left once 72 cells are in
reg [3:0]     hgt [0:W-1];
reg [W-1:0]   ring;          // one-hot column of the cell being received
reg [3:0]     rcnt;
reg [2:0]     pa, pb;
reg           first_cell;
reg           start;         // one cycle after the last cell
reg           busy;

wire last_cell = in_valid && ring[W-1] && (rcnt == 4'd11);

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
        if (in_valid && !busy) begin
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
reg [21:0] pend;             // legal candidates not yet issued
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

wire [21:0] sel_vec = start ? legal : pend;     // candidate pool seen by the issue logic
reg  [4:0]  nid;
integer qi;
always @(*) begin
    nid = 5'd0;
    for (qi = 21; qi >= 0; qi = qi - 1)
        if (sel_vec[qi]) nid = qi[4:0];
end
wire [21:0] sel_rest = sel_vec & (sel_vec - 22'd1);

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
        lo_en[lcol[2:0]] = 1'b1;     lo_val[lcol[2:0]]     = pa;
        lo_en[lcol[2:0] + 3'd1] = 1'b1; lo_val[lcol[2:0] + 3'd1] = pb;
    end else begin
        lcol = nid - 5'd17;
        lo_en[lcol[2:0]] = 1'b1;     lo_val[lcol[2:0]]     = pb;
        lo_en[lcol[2:0] + 3'd1] = 1'b1; lo_val[lcol[2:0] + 3'd1] = pa;
    end
    for (pc = 0; pc < W; pc = pc + 1)
        for (pj = 0; pj < H; pj = pj + 1) begin   // pj: row from the bottom
            if (lo_en[pc] && hgt[pc] == pj)
                placed[3*((H-1-pj)*W + pc) +: 3] = lo_val[pc];
            else if (hi_en[pc] && (hgt[pc] + 4'd1) == pj)
                placed[3*((H-1-pj)*W + pc) +: 3] = hi_val[pc];
            else
                placed[3*((H-1-pj)*W + pc) +: 3] = base[3*((H-1-pj)*W + pc) +: 3];
        end
end

// ------------------------------------------------------------ evaluation loop
reg [N*3-1:0] wb;
reg [4:0]     cid;
reg [4:0]     chain;
reg [6:0]     eacc;
reg [3:0]     cc [0:W-1];     // erased count per column of the previous round
reg           active;

wire [N-1:0]   mask;
wire [N*3-1:0] fallen;
wire [6:0]     erase_num_unused;

PUYO_SOFT_IP #(.WIDTH(W), .HEIGHT(H), .COUNT_EN(0)) u_soft_ip (
    .board_in  (wb),
    .erase_mask(mask),
    .erase_num (erase_num_unused)
);

PUYO_GRAV #(.W(W), .H(H)) u_grav (
    .board  (wb),
    .mask   (mask),
    .board_n(fallen),
    .cnt    ()
);

wire any_erase = |mask;
reg  [3:0] ccn [0:W-1];
integer cj, cr;
reg  [3:0] t4;
always @(*) begin
    for (cj = 0; cj < W; cj = cj + 1) begin
        t4 = 4'd0;
        for (cr = 0; cr < H; cr = cr + 1) t4 = t4 + mask[cr*W + cj];
        ccn[cj] = t4;
    end
end
reg [6:0] ccsum;
always @(*) begin
    ccsum = 7'd0;
    for (cj = 0; cj < W; cj = cj + 1) ccsum = ccsum + cc[cj];
end

wire done    = active && !any_erase;
wire more    = |pend;
wire fin     = done && !more;                  // last candidate finished

// result stage
reg        r_vld, r_last;
reg [4:0]  r_chain, r_cid;
reg [6:0]  r_er;
reg        have_best;
wire better = !have_best || (r_chain > out_chain) || (r_chain == out_chain && r_er > out_erased);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        busy <= 1'b0; active <= 1'b0;
        wb <= {N*3{1'b0}};
        cid <= 5'd0; chain <= 5'd0; eacc <= 7'd0; pend <= 22'd0;
        for (cj = 0; cj < W; cj = cj + 1) cc[cj] <= 4'd0;
        r_vld <= 1'b0; r_last <= 1'b0; r_chain <= 5'd0; r_cid <= 5'd0; r_er <= 7'd0;
        have_best <= 1'b0;
        out_valid <= 1'b0; out_best_candidate <= 5'd0; out_chain <= 5'd0; out_erased <= 7'd0;
    end else begin
        out_valid <= 1'b0;
        r_vld <= 1'b0;
        // ---- issue / loop
        if (start) begin
            busy <= 1'b1; active <= 1'b1;
            wb <= placed; cid <= nid; pend <= sel_rest;
            chain <= 5'd0; eacc <= 7'd0;
            for (cj = 0; cj < W; cj = cj + 1) cc[cj] <= 4'd0;
            have_best <= 1'b0;
            out_best_candidate <= 5'd0; out_chain <= 5'd0; out_erased <= 7'd0;
        end else if (active) begin
            if (any_erase) begin
                wb <= fallen;
                chain <= chain + 5'd1;
                eacc <= eacc + ccsum;
                for (cj = 0; cj < W; cj = cj + 1) cc[cj] <= ccn[cj];
            end else begin
                r_vld <= 1'b1; r_last <= !more;
                r_chain <= chain; r_er <= eacc + ccsum; r_cid <= cid;
                chain <= 5'd0; eacc <= 7'd0;
                for (cj = 0; cj < W; cj = cj + 1) cc[cj] <= 4'd0;
                if (more) begin
                    wb <= placed; cid <= nid; pend <= sel_rest;
                end else begin
                    active <= 1'b0; busy <= 1'b0;
                end
            end
        end
        // ---- compare stage
        if (r_vld) begin
            if (better) begin
                have_best <= 1'b1;
                out_best_candidate <= r_cid;
                out_chain <= r_chain;
                out_erased <= r_er;
            end
            if (r_last) out_valid <= 1'b1;
        end
    end
end

endmodule
