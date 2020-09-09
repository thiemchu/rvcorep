# ref: https://github.com/Digilent/digilent-xdc/blob/master/Arty-A7-35-Master.xdc

set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { clk_in }]
set_property -dict { PACKAGE_PIN C2    IOSTANDARD LVCMOS33 } [get_ports { rstx_in }]
set_property -dict { PACKAGE_PIN A9    IOSTANDARD LVCMOS33 } [get_ports { uart_rxd }]
set_property -dict { PACKAGE_PIN D10   IOSTANDARD LVCMOS33 } [get_ports { uart_txd }]

# ddr3 ports are defined in
# dram/mig_7series_0/mig_7series_0/user_design/constraints/mig_7series_0.xdc
# (mig_7series_0.xdc is generated during the synthesis of the ip core)
