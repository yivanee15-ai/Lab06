// One-round Puyo elimination detector (pure combinational, parameterized).
// A cell is removable iff it lies in a connected same-color group of >= 4,
// i.e. iff it is part of a monochrome tetromino. Adjacent-pair equality is
// computed once per edge and shared; every tetromino hit is the AND of the
// three edges of a spanning tree of its four cells.
module PUYO_SOFT_IP #(
    parameter WIDTH    = 6,
    parameter HEIGHT   = 12,
    parameter COUNT_EN = 1      // 0: erase_num is tied to 0 (unused by caller)
)(
    input  [WIDTH*HEIGHT*3-1:0]                board_in,
    output reg [WIDTH*HEIGHT-1:0]              erase_mask,
    output reg [$clog2(WIDTH*HEIGHT+1)-1:0]    erase_num
);

localparam N      = WIDTH * HEIGHT;
localparam NEH    = HEIGHT * (WIDTH - 1);
localparam NEV    = (HEIGHT - 1) * WIDTH;
localparam NSHAPE = 19;

// shape: {topology, q0, q1, q2, q3}, cell = {dr[1:0], dc[1:0]}
// topology 0: path q0-q1-q2-q3, 1: star centred on q1
function [16:0] shape_def;
    input integer s;
    begin
        case (s)
            0:  shape_def = {1'b0, 4'h0, 4'h1, 4'h2, 4'h3};
            1:  shape_def = {1'b0, 4'h0, 4'h4, 4'h8, 4'hc};
            2:  shape_def = {1'b0, 4'h0, 4'h1, 4'h5, 4'h4};
            3:  shape_def = {1'b1, 4'h0, 4'h1, 4'h2, 4'h5};
            4:  shape_def = {1'b1, 4'h4, 4'h5, 4'h6, 4'h1};
            5:  shape_def = {1'b1, 4'h0, 4'h4, 4'h8, 4'h5};
            6:  shape_def = {1'b1, 4'h1, 4'h5, 4'h9, 4'h4};
            7:  shape_def = {1'b0, 4'h4, 4'h5, 4'h1, 4'h2};
            8:  shape_def = {1'b0, 4'h0, 4'h4, 4'h5, 4'h9};
            9:  shape_def = {1'b0, 4'h0, 4'h1, 4'h5, 4'h6};
            10: shape_def = {1'b0, 4'h1, 4'h5, 4'h4, 4'h8};
            11: shape_def = {1'b0, 4'h0, 4'h4, 4'h8, 4'h9};
            12: shape_def = {1'b0, 4'h4, 4'h0, 4'h1, 4'h2};
            13: shape_def = {1'b0, 4'h0, 4'h1, 4'h5, 4'h9};
            14: shape_def = {1'b0, 4'h4, 4'h5, 4'h6, 4'h2};
            15: shape_def = {1'b0, 4'h1, 4'h5, 4'h9, 4'h8};
            16: shape_def = {1'b0, 4'h0, 4'h4, 4'h5, 4'h6};
            17: shape_def = {1'b0, 4'h8, 4'h4, 4'h0, 4'h1};
            default: shape_def = {1'b0, 4'h0, 4'h1, 4'h2, 4'h6};
        endcase
    end
endfunction

// ---- shared edge equality (equal and non-empty) ----
wire [NEH+NEV-1:0] edge_eq;
genvar r, c, s;
generate
    for (r = 0; r < HEIGHT; r = r + 1) begin : g_er
        for (c = 0; c < WIDTH; c = c + 1) begin : g_ec
            if (c < WIDTH - 1) begin : g_h
                wire [2:0] a = board_in[3*(r*WIDTH+c)     +: 3];
                wire [2:0] b = board_in[3*(r*WIDTH+c+1)   +: 3];
                assign edge_eq[r*(WIDTH-1)+c] = (a == b) && (a != 3'd0);
            end
            if (r < HEIGHT - 1) begin : g_v
                wire [2:0] a = board_in[3*(r*WIDTH+c)       +: 3];
                wire [2:0] b = board_in[3*((r+1)*WIDTH+c)   +: 3];
                assign edge_eq[NEH + r*WIDTH + c] = (a == b) && (a != 3'd0);
            end
        end
    end
endgenerate

// ---- tetromino hits ----
wire [N*NSHAPE-1:0] hit;
wire [N-1:0] erase_mask_w;
generate
    for (r = 0; r < HEIGHT; r = r + 1) begin : g_row
        for (c = 0; c < WIDTH; c = c + 1) begin : g_col
            for (s = 0; s < NSHAPE; s = s + 1) begin : g_shape
                localparam [16:0] SH = shape_def(s);
                localparam R0 = r + SH[15:14];  localparam C0 = c + SH[13:12];
                localparam R1 = r + SH[11:10];  localparam C1 = c + SH[9:8];
                localparam R2 = r + SH[7:6];    localparam C2 = c + SH[5:4];
                localparam R3 = r + SH[3:2];    localparam C3 = c + SH[1:0];
                localparam IN_RANGE = (R0 < HEIGHT) && (C0 < WIDTH) && (R1 < HEIGHT) && (C1 < WIDTH) &&
                                      (R2 < HEIGHT) && (C2 < WIDTH) && (R3 < HEIGHT) && (C3 < WIDTH);
                if (IN_RANGE) begin : g_chk
                    // edge q0-q1, q1-q2, and (q1-q3 for star | q2-q3 for path)
                    localparam RA = SH[16] ? R1 : R2;  localparam CA = SH[16] ? C1 : C2;
                    localparam E0 = (R0 == R1) ? (R0 < R1 ? R0 : R1) * (WIDTH-1) + (C0 < C1 ? C0 : C1)
                                               : NEH + (R0 < R1 ? R0 : R1) * WIDTH + C0;
                    localparam E1 = (R1 == R2) ? R1 * (WIDTH-1) + (C1 < C2 ? C1 : C2)
                                               : NEH + (R1 < R2 ? R1 : R2) * WIDTH + C1;
                    localparam E2 = (RA == R3) ? RA * (WIDTH-1) + (CA < C3 ? CA : C3)
                                               : NEH + (RA < R3 ? RA : R3) * WIDTH + CA;
                    assign hit[(r*WIDTH+c)*NSHAPE+s] = edge_eq[E0] & edge_eq[E1] & edge_eq[E2];
                end else begin : g_oob
                    assign hit[(r*WIDTH+c)*NSHAPE+s] = 1'b0;
                end
            end
        end
    end
endgenerate

// ---- per-cell OR of all hits covering it ----
genvar kk;
generate
    for (r = 0; r < HEIGHT; r = r + 1) begin : g_mr
        for (c = 0; c < WIDTH; c = c + 1) begin : g_mc
            wire [4*NSHAPE-1:0] terms;
            for (s = 0; s < NSHAPE; s = s + 1) begin : g_ms
                localparam [16:0] SH = shape_def(s);
                for (kk = 0; kk < 4; kk = kk + 1) begin : g_mk
                    // cell q_kk of this shape sits at offset (dr,dc) from the anchor
                    localparam [3:0] Q  = SH[12 - 4*kk +: 4];
                    localparam       VALID = (r >= Q[3:2]) && (c >= Q[1:0]);
                    localparam       AR = VALID ? r - Q[3:2] : 0;
                    localparam       AC = VALID ? c - Q[1:0] : 0;
                    if (VALID)
                        assign terms[s*4+kk] = hit[(AR*WIDTH+AC)*NSHAPE+s];
                    else
                        assign terms[s*4+kk] = 1'b0;
                end
            end
            assign erase_mask_w[r*WIDTH+c] = |terms;
        end
    end
endgenerate

integer b;
always @(*) begin
    erase_mask = erase_mask_w;
    erase_num = 0;
    if (COUNT_EN != 0)
        for (b = 0; b < N; b = b + 1)
            erase_num = erase_num + erase_mask_w[b];
end

endmodule
