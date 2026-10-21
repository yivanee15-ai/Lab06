// One-round Puyo elimination detector (pure combinational, parameterized).
// A cell is removed iff its same-colour group has >= 4 cells.  Every group of 1..3 cells is a
// single cell, a pair or a 3-cell path/corner, so it is recognised from the number of same-colour
// neighbours (degree) of the cell and of its neighbours; everything else is removed.
//   small(i) = deg0 | pair | centre3 | end3
//     pair    : deg 1, and its only neighbour has deg 1
//     centre3 : deg 2, and both neighbours have deg 1
//     end3    : deg 1, and its only neighbour is a centre3
module PUYO_SOFT_IP #(
    parameter WIDTH    = 6,
    parameter HEIGHT   = 12,
    parameter COUNT_EN = 1      // 0: erase_num is tied to 0 (unused by caller)
)(
    input  [WIDTH*HEIGHT*3-1:0]                board_in,
    output reg [WIDTH*HEIGHT-1:0]              erase_mask,
    output reg [$clog2(WIDTH*HEIGHT+1)-1:0]    erase_num
);

localparam N   = WIDTH * HEIGHT;
localparam NEH = HEIGHT * (WIDTH - 1);

// ---- same-colour (and non-empty) equality of adjacent cells
wire [NEH-1:0]            eh;      // (r,c)-(r,c+1)
wire [(HEIGHT-1)*WIDTH-1:0] ev;    // (r,c)-(r+1,c)
genvar r, c;
generate
    for (r = 0; r < HEIGHT; r = r + 1) begin : g_er
        for (c = 0; c < WIDTH; c = c + 1) begin : g_ec
            if (c < WIDTH - 1) begin : g_h
                wire [2:0] a = board_in[3*(r*WIDTH+c)   +: 3];
                wire [2:0] b = board_in[3*(r*WIDTH+c+1) +: 3];
                assign eh[r*(WIDTH-1)+c] = (a == b) && (a != 3'd0);
            end
            if (r < HEIGHT - 1) begin : g_v
                wire [2:0] a = board_in[3*(r*WIDTH+c)     +: 3];
                wire [2:0] b = board_in[3*((r+1)*WIDTH+c) +: 3];
                assign ev[r*WIDTH+c] = (a == b) && (a != 3'd0);
            end
        end
    end
endgenerate

// ---- per-cell degree classes
wire [N-1:0] d0, d1, d2;
wire [N-1:0] cen3;
wire [N-1:0] small_c;
generate
    for (r = 0; r < HEIGHT; r = r + 1) begin : g_dr
        for (c = 0; c < WIDTH; c = c + 1) begin : g_dc
            localparam I = r*WIDTH + c;
            wire eU = (r > 0)          ? ev[(r-1)*WIDTH + c]       : 1'b0;
            wire eD = (r < HEIGHT - 1) ? ev[r*WIDTH + c]           : 1'b0;
            wire eL = (c > 0)          ? eh[r*(WIDTH-1) + c - 1]   : 1'b0;
            wire eR = (c < WIDTH - 1)  ? eh[r*(WIDTH-1) + c]       : 1'b0;
            wire ge2 = (eU & eD) | (eL & eR) | ((eU | eD) & (eL | eR));
            wire ge3 = (eU & eD & (eL | eR)) | (eL & eR & (eU | eD));
            assign d0[I] = ~(eU | eD | eL | eR);
            assign d1[I] = (eU | eD | eL | eR) & ~ge2;
            assign d2[I] = ge2 & ~ge3;
        end
    end
endgenerate

generate
    for (r = 0; r < HEIGHT; r = r + 1) begin : g_cr
        for (c = 0; c < WIDTH; c = c + 1) begin : g_cc
            localparam I = r*WIDTH + c;
            wire eU = (r > 0)          ? ev[(r-1)*WIDTH + c]       : 1'b0;
            wire eD = (r < HEIGHT - 1) ? ev[r*WIDTH + c]           : 1'b0;
            wire eL = (c > 0)          ? eh[r*(WIDTH-1) + c - 1]   : 1'b0;
            wire eR = (c < WIDTH - 1)  ? eh[r*(WIDTH-1) + c]       : 1'b0;
            // neighbour degree-1 flags (0 outside the board; only used behind an edge)
            wire nU1 = (r > 0)          ? d1[I - WIDTH] : 1'b0;
            wire nD1 = (r < HEIGHT - 1) ? d1[I + WIDTH] : 1'b0;
            wire nL1 = (c > 0)          ? d1[I - 1]     : 1'b0;
            wire nR1 = (c < WIDTH - 1)  ? d1[I + 1]     : 1'b0;
            assign cen3[I] = d2[I] & (~eU | nU1) & (~eD | nD1) & (~eL | nL1) & (~eR | nR1);
        end
    end
endgenerate

generate
    for (r = 0; r < HEIGHT; r = r + 1) begin : g_sr
        for (c = 0; c < WIDTH; c = c + 1) begin : g_sc
            localparam I = r*WIDTH + c;
            wire eU = (r > 0)          ? ev[(r-1)*WIDTH + c]       : 1'b0;
            wire eD = (r < HEIGHT - 1) ? ev[r*WIDTH + c]           : 1'b0;
            wire eL = (c > 0)          ? eh[r*(WIDTH-1) + c - 1]   : 1'b0;
            wire eR = (c < WIDTH - 1)  ? eh[r*(WIDTH-1) + c]       : 1'b0;
            wire nU1 = (r > 0)          ? d1[I - WIDTH]   : 1'b0;
            wire nD1 = (r < HEIGHT - 1) ? d1[I + WIDTH]   : 1'b0;
            wire nL1 = (c > 0)          ? d1[I - 1]       : 1'b0;
            wire nR1 = (c < WIDTH - 1)  ? d1[I + 1]       : 1'b0;
            wire nUc = (r > 0)          ? cen3[I - WIDTH] : 1'b0;
            wire nDc = (r < HEIGHT - 1) ? cen3[I + WIDTH] : 1'b0;
            wire nLc = (c > 0)          ? cen3[I - 1]     : 1'b0;
            wire nRc = (c < WIDTH - 1)  ? cen3[I + 1]     : 1'b0;
            wire pair = d1[I] & ((eU & nU1) | (eD & nD1) | (eL & nL1) | (eR & nR1));
            wire end3 = d1[I] & ((eU & nUc) | (eD & nDc) | (eL & nLc) | (eR & nRc));
            assign small_c[I] = d0[I] | pair | cen3[I] | end3;
        end
    end
endgenerate

integer b;
always @(*) begin
    erase_mask = ~small_c;
    erase_num = 0;
    if (COUNT_EN != 0)
        for (b = 0; b < N; b = b + 1)
            erase_num = erase_num + erase_mask[b];
end

endmodule
