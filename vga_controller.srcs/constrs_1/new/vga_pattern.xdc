## Constraints for vga_pattern_top (EDGE Spartan-7): colour chart, only clk + VGA

set_property CFGBVS VCCO [current_design];
set_property CONFIG_VOLTAGE 3.3 [current_design];

# Clock (50 MHz -> 20 ns)
set_property -dict { PACKAGE_PIN H11 IOSTANDARD LVCMOS33 } [get_ports { clk }];
create_clock -period 20.000 -name sys_clk [get_ports { clk }];

# VGA 12 bit
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
