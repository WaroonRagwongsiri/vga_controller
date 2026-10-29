`timescale 1ns / 1ps
//==============================================================================
// vga_bus_rx.v - parallel pixel-bus receiver (input stage)
//
// Picture is 320 x 180 pixels, 5 bits per pixel (direct colour 2R 1G 2B).
//
// Word on the wires (22 data bits + 1 parity bit, written by the sender):
//   bus_d[8:0]   = X        (0..319)
//   bus_d[16:9]  = Y        (0..179)
//   bus_d[21:17] = colour   {R[1:0], G[0], B[1:0]}
//   bus_par      = even parity over bus_d (bus_par == ^bus_d)
//   bus_strobe   = rising edge means "read the bus now"
//
// Checks done here (a failed word is dropped and err_led is lit 100 ms):
//   1. both samples of the bus must match (stability check)
//   2. parity must be even over the 22 data bits + parity bit
//   3. X <= 319 and Y <= 179
//
// Sender timing needed (50 MHz clock here):
//   data stable >= ~50 ns before the strobe rises, held >= ~100 ns after it,
//   strobe low >= ~50 ns between words.
//==============================================================================
module vga_bus_rx (
    input  wire        clk,         // 50 MHz
    input  wire [21:0] bus_d,
    input  wire        bus_par,
    input  wire        bus_strobe,

    output reg         wr_en,       // one-clock write pulse
    output reg  [15:0] wr_addr,     // Y*320 + X
    output reg  [4:0]  wr_data,     // colour
    output wire        err_led      // stretched error indicator
);

    //--------------------------------------------------------------------------
    // 2-FF synchronizers (all lines are asynchronous to clk)
    // d_s2 and stb_s2 are the same sample in time, so they stay aligned.
    //--------------------------------------------------------------------------
    reg [22:0] d_s1   = 23'd0;
    reg [22:0] d_s2   = 23'd0;
    reg        stb_s1 = 1'b0;
    reg        stb_s2 = 1'b0;
    reg        stb_s3 = 1'b0;

    always @(posedge clk) begin
        d_s1   <= {bus_par, bus_d};
        d_s2   <= d_s1;
        stb_s1 <= bus_strobe;
        stb_s2 <= stb_s1;
        stb_s3 <= stb_s2;
    end

    wire stb_rise = stb_s2 & ~stb_s3;

    //--------------------------------------------------------------------------
    // Stage 1: capture on the strobe edge, compare with the next clock's sample
    //--------------------------------------------------------------------------
    reg        check_pending = 1'b0;    // a capture happened last clock, check it now
    reg [22:0] captured      = 23'd0;   // bus word saved on the strobe edge
    reg        word_valid    = 1'b0;    // one-clock pulse: `word` passed the stability check
    reg [22:0] word          = 23'd0;   // verified word {parity, colour, Y, X}
    reg        err_unstable  = 1'b0;    // one-clock pulse: bus changed right after the strobe

    always @(posedge clk) begin
        check_pending <= stb_rise;
        if (stb_rise)
            captured <= d_s2;

        word_valid   <= 1'b0;
        err_unstable <= 1'b0;
        if (check_pending) begin
            if (d_s2 == captured) begin
                word_valid <= 1'b1;
                word       <= captured;
            end else begin
                err_unstable <= 1'b1;
            end
        end
    end

    //--------------------------------------------------------------------------
    // Stage 2: parity + range checks, address calculation, write pulse
    //   addr = Y*320 + X = (Y<<8) + (Y<<6) + X   (no multiplier)
    //--------------------------------------------------------------------------
    wire [8:0]  x         = word[8:0];
    wire [7:0]  y         = word[16:9];
    wire [4:0]  colour    = word[21:17];
    wire        parity_ok = ~(^word);                       // even parity over all 23 bits
    wire        range_ok  = (x <= 9'd319) && (y <= 8'd179);
    wire [15:0] addr      = ({8'd0, y} << 8) + ({8'd0, y} << 6) + {7'd0, x};

    reg err_bad_word = 1'b0;    // one-clock pulse: parity or X/Y range check failed

    initial begin
        wr_en   = 1'b0;
        wr_addr = 16'd0;
        wr_data = 5'd0;
    end

    always @(posedge clk) begin
        wr_en        <= 1'b0;
        err_bad_word <= 1'b0;
        if (word_valid) begin
            if (parity_ok && range_ok) begin
                wr_en   <= 1'b1;
                wr_addr <= addr;
                wr_data <= colour;
            end else begin
                err_bad_word <= 1'b1;
            end
        end
    end

    //--------------------------------------------------------------------------
    // Error stretcher: ERR_HOLD clocks at 50 MHz = 100 ms, visible on an LED
    //   ERR_HOLD = CLK_HZ / 1000 * ERR_MS = 5,000,000 (fits in 23 bits, max ~167 ms)
    //--------------------------------------------------------------------------
    localparam integer CLK_HZ   = 50_000_000;
    localparam integer ERR_MS   = 100;
    localparam [22:0]  ERR_HOLD = CLK_HZ / 1000 * ERR_MS;

    reg [22:0] err_cnt = 23'd0;
    always @(posedge clk) begin
        if (err_unstable | err_bad_word)
            err_cnt <= ERR_HOLD;
        else if (err_cnt != 23'd0)
            err_cnt <= err_cnt - 23'd1;
    end

    assign err_led = (err_cnt != 23'd0);

endmodule
