// Erase + gravity in one step: removes masked cells and compacts every column
// toward the bottom. cnt = number of erased cells.
module PUYO_GRAV #(parameter W = 6, parameter H = 12)(
    input  [W*H*3-1:0] board,
    input  [W*H-1:0]   mask,
    output [W*H*3-1:0] board_n,
    output [4*W-1:0]   cc
);
wire [3:0] colcnt [0:W-1];

genvar c, j, k;
generate
    for (c = 0; c < W; c = c + 1) begin : g_col
        // bottom-first views of this column
        wire [2:0] cv [0:H-1];
        wire       m    [0:H-1];
        for (j = 0; j < H; j = j + 1) begin : g_v
            assign cv[j] = board[3*((H-1-j)*W + c) +: 3];
            assign m[j]    = mask[(H-1-j)*W + c];
        end
        // e[j] = erased cells strictly below j
        wire [H-1:0] mv;
        for (j = 0; j < H; j = j + 1) begin : g_mv
            assign mv[j] = m[j];
        end
        wire [3:0] e [0:H];
        for (j = 0; j <= H; j = j + 1) begin : g_e
            wire [H-1:0] pm = (j == 0) ? {H{1'b0}} : (mv & ((12'd1 << j) - 12'd1));
            // balanced popcount: 3 groups of 4 -> small adders
            wire [2:0] g0 = pm[0] + pm[1] + pm[2] + pm[3];
            wire [2:0] g1 = pm[4] + pm[5] + pm[6] + pm[7];
            wire [2:0] g2 = pm[8] + pm[9] + pm[10] + pm[11];
            assign e[j] = g0 + g1 + g2;
        end
        assign colcnt[c] = e[H];
        for (k = 0; k < H; k = k + 1) begin : g_out
            // survivor j lands on k iff it is kept and exactly j-k cells below it are erased
            wire [2:0] sel [0:H-1-k];
            wire [3*(H-k)-1:0] flat;
            for (j = k; j < H; j = j + 1) begin : g_s
                assign sel[j-k] = (!m[j] && e[j] == j-k) ? cv[j] : 3'd0;
                assign flat[3*(j-k) +: 3] = sel[j-k];
            end
            reg [2:0] o;
            integer q;
            always @(*) begin
                o = 3'd0;
                for (q = 0; q < H-k; q = q + 1) o = o | flat[3*q +: 3];
            end
            assign board_n[3*((H-1-k)*W + c) +: 3] = o;
        end
    end
endgenerate

genvar q;
generate
    for (q = 0; q < W; q = q + 1) begin : g_cc
        assign cc[4*q +: 4] = colcnt[q];
    end
endgenerate
endmodule
