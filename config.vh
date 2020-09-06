`ifndef __CONFIG__
`define __CONFIG__

/*****************************************************************************/
// init file
`define MEMFILE "test/test.mem"
//`define MEMFILE "dhrystone.mem"
/*****************************************************************************/
// MEMORY (Byte)
`define MEM_SIZE 1024*4   // 4KB
//`define MEM_SIZE 1024*8   // 8KB
//`define MEM_SIZE 1024*16  // 16KB
//`define MEM_SIZE 1024*32  // 32KB
/*****************************************************************************/
// start PC
`define START_PC 32'h00000000
/*****************************************************************************/
// uart queue size
`define QUEUE_SIZE 512
/*****************************************************************************/
// b = baud rate (in Mbps)
// f = frequency of the clk for the risc-v core (in MHz)
// SERIAL_WCNT = f/b
`define SERIAL_WCNT  100
/*****************************************************************************/

`endif
