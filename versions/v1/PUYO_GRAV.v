// Erase + gravity in one step: removes masked cells and compacts every column
// toward the bottom. cnt = number of erased cells.
module PUYO_GRAV #(parameter W = 6, parameter H = 12)(
    input  [W*H*3-1:0] board,
    input  [W*H-1:0]   mask,
    output [W*H*3-1:0] board_n,
    output [6:0]       cnt
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
        wire [3:0] e [0:H];
        assign e[0] = 4'd0;
        for (j = 0; j < H; j = j + 1) begin : g_e
            assign e[j+1] = e[j] + m[j];
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

reg [6:0] t;
integer i;
always @(*) begin
    t = 7'd0;
    for (i = 0; i < W; i = i + 1) t = t + colcnt[i];
end
assign cnt = t;
endmodule
