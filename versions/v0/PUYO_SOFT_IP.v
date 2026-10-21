// One-round Puyo elimination detector (pure combinational, parameterized).
// A connected group of >= 4 same-color cells always contains a connected
// 4-cell subset (tetromino) through every one of its cells, so a cell is
// removable iff it belongs to a monochrome, non-empty tetromino.
// Every anchor cell x every one of the 19 tetromino orientations is checked.
module PUYO_SOFT_IP #(
    parameter WIDTH  = 6,
    parameter HEIGHT = 12
)(
    input  [WIDTH*HEIGHT*3-1:0]          board_in,
    output reg [WIDTH*HEIGHT-1:0]        erase_mask,
    output reg [$clog2(WIDTH*HEIGHT+1)-1:0] erase_num
);

localparam N = WIDTH * HEIGHT;
localparam NSHAPE = 19;

// Shape s: four cells, each {dr[1:0], dc[1:0]}; dr grows downward, dc rightward.
function [15:0] shape_cells;
    input integer s;
    begin
        case (s)
            0:  shape_cells = {2'd0,2'd0, 2'd0,2'd1, 2'd0,2'd2, 2'd0,2'd3}; // I horizontal
            1:  shape_cells = {2'd0,2'd0, 2'd1,2'd0, 2'd2,2'd0, 2'd3,2'd0}; // I vertical
            2:  shape_cells = {2'd0,2'd0, 2'd0,2'd1, 2'd1,2'd0, 2'd1,2'd1}; // O
            3:  shape_cells = {2'd0,2'd0, 2'd0,2'd1, 2'd0,2'd2, 2'd1,2'd1}; // T down
            4:  shape_cells = {2'd0,2'd1, 2'd1,2'd0, 2'd1,2'd1, 2'd1,2'd2}; // T up
            5:  shape_cells = {2'd0,2'd0, 2'd1,2'd0, 2'd2,2'd0, 2'd1,2'd1}; // T right
            6:  shape_cells = {2'd0,2'd1, 2'd1,2'd1, 2'd2,2'd1, 2'd1,2'd0}; // T left
            7:  shape_cells = {2'd0,2'd1, 2'd0,2'd2, 2'd1,2'd0, 2'd1,2'd1}; // S horizontal
            8:  shape_cells = {2'd0,2'd0, 2'd1,2'd0, 2'd1,2'd1, 2'd2,2'd1}; // S vertical
            9:  shape_cells = {2'd0,2'd0, 2'd0,2'd1, 2'd1,2'd1, 2'd1,2'd2}; // Z horizontal
            10: shape_cells = {2'd0,2'd1, 2'd1,2'd0, 2'd1,2'd1, 2'd2,2'd0}; // Z vertical
            11: shape_cells = {2'd0,2'd0, 2'd1,2'd0, 2'd2,2'd0, 2'd2,2'd1}; // L
            12: shape_cells = {2'd0,2'd0, 2'd0,2'd1, 2'd0,2'd2, 2'd1,2'd0}; // L
            13: shape_cells = {2'd0,2'd0, 2'd0,2'd1, 2'd1,2'd1, 2'd2,2'd1}; // L
            14: shape_cells = {2'd0,2'd2, 2'd1,2'd0, 2'd1,2'd1, 2'd1,2'd2}; // L
            15: shape_cells = {2'd0,2'd1, 2'd1,2'd1, 2'd2,2'd1, 2'd2,2'd0}; // J
            16: shape_cells = {2'd0,2'd0, 2'd1,2'd0, 2'd1,2'd1, 2'd1,2'd2}; // J
            17: shape_cells = {2'd0,2'd0, 2'd0,2'd1, 2'd1,2'd0, 2'd2,2'd0}; // J
            default: shape_cells = {2'd0,2'd0, 2'd0,2'd1, 2'd0,2'd2, 2'd1,2'd2}; // J (18)
        endcase
    end
endfunction

wire [N-1:0] contrib [0:N*NSHAPE-1];

genvar r, c, s;
generate
    for (r = 0; r < HEIGHT; r = r + 1) begin : g_row
        for (c = 0; c < WIDTH; c = c + 1) begin : g_col
            for (s = 0; s < NSHAPE; s = s + 1) begin : g_shape
                localparam [15:0] SH = shape_cells(s);
                localparam R0 = r + SH[15:14];
                localparam C0 = c + SH[13:12];
                localparam R1 = r + SH[11:10];
                localparam C1 = c + SH[9:8];
                localparam R2 = r + SH[7:6];
                localparam C2 = c + SH[5:4];
                localparam R3 = r + SH[3:2];
                localparam C3 = c + SH[1:0];
                localparam IN_RANGE = (R0 < HEIGHT) && (C0 < WIDTH) &&
                                      (R1 < HEIGHT) && (C1 < WIDTH) &&
                                      (R2 < HEIGHT) && (C2 < WIDTH) &&
                                      (R3 < HEIGHT) && (C3 < WIDTH);
                if (IN_RANGE) begin : g_chk
                    localparam I0 = R0 * WIDTH + C0;
                    localparam I1 = R1 * WIDTH + C1;
                    localparam I2 = R2 * WIDTH + C2;
                    localparam I3 = R3 * WIDTH + C3;
                    wire [2:0] v0 = board_in[3*I0 +: 3];
                    wire [2:0] v1 = board_in[3*I1 +: 3];
                    wire [2:0] v2 = board_in[3*I2 +: 3];
                    wire [2:0] v3 = board_in[3*I3 +: 3];
                    wire hit = (v0 != 3'd0) && (v0 == v1) && (v0 == v2) && (v0 == v3);
                    wire [N-1:0] m0 = hit ? ({{(N-1){1'b0}}, 1'b1} << I0) : {N{1'b0}};
                    wire [N-1:0] m1 = hit ? ({{(N-1){1'b0}}, 1'b1} << I1) : {N{1'b0}};
                    wire [N-1:0] m2 = hit ? ({{(N-1){1'b0}}, 1'b1} << I2) : {N{1'b0}};
                    wire [N-1:0] m3 = hit ? ({{(N-1){1'b0}}, 1'b1} << I3) : {N{1'b0}};
                    assign contrib[r*WIDTH*NSHAPE + c*NSHAPE + s] = m0 | m1 | m2 | m3;
                end else begin : g_oob
                    assign contrib[r*WIDTH*NSHAPE + c*NSHAPE + s] = {N{1'b0}};
                end
            end
        end
    end
endgenerate

integer k, b;
always @(*) begin
    erase_mask = {N{1'b0}};
    for (k = 0; k < N*NSHAPE; k = k + 1)
        erase_mask = erase_mask | contrib[k];
    erase_num = 0;
    for (b = 0; b < N; b = b + 1)
        erase_num = erase_num + erase_mask[b];
end

endmodule
