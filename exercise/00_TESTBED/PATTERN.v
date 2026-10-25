`ifdef RTL
    `define CYCLE_TIME 20.0
`endif
`ifdef GATE
    `define CYCLE_TIME 7.0
`endif
`ifndef CYCLE_TIME
    `define CYCLE_TIME 20.0
`endif

`ifndef PAT_NUM
    `define PAT_NUM 1000
`endif
`define MAX_LATENCY 200

// Self-checking pattern generator for the Puyo Puyo Placement Solver.
// Boards are generated here (gravity-stable, no removable group, as the spec guarantees) and the
// expected answer is computed with a behavioural model: 22 candidates, flood-fill erase, gravity,
// chain counting, then the best-candidate rule.
module PATTERN(
    clk,
    rst_n,
    in_valid,
    in_cell,
    in_puyo_a,
    in_puyo_b,

    out_valid,
    out_best_candidate,
    out_chain,
    out_erased
);
output reg        clk;
output reg        rst_n;
output reg        in_valid;
output reg [2:0]  in_cell;
output reg [2:0]  in_puyo_a;
output reg [2:0]  in_puyo_b;

input             out_valid;
input      [4:0]  out_best_candidate;
input      [4:0]  out_chain;
input      [6:0]  out_erased;

localparam W = 6;
localparam H = 12;
localparam N = W * H;
real CYCLE = `CYCLE_TIME;

always #(CYCLE/2.0) clk = ~clk;

// ---------------------------------------------------------------- behavioural model
// cell index = row * W + col, row 0 is the bottom row
reg [2:0] base_b [0:N-1];       // input board
reg [2:0] wk     [0:N-1];       // working board
reg       msk    [0:N-1];
reg       seen   [0:N-1];
integer   stk    [0:N-1];
integer   cmp    [0:N-1];
integer   hcol   [0:W-1];
integer   gcnt;                 // cells found removable by find_groups
integer   ch_r, er_r;           // chain / erased of one evaluated board
integer   exp_id, exp_ch, exp_er;
reg       legal_any;
integer   seed;

