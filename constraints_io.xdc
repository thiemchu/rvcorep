# ref: https://github.com/Digilent/digilent-xdc/blob/master/Arty-A7-35-Master.xdc

set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { CLK }]
#set_property -dict { PACKAGE_PIN C2    IOSTANDARD LVCMOS33 } [get_ports { rstx_in }]
set_property -dict { PACKAGE_PIN A9   IOSTANDARD LVCMOS33 } [get_ports { w_rxd }]
set_property -dict { PACKAGE_PIN D10   IOSTANDARD LVCMOS33 } [get_ports { r_txd }]
