// Puyo Puyo Placement Solver (6 x 12 board).
// Flow: stream in 72 cells -> for each of 22 candidates: place, then loop
// {PUYO_SOFT_IP -> erase -> gravity} one round per cycle until erase_num == 0
// -> keep the best (chain, erased, smaller id) -> pulse out_valid.
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

localparam S_LOAD = 1'b0;
localparam S_EVAL = 1'b1;

reg         state;
reg [6:0]   cnt;
reg [N*3-1:0] board;      // flat, cell 0 = top-left
reg [2:0]   pa, pb;
reg [4:0]   cand;
reg         first;        // first evaluation cycle of the current candidate
reg [N*3-1:0] cur;        // working board between erase rounds
reg [4:0]   chain_acc;
reg [6:0]   erased_acc;
reg         have_best;

// ---------------- placement ----------------
reg [N*3-1:0] placed;
reg           legal;
reg [3:0]     hgt [0:W-1];
reg [2:0]     col_l, col_r;       // target columns (col_r == col_l for vertical)
reg [2:0]     put_l, put_r;       // puyo for left / right (vertical: bottom / top)
reg           vert;
integer       ci, ri;

always @(*) begin
    for (ci = 0; ci < W; ci = ci + 1) begin
        hgt[ci] = 4'd0;
        for (ri = 0; ri < H; ri = ri + 1)
            if (board[3*(ri*W+ci) +: 3] != 3'd0)
                hgt[ci] = hgt[ci] + 4'd1;
    end

    vert  = (cand < 5'd12);
    col_l = 3'd0; col_r = 3'd0; put_l = 3'd0; put_r = 3'd0;
    if (cand < 5'd6) begin                 // A above B, column = id
        col_l = cand[2:0];      col_r = cand[2:0];      put_l = pb; put_r = pa;
    end else if (cand < 5'd12) begin       // B above A, column = id - 6
        col_l = cand - 5'd6;    col_r = cand - 5'd6;    put_l = pa; put_r = pb;
    end else if (cand < 5'd17) begin       // A left of B
        col_l = cand - 5'd12;   col_r = cand - 5'd12 + 3'd1; put_l = pa; put_r = pb;
    end else begin                         // B left of A
        col_l = cand - 5'd17;   col_r = cand - 5'd17 + 3'd1; put_l = pb; put_r = pa;
    end

    placed = board;
    if (vert) begin
        legal = (hgt[col_l] <= 4'd10);
        if (legal) begin
            placed[3*((H-1-hgt[col_l])*W + col_l) +: 3]     = put_l;
            placed[3*((H-2-hgt[col_l])*W + col_l) +: 3]     = put_r;
        end
    end else begin
        legal = (hgt[col_l] < 4'd12) && (hgt[col_r] < 4'd12);
        if (legal) begin
            placed[3*((H-1-hgt[col_l])*W + col_l) +: 3] = put_l;
            placed[3*((H-1-hgt[col_r])*W + col_r) +: 3] = put_r;
        end
    end
end

// ---------------- Soft IP ----------------
wire [N*3-1:0] soft_in = first ? placed : cur;
wire [N-1:0]   erase_mask;
wire [6:0]     erase_num;

PUYO_SOFT_IP #(.WIDTH(W), .HEIGHT(H)) u_soft_ip (
    .board_in  (soft_in),
    .erase_mask(erase_mask),
    .erase_num (erase_num)
);

// ---------------- erase + gravity ----------------
reg [N*3-1:0] erased_board;
reg [N*3-1:0] fallen;
reg [3:0]     kpos;
integer       gc, gr;

always @(*) begin
    erased_board = soft_in;
    for (gr = 0; gr < N; gr = gr + 1)
        if (erase_mask[gr])
            erased_board[3*gr +: 3] = 3'd0;
    fallen = {N*3{1'b0}};
    kpos   = 4'd0;
    for (gc = 0; gc < W; gc = gc + 1) begin
        kpos = 4'd11;
        for (gr = H-1; gr >= 0; gr = gr - 1)
            if (erased_board[3*(gr*W+gc) +: 3] != 3'd0) begin
                fallen[3*(kpos*W+gc) +: 3] = erased_board[3*(gr*W+gc) +: 3];
                kpos = kpos - 4'd1;
            end
    end
end

// ---------------- compare ----------------
wire better = !have_best ||
              (chain_acc >  out_chain) ||
              (chain_acc == out_chain && erased_acc > out_erased);

// ---------------- control ----------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state              <= S_LOAD;
        cnt                <= 7'd0;
        board              <= {N*3{1'b0}};
        pa                 <= 3'd0;
        pb                 <= 3'd0;
        cand               <= 5'd0;
        first              <= 1'b1;
        cur                <= {N*3{1'b0}};
        chain_acc          <= 5'd0;
        erased_acc         <= 7'd0;
        have_best          <= 1'b0;
        out_valid          <= 1'b0;
        out_best_candidate <= 5'd0;
        out_chain          <= 5'd0;
        out_erased         <= 7'd0;
    end else begin
        out_valid <= 1'b0;
        case (state)
        S_LOAD: if (in_valid) begin
            board[3*cnt +: 3] <= in_cell;
            if (cnt == 7'd0) begin
                pa <= in_puyo_a;
                pb <= in_puyo_b;
                have_best          <= 1'b0;
                out_best_candidate <= 5'd0;
                out_chain          <= 5'd0;
                out_erased         <= 7'd0;
            end
            if (cnt == 7'd71) begin
                cnt        <= 7'd0;
                cand       <= 5'd0;
                first      <= 1'b1;
                chain_acc  <= 5'd0;
                erased_acc <= 7'd0;
                state      <= S_EVAL;
            end else
                cnt <= cnt + 7'd1;
        end
        S_EVAL: begin
            if (first && !legal) begin
                // illegal candidate: skip it
                if (cand == 5'd21) begin
                    out_valid <= 1'b1;
                    state     <= S_LOAD;
                end else
                    cand <= cand + 5'd1;
            end else if (erase_num == 7'd0) begin
                // candidate finished: compare accumulated result
                if (better) begin
                    have_best          <= 1'b1;
                    out_best_candidate <= cand;
                    out_chain          <= chain_acc;
                    out_erased         <= erased_acc;
                end
                chain_acc  <= 5'd0;
                erased_acc <= 7'd0;
                first      <= 1'b1;
                if (cand == 5'd21) begin
                    out_valid <= 1'b1;
                    state     <= S_LOAD;
                end else
                    cand <= cand + 5'd1;
            end else begin
                chain_acc  <= chain_acc + 5'd1;
                erased_acc <= erased_acc + erase_num;
                cur        <= fallen;
                first      <= 1'b0;
            end
        end
        endcase
    end
end

endmodule
