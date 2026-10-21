`timescale 1ns/1ps
// Soft-IP-only testbench: 6 parameter settings, vectors from dat/ip_WxH_*.dat
module ip_check #(parameter W = 6, parameter H = 12, parameter NV = 400, parameter TAG = "6x12");
localparam N = W*H;
reg  [N*3-1:0] board_in;
wire [N-1:0]   erase_mask;
wire [$clog2(N+1)-1:0] erase_num;
reg  [N*3-1:0] m_in   [0:NV-1];
reg  [N-1:0]   m_mask [0:NV-1];
reg  [31:0]    m_num  [0:NV-1];
integer t, errs;
reg [8*64:1] fn;
PUYO_SOFT_IP #(.WIDTH(W), .HEIGHT(H)) dut (.board_in(board_in), .erase_mask(erase_mask), .erase_num(erase_num));
initial begin
    errs = 0;
    $sformat(fn, "dat/ip_%0dx%0d_in.dat",   W, H); $readmemh(fn, m_in);
    $sformat(fn, "dat/ip_%0dx%0d_mask.dat", W, H); $readmemh(fn, m_mask);
    $sformat(fn, "dat/ip_%0dx%0d_num.dat",  W, H); $readmemh(fn, m_num);
    for (t = 0; t < NV; t = t + 1) begin
        board_in = m_in[t];
        #1;
        if (erase_mask !== m_mask[t] || erase_num !== m_num[t][$clog2(N+1)-1:0]) begin
            errs = errs + 1;
            if (errs < 4) $display("FAIL IP %0s vec %0d: mask %h exp %h, num %0d exp %0d",
                                   TAG, t, erase_mask, m_mask[t], erase_num, m_num[t]);
        end
    end
    $display("IP %0dx%0d : %0s (%0d vectors, %0d errors)", W, H, errs == 0 ? "PASS" : "FAIL", NV, errs);
end
endmodule

module Pattern_IP;
ip_check #(3, 4)  c0 ();
ip_check #(4, 6)  c1 ();
ip_check #(5, 8)  c2 ();
ip_check #(6, 10) c3 ();
ip_check #(6, 12) c4 ();
ip_check #(8, 12) c5 ();
initial #2000 $finish;
endmodule
