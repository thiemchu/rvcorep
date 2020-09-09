module main #(
              // DRAM_SIZE is in bytes;
              // DRAM_SIZE must be a multiple of
              // 16 bytes = 128 bits (APP_DATA_WIDTH)
              parameter DRAM_SIZE         = 1024*64,
              // only busrt length = 8 is supported
              parameter DRAM_BURST_LENGTH = 8,
              parameter APP_DATA_WIDTH    = 128,
              parameter APP_MASK_WIDTH    = 16)
    (
     // input clock, reset (active-high) ports
     input  wire  clk,
     input  wire  rst,
     // uart rx/tx ports
     input  wire  uart_rxd,
     output wire  uart_txd);

    localparam APP_ADDR_WIDTH = $clog2((DRAM_SIZE * 8) / APP_DATA_WIDTH) +
                                $clog2(DRAM_BURST_LENGTH) + 1;

    wire        dmem_init_done;
    wire [3:0]  dmem_init_wen;
    wire [31:0] dmem_init_addr;
    wire [31:0] dmem_init_din;
    wire        dmem_ren;
    wire [3:0]  dmem_wen;
    wire [31:0] dmem_addr;
    wire [31:0] dmem_din;
    wire [31:0] dmem_dout;
    wire        dmem_stall;

    reg         r_rxd_t1 = 1;
    reg         r_rxd_t2 = 1;

    wire [31:0] w_initdata;
    wire [31:0] w_initaddr;
    wire        w_initwe;
    wire        w_initdone;

    reg  [31:0] initdata = 0;
    reg  [31:0] initaddr = 0;
    reg  [3:0]  initwe   = 0;
    reg         initdone = 0;

    wire        w_halt;
    wire [31:0] w_rout, I_DATA, I_ADDR, D_DATA, WD_DATA, D_ADDR;
    wire [3:0]  D_WE;
    wire        D_RE, D_STALL;
    reg         core_rst = 1;

    reg         r_halt = 0;
    reg  [31:0] r_rout = 0;

    reg  [31:0] r_cnt = 0;

    reg         r_D_ADDR  = 0; // Note!!
    reg         r_D_WE    = 0; // Note!!
    reg  [31:0] r_WD_DATA = 0;

    reg  [7:0]  tohost_char = 0;
    reg         tohost_we = 0;
    reg  [31:0] tohost_data = 0;
    reg  [1:0]  tohost_cmd = 0;

    reg  [7:0]  squeue[0:`QUEUE_SIZE-1];

    reg  [$clog2(`QUEUE_SIZE)-1:0] queue_head = 0;
    reg  [$clog2(`QUEUE_SIZE)-1:0] queue_num  = 0;
    wire [$clog2(`QUEUE_SIZE)-1:0] queue_addr = queue_head+queue_num;
    wire                           printchar  = (tohost_cmd == 1);

    reg         poweroff = 0;

    reg  [7:0]  uartdata = 0;
    reg         uartwe   = 0;
    reg         r_txd;
    wire        w_txd;
    wire        tx_ready;

    integer i;

    assign dmem_init_done = initdone;
    assign dmem_init_wen = initwe;
    assign dmem_init_addr = initaddr;
    assign dmem_init_din = initdata;
    assign dmem_ren = D_RE;
    // (D_WE[0] && D_ADDR[15] && D_ADDR[30]) = 1 => memory-mapped uart tx
    //                                 otherwise => memory access (write)
    assign dmem_wen = (D_WE[0] && D_ADDR[15] && D_ADDR[30])? 0 : D_WE;
    // dmem_addr must be 4-byte aligned
    assign dmem_addr = {D_ADDR[31:2], 2'b00};
    assign dmem_din = WD_DATA;

    DataMemory #(
                 .DRAM_SIZE(DRAM_SIZE),
                 .DRAM_BURST_LENGTH(DRAM_BURST_LENGTH),
                 .APP_ADDR_WIDTH(APP_ADDR_WIDTH),
                 .APP_DATA_WIDTH(APP_DATA_WIDTH),
                 .APP_MASK_WIDTH(APP_MASK_WIDTH))
    dmem (
          .clk(clk),
          .i_rst(rst),
          // user design interface signals
          .i_dmem_init_done(dmem_init_done),
          .i_dmem_init_wen(dmem_init_wen),
          .i_dmem_init_addr(dmem_init_addr),
          .i_dmem_init_data(dmem_init_din),
          .i_dmem_ren(dmem_ren),
          .i_dmem_wen(dmem_wen),
          .i_dmem_addr(dmem_addr),
          .i_dmem_data(dmem_din),
          .o_dmem_data(dmem_dout),
          .o_dmem_stall(dmem_stall));

    /****************************************************************************************/
    always@(posedge clk) r_rxd_t1 <= uart_rxd;
    always@(posedge clk) r_rxd_t2 <= r_rxd_t1;
    /****************************************************************************************/
    PLOADER ploader(clk, !rst, r_rxd_t2, w_initaddr, w_initdata, w_initwe, w_initdone);

    always@(posedge clk) begin
        initdata <= (rst) ? 0 : (w_initwe) ? w_initdata   : 0;
        initaddr <= (rst) ? 0 : (initwe)   ? initaddr + 4 : initaddr;
        initwe   <= (rst) ? 0 : {4{w_initwe}};
        initdone <= (rst) ? 0 : w_initdone;
    end
    /****************************************************************************************/

    always @(posedge clk) core_rst <= (rst | !initdone);

    assign D_DATA = dmem_dout;
    assign D_STALL = dmem_stall;

    RVCore p(clk, !core_rst, w_rout, w_halt, I_ADDR, D_ADDR, I_DATA, D_DATA, WD_DATA, D_WE, D_RE, D_STALL);

    m_IMEM#(32,`MEM_SIZE/4) imem(clk, initwe[0], initaddr[$clog2(`MEM_SIZE)-1:2], I_ADDR[$clog2(`MEM_SIZE)-1:2], initdata, I_DATA);

    always @(posedge clk) begin
        if (!D_STALL) begin
            r_halt <= w_halt;
            r_rout <= w_rout;
        end
    end

    /****************************************************************************************/
    always @(posedge clk) r_cnt <= (core_rst) ? 0 : (~r_halt & ~poweroff) ? r_cnt+1 : r_cnt;
    /****************************************************************************************/

    always@(posedge clk) begin
        if (!D_STALL) begin
            r_D_ADDR  <= D_ADDR[15] & D_ADDR[30];
            r_D_WE    <= D_WE[0];
            r_WD_DATA <= WD_DATA;
        end
    end

    always@(posedge clk) begin
        if (!D_STALL) begin
            tohost_we   <= (r_D_ADDR && (r_D_WE));
            tohost_data <= r_WD_DATA;
            tohost_char <= (tohost_we) ? tohost_data[7:0] : 0;
            tohost_cmd  <= (tohost_we) ? tohost_data[17:16] : 0;
        end
    end

    always@(posedge clk)begin
        if (!D_STALL) begin
            poweroff <= (tohost_cmd==2) ? 1 : poweroff;
        end
    end
    wire sim_poweroff = poweroff | (tohost_cmd==2) | (tohost_we & (tohost_cmd==2));

    /****************************************************************************************/

    initial begin for(i=0; i<`QUEUE_SIZE; i=i+1) squeue[i]=8'h0; end

    always@(posedge clk) begin
        if (!D_STALL) begin
            if(printchar) squeue[queue_addr] <= tohost_char;
            queue_head <= (!printchar & tx_ready & (queue_num > 0) & !uartwe) ? queue_head + 1 : queue_head;
            queue_num <= (printchar) ? queue_num + 1 : (tx_ready & (queue_num > 0) & !uartwe) ? queue_num - 1 : queue_num;
        end
    end

    always@(posedge clk) begin
        if (!D_STALL) begin
            uartdata <= (!printchar & tx_ready & (queue_num > 0) & !uartwe) ? squeue[queue_head] : 0;
            uartwe   <= (!printchar & tx_ready & (queue_num > 0) & !uartwe) ? 1                  : 0;
        end else begin
            uartwe   <= 0;
            uartdata <= 0;
        end
    end

    always@(posedge clk) r_txd <= w_txd;
    // uart_txd: ouput port
    assign uart_txd = r_txd;

    UartTx UartTx0(clk, !core_rst, uartdata, uartwe, w_txd, tx_ready);

endmodule
