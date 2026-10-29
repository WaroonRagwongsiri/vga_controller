`timescale 1ns / 1ps
//==============================================================================
// vga_gfx_tb.v - self-checking testbench for vga_gfx_top (50 MHz clock)
//
// Checks:
//   * built-in test pattern is written (filler done)
//   * valid bus words land at the right framebuffer address
//   * bad parity, out-of-range X/Y and an unstable (glitching) word are
//     rejected and counted as 4 error events
//   * hsync 32 us / low 3.84 us, vsync 16.8 ms / low 64 us
//   * RGB is 0 during sync and outside the picture window
//   * picture window is screen lines 60..419 (white border rows)
//   * every palette colour appears on the VGA outputs
//
// Runtime: 40 ms of simulated time.
//==============================================================================
module vga_gfx_tb;

    reg         clk        = 1'b0;
    reg  [21:0] bus_d      = 22'd0;
    reg         bus_par    = 1'b0;
    reg         bus_strobe = 1'b0;

    wire        err_led;
    wire        hs, vs;
    wire [3:0]  r, g, b;

    vga_gfx_top #(.TEST_PATTERN(1)) dut (
        .clk        (clk),
        .bus_d      (bus_d),
        .bus_par    (bus_par),
        .bus_strobe (bus_strobe),
        .err_led    (err_led),
        .vga_hsync  (hs),
        .vga_vsync  (vs),
        .vga_r      (r),
        .vga_g      (g),
        .vga_b      (b)
    );

    always #10 clk = ~clk;           // 50 MHz

    //--------------------------------------------------------------------------
    // Sender model: data first, strobe later, hold, release
    //--------------------------------------------------------------------------
    task send_word;
        input [21:0] d;
        input        p;
        input        glitch;         // 1 = data changes right after the strobe rises
        begin
            @(posedge clk); #1;
            bus_d   = d;
            bus_par = p;
            repeat (3) @(posedge clk);       // setup (60 ns)
            #1; bus_strobe = 1'b1;
            if (glitch) begin
                #25; bus_d = ~d;             // falls between the two samples
            end
            repeat (6) @(posedge clk);       // hold (120 ns)
            #1; bus_strobe = 1'b0;
            repeat (3) @(posedge clk);       // strobe low (60 ns)
        end
    endtask

    //--------------------------------------------------------------------------
    // Expected palette (formula, independent of the case table in the DUT)
    //--------------------------------------------------------------------------
    function [11:0] exp_rgb;
        input [4:0] idx;
        reg   [3:0] v;
        begin
            v = {idx[2:0], idx[2]};
            case (idx[4:3])
                2'd0: exp_rgb = {v,    v,    v   };
                2'd1: exp_rgb = {v,    4'h0, 4'h0};
                2'd2: exp_rgb = {4'h0, v,    4'h0};
                2'd3: exp_rgb = {4'h0, 4'h0, v   };
            endcase
        end
    endfunction

    function [4:0] fb_read;
        input [15:0] a;
        begin
            fb_read = {dut.gfx.fb_hi[a], dut.gfx.fb_lo[a]};
        end
    endfunction

    localparam H_PERIOD = 32000;
    localparam H_LOW    = 3840;
    localparam V_PERIOD = 16800000;
    localparam V_LOW    = 64000;

    time    h_fall_prev = 0, h_fall = 0;
    time    v_fall_prev = 0, v_fall = 0;
    integer errors     = 0;
    integer h_checks   = 0;
    integer v_checks   = 0;
    integer err_events = 0;
    integer k;
    integer wmin = 9999, wmax = -1;
    reg [31:0] seen    = 32'd0;
    reg [11:0] last_rgb = 12'd0;
    reg        on2     = 1'b0;
    reg        saw_err_led = 1'b0;

    //--------------------------------------------------------------------------
    // hsync / vsync timing
    //--------------------------------------------------------------------------
    always @(negedge hs) begin
        h_fall = $time;
        if (h_fall_prev != 0) begin
            h_checks = h_checks + 1;
            if ((h_fall - h_fall_prev) != H_PERIOD) begin
                errors = errors + 1;
                $display("ERROR: hsync period = %0d ns (expected %0d)", h_fall - h_fall_prev, H_PERIOD);
            end
        end
        h_fall_prev = h_fall;
    end

    always @(posedge hs) begin
        if (h_fall != 0 && ($time - h_fall) != H_LOW) begin
            errors = errors + 1;
            $display("ERROR: hsync low = %0d ns (expected %0d)", $time - h_fall, H_LOW);
        end
    end

    always @(negedge vs) begin
        v_fall = $time;
        if (v_fall_prev != 0) begin
            v_checks = v_checks + 1;
            if ((v_fall - v_fall_prev) != V_PERIOD) begin
                errors = errors + 1;
                $display("ERROR: vsync period = %0d ns (expected %0d)", v_fall - v_fall_prev, V_PERIOD);
            end
        end
        v_fall_prev = v_fall;
    end

    always @(posedge vs) begin
        if (v_fall != 0 && ($time - v_fall) != V_LOW) begin
            errors = errors + 1;
            $display("ERROR: vsync low = %0d ns (expected %0d)", $time - v_fall, V_LOW);
        end
    end

    //--------------------------------------------------------------------------
    // blanking, palette colours, window rows, error events
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        on2 <= dut.gfx.win_on_delayed;

        if ((!hs || !vs) && ({r, g, b} !== 12'h000)) begin
            errors = errors + 1;
            $display("ERROR: RGB nonzero during sync at %0d ns", $time);
        end
        if (!on2 && ({r, g, b} !== 12'h000)) begin
            errors = errors + 1;
            $display("ERROR: RGB nonzero outside the picture window at %0d ns", $time);
        end

        if ({r, g, b} != last_rgb) begin
            last_rgb <= {r, g, b};
            for (k = 0; k < 32; k = k + 1)
                if ({r, g, b} == exp_rgb(k))
                    seen[k] = 1'b1;
        end

        if ($time > 2_000_000 && {r, g, b} == 12'hFFF) begin
            if (dut.gfx.v < wmin) wmin = dut.gfx.v;
            if (dut.gfx.v > wmax) wmax = dut.gfx.v;
        end

        if (dut.rx.err_unstable || dut.rx.err_bad_word)
            err_events = err_events + 1;

        if (err_led)
            saw_err_led = 1'b1;
    end

    //--------------------------------------------------------------------------
    // Stimulus and final checks
    //--------------------------------------------------------------------------
    reg [21:0] w;

    initial begin
        #1_500_000;                          // 1.5 ms: test-pattern fill is done

        if (dut.done !== 1'b1) begin
            errors = errors + 1;
            $display("ERROR: test-pattern filler not done after 1.5 ms");
        end

        // valid pixels
        w = {5'd31, 8'd50,  9'd100}; send_word(w, ^w, 1'b0);
        w = {5'd15, 8'd179, 9'd319}; send_word(w, ^w, 1'b0);
        w = {5'd23, 8'd0,   9'd0  }; send_word(w, ^w, 1'b0);

        // rejected: wrong parity
        w = {5'd30, 8'd10,  9'd10 }; send_word(w, ~(^w), 1'b0);
        // rejected: X out of range (320), Y out of range (180)
        w = {5'd29, 8'd10,  9'd320}; send_word(w, ^w, 1'b0);
        w = {5'd28, 8'd180, 9'd5  }; send_word(w, ^w, 1'b0);
        // rejected: bus not stable around the strobe
        w = {5'd27, 8'd20,  9'd50 }; send_word(w, ^w, 1'b1);

        #38_000_000;                         // run to about 40 ms in total

        // accepted writes
        if (fb_read(16'd16100) !== 5'd31) begin errors = errors + 1; $display("ERROR: fb(100,50)  != 31"); end
        if (fb_read(16'd57599) !== 5'd15) begin errors = errors + 1; $display("ERROR: fb(319,179) != 15"); end
        if (fb_read(16'd0)     !== 5'd23) begin errors = errors + 1; $display("ERROR: fb(0,0)     != 23"); end

        // rejected writes must leave the test pattern untouched
        if (fb_read(16'd3210)  !== 5'd1 ) begin errors = errors + 1; $display("ERROR: bad-parity word was written"); end
        if (fb_read(16'd3520)  !== 5'd7 ) begin errors = errors + 1; $display("ERROR: out-of-range X word was written"); end
        if (fb_read(16'd6450)  !== 5'd5 ) begin errors = errors + 1; $display("ERROR: unstable word was written"); end

        // test pattern spot checks (bar 3 at x=35, checker squares)
        if (fb_read(16'd10*320+16'd35) !== 5'd3) begin errors = errors + 1; $display("ERROR: bar at x=35 != 3"); end
        if (fb_read(16'd120*320+16'd0) !== 5'd7) begin errors = errors + 1; $display("ERROR: border at x=0 != 7"); end
        if (fb_read(16'd100*320+16'd8)  !== 5'd7) begin errors = errors + 1; $display("ERROR: checker (8,100)  != 7"); end
        if (fb_read(16'd100*320+16'd16) !== 5'd0) begin errors = errors + 1; $display("ERROR: checker (16,100) != 0"); end

        // error events and LED
        if (err_events != 4) begin
            errors = errors + 1;
            $display("ERROR: %0d error events (expected 4)", err_events);
        end
        if (!saw_err_led) begin
            errors = errors + 1;
            $display("ERROR: err_led never lit");
        end

        // picture window rows
        if (wmin != 60 || wmax != 419) begin
            errors = errors + 1;
            $display("ERROR: white border rows span lines %0d..%0d (expected 60..419)", wmin, wmax);
        end

        // palette colours (index 0, 8, 16, 24 are all black and always present)
        if ((seen | 32'h01010101) !== 32'hFFFFFFFF) begin
            errors = errors + 1;
            $display("ERROR: palette colours seen mask = %h", seen);
        end

        $display("----------------------------------------------");
        $display("hsync checks: %0d, vsync checks: %0d, error events: %0d", h_checks, v_checks, err_events);
        if (errors == 0) $display("PASS: bus, framebuffer, palette and VGA timing OK");
        else             $display("FAIL: %0d error(s)", errors);
        $display("----------------------------------------------");
        $finish;
    end

endmodule