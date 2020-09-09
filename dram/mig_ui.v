module MIGUI #(
               parameter APP_ADDR_WIDTH = 28,
               parameter APP_CMD_WIDTH  = 3,
               parameter APP_DATA_WIDTH = 128,
               parameter APP_MASK_WIDTH = 16)
    (
     input  wire                         clk,
     input  wire                         i_rst,
     // signals from/to user design side
     input  wire                         i_rd_en,
     input  wire                         i_wr_en,
     input  wire [APP_ADDR_WIDTH-1 : 0]  i_addr,
     input  wire [APP_DATA_WIDTH-1 : 0]  i_data,
     input  wire [APP_MASK_WIDTH-1 : 0]  i_mask,
     output wire [APP_DATA_WIDTH-1 : 0]  o_data,
     output wire                         o_data_valid,
     output wire                         o_ready,
     output wire                         o_wdf_ready,
     output wire                         o_init_calib_complete,
     // signals to/from MIG
     output wire [APP_ADDR_WIDTH-1 : 0]  app_addr,
     output wire [APP_CMD_WIDTH-1 : 0]   app_cmd,
     output wire                         app_en,
     output wire [APP_DATA_WIDTH-1 : 0]  app_wdf_data,
     output wire                         app_wdf_wren,
     output wire [APP_MASK_WIDTH-1 : 0]  app_wdf_mask,
     input  wire                         app_rdy,
     input  wire                         app_wdf_rdy,
     input  wire [APP_DATA_WIDTH-1 : 0]  app_rd_data,
     input  wire                         app_rd_data_valid,
     input  wire                         i_init_calib_complete);

    localparam STATE_CALIB           = 3'b000;
    localparam STATE_IDLE            = 3'b001;
    localparam STATE_ISSUE_CMD_WDATA = 3'b010;
    localparam STATE_ISSUE_CMD       = 3'b011;
    localparam STATE_ISSUE_WDATA     = 3'b100;

    localparam CMD_READ  = 3'b001;
    localparam CMD_WRITE = 3'b000;

    reg  [APP_ADDR_WIDTH-1 : 0] addr;
    reg  [APP_CMD_WIDTH-1 : 0]  cmd;
    reg                         en;
    reg  [APP_DATA_WIDTH-1 : 0] wdf_data;
    reg                         wdf_wren;
    reg  [APP_MASK_WIDTH-1 : 0] wdf_mask;

    reg  [2:0]                  state;

    assign o_data = app_rd_data;
    assign o_data_valid = app_rd_data_valid;
    assign o_ready = app_rdy;
    assign o_wdf_ready = app_wdf_rdy;
    assign o_init_calib_complete = i_init_calib_complete;

    assign app_addr = addr;
    assign app_cmd = cmd;
    assign app_en = en;
    assign app_wdf_data = wdf_data;
    assign app_wdf_wren = wdf_wren;
    assign app_wdf_mask = wdf_mask;

    always @(posedge clk) begin
        if (i_rst) begin
            state <= STATE_CALIB;
            cmd <= 0;
            addr <= 0;
            en <= 0;
            wdf_data <= 0;
            wdf_wren <= 0;
            wdf_mask <= 0;
        end else begin
            case (state)
                STATE_CALIB: begin
                    if (i_init_calib_complete) begin
                        state <= STATE_IDLE;
                    end
                end
                STATE_IDLE: begin
                    if (i_wr_en) begin
                        cmd <= CMD_WRITE;
                        addr <= i_addr;
                        en <= 1;
                        wdf_data <= i_data;
                        wdf_wren <= 1;
                        wdf_mask <= i_mask;
                        state <= STATE_ISSUE_CMD_WDATA;
                    end else if (i_rd_en) begin
                        cmd <= CMD_READ;
                        addr <= i_addr;
                        en <= 1;
                        wdf_wren <= 0;
                        state <= STATE_ISSUE_CMD;
                    end
                end
                STATE_ISSUE_CMD_WDATA: begin
                    if (app_rdy && app_wdf_rdy) begin
                        if (i_wr_en) begin
                            cmd <= CMD_WRITE;
                            addr <= i_addr;
                            en <= 1;
                            wdf_data <= i_data;
                            wdf_wren <= 1;
                            wdf_mask <= i_mask;
                            state <= STATE_ISSUE_CMD_WDATA;
                        end else if (i_rd_en) begin
                            cmd <= CMD_READ;
                            addr <= i_addr;
                            en <= 1;
                            wdf_wren <= 0;
                            state <= STATE_ISSUE_CMD;
                        end else begin
                            en <= 0;
                            wdf_wren <= 0;
                            state <= STATE_IDLE;
                        end
                    end else if (app_rdy) begin
                        en <= 0;
                        state <= STATE_ISSUE_WDATA;
                    end else if (app_wdf_rdy) begin
                        wdf_wren <= 0;
                        state <= STATE_ISSUE_CMD;
                    end
                end
                STATE_ISSUE_CMD: begin
                    if (app_rdy) begin
                        if (i_wr_en) begin
                            cmd <= CMD_WRITE;
                            addr <= i_addr;
                            en <= 1;
                            wdf_data <= i_data;
                            wdf_wren <= 1;
                            wdf_mask <= i_mask;
                            state <= STATE_ISSUE_CMD_WDATA;
                        end else if (i_rd_en) begin
                            cmd <= CMD_READ;
                            addr <= i_addr;
                            en <= 1;
                            wdf_wren <= 0;
                            state <= STATE_ISSUE_CMD;
                        end else begin
                            en <= 0;
                            wdf_wren <= 0;
                            state <= STATE_IDLE;
                        end
                    end
                end
                STATE_ISSUE_WDATA: begin
                    if (app_wdf_rdy) begin
                        if (i_wr_en) begin
                            cmd <= CMD_WRITE;
                            addr <= i_addr;
                            en <= 1;
                            wdf_data <= i_data;
                            wdf_wren <= 1;
                            wdf_mask <= i_mask;
                            state <= STATE_ISSUE_CMD_WDATA;
                        end else if (i_rd_en) begin
                            cmd <= CMD_READ;
                            addr <= i_addr;
                            en <= 1;
                            wdf_wren <= 0;
                            state <= STATE_ISSUE_CMD;
                        end else begin
                            wdf_wren <= 0;
                            state <= STATE_IDLE;
                        end
                    end
                end
                default: begin
                    en <= 0;
                    wdf_wren <= 0;
                    state <= STATE_IDLE;
                end
            endcase
        end
    end

endmodule
