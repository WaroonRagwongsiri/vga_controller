`timescale 1ns / 1ps
//==============================================================================
// vga_gfx.v - VGA scanner + framebuffer + direct-colour decode
//
//   Signal   : 640x480 @ ~60 Hz (VESA timing, 25 MHz pixel tick from 50 MHz)
//   Picture  : 320x180 pixels, 5 bits each, drawn 2x2 -> 640x360 on screen,
//              screen lines 60..419, black bars above and below
//   Memory   : two block RAMs, 57,600 x 4 bit (8 tiles) + 57,600 x 1 bit (2 tiles)
//   Colour   : 5 bits = {R[1:0], G[0], B[1:0]}, expanded to RGB444 (see colour_to_rgb)
//
// Pipeline (all aligned by the same 2-clock delay):
//   t+0 : h, v counters -> framebuffer read address
//   t+1 : RAM data (colour) arrives; hsync / vsync / window flag delayed
//   t+2 : colour expand -> registered VGA outputs
//==============================================================================
module vga_gfx (
    input  wire        clk,         // 50 MHz

    // framebuffer write port (same clock).  address = Y*320 + X
    input  wire        wr_en,
    input  wire [15:0] wr_addr,
    input  wire [4:0]  wr_data,

    // VGA outputs
    output reg         vga_hsync,   // active low
    output reg         vga_vsync,   // active low
    output reg  [3:0]  vga_r,
    output reg  [3:0]  vga_g,
    output reg  [3:0]  vga_b,

    // status
    output reg         vblank       // high while v >= 480
);

    //--------------------------------------------------------------------------
    // 640x480 @ 60 Hz timing constants
    //--------------------------------------------------------------------------
    localparam H_VISIBLE = 640;
    localparam H_FRONT   = 16;
    localparam H_SYNC    = 96;
    localparam H_BACK    = 48;
    localparam H_TOTAL   = H_VISIBLE + H_FRONT + H_SYNC + H_BACK;   // 800

    localparam V_VISIBLE = 480;
    localparam V_FRONT   = 10;
    localparam V_SYNC    = 2;
    localparam V_BACK    = 33;
    localparam V_TOTAL   = V_VISIBLE + V_FRONT + V_SYNC + V_BACK;   // 525

    localparam H_SYNC_START = H_VISIBLE + H_FRONT;                  // 656
    localparam H_SYNC_END   = H_SYNC_START + H_SYNC;                // 752
    localparam V_SYNC_START = V_VISIBLE + V_FRONT;                  // 490
    localparam V_SYNC_END   = V_SYNC_START + V_SYNC;                // 492

    // picture window on screen: 360 lines centred in 480
    localparam WIN_V_START = 60;
    localparam WIN_V_END   = 420;

    localparam FB_SIZE = 320 * 180;                                 // 57,600

    //--------------------------------------------------------------------------
    // Pixel tick: 50 MHz / 2 = 25 MHz (clock enable)
    //--------------------------------------------------------------------------
    reg tick = 1'b0;
    always @(posedge clk)
        tick <= ~tick;

    //--------------------------------------------------------------------------
    // Pixel counters
    //--------------------------------------------------------------------------
    reg [9:0] h = 10'd0;
    reg [9:0] v = 10'd0;

    always @(posedge clk) begin
        if (tick) begin
            if (h == H_TOTAL - 1) begin
                h <= 10'd0;
                if (v == V_TOTAL - 1)
                    v <= 10'd0;
                else
                    v <= v + 10'd1;
            end else begin
                h <= h + 10'd1;
            end
        end
    end

    wire win_on = (h < H_VISIBLE) && (v >= WIN_V_START) && (v < WIN_V_END);

    //--------------------------------------------------------------------------
    // Framebuffer read address: x = h/2 (0..319), y = (v-60)/2 (0..179)
    // addr = y*320 + x = (y<<8) + (y<<6) + x
    //--------------------------------------------------------------------------
    wire [9:0]  v_win = v - 10'd60;
    wire [8:0]  x_fb  = h[9:1];
    wire [7:0]  y_fb  = v_win[8:1];
    wire [15:0] rd_addr_raw = ({8'd0, y_fb} << 8) + ({8'd0, y_fb} << 6) + {7'd0, x_fb};
    wire [15:0] rd_addr     = win_on ? rd_addr_raw : 16'd0;   // keep in range

    //--------------------------------------------------------------------------
    // Framebuffer: two simple dual-port block RAMs (4-bit part + 1-bit part)
    // Written as separate memories so Vivado maps them to 8 + 2 tiles.
    //--------------------------------------------------------------------------
    (* ram_style = "block" *) reg [3:0] fb_lo [0:FB_SIZE-1];   // colour bits [3:0]
    (* ram_style = "block" *) reg       fb_hi [0:FB_SIZE-1];   // colour bit  [4]

    integer i;
    initial begin
        for (i = 0; i < FB_SIZE; i = i + 1) begin
            fb_lo[i] = 4'd0;
            fb_hi[i] = 1'b0;
        end
    end

    reg [3:0] rd_lo = 4'd0;
    reg       rd_hi = 1'b0;

    always @(posedge clk) begin
        if (wr_en) begin
            fb_lo[wr_addr] <= wr_data[3:0];
            fb_hi[wr_addr] <= wr_data[4];
        end
        rd_lo <= fb_lo[rd_addr];
        rd_hi <= fb_hi[rd_addr];
    end

    //--------------------------------------------------------------------------
    // Direct colour: 5 bits = {R[1:0], G[0], B[1:0]} -> RGB444.
    // Each field is replicated to fill 4 bits so full scale is exactly F:
    //   2-bit 00,01,10,11 -> 0,5,A,F      1-bit 0,1 -> 0,F
    //--------------------------------------------------------------------------
    function [11:0] colour_to_rgb;
        input [4:0] c;
        reg   [1:0] r;
        reg         g;
        reg   [1:0] b;
        begin
            r = c[4:3];
            g = c[2];
            b = c[1:0];
            colour_to_rgb = {r, r, {4{g}}, b, b};
        end
    endfunction

    //--------------------------------------------------------------------------
    // Pipeline stage 1: delay sync and window flag to match the RAM latency
    //--------------------------------------------------------------------------
    reg hs1 = 1'b1;
    reg vs1 = 1'b1;
    reg on1 = 1'b0;

    always @(posedge clk) begin
        hs1 <= ~((h >= H_SYNC_START) && (h < H_SYNC_END));
        vs1 <= ~((v >= V_SYNC_START) && (v < V_SYNC_END));
        on1 <= win_on;
    end

    //--------------------------------------------------------------------------
    // Pipeline stage 2: colour expand and registered outputs
    //--------------------------------------------------------------------------
    initial begin
        vga_hsync = 1'b1;
        vga_vsync = 1'b1;
        vga_r     = 4'd0;
        vga_g     = 4'd0;
        vga_b     = 4'd0;
        vblank    = 1'b0;
    end

    wire [11:0] pix_rgb = colour_to_rgb({rd_hi, rd_lo});

    always @(posedge clk) begin
        vga_hsync <= hs1;
        vga_vsync <= vs1;
        vblank    <= (v >= V_VISIBLE);

        if (on1) begin
            vga_r <= pix_rgb[11:8];
            vga_g <= pix_rgb[7:4];
            vga_b <= pix_rgb[3:0];
        end else begin
            vga_r <= 4'd0;
            vga_g <= 4'd0;
            vga_b <= 4'd0;
        end
    end

endmodule
