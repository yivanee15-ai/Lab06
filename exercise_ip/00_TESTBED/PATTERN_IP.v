`ifndef CYCLE_TIME
    `define CYCLE_TIME 20.0
`endif

// Self-checking pattern for PUYO_SOFT_IP.
// The expected result is computed here with a behavioural flood fill (4-neighbour groups of the
// same non-zero colour; a group of four or more cells is erased), then compared with the DUT.
module PATTERN_IP #(parameter WIDTH = 6, parameter HEIGHT = 12)(
    output reg [WIDTH*HEIGHT*3-1:0] board_in,
    input      [WIDTH*HEIGHT-1:0]   erase_mask,
    input      [$clog2(WIDTH*HEIGHT+1)-1:0] erase_num
);

localparam N = WIDTH * HEIGHT;

reg [2:0]  cell_v   [0:N-1];
reg        visited  [0:N-1];
integer    stack_a  [0:N-1];
integer    comp_a   [0:N-1];
reg [N-1:0] exp_mask;
integer     exp_num;
integer     errors, total, seed;

// ---------------------------------------------------------------- golden model
task compute_golden;
    integer i, j, k, sp, cnt, r, c, nj;
    begin
        exp_mask = {N{1'b0}};
        exp_num  = 0;
        for (i = 0; i < N; i = i + 1) visited[i] = 1'b0;
        for (i = 0; i < N; i = i + 1) begin
            if (cell_v[i] != 3'd0 && !visited[i]) begin
                sp = 0; cnt = 0;
                stack_a[0] = i; sp = 1; visited[i] = 1'b1;
                while (sp > 0) begin
                    sp = sp - 1;
                    j = stack_a[sp];
                    comp_a[cnt] = j; cnt = cnt + 1;
                    r = j / WIDTH; c = j % WIDTH;
                    if (r > 0) begin
                        nj = j - WIDTH;
                        if (!visited[nj] && cell_v[nj] == cell_v[j]) begin visited[nj] = 1'b1; stack_a[sp] = nj; sp = sp + 1; end
                    end
                    if (r < HEIGHT - 1) begin
                        nj = j + WIDTH;
                        if (!visited[nj] && cell_v[nj] == cell_v[j]) begin visited[nj] = 1'b1; stack_a[sp] = nj; sp = sp + 1; end
                    end
                    if (c > 0) begin
                        nj = j - 1;
                        if (!visited[nj] && cell_v[nj] == cell_v[j]) begin visited[nj] = 1'b1; stack_a[sp] = nj; sp = sp + 1; end
                    end
                    if (c < WIDTH - 1) begin
                        nj = j + 1;
                        if (!visited[nj] && cell_v[nj] == cell_v[j]) begin visited[nj] = 1'b1; stack_a[sp] = nj; sp = sp + 1; end
                    end
                end
                if (cnt >= 4)
                    for (k = 0; k < cnt; k = k + 1) begin
                        exp_mask[comp_a[k]] = 1'b1;
                        exp_num = exp_num + 1;
                    end
            end
        end
    end
endtask

// ---------------------------------------------------------------- apply one board and check
task apply_and_check;
    input [8*24-1:0] tag;
    integer i;
    begin
        for (i = 0; i < N; i = i + 1) board_in[3*i +: 3] = cell_v[i];
        compute_golden;
        #(`CYCLE_TIME);
        total = total + 1;
        if (erase_mask !== exp_mask || erase_num !== exp_num[$clog2(N+1)-1:0]) begin
            errors = errors + 1;
            if (errors <= 10) begin
                $display("[FAIL] %0s #%0d  size %0dx%0d", tag, total, WIDTH, HEIGHT);
                $display("       board_in   = %h", board_in);
                $display("       erase_mask = %h  expected %h", erase_mask, exp_mask);
                $display("       erase_num  = %0d  expected %0d", erase_num, exp_num);
            end
        end
    end
endtask

// ---------------------------------------------------------------- pattern helpers
integer ii, jj, kk, rr, cc, len, col, ncol, dens;

task clear_board;
    begin
        for (ii = 0; ii < N; ii = ii + 1) cell_v[ii] = 3'd0;
    end
endtask

task random_board;
    input integer ncolors;
    input integer empty_pct;
    begin
        for (ii = 0; ii < N; ii = ii + 1)
            if (({$random(seed)} % 100) < empty_pct) cell_v[ii] = 3'd0;
            else cell_v[ii] = 1 + ({$random(seed)} % ncolors);
    end
