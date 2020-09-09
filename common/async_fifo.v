module AsyncFIFO #(
                   parameter DATA_WIDTH  = 512,
                   parameter ADDR_WIDTH  = 8) // FIFO_DEPTH = 2^ADDR_WIDTH
    (
     input  wire                    wclk,
     input  wire                    rclk,
     input  wire                    i_wrst,
     input  wire                    i_rrst,
     input  wire                    i_wen,
     input  wire [DATA_WIDTH-1 : 0] i_data,
     input  wire                    i_ren,
     output wire [DATA_WIDTH-1 : 0] o_data,
     output wire                    o_empty,
     output wire                    o_full);

    reg  [DATA_WIDTH-1 : 0] afifo[(2**ADDR_WIDTH)-1 : 0];
    reg  [ADDR_WIDTH : 0]   waddr;
    reg  [ADDR_WIDTH : 0]   raddr;

    reg  [ADDR_WIDTH : 0]   raddr_gray1;
    reg  [ADDR_WIDTH : 0]   raddr_gray2;

    reg  [ADDR_WIDTH : 0]   waddr_gray1;
    reg  [ADDR_WIDTH : 0]   waddr_gray2;

    wire [DATA_WIDTH-1 : 0] data;

    wire [ADDR_WIDTH : 0]   raddr_gray;
    wire [ADDR_WIDTH : 0]   waddr_gray;

    wire [ADDR_WIDTH : 0]   raddr2;
    wire [ADDR_WIDTH : 0]   waddr2;

    genvar genvar_i;

    // output signals
    assign o_data  = data;
    assign o_empty = (raddr == waddr2);
    assign o_full  = (waddr[ADDR_WIDTH] != raddr2[ADDR_WIDTH]) &&
                     (waddr[ADDR_WIDTH-1 : 0] == raddr2[ADDR_WIDTH-1 : 0]);

    // binary code to gray code
    assign raddr_gray = raddr[ADDR_WIDTH : 0] ^ {1'b0, raddr[ADDR_WIDTH : 1]};
    assign waddr_gray = waddr[ADDR_WIDTH : 0] ^ {1'b0, waddr[ADDR_WIDTH : 1]};

    // gray code to binary code
    generate
        for (genvar_i = 0; genvar_i <= ADDR_WIDTH; genvar_i = genvar_i + 1) begin
            assign raddr2[genvar_i] = ^raddr_gray2[ADDR_WIDTH : genvar_i];
            assign waddr2[genvar_i] = ^waddr_gray2[ADDR_WIDTH : genvar_i];
        end
    endgenerate

    // double flopping read address before using it in write clock domain
    always @(posedge wclk) begin
        if (i_wrst) begin
            raddr_gray1 <= 0;
            raddr_gray2 <= 0;
        end else begin
            raddr_gray1 <= raddr_gray;
            raddr_gray2 <= raddr_gray1;
        end
    end

    // double flopping write address before using it in read clock domain
    always @(posedge rclk) begin
        if (i_rrst) begin
            waddr_gray1 <= 0;
            waddr_gray2 <= 0;
        end else begin
            waddr_gray1 <= waddr_gray;
            waddr_gray2 <= waddr_gray1;
        end
    end

    // read
    assign data = afifo[raddr[ADDR_WIDTH-1 : 0]];
    always @(posedge rclk) begin
        if (i_rrst) begin
            raddr <= 0;
        end else if (i_ren) begin
            raddr <= raddr + 1;
        end
    end

    // write
    always @(posedge wclk) begin
        if (i_wrst) begin
            waddr <= 0;
        end else if (i_wen) begin
            afifo[waddr[ADDR_WIDTH-1 : 0]] <= i_data;
            waddr <= waddr + 1;
        end
    end

endmodule
