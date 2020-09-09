module DataMemory #(
                    // DRAM_SIZE is in bytes
                    // DRAM_SIZE must be a multiple of
                    // 16 bytes = 128 bits (APP_DATA_WIDTH)
                    parameter DRAM_SIZE         = 4 * 1024,
                    // only busrt length = 8 is supported
                    parameter DRAM_BURST_LENGTH = 8,
                    parameter APP_ADDR_WIDTH,
                    parameter APP_DATA_WIDTH    = 128,
                    parameter APP_MASK_WIDTH    = 16)
    (
     input  wire                         clk,
     input  wire                         i_rst,
     // user design interface signals
     input  wire                         i_dmem_init_done,
     input  wire [3:0]                   i_dmem_init_wen,
     input  wire [31:0]                  i_dmem_init_addr,
     input  wire [31:0]                  i_dmem_init_data,
     input  wire                         i_dmem_ren,
     input  wire [3:0]                   i_dmem_wen,
     input  wire [31:0]                  i_dmem_addr,
     input  wire [31:0]                  i_dmem_data,
     output wire [31:0]                  o_dmem_data,
     output wire                         o_dmem_stall);

    localparam STATE_DRAM_CALIB     = 3'b000;
    localparam STATE_DRAM_IDLE      = 3'b001;
    localparam STATE_DRAM_WRITE     = 3'b010;
    localparam STATE_DRAM_READ      = 3'b011;
    localparam STATE_DRAM_READ_WAIT = 3'b100;

    wire                        dram_ren;
    wire                        dram_wen;
    wire [APP_ADDR_WIDTH-2 : 0] dram_addr;
    wire [2:0]                  dram_addr_column_offset;
    reg  [APP_DATA_WIDTH-1 : 0] dram_din;
    reg  [APP_MASK_WIDTH-1 : 0] dram_mask;
    wire                        dram_init_calib_complete;
    wire [APP_DATA_WIDTH-1 : 0] dram_dout;
    wire                        dram_dout_valid;
    wire                        dram_busy;

    wire                        user_design_busy;

    reg  [APP_DATA_WIDTH-1:0]   dram_dout_reg;

    wire                        dmem_ren;
    wire [3:0]                  dmem_wen;
    wire [31:0]                 dmem_addr;
    wire [31:0]                 dmem_din;
    reg  [31:0]                 dmem_dout;
    wire                        dmem_stall;

    reg  [3:0]                  dmem_wen_reg;
    reg  [31:0]                 dmem_addr_reg;
    reg  [31:0]                 dmem_din_reg;

    reg  [2:0]                  state;

    integer i;

    assign o_dmem_data = dmem_dout;
    assign o_dmem_stall = dmem_stall;

    assign dmem_ren  = (i_dmem_init_done)? i_dmem_ren  : 0;
    assign dmem_wen  = (i_dmem_init_done)? i_dmem_wen  : i_dmem_init_wen;
    assign dmem_addr = (i_dmem_init_done)? i_dmem_addr : i_dmem_init_addr;
    assign dmem_din  = (i_dmem_init_done)? i_dmem_data : i_dmem_init_data;

    always @(*) begin
        dmem_dout = 0;
        for (i = 0; i < 4; i = i + 1) begin // 4: APP_DATA_WIDTH/32
            if (dram_addr_column_offset[2:1] == i) begin
                dmem_dout = dram_dout_reg[i*32 +: 32];
            end
        end
    end

    assign dmem_stall = (state != STATE_DRAM_IDLE);

    assign dram_ren = ((state == STATE_DRAM_READ) && !dram_busy);
    assign dram_wen = ((state == STATE_DRAM_WRITE) && !dram_busy);
    assign dram_addr = {dmem_addr_reg[APP_ADDR_WIDTH-1 : 4], 3'b000};
    assign dram_addr_column_offset = dmem_addr_reg[3:1];

    always @(*) begin
        dram_din = 0;
        for (i = 0; i < 4; i = i + 1) begin // 4: APP_DATA_WIDTH/32
            if (dram_addr_column_offset[2:1] == i) begin
                dram_din[i*32 +: 32] = dmem_din_reg;
            end
        end
    end

    always @(*) begin
        dram_mask = {(APP_MASK_WIDTH){1'b1}};
        for (i = 0; i < APP_MASK_WIDTH; i = i + 4) begin // 4: 32/8
            if ({dram_addr_column_offset, 1'b0} == i) begin
                dram_mask[i +: 4] = (~dmem_wen_reg);
            end
        end
    end

    // in this implementation, user design is stalled when dram is accessed;
    // thus, when data are available, user design can always accept them
    assign user_design_busy = 1'b0;

    DRAM #(
           .DRAM_SIZE(DRAM_SIZE),
           .DRAM_BURST_LENGTH(DRAM_BURST_LENGTH),
           .APP_ADDR_WIDTH(APP_ADDR_WIDTH),
           .APP_DATA_WIDTH(APP_DATA_WIDTH),
           .APP_MASK_WIDTH(APP_MASK_WIDTH))
    dram (
          .clk(clk),
          .i_rst(i_rst),
          // user design interface signals
          .i_ren(dram_ren),
          .i_wen(dram_wen),
          .i_addr(dram_addr),
          .i_data(dram_din),
          .i_mask(dram_mask),
          .i_busy(user_design_busy),
          .o_init_calib_complete(dram_init_calib_complete),
          .o_data(dram_dout),
          .o_data_valid(dram_dout_valid),
          .o_busy(dram_busy));

    always @(posedge clk) begin
        if (i_rst) begin
            state <= STATE_DRAM_CALIB;
            dmem_wen_reg <= 0;
            dmem_addr_reg <= 0;
            dmem_din_reg <= 0;
            dram_dout_reg <= 0;
        end else begin
            case (state)
                STATE_DRAM_CALIB: begin
                    if (dram_init_calib_complete) begin
                        state <= STATE_DRAM_IDLE;
                    end
                end
                STATE_DRAM_IDLE: begin
                    dmem_wen_reg <= dmem_wen;
                    dmem_addr_reg <= dmem_addr;
                    dmem_din_reg <= dmem_din;
                    if (dmem_wen != 0) begin
                        state <= STATE_DRAM_WRITE;
                    end else if (dmem_ren) begin
                        state <= STATE_DRAM_READ;
                    end
                end
                STATE_DRAM_WRITE: begin
                    if (!dram_busy) begin
                        state <= STATE_DRAM_IDLE;
                    end
                end
                STATE_DRAM_READ: begin
                    if (!dram_busy) begin
                        state <= STATE_DRAM_READ_WAIT;
                    end
                end
                default: begin // STATE_DRAM_READ_WAIT
                    dram_dout_reg <= dram_dout;
                    if (dram_dout_valid) begin
                        state <= STATE_DRAM_IDLE;
                    end
                end
            endcase
        end
    end

endmodule
