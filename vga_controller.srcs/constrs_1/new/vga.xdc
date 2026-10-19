## Constraints for vga_bus_top / vga_gfx_top (EDGE Spartan-7, 50 MHz clock)
## Use this file INSTEAD of the big spartan7.xdc (that one assigns the same pins
## to several peripherals).
##
## Bus word: bus_d = {colour[4:0], Y[7:0], X[8:0]}, bus_par = even parity, bus_strobe
##   bus_d[8:0]   = X        bus_d[16:9]  = Y        bus_d[21:17] = colour {R[1:0],G,B[1:0]}
##
## Wiring is "plug in order" from a Raspberry Pi Pico:
##   Pico GP0..GP15  -> J5 pin5..pin20        (bus_d[0..15])
##   Pico GP16..GP21 -> LCD connector D0..D5  (bus_d[16..21])
##   Pico GP22       -> LCD connector D6      (bus_par)
##   Pico GP26       -> LCD connector D7      (bus_strobe)
##   Pico GND        -> J5 pin4
## LCD E and RS are not used.  err_led and vblank_out are on board LEDs 15 and 8.

# Configuration voltage (avoids the CFGBVS DRC warning)
set_property CFGBVS VCCO [current_design];
set_property CONFIG_VOLTAGE 3.3 [current_design];

# Clock (50 MHz -> 20 ns)
set_property -dict { PACKAGE_PIN H11 IOSTANDARD LVCMOS33 } [get_ports { clk }];
create_clock -period 20.000 -name sys_clk [get_ports { clk }];

# ---- J5 header: pin5..pin20 = bus_d[0..15]
set_property -dict { PACKAGE_PIN L14 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { bus_d[0] }];   # J5 pin5
set_property -dict { PACKAGE_PIN M13 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { bus_d[1] }];   # J5 pin6
set_property -dict { PACKAGE_PIN H14 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { bus_d[2] }];   # J5 pin7
set_property -dict { PACKAGE_PIN H13 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { bus_d[3] }];   # J5 pin8
set_property -dict { PACKAGE_PIN F11 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { bus_d[4] }];   # J5 pin9
set_property -dict { PACKAGE_PIN G11 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { bus_d[5] }];   # J5 pin10
set_property -dict { PACKAGE_PIN C14 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { bus_d[6] }];   # J5 pin11
set_property -dict { PACKAGE_PIN D14 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { bus_d[7] }];   # J5 pin12
set_property -dict { PACKAGE_PIN E13 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { bus_d[8] }];   # J5 pin13
set_property -dict { PACKAGE_PIN F13 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { bus_d[9] }];   # J5 pin14
set_property -dict { PACKAGE_PIN F14 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { bus_d[10] }];  # J5 pin15
set_property -dict { PACKAGE_PIN G14 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { bus_d[11] }];  # J5 pin16
set_property -dict { PACKAGE_PIN D13 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { bus_d[12] }];  # J5 pin17
set_property -dict { PACKAGE_PIN D12 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { bus_d[13] }];  # J5 pin18
set_property -dict { PACKAGE_PIN E12 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { bus_d[14] }];  # J5 pin19
set_property -dict { PACKAGE_PIN F12 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { bus_d[15] }];  # J5 pin20

# ---- LCD connector data pins D0..D7 = bus_d[16..21], bus_par, bus_strobe
# These are shared with board LEDs 7..0, so those LEDs will flicker with the data.
set_property -dict { PACKAGE_PIN M4  IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { bus_d[16] }];  # lcd D0, led[7]
set_property -dict { PACKAGE_PIN L5  IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { bus_d[17] }];  # lcd D1, led[6]
set_property -dict { PACKAGE_PIN P11 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { bus_d[18] }];  # lcd D2, led[5]
set_property -dict { PACKAGE_PIN N11 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { bus_d[19] }];  # lcd D3, led[4]
set_property -dict { PACKAGE_PIN P13 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { bus_d[20] }];  # lcd D4, led[3]
set_property -dict { PACKAGE_PIN M14 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { bus_d[21] }];  # lcd D5, led[2]
set_property -dict { PACKAGE_PIN M12 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { bus_par }];    # lcd D6, led[1]
set_property -dict { PACKAGE_PIN K12 IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { bus_strobe }]; # lcd D7, led[0]

# ---- Status outputs on board LEDs (no wire needed)
set_property -dict { PACKAGE_PIN M1 IOSTANDARD LVCMOS33 } [get_ports { err_led }];     # led[15]: lit ~84 ms after a rejected word
set_property -dict { PACKAGE_PIN J4 IOSTANDARD LVCMOS33 } [get_ports { vblank_out }];  # led[8]: dim glow = vertical blanking

# ---- VGA
set_property -dict { PACKAGE_PIN C4 IOSTANDARD LVCMOS33 } [get_ports { vga_hsync }];
set_property -dict { PACKAGE_PIN E4 IOSTANDARD LVCMOS33 } [get_ports { vga_vsync }];

set_property -dict { PACKAGE_PIN B6 IOSTANDARD LVCMOS33 } [get_ports { vga_r[0] }];
set_property -dict { PACKAGE_PIN D3 IOSTANDARD LVCMOS33 } [get_ports { vga_r[1] }];
set_property -dict { PACKAGE_PIN C3 IOSTANDARD LVCMOS33 } [get_ports { vga_r[2] }];
set_property -dict { PACKAGE_PIN A4 IOSTANDARD LVCMOS33 } [get_ports { vga_r[3] }];

set_property -dict { PACKAGE_PIN A3 IOSTANDARD LVCMOS33 } [get_ports { vga_g[0] }];
set_property -dict { PACKAGE_PIN B3 IOSTANDARD LVCMOS33 } [get_ports { vga_g[1] }];
set_property -dict { PACKAGE_PIN A2 IOSTANDARD LVCMOS33 } [get_ports { vga_g[2] }];
set_property -dict { PACKAGE_PIN B5 IOSTANDARD LVCMOS33 } [get_ports { vga_g[3] }];

set_property -dict { PACKAGE_PIN A5 IOSTANDARD LVCMOS33 } [get_ports { vga_b[0] }];
set_property -dict { PACKAGE_PIN B2 IOSTANDARD LVCMOS33 } [get_ports { vga_b[1] }];
set_property -dict { PACKAGE_PIN B1 IOSTANDARD LVCMOS33 } [get_ports { vga_b[2] }];
set_property -dict { PACKAGE_PIN C5 IOSTANDARD LVCMOS33 } [get_ports { vga_b[3] }];

# Bus inputs are asynchronous (double-registered in the RTL); status outputs are static
set_false_path -from [get_ports { bus_d[*] bus_par bus_strobe }]
set_false_path -to   [get_ports { err_led vblank_out }]