endtask

// a straight run of colour col starting at (rr,cc); horizontal when dir == 0, vertical otherwise
task put_run;
    input integer r0, c0, n, dir, colr;
    integer t;
    begin
        for (t = 0; t < n; t = t + 1) begin
            if (dir == 0) begin
                if (c0 + t < WIDTH)  cell_v[r0*WIDTH + c0 + t] = colr;
            end else begin
                if (r0 + t < HEIGHT) cell_v[(r0 + t)*WIDTH + c0] = colr;
            end
        end
    end
endtask

// ---------------------------------------------------------------- stimulus
initial begin
    errors = 0; total = 0; seed = 20261026 + WIDTH * 100 + HEIGHT;
    board_in = {N*3{1'b0}};
    #(`CYCLE_TIME);

    // all empty
    clear_board;                                  apply_and_check("all empty");
    // all one colour (every cell erased) for each colour
    for (col = 1; col <= 4; col = col + 1) begin
        for (ii = 0; ii < N; ii = ii + 1) cell_v[ii] = col;
        apply_and_check("all same colour");
    end
    // checkerboard of two colours: nothing is connected
    for (ii = 0; ii < N; ii = ii + 1) cell_v[ii] = 1 + (((ii / WIDTH) + (ii % WIDTH)) % 2);
    apply_and_check("checkerboard");
    // four colours in a diagonal-stripe pattern: nothing is connected
    for (ii = 0; ii < N; ii = ii + 1) cell_v[ii] = 1 + (((ii / WIDTH) + 2 * (ii % WIDTH)) % 4);
    apply_and_check("stripes");

    // single runs of length 1..5, every start position, both directions
    for (len = 1; len <= 5; len = len + 1)
        for (rr = 0; rr < HEIGHT; rr = rr + 1)
            for (cc = 0; cc < WIDTH; cc = cc + 1) begin
                clear_board; put_run(rr, cc, len, 0, 1 + ((rr + cc) % 4)); apply_and_check("horizontal run");
                clear_board; put_run(rr, cc, len, 1, 1 + ((rr + cc) % 4)); apply_and_check("vertical run");
            end

    // L / T / S / square shapes of four cells and the same shapes with a different colour tail
    for (rr = 0; rr < HEIGHT - 1; rr = rr + 1)
        for (cc = 0; cc < WIDTH - 1; cc = cc + 1) begin
            clear_board; cell_v[rr*WIDTH+cc] = 2; cell_v[rr*WIDTH+cc+1] = 2;
                         cell_v[(rr+1)*WIDTH+cc] = 2; cell_v[(rr+1)*WIDTH+cc+1] = 2;      apply_and_check("square");
            cell_v[(rr+1)*WIDTH+cc+1] = 3;                                                apply_and_check("square minus one");
            clear_board; cell_v[rr*WIDTH+cc] = 4; cell_v[(rr+1)*WIDTH+cc+1] = 4;          apply_and_check("diagonal only");
        end
    for (rr = 0; rr < HEIGHT - 1; rr = rr + 1)
        for (cc = 1; cc < WIDTH - 1; cc = cc + 1) begin
            clear_board; put_run(rr, cc-1, 3, 0, 3); cell_v[(rr+1)*WIDTH+cc] = 3;         apply_and_check("T shape");
            clear_board; put_run(rr, cc-1, 3, 0, 3); cell_v[(rr+1)*WIDTH+cc] = 1;         apply_and_check("T wrong tail");
        end

    // random boards: colour count, density of empty cells and size of the board all vary
    for (kk = 0; kk < 3000; kk = kk + 1) begin
        ncol = 1 + ({$random(seed)} % 4);
        dens = ({$random(seed)} % 4) * 15;
        random_board(ncol, dens);
        apply_and_check("random");
    end

    if (errors == 0) begin
        $display("**********************************************");
        $display("  IP PASS  %0dx%0d : %0d boards", WIDTH, HEIGHT, total);
        $display("**********************************************");
    end else begin
        $display("**********************************************");
        $display("  IP FAIL  %0dx%0d : %0d of %0d boards wrong", WIDTH, HEIGHT, errors, total);
        $display("**********************************************");
    end
    $finish;
end

endmodule
