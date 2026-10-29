`timescale 1ns / 1ps
//==============================================================================
// vga_bus_top.v - the real top: pixels arrive on the bus pins (no test pattern)
//
// EDGE Spartan-7 as a VGA display chip.  A sender board writes pixels over a
// 24-wire parallel bus; each accepted write goes into a 320x180x5 framebuffer
// that is shown as 640x480 @ 60 Hz VGA (picture 640x360, 2x2 per pixel,
// screen lines 60..419).
//
// One pixel write = one word on the wires + one strobe pulse:
//   bus_d[8:0]   = X        (0..319)
//   bus_d[16:9]  = Y        (0..179)
//   bus_d[21:17] = colour   {R[1:0], G[0], B[1:0]}  (direct colour, 2R 1G 2B)
//   bus_par      = even parity over bus_d  (bus_par == ^bus_d)
//   bus_strobe   = rising edge: "read all the lines now"
//
// Colour examples (5 bits, R G B):
//   00000 black   11000 red     00100 green   00011 blue
//   11100 yellow  00111 cyan    11011 magenta 11111 white
//
// Sender timing (50 MHz receiver):
//   1. put data + parity on the wires
//   2. wait >= ~50 ns
//   3. strobe high, hold >= ~100 ns (data unchanged)
//   4. strobe low, wait >= ~50 ns, then next word
//
// A word with bad parity, X > 319, Y > 179, or data that changed around the
// strobe is dropped and err_led lights for 100 ms.
// The frame buffer starts black.  There is no clear command: to erase, write
// black (colour 0) over the pixels.
//
// Pins: see vga_bus.xdc.  Share GND with the sender (J5 pin 4).
//==============================================================================
module vga_bus_top (
    input  wire        clk,          // 50 MHz

    input  wire [21:0] bus_d,
    input  wire        bus_par,
    input  wire        bus_strobe,

    output wire        err_led,      // lit 100 ms after a rejected word

    output wire        vga_hsync,
    output wire        vga_vsync,
    output wire [3:0]  vga_r,
    output wire [3:0]  vga_g,
    output wire [3:0]  vga_b
);

    wire        rx_we;
    wire [15:0] rx_addr;
    wire [4:0]  rx_data;

    vga_bus_rx rx (
        .clk        (clk),
        .bus_d      (bus_d),
        .bus_par    (bus_par),
        .bus_strobe (bus_strobe),
        .wr_en      (rx_we),
        .wr_addr    (rx_addr),
        .wr_data    (rx_data),
        .err_led    (err_led)
    );

    vga_gfx gfx (
        .clk       (clk),
        .wr_en     (rx_we),
        .wr_addr   (rx_addr),
        .wr_data   (rx_data),
        .vga_hsync (vga_hsync),
        .vga_vsync (vga_vsync),
        .vga_r     (vga_r),
        .vga_g     (vga_g),
        .vga_b     (vga_b)
    );

endmodule
