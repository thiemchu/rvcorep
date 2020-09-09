#########################################################################
if {[llength $argv] != 2} {
    puts "Usage: vivado.tcl <out_dir> <#threads>"
    puts "Got [llength $argv] arguments."
    exit
}

#########################################################################
# utilities

proc freq_mhz { period_ns } {
    return [expr (1.0 / $period_ns) * 1000 ]
}

proc format_fp { value } {
    return [format "%7.3f" $value]
}

proc show_period_freq { period_ns } {
    return "[format_fp $period_ns]ns ([format_fp [freq_mhz $period_ns]]MHz)"
}

proc synthesize_ip { ip_dir ip_list } {
    foreach i $ip_list {
        if [file exists "${ip_dir}/${i}/${i}.dcp"] {
            read_checkpoint "${ip_dir}/${i}/${i}.dcp"
        } else {
            read_ip "${ip_dir}/${i}/${i}.xci"
            set locked [get_property IS_LOCKED [get_ips ${i}]]
            set upgrade [get_property UPGRADE_VERSIONS [get_ips ${i}]]
            if {$locked && $upgrade != ""} {
                upgrade_ip [get_ips ${i}]
            }
            generate_target all [get_ips ${i}]
            synth_ip [get_ips ${i}]
        }
    }
}

#########################################################################

config_webtalk -user off

set out_dir            [lindex $argv 0]
set vivado_num_threads [lindex $argv 1]

# arty a7-35t board
set target_fpga "xc7a35ticsg324-1L"

set_part $target_fpga
set_param general.maxThreads $vivado_num_threads

#########################################################################
# assemble the design source files

# ip files
synthesize_ip "dram" [list clk_wiz_0 mig_7series_0]
synthesize_ip "." [list clk_wiz_1]

# verilog files
read_verilog {
    config.vh
}
set_property is_global_include true [get_files config.vh]
read_verilog {
    common/async_fifo.v
    common/sync_fifo.v
    dram/dram.v
    dram/dram_controller.v
    dram/mig_ui.v
    data_memory.v
    main.v
    proc.v
    uart.v
}

# verilog file containing the top module
set top_module_file "main.v"

# top module name
set top_module main

# constraint files
read_xdc constraints_io.xdc

#########################################################################
# run synthesis and implementation

set synth_start_time [clock clicks -milliseconds]

# synthesis
synth_design -top $top_module -fanout_limit 400 -fsm_extraction one_hot -keep_equivalent_registers -resource_sharing off -no_lc -shreg_min_size 5
write_checkpoint -force -noxdef "${out_dir}/${top_module}_synth.dcp"
report_utilization -file "${out_dir}/${top_module}_utilization_synth.rpt"
report_timing -sort_by group -max_paths 10 -path_type summary -file "${out_dir}/${top_module}_timing_synth.rpt"

set synth_finish_time [clock clicks -milliseconds]
set synth_time [expr ($synth_finish_time - $synth_start_time) / 1000]
puts "Synthesis time = [expr $synth_time / 60]:[format %02d [expr $synth_time % 60]]"

set impl_start_time [clock clicks -milliseconds]

# additional constraint files (for implementation)
read_xdc constraints_timing.xdc

# implementation
opt_design -directive Explore
place_design -directive Explore
write_checkpoint -force "${out_dir}/${top_module}_placed.dcp"
phys_opt_design -directive Explore
route_design -directive Explore
phys_opt_design -directive Explore
write_checkpoint -force "${out_dir}/${top_module}_routed.dcp"

# generate reports
report_timing_summary -file "${out_dir}/${top_module}_timing_summary_routed.rpt" -warn_on_violation
report_timing -sort_by group -max_paths 10 -path_type summary -file "${out_dir}/${top_module}_timing_routed.rpt"
report_utilization -file "${out_dir}/${top_module}_utilization_routed.rpt"
report_utilization -hierarchical -file "${out_dir}/${top_module}_utilization_routed_hierarchical.rpt"
report_drc -file "${out_dir}/${top_module}_drc_routed.rpt"

# display timing report summary
# "user_design_clk" is defined in "constraints_timing.xdc"
set user_design_clk_period_ns [get_property PERIOD [get_clocks user_design_clk]]
puts "User design clock: [show_period_freq $user_design_clk_period_ns]"
set wns [get_property SLACK [get_timing_paths]]
set timing_met [expr {$wns >= 0}]
if {$timing_met} {
    puts "Timing constraints: met (worst negative slack = $wns)"
} else {
    puts "Timing constraints: violated (worst negative slack = $wns)"
}

set impl_finish_time [clock clicks -milliseconds]
set impl_time [expr ($impl_finish_time - $impl_start_time) / 1000]
puts "Implementation time = [expr $impl_time / 60]:[format %02d [expr $impl_time % 60]]"

#########################################################################
# generate bitstream file
write_bitstream -force -file "${out_dir}/${top_module}.bit"
