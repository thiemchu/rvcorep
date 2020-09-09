module SyncFIFO #(
                  parameter DATA_WIDTH  = 512,
                  parameter ADDR_WIDTH  = 8) // FIFO_DEPTH = 2^ADDR_WIDTH
    (
     input  wire                    clk,
     input  wire                    i_rst,
     input  wire                    i_wen,
     input  wire [DATA_WIDTH-1 : 0] i_data,
     input  wire                    i_ren,
     output wire [DATA_WIDTH-1 : 0] o_data,
     output wire                    o_empty,
     output wire                    o_full);

    reg  [DATA_WIDTH-1 : 0] sfifo[(2**ADDR_WIDTH)-1 : 0];
    reg  [ADDR_WIDTH : 0]   waddr;
    reg  [ADDR_WIDTH : 0]   raddr;

    wire [DATA_WIDTH-1 : 0] data;

    // output signals
    assign o_data  = data;
    assign o_empty = (waddr == raddr);
    assign o_full  = (waddr[ADDR_WIDTH] != raddr[ADDR_WIDTH]) &&
                     (waddr[ADDR_WIDTH-1 : 0] == raddr[ADDR_WIDTH-1 : 0]);

    // read
    assign data = sfifo[raddr[ADDR_WIDTH-1 : 0]];
    always @(posedge clk) begin
        if (i_rst) begin
            raddr <= 0;
        end else if (i_ren) begin
            raddr <= raddr + 1;
        end
    end

    // write
    always @(posedge clk) begin
        if (i_rst) begin
            waddr <= 0;
        end else if (i_wen) begin
            sfifo[waddr[ADDR_WIDTH-1 : 0]] <= i_data;
            waddr <= waddr + 1;
        end
    end

endmodule
