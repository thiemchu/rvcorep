# Detailed explanations(in Japanese) (especially [4] and [5]):
- [1] https://www.acri.c.titech.ac.jp/wordpress/archives/6048
- [2] https://www.acri.c.titech.ac.jp/wordpress/archives/6767
- [3] https://www.acri.c.titech.ac.jp/wordpress/archives/7284
- [4] https://www.acri.c.titech.ac.jp/wordpress/archives/8036
- [5] https://www.acri.c.titech.ac.jp/wordpress/archives/8070

# RVCoreP
[RVCoreP](https://www.arch.cs.titech.ac.jp/wk/rvcore/doku.php?id=start) is a five-stage pipelined RISC-V soft processor developed by [Miyazaki et al.](https://arxiv.org/pdf/2002.03568.pdf) at Tokyo Institute of Technology.

Though RVCoreP is very fast, it implements both instruction memory and data memory using FPGA on-chip block RAMs (BRAMs). Since the total BRAM capacity on a typical FPGA is very limited (from several hundreds kilobytes to several megabytes), RVCoreP can execute only small applications.

In this project, we enhance the capability of RVCoreP by implementing the data memory using off-chip DRAM. For this purpose, besides the logic for the DRAM controller as well as for integrating the processor core with the DRAM controller, we have modified the processor core as follows:
 - We add a stall signal that is asserted when data memory is accessed. The original processor core does not have this signal since accessing BRAMs takes only one clock cycle, which does not stall the pipeline.
 - We add a read enable signal for the data memory. This signal is required because of the difference in the length of the memory access stage in the cases of loading (multiple clock cycles) and not loading (one clock cycle) data from data memory. In the original processor core, regardless of whether or not the data memory is accessed, the length of the memory access stage is always one clock cycle; and therefore, only write enable signal is required for correct operation.

We provide some script files for synthesizing the design using Vivado in batch mode (command line mode).

We also add Verilog code for simulating the DRAM-based design in which we emulate the behavior of DRAM. This has been shown to be very effective in the development of the project.

## Development environment
 - FPGA board: [Arty A7-35T](https://reference.digilentinc.com/reference/programmable-logic/arty-a7/start)
 - Synthesis: Vivado 2019.2
 - Simulation: Synopsys VCS
 - OS: Ubuntu

## Source code organization
 - ```clk_wiz_1/```, ```common/```, ```dram/```: DRAM controller implementation
 - ```sim/```, ```Makefile```, ```simsrc```: for simulation
 - ```config.vh``` defines some parameters for the design (see later explanation)
 - ```data_memory.v```: data memory implementation using DRAM
 - ```proc.v```: processor core implementation
 - ```uart.v```: implementation for program loader and serial port communication
 - ```main.v```: top module of the design
 - ```constraints_io.xdc```, ```constraints_timing.xdc```: constraints for I/O ports and timing of the design; the timing constraints are used only at the implementation stage
 - ```vivado.sh```, ```vivado.tcl```, ```vivado_slurm.sh```: scripts for synthesizing the design using Vivado in batch mode
 - ```verification/```: verification programs
   - ```*.bin``` files are for executing on an FPGA board
   - ```*.mem``` files are for simulation

## Some important parameters in ```config.vh```
 - ```MEM_FILE```: path to the verification program (this parameter is used only in simulation)
 - ```MEM_SIZE```: must be set appropriately according to the size of the verification programs
   - Verification programs in ```verification/test/```: ```MEM_SIZE``` should be set to 1024*4 (4KB)
   - Verification programs in ```verification/bench/```: ```MEM_SIZE``` should be set to 1024*32 (32KB)
   - Verification programs in ```verification/embench/```: ```MEM_SIZE``` should be set to 1024*64 (64KB)
 - ```SERIAL_WCNT```: must be set appropriately according to the frequency of the clock for the processor core and the desired baud rate for the serial port. For example, if the frequency of the clock for the processor core is 100MHz and the desired baud rate is 1MegaBaud, ```SERIAL_WCNT``` should be set to 100.

## Synthesis
 - In development environments with the [Slurm workload mamanger](https://www.schedmd.com/):
   ```lang-bash
   ./vivado_slurm.sh <#threads> <walltime(hour(s))> <vivado version (e.g., 20183, 20191, etc.)>
   ```
   For example, the command
   ```lang-bash
   ./vivado_slurm.sh 8 3 20192
   ```
   will create a job for synthesizing the design with Vivado 2019.2 in maximum 3 hours using 8 parallel threads.
   
   **Note**: you may need to edit the Vivado installation path in ```vivado_slurm.sh``` before using it.
 - In development environments without the Slurm workload manager:
   ```lang-bash
   ./vivado.sh <#threads> <vivado version (e.g., 20183, 20191, etc.)>
   ```
   For example, the command
   ```lang-bash
   ./vivado.sh 8 20192
   ```
   will synthesize the design with Vivado 2019.2 using 8 parallel threads.
   
   **Note**: similar to the ```vivado_slurm.sh``` script, you may need to edit the Vivado installation path.

**Program the FPGA and execute a verification program**: after programming the FPGA, use the ```serial_rvcorep.py``` python script in ```verification/``` to send a verification program to the FPGA ([pySerial](https://pythonhosted.org/pyserial/pyserial.html#installation) is required to run this script). For example, the command
``` lang-bash
python3 serial_rvcorep.py 1 test/test.bin
```
will send the ```test/test.bin``` program to the FPGA via the serial port at a baud rate of 1MegaBaud (you may need to change the location of the serial port in line 4 of the script). The baud rate specified here must be the same as that assumed when setting the parameter ```SERIAL_WCNT``` in ```config.vh```, which is described above.

In the current design, to execute another verification program, it is necessary to reprogram the FPGA.

The frequency of the clock for the processor core is currently set to 100MHz. This clock is generated by the clocking wizard IP core in ```dram/clk_wiz_0/```. This IP core takes as input a *no buffer* 83.333MHz clock which is output by the DRAM controller and generates a 100MHz clock. You can change the output clock frequency of the IP core but the specification of the input clock (*no buffer*, 83.333MHz) cannot be changed (it is related to the settings of the MIG IP core in the DRAM controller).

We generate the clocking wizad IP core in ```dram/clk_wiz_0/``` using the scripts in [here](https://github.com/thiemchu/clkwiz) (see README for the usage of the scripts).
``` lang-bash
./clkwiz.sh aa35 n 83.333 100.000 20192
```
The IP core can also be generated using Vivado in GUI mode.

## Simulation
``` lang-bash
make
make run
```
The simulation of executing the verification programs in ```verification/bench/``` and ```verification/embench/``` (especially those in the latter) is very time-consuming. For example, the execution of ```verification/embench/wikisort.mem``` takes more than 30 minutes in our environment (Core i9 9900K CPU with 64GB DDR4 memory).
