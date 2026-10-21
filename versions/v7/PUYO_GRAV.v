// Erase + gravity, hierarchical compaction: groups of 4 cells are compacted locally, then
// concatenated with one-hot count selects.
module PUYO_GRAV #(parameter W = 6, parameter H = 12)(
    input  [W*H*2-1:0] board,
    input  [W*H-1:0]   mask,
    input  [4*W-1:0]   hgt,        // valid cells per column (cells above are padding)
    output [W*H*2-1:0] board_n,
    output [4*W-1:0]   hgt_n       // survivors per column
);
genvar c, g, p, a;
generate
    for (c = 0; c < W; c = c + 1) begin : g_col
        // ---- level 1: compact each group of 4 (bottom-first)
        wire [1:0] cg [0:2][0:3];       // compacted cells of group g
        wire [4:0] oh [0:2];            // one-hot kept count of group g (0..4)
        for (g = 0; g < 3; g = g + 1) begin : g_g
            wire [1:0] v [0:3];
            wire       k [0:3];         // kept
            for (p = 0; p < 4; p = p + 1) begin : g_v
                assign v[p] = board[2*((H-1-(4*g+p))*W + c) +: 2];
                assign k[p] = ~mask[(H-1-(4*g+p))*W + c] && ((4*g+p) < hgt[4*c +: 4]);   // padding never survives
            end
            // rank of each kept cell inside the group
            wire [2:0] rk0 = 3'd0;
            wire [2:0] rk1 = {2'b0, k[0]};
            wire [2:0] rk2 = {2'b0, k[0]} + {2'b0, k[1]};
            wire [2:0] rk3 = {2'b0, k[0]} + {2'b0, k[1]} + {2'b0, k[2]};
            wire [2:0] kc  = rk3 + {2'b0, k[3]};
            for (p = 0; p < 5; p = p + 1) begin : g_oh
                assign oh[g][p] = (kc == p);
            end
            for (p = 0; p < 4; p = p + 1) begin : g_c
                assign cg[g][p] = ({2{k[0] && rk0 == p}} & v[0]) | ({2{k[1] && rk1 == p}} & v[1]) |
                                  ({2{k[2] && rk2 == p}} & v[2]) | ({2{k[3] && rk3 == p}} & v[3]);
            end
        end
        // ---- level 2: merge group 0 and 1 -> 8 cells, count one-hot (0..8)
        wire [1:0] m01 [0:7];
        wire [8:0] oh01;
        for (p = 0; p < 9; p = p + 1) begin : g_o01
            // number of (a,b) with a+b == p
            reg t;
            integer ia;
            always @(*) begin
                t = 1'b0;
                for (ia = 0; ia < 5; ia = ia + 1)
                    if (p - ia >= 0 && p - ia <= 4) t = t | (oh[0][ia] & oh[1][p-ia]);
            end
            assign oh01[p] = t;
        end
        for (p = 0; p < 8; p = p + 1) begin : g_m01
            reg [1:0] o;
            integer ia;
            always @(*) begin
                o = 2'd0;
                for (ia = 0; ia < 5; ia = ia + 1) begin
                    if (p < ia)                      o = o | ({2{oh[0][ia]}} & cg[0][(p < 4) ? p : 0]);
                    else if (p - ia <= 3)            o = o | ({2{oh[0][ia]}} & cg[1][p-ia]);
                end
            end
            assign m01[p] = o;
        end
        // ---- survivors of the column: one-hot convolution of (group 0+1) and group 2, then encode
        wire [12:0] ohT;
        for (p = 0; p < 13; p = p + 1) begin : g_ot
            reg t;
            integer ib;
            always @(*) begin
                t = 1'b0;
                for (ib = 0; ib < 9; ib = ib + 1)
                    if (p - ib >= 0 && p - ib <= 4) t = t | (oh01[ib] & oh[2][p-ib]);
            end
            assign ohT[p] = t;
        end
        assign hgt_n[4*c+0] = ohT[1] | ohT[3] | ohT[5] | ohT[7] | ohT[9]  | ohT[11];
        assign hgt_n[4*c+1] = ohT[2] | ohT[3] | ohT[6] | ohT[7] | ohT[10] | ohT[11];
        assign hgt_n[4*c+2] = ohT[4] | ohT[5] | ohT[6] | ohT[7] | ohT[12];
        assign hgt_n[4*c+3] = ohT[8] | ohT[9] | ohT[10] | ohT[11] | ohT[12];
        // ---- level 3: append group 2 after the first k01 cells
        for (p = 0; p < 12; p = p + 1) begin : g_m
            reg [1:0] o;
            integer ib;
            always @(*) begin
                o = 2'd0;
                for (ib = 0; ib < 9; ib = ib + 1) begin
                    if (p < ib)                      o = o | ({2{oh01[ib]}} & m01[(p < 8) ? p : 0]);
                    else if (p - ib <= 3)            o = o | ({2{oh01[ib]}} & cg[2][p-ib]);
                end
            end
            assign board_n[2*((H-1-p)*W + c) +: 2] = o;
        end
    end
endgenerate
endmodule
