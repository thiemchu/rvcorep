// The implementation in this file adheres to the JEDEC Standard.
// Only one burst length is supported: BL = 8.
// Addressing:
//     (1) Write:
//         The burst order for a write with BL=8 will always
//         start at column address 0 and count up sequentially to 7.
//     (2) Read:
//         The burst order for a sequential read with BL=8 will
//         start at the column address specified and
//         increment sequentially but wrap around after address 3 and 7.
//         The burst is divided into the top 4 and bottom 4 address locations.
//         For example, for a column address of 3'b011,
//         the data returned will follow the sequence 3,0,1,2,7,4,5,6.
//         While, for a column address of 3'b101,
//         the data returned will follow the sequence 5,6,7,4,1,2,3,0.

module DRAM #(
              // DRAM_SIZE is in bytes;
              // DRAM_SIZE must be a multiple of
              // 16 bytes = 128 bits (APP_DATA_WIDTH)
              parameter DRAM_SIZE         = 1024*64,
              // only burst length = 8 is supported
              parameter DRAM_BURST_LENGTH = 8,
              parameter APP_ADDR_WIDTH,
              parameter APP_DATA_WIDTH    = 128,
              parameter APP_MASK_WIDTH    = 16)
    (
     input  wire                        clk,
     input  wire                        i_rst,
     input  wire                        i_ren,
     input  wire                        i_wen,
     input  wire [APP_ADDR_WIDTH-2 : 0] i_addr,
     input  wire [APP_DATA_WIDTH-1 : 0] i_data,
     input  wire [APP_MASK_WIDTH-1 : 0] i_mask,
     input  wire                        i_busy,
     output wire                        o_init_calib_complete,
     output wire [APP_DATA_WIDTH-1 : 0] o_data,
     output wire                        o_data_valid,
     output wire                        o_busy);

    localparam MEM_DEPTH      = (DRAM_SIZE * 8) / APP_DATA_WIDTH;
    localparam MEM_ADDR_WIDTH = $clog2(MEM_DEPTH);

    // burst length = 2**MEM_ADDR_OFFSET_WIDTH
    localparam MEM_ADDR_OFFSET_WIDTH = $clog2(DRAM_BURST_LENGTH);
    localparam MEM_DATA_UNIT_WIDTH   = APP_DATA_WIDTH / DRAM_BURST_LENGTH;

    // common case: APP_DATA_UNIT_WIDTH = 8 bits (1 byte)
    localparam APP_DATA_UNIT_WIDTH = APP_DATA_WIDTH / APP_MASK_WIDTH;

    localparam STATE_READY = 2'b00;
    localparam STATE_RDATA = 2'b01;
    localparam STATE_WDATA = 2'b10;
    localparam RANDOM_RANGE = 8;

    localparam DRAM_CMD_FIFO_DATA_WIDTH = 1 + MEM_ADDR_WIDTH +
                                          MEM_ADDR_OFFSET_WIDTH +
                                          APP_DATA_WIDTH + APP_MASK_WIDTH;

    localparam DRAM_READ_FIFO_ADDR_WIDTH = 3;
    localparam DRAM_READ_FIFO_DEPTH      = 2**DRAM_READ_FIFO_ADDR_WIDTH;

    wire [MEM_ADDR_WIDTH-1 : 0]           addr;
    wire [MEM_ADDR_OFFSET_WIDTH-1 : 0]    addr_offset;

    reg  [APP_DATA_WIDTH-1 : 0]           mem[MEM_DEPTH-1 : 0];
    reg  [APP_DATA_WIDTH-1 : 0]           dout;
    reg                                   dout_valid;
    reg                                   rst_done = 0;

    reg  [1:0]                            state;
    reg  [MEM_ADDR_WIDTH-1 : 0]           baddr;
    reg  [MEM_ADDR_OFFSET_WIDTH-1 : 0]    oaddr;
    reg  [APP_DATA_WIDTH-1 : 0]           wdata;
    reg  [APP_MASK_WIDTH-1 : 0]           wmask;
    reg  [6:0]                            count;

    reg                                   dram_clk = 0;
    reg                                   dram_rst;

    wire                                  dram_init_calib_complete;
    wire                                  dram_ren;
    wire                                  dram_wen;
    wire [MEM_ADDR_WIDTH-1 : 0]           dram_addr;
    wire [MEM_ADDR_OFFSET_WIDTH-1 : 0]    dram_addr_offset;
    wire [APP_DATA_WIDTH-1 : 0]           dram_din;
    wire [APP_MASK_WIDTH-1 : 0]           dram_mask;
    reg  [APP_DATA_WIDTH-1 : 0]           dram_dout;
    wire                                  dram_dout_valid;

    wire                                  wen_afifo1;
    wire [DRAM_CMD_FIFO_DATA_WIDTH-1 : 0] din_afifo1;
    wire                                  ren_afifo1;
    wire [DRAM_CMD_FIFO_DATA_WIDTH-1 : 0] dout_afifo1;
    wire                                  empty_afifo1;
    wire                                  full_afifo1;
    wire                                  dout_afifo1_wen;
    wire [MEM_ADDR_WIDTH-1 : 0]           dout_afifo1_addr;
    wire [MEM_ADDR_OFFSET_WIDTH-1 : 0]    dout_afifo1_addr_offset;
    wire [APP_DATA_WIDTH-1 : 0]           dout_afifo1_data;
    wire [APP_MASK_WIDTH-1 : 0]           dout_afifo1_mask;

    wire                                  wen_afifo2;
    wire [APP_DATA_WIDTH-1 : 0]           din_afifo2;
    wire                                  ren_afifo2;
    wire [APP_DATA_WIDTH-1 : 0]           dout_afifo2;
    wire                                  empty_afifo2;
    wire                                  full_afifo2;

    wire                                  wen_sfifo;
    wire [APP_DATA_WIDTH-1 : 0]           din_sfifo;
    wire                                  ren_sfifo;
    wire [APP_DATA_WIDTH-1 : 0]           dout_sfifo;
    wire                                  empty_sfifo;

    reg  [APP_DATA_WIDTH-1 : 0]           data1;
    reg                                   data_valid1 = 0;
    reg  [APP_DATA_WIDTH-1 : 0]           data2;
    reg                                   data_valid2 = 0;

    reg                                   dram_init_calib_complete_sync1 = 0;
    reg                                   dram_init_calib_complete_sync2 = 0;

    reg  [DRAM_READ_FIFO_ADDR_WIDTH : 0]  rreq_count;
    reg  [DRAM_READ_FIFO_ADDR_WIDTH : 0]  rdat_count;

    always #15 dram_clk = ~dram_clk;

    initial begin
        dram_rst = 1;
        #30 dram_rst = 0;
    end

    assign addr = i_addr[APP_ADDR_WIDTH-2 : MEM_ADDR_OFFSET_WIDTH];
    assign addr_offset = i_addr[MEM_ADDR_OFFSET_WIDTH-1 : 0];

    // synchronize the calibration status signal
    assign o_init_calib_complete = dram_init_calib_complete_sync2;
    always @(posedge clk) begin
        if (i_rst) begin
            dram_init_calib_complete_sync1 <= 1'b0;
            dram_init_calib_complete_sync2 <= 1'b0;
        end else begin
            dram_init_calib_complete_sync1 <= dram_init_calib_complete;
            dram_init_calib_complete_sync2 <= dram_init_calib_complete_sync1;
        end
    end

    // user design -> DRAM controller
    assign wen_afifo1 = (i_ren || i_wen);
    assign din_afifo1 = {i_wen, addr, addr_offset, i_data, i_mask};
    assign ren_afifo1 = (dram_ren || dram_wen);
    AsyncFIFO #(
                .DATA_WIDTH(DRAM_CMD_FIFO_DATA_WIDTH),
                .ADDR_WIDTH(3))
    afifo1 (
            .wclk(clk),
            .rclk(dram_clk),
            .i_wrst(i_rst),
            .i_rrst(dram_rst),
            .i_wen(wen_afifo1),
            .i_data(din_afifo1),
            .i_ren(ren_afifo1),
            .o_data(dout_afifo1),
            .o_empty(empty_afifo1),
            .o_full(full_afifo1));

    // DRAM controller -> user design
    assign wen_afifo2 = ren_sfifo;
    assign din_afifo2 = dout_sfifo;
    assign ren_afifo2 = (!empty_afifo2 && !i_busy);
    AsyncFIFO #(
                .DATA_WIDTH(APP_DATA_WIDTH),
                .ADDR_WIDTH(3))
    afifo2 (
            .wclk(dram_clk),
            .rclk(clk),
            .i_wrst(dram_rst),
            .i_rrst(i_rst),
            .i_wen(wen_afifo2),
            .i_data(din_afifo2),
            .i_ren(ren_afifo2),
            .o_data(dout_afifo2),
            .o_empty(empty_afifo2),
            .o_full(full_afifo2));

    // DRAM read FIFO
    assign wen_sfifo = dram_dout_valid;
    assign din_sfifo = dram_dout;
    assign ren_sfifo = (!empty_sfifo && !full_afifo2);
    SyncFIFO #(
               .DATA_WIDTH(APP_DATA_WIDTH),
               .ADDR_WIDTH(DRAM_READ_FIFO_ADDR_WIDTH))
    sfifo(
          .clk(dram_clk),
          .i_rst(dram_rst),
          .i_wen(wen_sfifo),
          .i_data(din_sfifo),
          .i_ren(ren_sfifo),
          .o_data(dout_sfifo),
          .o_empty(empty_sfifo),
          .o_full());

    assign dram_init_calib_complete = rst_done;

    assign {dout_afifo1_wen, dout_afifo1_addr, dout_afifo1_addr_offset, dout_afifo1_data, dout_afifo1_mask} = dout_afifo1;
    assign dram_ren = (!empty_afifo1 && !dout_afifo1_wen && (state == STATE_READY) && (rreq_count < DRAM_READ_FIFO_DEPTH));
    assign dram_wen = (!empty_afifo1 && dout_afifo1_wen && (state == STATE_READY));
    assign dram_addr = dout_afifo1_addr;
    assign dram_addr_offset = dout_afifo1_addr_offset;
    assign dram_din = dout_afifo1_data;
    assign dram_mask = dout_afifo1_mask;
    // dram_dout
    reg  [MEM_ADDR_OFFSET_WIDTH : 0]   x;
    reg  [MEM_ADDR_OFFSET_WIDTH-1 : 0] y;
    always @(*) begin
        y = oaddr;
        for (x = 0; x < 2**MEM_ADDR_OFFSET_WIDTH; x = x + 1) begin
            dram_dout[x*MEM_DATA_UNIT_WIDTH +:
                      MEM_DATA_UNIT_WIDTH] = dout[y*MEM_DATA_UNIT_WIDTH +: MEM_DATA_UNIT_WIDTH];
            // the current implementation supports only one burst length BL = 8
            // (MEM_ADDR_OFFSET_WIDTH = 3)
            y[MEM_ADDR_OFFSET_WIDTH-2 : 0] = y[MEM_ADDR_OFFSET_WIDTH-2 : 0] + 1;
            if (x[MEM_ADDR_OFFSET_WIDTH-2 : 0] == {(MEM_ADDR_OFFSET_WIDTH-1){1'b1}}) begin
                y[MEM_ADDR_OFFSET_WIDTH-1] = !y[MEM_ADDR_OFFSET_WIDTH-1];
            end
        end
    end
    assign dram_dout_valid = dout_valid;

    wire                        mem_wen;
    wire [MEM_ADDR_WIDTH-1 : 0] mem_raddr;
    wire [MEM_ADDR_WIDTH-1 : 0] mem_waddr;
    reg  [APP_DATA_WIDTH-1 : 0] mem_rdata;
    reg  [APP_DATA_WIDTH-1 : 0] mem_wdata;
    integer i;

    assign mem_wen = ((state == STATE_WDATA) && (count == 0));
    assign mem_raddr = baddr;
    assign mem_waddr = baddr;
    always @(*) begin
        mem_wdata = dout;
        for (i = 0; i < APP_MASK_WIDTH; i = i + 1) begin
            if (wmask[i] == 0) begin // write operation is performed when mask = 0
                mem_wdata[i*APP_DATA_UNIT_WIDTH +:
                          APP_DATA_UNIT_WIDTH] = wdata[i*APP_DATA_UNIT_WIDTH +: APP_DATA_UNIT_WIDTH];
            end
        end
    end

    always @(posedge dram_clk) begin
        mem_rdata <= mem[mem_raddr];
        if (mem_wen) begin
            mem[mem_waddr] <= mem_wdata;
        end
    end

    always @(posedge dram_clk) begin
        if (dram_rst) begin
            rst_done <= 0;
            dout <= 0;
            dout_valid <= 0;
            state <= STATE_READY;
            baddr <= 0;
            oaddr <= 0;
            wdata <= 0;
            wmask <= 0;
            count <= 0;
        end else begin
            rst_done <= 1;
            dout_valid <= 0;
            case (state)
                STATE_READY: begin
                    baddr <= dram_addr;
                    oaddr <= dram_addr_offset;
                    if (dram_ren) begin
                        state <= STATE_RDATA;
                        count <= 1 + ({$random} % RANDOM_RANGE); // count >= 1
                    end else if (dram_wen) begin
                        state <= STATE_WDATA;
                        wdata <= dram_din;
                        wmask <= dram_mask;
                        count <= 2 + ({$random} % RANDOM_RANGE); // count >= 2
                    end
                end
                STATE_RDATA: begin
                    if (count == 0) begin
                        state <= STATE_READY;
                        dout <= mem_rdata;
                        dout_valid <= 1;
                    end else begin
                        count <= count - 1;
                    end
                end
                STATE_WDATA: begin
                    if (count == 0) begin
                        state <= STATE_READY;
                    end else begin
                        dout <= mem_rdata;
                        count <= count - 1;
                    end
                end
            endcase
        end
    end

    always @(posedge dram_clk) begin
        if (dram_rst) begin
            rreq_count <= 0;
            rdat_count <= 0;
        end else begin
            if (dram_ren) begin
                rreq_count <= rreq_count + 1;
            end
            if (dram_dout_valid) begin
                rdat_count <= rdat_count + 1;
            end
            if ((rdat_count == DRAM_READ_FIFO_DEPTH) && empty_sfifo) begin
                rreq_count <= 0;
                rdat_count <= 0;
            end
        end
    end

    always @(posedge clk) begin
        data1 <= dout_afifo2;
        data_valid1 <= !empty_afifo2;
        data2 <= data1;
        data_valid2 <= data_valid1;
    end

    assign o_data = data2;
    assign o_data_valid = data_valid2;
    assign o_busy = (!o_init_calib_complete || full_afifo1);

endmodule
