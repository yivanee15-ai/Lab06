// One-round Puyo elimination detector (pure combinational, parameterized).
// A cell is removed iff its same-colour group has >= 4 cells.  Every group of 1..3 cells is a
// single cell, a pair or a 3-cell path/corner, so it is recognised from the number of same-colour
// neighbours (degree) of the cell and of its neighbours; everything else is removed.
//   small(i) = deg0 | pair | centre3 | end3
//     pair    : deg 1, and its only neighbour has deg 1
//     centre3 : deg 2, and both neighbours have deg 1
//     end3    : deg 1, and its only neighbour is a centre3
// Cell values are 0 (empty) and 1..4; two non-empty cells have the same colour iff their two
// low bits are equal (4 = 3'b100 is the only value whose low bits are 00).
module PUYO_SOFT_IP #(
    parameter WIDTH    = 6,
    parameter HEIGHT   = 12,
    parameter COUNT_EN = 1      // 0: erase_num is tied to 0 (the caller does not use it)
)(
    input  [WIDTH*HEIGHT*3-1:0]                board_in,
    output [WIDTH*HEIGHT-1:0]                  erase_mask,
    output [$clog2(WIDTH*HEIGHT+1)-1:0]        erase_num
);

localparam N   = WIDTH * HEIGHT;
localparam NEH = HEIGHT * (WIDTH - 1);
localparam NEV = (HEIGHT - 1) * WIDTH;

genvar r, c;

// ---- non-empty flag of every cell
wire [N-1:0] ne;
generate
    for (r = 0; r < N; r = r + 1) begin : g_ne
        assign ne[r] = |board_in[3*r +: 3];
    end
endgenerate

// ---- same-colour equality of adjacent non-empty cells
wire [NEH-1:0] eh;        // (r,c)-(r,c+1)
wire [NEV-1:0] ev;        // (r,c)-(r+1,c)
generate
    for (r = 0; r < HEIGHT; r = r + 1) begin : g_er
        for (c = 0; c < WIDTH; c = c + 1) begin : g_ec
            if (c < WIDTH - 1) begin : g_h
                assign eh[r*(WIDTH-1)+c] = (board_in[3*(r*WIDTH+c) +: 2] == board_in[3*(r*WIDTH+c+1) +: 2]) &
                                           ne[r*WIDTH+c] & ne[r*WIDTH+c+1];
            end
            if (r < HEIGHT - 1) begin : g_v
                assign ev[r*WIDTH+c] = (board_in[3*(r*WIDTH+c) +: 2] == board_in[3*((r+1)*WIDTH+c) +: 2]) &
                                       ne[r*WIDTH+c] & ne[(r+1)*WIDTH+c];
            end
        end
    end
endgenerate

// ---- edges of every cell as {up, down, left, right}; absent edges are 0
wire [4*N-1:0] ed;
generate
    for (r = 0; r < HEIGHT; r = r + 1) begin : g_edr
        for (c = 0; c < WIDTH; c = c + 1) begin : g_edc
            if (r > 0)          begin : g_u assign ed[4*(r*WIDTH+c)+3] = ev[(r-1)*WIDTH+c];      end
            else                begin : g_u assign ed[4*(r*WIDTH+c)+3] = 1'b0;                   end
            if (r < HEIGHT - 1) begin : g_d assign ed[4*(r*WIDTH+c)+2] = ev[r*WIDTH+c];          end
            else                begin : g_d assign ed[4*(r*WIDTH+c)+2] = 1'b0;                   end
            if (c > 0)          begin : g_l assign ed[4*(r*WIDTH+c)+1] = eh[r*(WIDTH-1)+c-1];    end
            else                begin : g_l assign ed[4*(r*WIDTH+c)+1] = 1'b0;                   end
            if (c < WIDTH - 1)  begin : g_r assign ed[4*(r*WIDTH+c)+0] = eh[r*(WIDTH-1)+c];      end
            else                begin : g_r assign ed[4*(r*WIDTH+c)+0] = 1'b0;                   end
        end
    end
