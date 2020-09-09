module main #(
              parameter DDR3_DQ_WIDTH   = 16,
              parameter DDR3_DQS_WIDTH  = 2,
              parameter DDR3_ADDR_WIDTH = 14,
              parameter DDR3_BA_WIDTH   = 3,
              parameter DDR3_DM_WIDTH   = 2,
              parameter APP_ADDR_WIDTH  = 28,
              parameter APP_CMD_WIDTH   = 3,
              parameter APP_DATA_WIDTH  = 128,
              parameter APP_MASK_WIDTH  = 16)
    (
     // input clock (100MHz), reset (active-low) ports
     input  wire                         clk_in,
     input  wire                         rstx_in,
     // dram interface ports
     inout  wire [DDR3_DQ_WIDTH-1 : 0]   ddr3_dq,
     inout  wire [DDR3_DQS_WIDTH-1 : 0]  ddr3_dqs_n,
     inout  wire [DDR3_DQS_WIDTH-1 : 0]  ddr3_dqs_p,
     output wire [DDR3_ADDR_WIDTH-1 : 0] ddr3_addr,
     output wire [DDR3_BA_WIDTH-1 : 0]   ddr3_ba,
     output wire                         ddr3_ras_n,
     output wire                         ddr3_cas_n,
     output wire                         ddr3_we_n,
     output wire                         ddr3_reset_n,
     output wire [0:0]                   ddr3_ck_p,
     output wire [0:0]                   ddr3_ck_n,
     output wire [0:0]                   ddr3_cke,
     output wire [0:0]                   ddr3_cs_n,
     output wire [DDR3_DM_WIDTH-1 : 0]   ddr3_dm,
     output wire [0:0]                   ddr3_odt,
     // uart rx/tx port
     input  wire                         uart_rxd,
     output wire                         uart_txd);

    wire        clk;
    wire        rst;

    wire        clk_166_67_mhz;
    wire        clk_200_mhz;
    wire        dram_rst;
    wire        dram_rstx_async;
    reg         dram_rst_sync1;
    reg         dram_rst_sync2;
    wire        locked;

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

    clk_wiz_1 dram_clkgen (
                           .clk_in1(clk_in),
                           .resetn(rstx_in),
                           .clk_out1(clk_166_67_mhz),
                           .clk_out2(clk_200_mhz),
                           .locked(locked));

    assign dram_rstx_async = rstx_in & locked;
    assign dram_rst = dram_rst_sync2;

    always @(posedge clk_166_67_mhz or negedge dram_rstx_async) begin
        if (!dram_rstx_async) begin
            dram_rst_sync1 <= 1'b1;
            dram_rst_sync2 <= 1'b1;
        end else begin
            dram_rst_sync1 <= 1'b0;
            dram_rst_sync2 <= dram_rst_sync1;
        end
    end

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
    assign D_DATA = dmem_dout;
    assign D_STALL = dmem_stall;

    DataMemory #(
                 .DDR3_DQ_WIDTH(DDR3_DQ_WIDTH),
                 .DDR3_DQS_WIDTH(DDR3_DQS_WIDTH),
                 .DDR3_ADDR_WIDTH(DDR3_ADDR_WIDTH),
                 .DDR3_BA_WIDTH(DDR3_BA_WIDTH),
                 .DDR3_DM_WIDTH(DDR3_DM_WIDTH),
                 .APP_ADDR_WIDTH(APP_ADDR_WIDTH),
                 .APP_CMD_WIDTH(APP_CMD_WIDTH),
                 .APP_DATA_WIDTH(APP_DATA_WIDTH),
                 .APP_MASK_WIDTH(APP_MASK_WIDTH))
    dmem (
          // input clock (166.67MHz),
          // reference clock (200MHz),
          // reset (active-high)
          .sys_clk(clk_166_67_mhz),
          .ref_clk(clk_200_mhz),
          .sys_rst(dram_rst),
          // dram interface signals
          .ddr3_dq(ddr3_dq),
          .ddr3_dqs_n(ddr3_dqs_n),
          .ddr3_dqs_p(ddr3_dqs_p),
          .ddr3_addr(ddr3_addr),
          .ddr3_ba(ddr3_ba),
          .ddr3_ras_n(ddr3_ras_n),
          .ddr3_cas_n(ddr3_cas_n),
          .ddr3_we_n(ddr3_we_n),
          .ddr3_reset_n(ddr3_reset_n),
          .ddr3_ck_p(ddr3_ck_p),
          .ddr3_ck_n(ddr3_ck_n),
          .ddr3_cke(ddr3_cke),
          .ddr3_cs_n(ddr3_cs_n),
          .ddr3_dm(ddr3_dm),
          .ddr3_odt(ddr3_odt),
          // output clock and reset (active-high) signals for user design
          .o_clk(clk),
          .o_rst(rst),
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

    always@(posedge clk) begin
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
            uartdata <= 0;
            uartwe   <= 0;
        end
    end

    always@(posedge clk) r_txd <= w_txd;
    // uart_txd: ouput port
    assign uart_txd = r_txd;

    UartTx UartTx0(clk, !core_rst, uartdata, uartwe, w_txd, tx_ready);

endmodule
