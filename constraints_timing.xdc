# used in implementation
create_generated_clock -name user_design_clk [get_pins clk_wiz/inst/mmcm_adv_inst/CLKOUT0]
set_clock_groups -asynchronous -group {user_design_clk}
