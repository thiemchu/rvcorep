module top;
    reg         CLK = 0;
    reg         w_rst = 1;

    wire        w_rxd;
    wire        w_txd;

    reg  [31:0] mem[0:`MEM_SIZE/4-1];

    reg  [1:0]  bytecnt  = 0;
    reg  [31:0] initdata = 0;
    reg  [31:0] memaddr  = 0;
    reg         initwe   = 0;

    wire        initdone, init_txd, tx_ready;

    reg [63: 0] r_TCNT = 0; // elapsed clock cycles
    reg [63: 0] r_ICNT = 0; // the number of executed valid instructions
    reg [63: 0] r_cnt_bphit = 0;
    reg [63: 0] r_cnt_bpmis = 0;
    reg [63: 0] r_SCNT  = 0; // the number of 2-cycle load-use stalls

    reg [31:0]  r_tc = 1;

    wire [7:0]  uartdata;
    wire        uartwe;

    initial forever #10 CLK = ~CLK;
    initial         #50 w_rst = 0;
    initial $readmemh(`MEMFILE, mem);

    initial begin
        $write("Run %s\n", `MEMFILE);
        $write("Initializing : ");
    end
    always@(posedge CLK) begin
        if(memaddr % (`MEM_SIZE/4/10) == 0 && initwe && (bytecnt==0)) begin
            $write(".");
            $fflush();
        end
        if(initdone & initwe) $write("\n--------------------------------------------------\n");
    end

    main m(CLK, w_rst, w_rxd, w_txd);

    /****************************************************************************************/

    always@(posedge CLK) begin
        if (m.dmem.dram.o_init_calib_complete) begin
            bytecnt  <= (w_rst) ? 0 : (tx_ready & !initwe & !initdone) ? bytecnt+1 : bytecnt;
            initdata <= (w_rst) ? 0 : (tx_ready & !initwe & !initdone) ? ((bytecnt==0) ? mem[memaddr] : {8'h0,initdata[31:8]}) : initdata;
            memaddr  <= (w_rst) ? 0 : (tx_ready & !initwe & !initdone & bytecnt==0) ? memaddr+1 : memaddr;
            initwe   <= (w_rst) ? 0 : (tx_ready & !initwe & !initdone) ? 1 : 0;
        end
    end
    assign initdone = (memaddr >= `MEM_SIZE/4) & (bytecnt==0);

    UartTx UartTx_init(CLK, !w_rst, initdata[7:0], initwe, init_txd, tx_ready);

    assign w_rxd = init_txd;

    /****************************************************************************************/
    
    always@(posedge CLK) begin
        r_TCNT <= (m.core_rst) ? 0 : (~m.poweroff) ? r_TCNT+1 : r_TCNT;
        if (!m.p.D_STALL) begin
            r_ICNT <= (m.core_rst) ? 0 : (m.p.ExMa_v & ~m.sim_poweroff)  ? r_ICNT+1 : r_ICNT;
            r_SCNT <= (m.core_rst) ? 0 : (m.p.w_stall & ~m.sim_poweroff) ? r_SCNT+1 : r_SCNT;
            if(~m.core_rst & m.p.ExMa_v & m.p.ExMa_b & ~m.p.w_bmis & ~m.sim_poweroff) r_cnt_bphit <= r_cnt_bphit + 1;
            if(~m.core_rst & m.p.ExMa_v & m.p.ExMa_b &  m.p.w_bmis & ~m.sim_poweroff) r_cnt_bpmis <= r_cnt_bpmis + 1;
        end
    end

    always@(posedge CLK) begin
        if (m.r_halt) begin $write("HALT detect!\n"); $finish(); end
    end

    always@(negedge CLK) begin
        if(m.sim_poweroff & (m.queue_num==0) & m.tx_ready & !m.uartwe) begin
            $write("\n");
            $write("== elapsed clock cycles              : %16d\n", r_TCNT);
            $write("== valid instructions executed       : %16d\n", r_ICNT);
            $write("== IPC                               :            0.%3d\n", r_ICNT * 1000 / r_TCNT);
            $write("== branch prediction hit             : %16d\n", r_cnt_bphit);
            $write("== branch prediction miss            : %16d\n", r_cnt_bpmis);
            $write("== branch prediction total           : %16d\n", r_cnt_bphit + r_cnt_bpmis);
            $write("== branch prediction hit rate        :            0.%3d\n", r_cnt_bphit * 1000 / (r_cnt_bphit + r_cnt_bpmis));
            $write("== the num of load-use stall         : %16d\n", r_SCNT);
            $write("== estimated clock cycles            : %16d\n", r_ICNT + r_SCNT * 1 + r_cnt_bpmis * 3);
            $write("== r_cnt                             :         %08x\n", m.r_cnt);
            $write("== r_rout                            :         %08x\n", m.r_rout);
            $finish();
        end
    end

    always @(posedge CLK) if(m.p.RST_X && m.p.MaWb_v) r_tc <= r_tc + 1;

    always@(posedge CLK) begin
        if(uartwe) $write("%c", uartdata);
        if (uartwe && (uartdata < 20 || uartdata > 126) && (uartdata != 10)) $write("  %-d  ", uartdata);
        if(m.queue_num == `QUEUE_SIZE-1) begin
            $write("\nqueue num error\n");
            $finish();
        end
    end

    serialc serc (CLK, !w_rst, w_txd, uartdata, uartwe);

endmodule
/********************************************************************************************/