task find_groups;               // marks msk[] on wk[], result in gcnt
    integer i, j, k, sp, cnt, r, c, nj;
    begin
        gcnt = 0;
        for (i = 0; i < N; i = i + 1) begin msk[i] = 1'b0; seen[i] = 1'b0; end
        for (i = 0; i < N; i = i + 1) begin
            if (wk[i] != 3'd0 && !seen[i]) begin
                sp = 1; cnt = 0; stk[0] = i; seen[i] = 1'b1;
                while (sp > 0) begin
                    sp = sp - 1; j = stk[sp];
                    cmp[cnt] = j; cnt = cnt + 1;
                    r = j / W; c = j % W;
                    if (r > 0)     begin nj = j - W; if (!seen[nj] && wk[nj] == wk[j]) begin seen[nj] = 1'b1; stk[sp] = nj; sp = sp + 1; end end
                    if (r < H - 1) begin nj = j + W; if (!seen[nj] && wk[nj] == wk[j]) begin seen[nj] = 1'b1; stk[sp] = nj; sp = sp + 1; end end
                    if (c > 0)     begin nj = j - 1; if (!seen[nj] && wk[nj] == wk[j]) begin seen[nj] = 1'b1; stk[sp] = nj; sp = sp + 1; end end
                    if (c < W - 1) begin nj = j + 1; if (!seen[nj] && wk[nj] == wk[j]) begin seen[nj] = 1'b1; stk[sp] = nj; sp = sp + 1; end end
                end
                if (cnt >= 4)
                    for (k = 0; k < cnt; k = k + 1) begin msk[cmp[k]] = 1'b1; gcnt = gcnt + 1; end
            end
        end
    end
endtask

task gravity_wk;
    integer c, r, k;
    begin
        for (c = 0; c < W; c = c + 1) begin
            k = 0;
            for (r = 0; r < H; r = r + 1)
                if (wk[r*W + c] != 3'd0) begin
                    if (k != r) begin wk[k*W + c] = wk[r*W + c]; wk[r*W + c] = 3'd0; end
                    k = k + 1;
                end
        end
    end
endtask

task eval_wk;                   // chain reaction on wk -> ch_r, er_r
    integer i;
    begin
        ch_r = 0; er_r = 0;
        find_groups;
        while (gcnt > 0) begin
            ch_r = ch_r + 1; er_r = er_r + gcnt;
            for (i = 0; i < N; i = i + 1) if (msk[i]) wk[i] = 3'd0;
            gravity_wk;
            find_groups;
        end
    end
endtask

task heights;
    integer c, r;
    begin
        for (c = 0; c < W; c = c + 1) begin
            hcol[c] = 0;
            for (r = 0; r < H; r = r + 1) if (base_b[r*W + c] != 3'd0) hcol[c] = hcol[c] + 1;
        end
    end
endtask

task place_cand;                // builds wk from base_b; ok = 0 when the candidate is illegal
    input integer k;
    input [2:0] a, b;
    output ok;
    integer i, c, l;
    reg [2:0] lo, hi;
    begin
        for (i = 0; i < N; i = i + 1) wk[i] = base_b[i];
        ok = 1'b1;
        if (k < 12) begin
            c = (k < 6) ? k : k - 6;
            lo = (k < 6) ? b : a;  hi = (k < 6) ? a : b;
            if (hcol[c] > 10) ok = 1'b0;
            else begin wk[hcol[c]*W + c] = lo; wk[(hcol[c]+1)*W + c] = hi; end
        end else begin
            l = (k < 17) ? k - 12 : k - 17;
            lo = (k < 17) ? a : b;  hi = (k < 17) ? b : a;       // lo = left piece, hi = right piece
            if (hcol[l] > 11 || hcol[l+1] > 11) ok = 1'b0;
            else begin wk[hcol[l]*W + l] = lo; wk[hcol[l+1]*W + l + 1] = hi; end
        end
    end
endtask

task calc_best;                     // best candidate for base_b with pieces a, b
    input [2:0] a, b;
    integer k;
    reg ok;
    begin
        heights;
        legal_any = 1'b0; exp_id = 0; exp_ch = 0; exp_er = 0;
        for (k = 0; k < 22; k = k + 1) begin
            place_cand(k, a, b, ok);
            if (ok) begin
                eval_wk;
                if (!legal_any || ch_r > exp_ch || (ch_r == exp_ch && er_r > exp_er)) begin
                    legal_any = 1'b1; exp_id = k; exp_ch = ch_r; exp_er = er_r;
                end
            end
        end
    end
endtask

// ---------------------------------------------------------------- board generation
function integer rnd;
    input integer n;
    begin rnd = {$random(seed)} % n; end
endfunction

task gen_board;                 // fill: average column height in cells, ncol: number of colours
    input integer fill;
    input integer ncol;
    integer c, r, h_t, t, col0, col, i, done;
    begin
        for (i = 0; i < N; i = i + 1) base_b[i] = 3'd0;
        for (c = 0; c < W; c = c + 1) begin
            h_t = fill + rnd(5) - 2;
            if (h_t < 0) h_t = 0;
            if (h_t > H) h_t = H;
            for (r = 0; r < h_t; r = r + 1) begin
                done = 0; col0 = rnd(ncol);
                for (t = 0; t < ncol && !done; t = t + 1) begin
                    col = 1 + ((col0 + t) % ncol);
                    base_b[r*W + c] = col;
                    for (i = 0; i < N; i = i + 1) wk[i] = base_b[i];
                    find_groups;
                    if (gcnt == 0) done = 1;
                end
                if (!done) begin base_b[r*W + c] = 3'd0; r = h_t; end
            end
        end
    end
endtask

task climb;                     // mutate the board while keeping it legal, to find long chains
    input [2:0] a, b;
    input integer steps;
    integer s, p, old, ch_best, er_best, i;
    begin
        calc_best(a, b);
        ch_best = exp_ch; er_best = exp_er;
        for (s = 0; s < steps; s = s + 1) begin
            p = rnd(N);
            if (base_b[p] != 3'd0) begin
                old = base_b[p];
                base_b[p] = 1 + rnd(4);
                for (i = 0; i < N; i = i + 1) wk[i] = base_b[i];
                find_groups;
                if (gcnt != 0) base_b[p] = old;
                else begin
                    calc_best(a, b);
                    if (legal_any && (exp_ch > ch_best || (exp_ch == ch_best && exp_er >= er_best))) begin
                        ch_best = exp_ch; er_best = exp_er;
                    end else base_b[p] = old;
                end
            end
        end
    end
endtask

// ---------------------------------------------------------------- stimulus and checking
integer pat, i, lat, gap, mismatch, max_lat, sum_lat, mode;
reg [2:0] pa, pb;

task wait_cycles;
    input integer n;
    integer t;
    begin for (t = 0; t < n; t = t + 1) @(negedge clk); end
endtask

// out_valid must stay low while in_valid is high
always @(negedge clk) begin
    if (in_valid === 1'b1 && out_valid === 1'b1) begin
        $display("[FAIL] out_valid is high while in_valid is high (time %0t)", $time);
        $finish;
    end
end

initial begin
    clk = 1'b0; rst_n = 1'b1; in_valid = 1'b0;
    in_cell = 3'bx; in_puyo_a = 3'bx; in_puyo_b = 3'bx;
    seed = 20261026;
    mismatch = 0; max_lat = 0; sum_lat = 0;

    // ---- reset: all outputs must be 0 while / after reset is asserted
    #(CYCLE * 0.25) rst_n = 1'b0;
    #(CYCLE * 2.0);
    @(negedge clk);
    if (out_valid !== 1'b0 || out_best_candidate !== 5'd0 || out_chain !== 5'd0 || out_erased !== 7'd0) begin
        $display("[FAIL] outputs are not 0 after reset: valid=%b cand=%0d chain=%0d erased=%0d",
                 out_valid, out_best_candidate, out_chain, out_erased);
        mismatch = mismatch + 1;
    end
    #(CYCLE * 0.5) rst_n = 1'b1;
    wait_cycles(3);

    for (pat = 0; pat < `PAT_NUM; pat = pat + 1) begin
        // ---- build one input
        legal_any = 1'b0;
        while (!legal_any) begin
            mode = pat % 10;
            case (mode)
                0: gen_board(0, 4);             // empty board
                1: gen_board(2, 4);
                2: gen_board(4, 4);
                3: gen_board(7, 4);
                4: gen_board(10, 4);
                5: gen_board(12, 4);            // (nearly) full
                6: gen_board(6, 2);             // two colours: many near-groups
                7: gen_board(8, 3);
                8: gen_board(6, 4);
                default: gen_board(8, 4);
            endcase
            pa = 1 + rnd(4);
            pb = (rnd(5) == 0) ? pa : 1 + rnd(4);
            if (mode == 9 && pat % 20 == 9) pb = pa;
            calc_best(pa, pb);
            if (legal_any && (mode == 8 || mode == 9)) begin
                climb(pa, pb, 40);                 // long-chain boards
                calc_best(pa, pb);
            end
        end

        // ---- drive the board: top row first, left to right, inputs change on the negative edge
        for (i = 0; i < N; i = i + 1) begin
            in_valid  = 1'b1;
            in_cell   = base_b[(H - 1 - i / W) * W + (i % W)];
            in_puyo_a = (i == 0) ? pa : 3'bx;
            in_puyo_b = (i == 0) ? pb : 3'bx;
            @(negedge clk);
        end
        in_valid = 1'b0; in_cell = 3'bx; in_puyo_a = 3'bx; in_puyo_b = 3'bx;

        // ---- wait for the answer
        lat = 0;
        while (out_valid !== 1'b1 && lat < `MAX_LATENCY) begin
            @(negedge clk);
            lat = lat + 1;
        end
        if (out_valid !== 1'b1) begin
            $display("[FAIL] pattern %0d: no out_valid within %0d cycles", pat, `MAX_LATENCY);
            $finish;
        end
        if (lat > max_lat) max_lat = lat;
        sum_lat = sum_lat + lat;
        if (out_best_candidate !== exp_id[4:0] || out_chain !== exp_ch[4:0] || out_erased !== exp_er[6:0]) begin
            mismatch = mismatch + 1;
            if (mismatch <= 10)
                $display("[FAIL] pattern %0d (A=%0d B=%0d): got cand=%0d chain=%0d erased=%0d, expected cand=%0d chain=%0d erased=%0d",
                         pat, pa, pb, out_best_candidate, out_chain, out_erased, exp_id, exp_ch, exp_er);
        end
        @(negedge clk);
        if (out_valid !== 1'b0) begin
            $display("[FAIL] pattern %0d: out_valid is high for more than one cycle", pat);
            mismatch = mismatch + 1;
        end
        gap = 2 + rnd(4);
        wait_cycles(gap);
    end

    if (mismatch == 0) begin
        $display("**********************************************");
        $display("  PASS  %0d patterns, max latency %0d, average latency %0d.%02d cycles",
                 `PAT_NUM, max_lat, sum_lat / `PAT_NUM, (sum_lat * 100 / `PAT_NUM) % 100);
        $display("**********************************************");
    end else begin
        $display("**********************************************");
        $display("  FAIL  %0d wrong results out of %0d patterns", mismatch, `PAT_NUM);
        $display("**********************************************");
    end
    $finish;
end

endmodule
