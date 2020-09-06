`include "config.vh"

module main(CLK, w_rxd, r_txd);
    input  wire        CLK;
    input  wire        w_rxd;
    output reg         r_txd = 1;

    wire w_clk, w_locked;
    clk_wiz_1 clk_wiz (w_clk, 0, w_locked, CLK);

    reg r_rst = 1; // reset signal
    always @(posedge w_clk) r_rst <= (!w_locked);

    reg core_rst = 1;

    always @(posedge w_clk) core_rst <= (r_rst | !initdone);

    /****************************************************************************************/
    reg r_rxd_t1=1,  r_rxd_t2=1;
    always@(posedge w_clk) r_rxd_t1 <= w_rxd;
    always@(posedge w_clk) r_rxd_t2 <= r_rxd_t1;
    /****************************************************************************************/
    wire [31:0] w_initdata;
    wire [31:0] w_initaddr;
    wire        w_initwe;
    wire        w_initdone;
    PLOADER ploader(w_clk, !r_rst, r_rxd_t2, w_initaddr, w_initdata, w_initwe, w_initdone);

    reg  [31:0] initdata = 0;
    reg  [31:0] initaddr = 0;
    reg  [3:0]  initwe   = 0;
    reg         initdone = 0;
    always@(posedge w_clk) begin
        initdata <= (r_rst) ? 0 : (w_initwe) ? w_initdata   : 0;
        initaddr <= (r_rst) ? 0 : (initwe)   ? initaddr + 4 : initaddr;
        initwe   <= (r_rst) ? 0 : {4{w_initwe}};
        initdone <= (r_rst) ? 0 : w_initdone;
    end
    /****************************************************************************************/
    wire        w_halt;
    wire [31:0] w_rout, I_DATA, I_ADDR, D_DATA, WD_DATA, D_ADDR;
    wire [3:0]  D_WE;

    RVCore p(w_clk, !core_rst, w_rout, w_halt, I_ADDR, D_ADDR, I_DATA, D_DATA, WD_DATA, D_WE);

    wire [31:0] tmpdata;
    m_IMEM#(32,`MEM_SIZE/4) imem(w_clk, initwe[0], initaddr[$clog2(`MEM_SIZE)-1:2], I_ADDR[$clog2(`MEM_SIZE)-1:2], initdata, I_DATA);
    m_DMEM#(32,`MEM_SIZE/4) dmem(w_clk, core_rst, initwe, initaddr[$clog2(`MEM_SIZE)-1:2], initdata, tmpdata, w_clk, !core_rst, D_WE, D_ADDR[$clog2(`MEM_SIZE)-1:2], WD_DATA, D_DATA);

    reg        r_halt = 0;
    reg [31:0] r_rout = 0;
    always @(posedge w_clk) begin
        r_halt <= w_halt;
        r_rout <= w_rout;
    end

    /****************************************************************************************/
    reg [31:0] r_cnt = 0;
    always @(posedge w_clk) r_cnt <= (core_rst) ? 0 : (~r_halt & ~poweroff) ? r_cnt+1 : r_cnt;
    /****************************************************************************************/

    reg        r_D_ADDR  = 0; // Note!!
    reg        r_D_WE    = 0; // Note!!
    reg [31:0] r_WD_DATA = 0;
    always@(posedge w_clk) begin
        r_D_ADDR  <= D_ADDR[15] & D_ADDR[30];
        r_D_WE    <= D_WE[0];
        r_WD_DATA <= WD_DATA;
    end

    reg [7:0]  tohost_char=0;
    reg        tohost_we=0;
    reg [31:0] tohost_data=0;
    reg [1:0]  tohost_cmd=0;
    always@(posedge w_clk) begin
        tohost_we   <= (r_D_ADDR && (r_D_WE));
        tohost_data <= r_WD_DATA;
        tohost_char <= (tohost_we) ? tohost_data[7:0] : 0;
        tohost_cmd  <= (tohost_we) ? tohost_data[17:16] : 0;
    end

    reg poweroff = 0;
    always@(posedge w_clk) poweroff <= (tohost_cmd==2) ? 1 : poweroff;
    wire sim_poweroff = poweroff | (tohost_cmd==2) | (tohost_we & (tohost_cmd==2));

    /****************************************************************************************/

    reg [7:0]  squeue[0:`QUEUE_SIZE-1];
    integer i;
    initial begin for(i=0; i<`QUEUE_SIZE; i=i+1) squeue[i]=8'h0; end

    reg  [$clog2(`QUEUE_SIZE)-1:0] queue_head = 0;
    reg  [$clog2(`QUEUE_SIZE)-1:0] queue_num  = 0;
    wire [$clog2(`QUEUE_SIZE)-1:0] queue_addr = queue_head+queue_num;
    wire printchar = (tohost_cmd==1);
    always@(posedge w_clk) begin
        if(printchar) squeue[queue_addr] <= tohost_char;
        queue_head <= (!printchar & tx_ready & (queue_num > 0) & !uartwe) ? queue_head + 1 : queue_head;
        queue_num <= (printchar) ? queue_num + 1 : (tx_ready & (queue_num > 0) & !uartwe) ? queue_num - 1 : queue_num;
    end

    reg [7:0] uartdata = 0;
    reg       uartwe   = 0;
    always@(posedge w_clk) begin
        uartdata <= (!printchar & tx_ready & (queue_num > 0) & !uartwe) ? squeue[queue_head] : 0;
        uartwe   <= (!printchar & tx_ready & (queue_num > 0) & !uartwe) ? 1                  : 0;
    end
    
    always@(posedge w_clk) r_txd <= w_txd;

    wire w_txd;
    wire tx_ready;
    UartTx UartTx0(w_clk, !core_rst, uartdata, uartwe, w_txd, tx_ready);

endmodule
