// Erase + gravity for 2-bit colour columns. Empty cells above the column top carry
// don't-care colours: they are never erased and only ever land above the new top.
module PUYO_GRAV #(parameter W = 6, parameter H = 12)(
    input  [W*H*2-1:0] board,
    input  [W*H-1:0]   mask,
    output [W*H*2-1:0] board_n,
    output [4*W-1:0]   cc          // erased cells per column
);
genvar c, j, k;
generate
    for (c = 0; c < W; c = c + 1) begin : g_col
        wire [1:0] cv [0:H-1];
        wire       m  [0:H-1];
        for (j = 0; j < H; j = j + 1) begin : g_v
            assign cv[j] = board[2*((H-1-j)*W + c) +: 2];
            assign m[j]  = mask[(H-1-j)*W + c];
        end
        wire [H-1:0] mv;
        for (j = 0; j < H; j = j + 1) begin : g_mv
            assign mv[j] = m[j];
        end
        // e[j] = erased cells strictly below j
        wire [3:0] e [0:H];
        for (j = 0; j <= H; j = j + 1) begin : g_e
            wire [H-1:0] pm = (j == 0) ? {H{1'b0}} : (mv & ((12'd1 << j) - 12'd1));
            wire [2:0] g0 = pm[0] + pm[1] + pm[2] + pm[3];
            wire [2:0] g1 = pm[4] + pm[5] + pm[6] + pm[7];
            wire [2:0] g2 = pm[8] + pm[9] + pm[10] + pm[11];
            assign e[j] = g0 + g1 + g2;
        end
        assign cc[4*c +: 4] = e[H];
        for (k = 0; k < H; k = k + 1) begin : g_out
            // survivor j lands on k iff it is kept and exactly j-k cells below it are erased
            wire [2*(H-k)-1:0] flat;
            for (j = k; j < H; j = j + 1) begin : g_s
                assign flat[2*(j-k) +: 2] = (!m[j] && e[j] == j-k) ? cv[j] : 2'd0;
            end
            reg [1:0] o;
            integer q;
            always @(*) begin
                o = 2'd0;
                for (q = 0; q < H-k; q = q + 1) o = o | flat[2*q +: 2];
            end
            assign board_n[2*((H-1-k)*W + c) +: 2] = o;
        end
    end
endgenerate
endmodule
