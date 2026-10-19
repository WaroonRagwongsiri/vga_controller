`timescale 1ns / 1ps
//==============================================================================
// vga_pattern_top.v - colour-chart top (no bus input, only VGA out)
//
// Draws every possible colour of the 5-bit direct-colour format
// {R[1:0], G[0], B[1:0]} once into the framebuffer, then just keeps showing it.
// Uses the same core as the real design (vga_gfx.v), so it tests the
// framebuffer, colour decode, 2x scaling and VGA timing.
//
// Chart (320x180 picture, 8 columns x 4 rows of 40x45 swatches):
//   row    = red   level 0..3   (top to bottom)
//   column = {G, B}: 0..7 left to right
//              col 0..3 : green off, blue 0..3
//              col 4..7 : green on,  blue 0..3
//   colour value of a swatch = row*8 + column   (0 = black .. 31 = white)
// A 1-pixel white frame marks the edge of the picture.
//
// Needs only clk and the VGA pins: use vga_pattern.xdc.
//==============================================================================
module vga_pattern_top (
    input  wire        clk,          // 50 MHz

    output wire        vga_hsync,
    output wire        vga_vsync,
    output wire [3:0]  vga_r,
    output wire [3:0]  vga_g,
    output wire [3:0]  vga_b
);

    //--------------------------------------------------------------------------
    // Chart filler: writes all 57,600 pixels once after configuration
    //--------------------------------------------------------------------------
    reg        f_we    = 1'b0;
    reg [15:0] f_addr  = 16'd0;
    reg [4:0]  f_data  = 5'd0;

    reg        done    = 1'b0;
    reg [15:0] a_cnt   = 16'd0;      // running address = y*320 + x
    reg [8:0]  fx      = 9'd0;       // 0..319
    reg [7:0]  fy      = 8'd0;       // 0..179
    reg [2:0]  col     = 3'd0;       // swatch column 0..7
    reg [5:0]  col_cnt = 6'd0;       // pixels into the swatch (0..39)
    reg [1:0]  row     = 2'd0;       // swatch row 0..3
    reg [5:0]  row_cnt = 6'd0;       // lines into the swatch (0..44)

    wire       border  = (fx == 9'd0) || (fx == 9'd319) || (fy == 8'd0) || (fy == 8'd179);
    wire [4:0] pattern = border ? 5'd31 : {row, col};

    always @(posedge clk) begin
        if (!done) begin
            f_we   <= 1'b1;
            f_addr <= a_cnt;
            f_data <= pattern;
            a_cnt  <= a_cnt + 16'd1;

            if (fx == 9'd319) begin
                fx      <= 9'd0;
                col     <= 3'd0;
                col_cnt <= 6'd0;
                fy      <= fy + 8'd1;
                if (row_cnt == 6'd44) begin
                    row_cnt <= 6'd0;
                    row     <= row + 2'd1;
                end else begin
                    row_cnt <= row_cnt + 6'd1;
                end
            end else begin
                fx <= fx + 9'd1;
                if (col_cnt == 6'd39) begin
                    col_cnt <= 6'd0;
                    col     <= col + 3'd1;
                end else begin
                    col_cnt <= col_cnt + 6'd1;
                end
            end

            if (a_cnt == 16'd57599)
                done <= 1'b1;
        end else begin
            f_we <= 1'b0;
        end
    end

    //--------------------------------------------------------------------------
    // Graphics core (same module as the real design)
    //--------------------------------------------------------------------------
    vga_gfx gfx (
        .clk       (clk),
        .wr_en     (f_we),
        .wr_addr   (f_addr),
        .wr_data   (f_data),
        .vga_hsync (vga_hsync),
        .vga_vsync (vga_vsync),
        .vga_r     (vga_r),
        .vga_g     (vga_g),
        .vga_b     (vga_b),
        .vblank    ()
    );

endmodule