endgenerate

// ---- degree classes
wire [N-1:0] d0, d1, d2;
generate
    for (r = 0; r < N; r = r + 1) begin : g_deg
        wire eU = ed[4*r+3], eD = ed[4*r+2], eL = ed[4*r+1], eR = ed[4*r+0];
        wire ge2 = (eU & eD) | (eL & eR) | ((eU | eD) & (eL | eR));
        wire ge3 = (eU & eD & (eL | eR)) | (eL & eR & (eU | eD));
        assign d0[r] = ~(eU | eD | eL | eR);
        assign d1[r] = (eU | eD | eL | eR) & ~ge2;
        assign d2[r] = ge2 & ~ge3;
    end
endgenerate

// ---- centre of a 3-cell group: two neighbours, both with degree 1
wire [N-1:0] cen3, small_c;
generate
    for (r = 0; r < HEIGHT; r = r + 1) begin : g_cr
        for (c = 0; c < WIDTH; c = c + 1) begin : g_cc
            localparam I = r*WIDTH + c;
            wire [3:0] n1;                                  // degree-1 flag of the {up,down,left,right} neighbour
            if (r > 0)          begin : g_u assign n1[3] = d1[I-WIDTH]; end else begin : g_u assign n1[3] = 1'b0; end
            if (r < HEIGHT - 1) begin : g_d assign n1[2] = d1[I+WIDTH]; end else begin : g_d assign n1[2] = 1'b0; end
            if (c > 0)          begin : g_l assign n1[1] = d1[I-1];     end else begin : g_l assign n1[1] = 1'b0; end
            if (c < WIDTH - 1)  begin : g_r assign n1[0] = d1[I+1];     end else begin : g_r assign n1[0] = 1'b0; end
            assign cen3[I] = d2[I] & ~|(ed[4*I +: 4] & ~n1);
        end
    end
endgenerate

generate
    for (r = 0; r < HEIGHT; r = r + 1) begin : g_sr
        for (c = 0; c < WIDTH; c = c + 1) begin : g_sc
            localparam I = r*WIDTH + c;
            wire [3:0] n1, nc;                              // degree-1 / centre3 flag of each neighbour
            if (r > 0)          begin : g_u assign n1[3] = d1[I-WIDTH]; assign nc[3] = cen3[I-WIDTH]; end
            else                begin : g_u assign n1[3] = 1'b0;        assign nc[3] = 1'b0;          end
            if (r < HEIGHT - 1) begin : g_d assign n1[2] = d1[I+WIDTH]; assign nc[2] = cen3[I+WIDTH]; end
            else                begin : g_d assign n1[2] = 1'b0;        assign nc[2] = 1'b0;          end
            if (c > 0)          begin : g_l assign n1[1] = d1[I-1];     assign nc[1] = cen3[I-1];     end
            else                begin : g_l assign n1[1] = 1'b0;        assign nc[1] = 1'b0;          end
            if (c < WIDTH - 1)  begin : g_r assign n1[0] = d1[I+1];     assign nc[0] = cen3[I+1];     end
            else                begin : g_r assign n1[0] = 1'b0;        assign nc[0] = 1'b0;          end
            wire pair = d1[I] & |(ed[4*I +: 4] & n1);
            wire end3 = d1[I] & |(ed[4*I +: 4] & nc);
            assign small_c[I] = d0[I] | pair | cen3[I] | end3;
        end
    end
endgenerate

assign erase_mask = ~small_c;

// ---- number of removed cells (only built when requested)
generate
    if (COUNT_EN != 0) begin : g_cnt
        integer b;
        reg [$clog2(N+1)-1:0] cnt;
        always @(*) begin
            cnt = 0;
            for (b = 0; b < N; b = b + 1)
                cnt = cnt + erase_mask[b];
        end
        assign erase_num = cnt;
    end else begin : g_nocnt
        assign erase_num = {($clog2(N+1)){1'b0}};
    end
endgenerate

endmodule
