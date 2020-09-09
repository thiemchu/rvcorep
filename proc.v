/********************************************************************************************/
/* RVCoreP (RISC-V Core Pipelining) v2019-11-19a (t111) since 2018-08-07 ArchLab. TokyoTech */
/********************************************************************************************/

/** some definitions, do not change these values                                           **/
/********************************************************************************************/
`define OPCODE_HALT____ 7'h7F // unique for RVCore
`define ALU_CTRL_ADD___ 4'h0
`define ALU_CTRL_SLL___ 4'h1
`define ALU_CTRL_SLT___ 4'h2
`define ALU_CTRL_SLTU__ 4'h3
`define ALU_CTRL_XOR___ 4'h4
`define ALU_CTRL_SRL___ 4'h5
`define ALU_CTRL_OR____ 4'h6
`define ALU_CTRL_AND___ 4'h7
`define ALU_CTRL_SUB___ 4'h8
`define ALU_CTRL_LUI___ 4'h9
`define ALU_CTRL_AUIPC_ 4'hA
`define ALU_CTRL_JAL___ 4'hB
`define ALU_CTRL_JALR__ 4'hC
`define ALU_CTRL_SRA___ 4'hD
  
/********************************************************************************************/  
module regfile(CLK, rs1, rs2, rdata1, rdata2, WE, rd, wdata, D_STALL);
    input  wire        CLK;
    input  wire [ 4:0] rs1, rs2;
    output wire [31:0] rdata1, rdata2;
    input  wire        WE;
    input  wire [ 4:0] rd;
    input  wire [31:0] wdata;
    input  wire        D_STALL;

    reg [31:0] mem [0:31];
    integer i; initial begin for(i=0; i<32; i=i+1) mem[i]=0; end

    assign rdata1 = (rs1 == 0) ? 0 : (rs1==rd) ? wdata : mem[rs1];
    assign rdata2 = (rs2 == 0) ? 0 : (rs2==rd) ? wdata : mem[rs2];
    always @(posedge CLK) begin
        if (!D_STALL) begin
            if(WE && (rd!=0)) mem[rd] <= wdata;
        end
    end
endmodule

/********************************************************************************************/
module m_IMEM#(parameter WIDTH=32, ENTRY=256)(CLK, WE, WADDR, RADDR, IDATA, ODATA);
    input  wire                     CLK, WE;
    input  wire [$clog2(ENTRY)-1:0] WADDR;
    input  wire [$clog2(ENTRY)-1:0] RADDR;
    input  wire [WIDTH-1:0]         IDATA;
    output reg  [WIDTH-1:0]         ODATA;
//    initial $write("Config: Sync_IMEM is used\n");
    
    (* ram_style = "block" *) reg [WIDTH-1:0] mem[0:ENTRY-1];
    reg [$clog2(ENTRY)-1:0] r_addr=0;
    always @(posedge CLK) begin
        if (WE) mem[WADDR] <= IDATA;
        ODATA <= mem[RADDR];
    end
endmodule

/********************************************************************************************/
/* Branch Target Buffer (BTB) : valid(1bit) + tag(7bit) + data(18bit) + cnt(2bit) = 28bit   */
/********************************************************************************************/
module m_BTB(CLK, WE, WADDR, IDATA, RADDR, ODATA, D_STALL);
    input  wire  CLK;
    input  wire  WE;
    input  wire  [8:0]  WADDR, RADDR;
    input  wire  [27:0] IDATA;
    output reg   [27:0] ODATA;
    input  wire         D_STALL;

    (* ram_style = "block" *) reg [27:0] mem[0:511];
    integer i; initial begin for(i=0; i<512; i=i+1) mem[i]=0; end
    
    always @(posedge CLK) begin
        if (!D_STALL) begin
            if (WE) mem[WADDR] <= IDATA;
            ODATA <= mem[RADDR];
        end
    end
endmodule

/********************************************************************************************/
module m_PHT(CLK, WE, IDATA, pPC, BHR, ODATA, D_STALL);
    input  wire  CLK;
    input  wire  WE;
    input  wire  [12:0] pPC;
    input  wire  [12:0] BHR;
    input  wire  [14:0] IDATA;
    output wire  [14:0] ODATA;
    input  wire         D_STALL;

    (* ram_style = "block" *) reg [1:0] mem[0:8191];
    integer i; initial for(i=0; i<8192; i=i+1) mem[i]=2; /* init by weakly-taken */
    
    reg  [12:0] PC    = 0;        // program counter
    reg  [12:0] IDX_u = 0;        // the used index
    reg  [ 1:0] TBC   = 0;        // two-bit saturating counter
    wire [12:0] index = PC ^ BHR; // index, compute using Ex-or for Gshare
    always @(posedge CLK) begin
        if (!D_STALL) begin
            if (WE) mem[IDATA[14:2]] <= IDATA[1:0];
            TBC   <= mem[index];
            PC    <= pPC;
            IDX_u <= index;
        end
    end
    assign ODATA = {IDX_u, TBC};
endmodule
/********************************************************************************************/

module m_ALU (in1, in2, imm, s, result, bsel, out);
    input  wire [31:0] in1, in2, imm;
    input  wire [10:0] s;      // select signal for ALU
    output wire [31:0] result; // output data of ALU
    input  wire  [6:0] bsel;   // select signal for BRU (Branch Resolution Unit)
    output wire  [6:0] out;    // output data of BRU
    
    wire signed [31:0] sin1 = in1;
    wire signed [31:0] sin2 = in2;
    wire signed [31:0] w_sra = (sin1 >>> in2[4:0]);
    wire        [31:0] w_srl = ( in1  >> in2[4:0]);
    
    wire        w_cmp = (s[0] & (in1 < in2)) ^ (s[1] & (sin1 < sin2));
    wire [31:0] w_add = (s[3]) ? in1 - in2 : (s[2]) ? in1 + in2 : 0;
    wire [31:0] w_log = (s[4]) ? in1 ^ in2 : (s[5]) ? in1 | in2 : (s[6]) ? in1 & in2 : imm;
    wire [31:0] w_sf1 = (s[7]) ? (in1 << in2[4:0]) : 0;
    wire [31:0] w_sf2 = (s[8]) ? w_srl : 0;
    wire [31:0] w_sf3 = (s[9]) ? w_sra : 0;

    assign result[0]    = w_cmp ^ (w_add[0]  ^ w_log[0]) ^ (w_sf1[0] ^ ((s[10]) & w_srl[0]));
    assign result[31:1] = w_add[31:1] ^ w_log[31:1] ^ (w_sf1[31:1] ^ w_sf2[31:1] ^ w_sf3[31:1]);

    wire w_op0 = (bsel[0]  & ( in1 ==  in2));
    wire w_op1 = (bsel[1]  & ( in1 !=  in2));
    wire w_op2 = (bsel[2]  & (sin1 <  sin2));
    wire w_op3 = (bsel[3]  & (sin1 >= sin2));
    wire w_op4 = (bsel[4]  & ( in1 <   in2));
    wire w_op5 = (bsel[5]  & ( in1 >=  in2));
    assign out = {bsel[6], w_op5, w_op4, w_op3, w_op2, w_op1, w_op0};
endmodule


/********************************************************************************************/
module RVCore(CLK, RST_X, r_rout, r_halt, I_ADDR, D_ADDR, I_IN, D_IN, D_OUT, D_WE, D_RE, D_STALL);
    input  wire        CLK, RST_X;
    output reg  [31:0] r_rout;
    output reg         r_halt;
    output wire [31:0] I_ADDR, D_ADDR;
    input  wire [31:0] I_IN, D_IN;
    output wire [31:0] D_OUT;
    output wire  [3:0] D_WE;
    output wire        D_RE;
    input  wire        D_STALL;

    /**************************** Architecture Register and Pipeline Register ***************/
    reg [17:0] r_pc          = `START_PC; // Program Counter
    
    reg        IfId_v        = 0; ///// IF/ID pipeline register
    reg [31:0] IfId_ir       = 0; // fetched instruction
    reg [17:0] IfId_pc       = 0;
    reg [17:0] IfId_pc_n     = 0;
    reg [ 6:0] IfId_op       = 0;
    reg [ 2:0] IfId_funct3   = 0;
    reg [ 4:0] IfId_rs1      = 0;
    reg [ 4:0] IfId_rs2      = 0;
    reg [ 4:0] IfId_rd       = 0;
    reg        IfId_mem_we   = 0;
    reg        IfId_reg_we   = 0;
    reg        IfId_op_ld    = 0;
    reg        IfId_op_im    = 0;
    reg        IfId_s1       = 0;
    reg        IfId_s2       = 0;
    reg [2:0]  IfId_im_s     = 0;

    reg        IdEx_v        = 0; ///// ID/EX pipeline register
    reg [17:0] IdEx_pc       = 0;
    reg [17:0] IdEx_pc_n     = 0;
    reg [ 6:0] IdEx_op       = 0;
    reg [ 2:0] IdEx_funct3   = 0;
    reg [ 4:0] IdEx_rd       = 0;
    reg [31:0] IdEx_imm      = 0;
    reg        IdEx_mem_we   = 0;
    reg        IdEx_reg_we   = 0;
    reg        IdEx_op_ld    = 0;
    reg [10:0] IdEx_alu_ctrl = 0; // Note!!
    reg [ 6:0] IdEx_bru_ctrl = 0;
    reg [31:0] IdEx_rrs1     = 0;
    reg [31:0] IdEx_rrs2     = 0;
    reg [31:0] IdEx_alu_imm  = 0; // additional value for ALU
    reg [31:0] IdEx_ir       = 0;
    reg [31:0] IdEx_s1       = 0;
    reg [31:0] IdEx_s2       = 0;
    reg [31:0] IdEx_u1       = 0;
    reg [31:0] IdEx_u2       = 0;
    reg        IdEx_luse     = 1; // Note
    reg        IdEx_JALR     = 0;
    reg [2:0]  IdEx_st_we    = 0;
    
    reg        ExMa_v        = 0; ///// EX/MA pipeline register
    reg [17:0] ExMa_pc       = 0;
    reg [17:0] ExMa_pc_n     = 0;
    reg [ 6:0] ExMa_op       = 0;
    reg [ 4:0] ExMa_rd       = 0;
    reg        ExMa_reg_we   = 0;
    reg        ExMa_op_ld    = 0;
    reg [31:0] ExMa_rslt     = 0;
    reg [ 6:0] ExMa_b_rslt   = 0;
    reg [17:0] ExMa_tkn_pc   = 0;
    reg [ 1:0] ExMa_addr     = 0;
    reg        ExMa_b        = 0;
    reg [31:0] ExMa_wdata    = 0;
    reg [31:0] ExMa_ir       = 0;
    reg [17:0] ExMa_npc      = 0;
    reg [17:0] ExMa_ppc      = 0;
    reg        ExMa_b_rslt_t1= 0;
    reg        ExMa_b_rslt_t2= 0;
    reg [ 6:0] ExMa_bru_ctrl = 0;
//    (* max_fanout = 6 *) reg [ 4:0] ExMa_lds      = 0; /***** for load instructions *****/
    reg [ 4:0] ExMa_lds      = 0; /***** for load instructions *****/
    reg  [2:0] ExMa_funct3   = 0;
    
    reg        MaWb_v        = 0; ///// MA/WB pipeline register
    reg [ 4:0] MaWb_rd       = 0;
    reg [31:0] MaWb_rslt     = 0;
    reg [17:0] MaWb_pc       = 0;
    reg [31:0] MaWb_wdata    = 0;
    reg [31:0] MaWb_ir       = 0; // just for verify

    /****************************************************************************************/
    reg r_RST = 1;
    always @(posedge CLK) r_RST <= !RST_X | r_halt;

    /**************************** IF  *******************************************************/
    wire [31:0]  w_ir   = I_IN;
    wire w_stall = IdEx_luse;  // stall by load-use (luse) data dependency

    /***** compute the next cycle pc using branch prediction *****/
    wire w_bmis = ExMa_b & (ExMa_b_rslt ? ExMa_b_rslt_t1 : ExMa_b_rslt_t2);
    wire [17:0] w_pc_true = {((ExMa_b_rslt) ? ExMa_tkn_pc[17:2]: ExMa_npc[17:2]), 2'b00};

    reg  [27:0] r_btb=0;
    wire [14:0] w_pht;
    reg         r_btkn_t = 0; // BTB taken temporal, valid, and tag match, prev insn untkn
    reg         IdEx_luse_x = 0;
    wire w_btkn = (r_btkn_t & w_pht[1]); // BTB says tkn, when pred tkn and prev insn untkn

    wire [15:0] w_npc = (w_bmis) ? w_pc_true[17:2] : ((IdEx_luse_x & ~D_STALL) & w_btkn) ? r_btb[19:4] : r_pc[17:2]+(IdEx_luse_x & ~D_STALL);
    
//    wire [15:0] w_npc = (w_bmis) ? w_pc_true[17:2] : (w_stall) ? r_pc[17:2] :
//                (w_btkn) ? r_btb[19:4]     : r_pc[17:2]+1;
    always @(posedge CLK) begin
        r_pc <= {w_npc, 2'b00};
    end

    wire w_pc_untkn = (w_bmis | (w_stall | D_STALL) | w_btkn) ? 0 : 1; //prev insn untkn

    wire [27:0] w_btbd = {1'b1, ExMa_ppc[17:11], ExMa_tkn_pc, 2'b00};
    wire [27:0] w_btb;
    m_BTB m_BTB(CLK, ExMa_b, ExMa_ppc[10:2], w_btbd, w_npc[8:0], w_btb, D_STALL);

//    always @(posedge CLK) r_btkn_t <= (w_btb[27] & (w_btb[23:20]==w_npc[12:9])) & w_pc_untkn;
//    always @(posedge CLK) r_btkn_t <= (w_btb[27] & (w_btb[23:20]==r_pc[14:11])) & w_pc_untkn;
    always @(posedge CLK) begin
        if (!D_STALL) begin
            r_btkn_t <= (w_btb[27] & (w_btb[26:20]==r_pc[17:11])) & w_pc_untkn;
        end
    end
    always @(posedge CLK) begin
        if (!D_STALL) begin
            r_btb <= w_btb;
        end
    end

    /********** for gshare branch predictor *************************************************/
    wire Ma_tkn = (ExMa_b_rslt!=0);                 // taken by branch or jump
    wire Ma_bb  = (ExMa_b & ExMa_bru_ctrl[6]==0);   // valid branch insn
    wire If_vbb = ~(w_stall | D_STALL) & (w_ir[6:2]==5'b11000); // valid branch, not stall and branch

    reg  [12:0] r_bhr    = 0; /* branch history register (speculatively updated) */
    reg  [12:0] r_bhr_d  = 0; /* branch history register (decided, or fixed)     */
    reg  [14:0] r_pht_wd = 0; /* PHT write data   */
    reg         r_pht_we = 0; /* PHT write enable */
    
    m_PHT m_PHT(CLK, r_pht_we, r_pht_wd, w_npc[12:0], r_bhr, w_pht, D_STALL);

    wire [12:0] w_bhr_d = (Ma_bb) ? {r_bhr_d[11:0], Ma_tkn} : r_bhr_d;
    wire [12:0] w_pht_idx = ExMa_ppc[14:2] ^ r_bhr_d;
    reg [14:0] ExMa_bp = 0;
    wire [1:0] w_tbc_t = ExMa_bp[1:0];
    wire [1:0] w_tbc = ( Ma_tkn & w_tbc_t<3) ? w_tbc_t+1 :
                       (!Ma_tkn & w_tbc_t>0) ? w_tbc_t-1 : w_tbc_t;
    always @(posedge CLK) begin
        if (!D_STALL) begin
            r_bhr    <= (w_bmis) ? w_bhr_d : (If_vbb) ? {r_bhr[11:0], w_btkn} : r_bhr;
            r_bhr_d  <= w_bhr_d;
            r_pht_wd <= {ExMa_bp[14:2], w_tbc}; // Note
            r_pht_we <= ExMa_b;  // update PHT by Jump and Branch
        end
    end
  
    reg [14:0] IfId_bp = 0;
    reg [14:0] IdEx_bp = 0;
    always @(posedge CLK) begin
        if (!D_STALL) begin
            IfId_bp <= (w_stall) ? IfId_bp : w_pht;
            IdEx_bp <= IfId_bp;
            ExMa_bp <= (!RST_X) ? 0 : IdEx_bp;
        end
    end

    assign I_ADDR = {w_npc, 2'b00};

    /****************************************************************************************/
    wire [ 4:0]  If_rd;
    wire [ 4:0]  If_rs1;
    wire [ 4:0]  If_rs2;
    wire [31:0]  w_rrs1;
    wire [31:0]  w_rrs2;
    wire         w_mem_we;
    wire         w_reg_we;
    wire         w_op_ld;
    wire         w_op_im;
    decoder_if dec_if0(w_ir, If_rd, If_rs1, If_rs2, w_mem_we, w_reg_we, w_op_ld, w_op_im);

    always @(posedge CLK) begin
        if (!D_STALL) begin
            IfId_v        <= (w_bmis) ? 0 : (w_stall) ? IfId_v      : 1;
            IfId_mem_we   <= (w_bmis) ? 0 : (w_stall) ? IfId_mem_we : w_mem_we;
            IfId_reg_we   <= (w_bmis) ? 0 : (w_stall) ? IfId_reg_we : w_reg_we;
            IfId_rd       <= (w_bmis) ? 0 : (w_stall) ? IfId_rd     : If_rd;
            IfId_op_ld    <= (w_bmis) ? 0 : (w_stall) ? IfId_op_ld  : w_op_ld;
            IfId_s1       <= (w_bmis | w_stall) ? 0 : ((If_rs1==IfId_rd) & IfId_reg_we);
            IfId_s2       <= (w_bmis | w_stall) ? 0 : ((If_rs2==IfId_rd) & IfId_reg_we);
            if(!w_stall) begin
                IfId_rs1    <= If_rs1;
                IfId_rs2    <= If_rs2;
                IfId_op     <= w_ir[6:0];
                IfId_pc     <= r_pc;
                IfId_pc_n   <= {w_npc, 2'b00};
                IfId_ir     <= w_ir;
                IfId_funct3 <= w_ir[14:12];
                IfId_op_im  <= w_op_im;
                IfId_im_s   <= (w_ir[6:2]==5'b01101) ? 3'b001 :    // LUI
                               (w_ir[6:2]==5'b00101) ? 3'b010 :    // AUIPC
                               (w_ir[6:2]==5'b11001) ? 3'b100 :    // JALR
                               (w_ir[6:2]==5'b11011) ? 3'b100 : 0; // JAL
            end
        end
    end

    /**************************** ID  *******************************************************/
    wire [9:0]  Id_alu_ctrl;
    wire [6:0]  Id_bru_ctrl;
    wire [31:0] Id_imm;
    decoder_id dec_id0(IfId_ir, Id_alu_ctrl, Id_bru_ctrl, Id_imm);

    regfile regs0(CLK, IfId_rs1, IfId_rs2, w_rrs1, w_rrs2, 1'b1, MaWb_rd, MaWb_rslt, D_STALL);
    
    /***** control signal for data forwarding *****/
    wire w_fwd_s1 = (IfId_rs1==ExMa_rd) & (ExMa_reg_we);
    wire w_fwd_s2 = (IfId_rs2==ExMa_rd) & (ExMa_reg_we);

    wire Id_s1 = (IfId_rs1==IdEx_rd) & (IdEx_reg_we);
    wire Id_s2 = (IfId_rs2==IdEx_rd) & (IdEx_reg_we);
         
    wire Id_luse = r_RST | !IdEx_luse &
         (IfId_op_ld) & ((w_ir[19:15]==IfId_rd) | (w_ir[24:20]==IfId_rd));
                   // Note: this condition of load-use may gererate false dependency
    always @(posedge CLK) begin
        if (!D_STALL) begin
            IdEx_v        <= (w_bmis | w_stall) ? 0 : IfId_v;
            IdEx_op_ld    <= (w_bmis | w_stall) ? 0 : IfId_op_ld;
            IdEx_mem_we   <= (w_bmis | w_stall) ? 0 : IfId_mem_we;
            IdEx_reg_we   <= (w_bmis | w_stall) ? 0 : IfId_reg_we;
            IdEx_luse     <= Id_luse;
            IdEx_luse_x   <= !Id_luse;
            IdEx_op       <= IfId_op;
            IdEx_pc       <= IfId_pc;
            IdEx_pc_n     <= IfId_pc_n;
            IdEx_rd       <= IfId_rd;
            IdEx_ir       <= IfId_ir;
            IdEx_funct3   <= IfId_funct3;
            IdEx_imm      <= Id_imm;
            IdEx_alu_ctrl <= {(Id_alu_ctrl[9] |Id_alu_ctrl[8]), Id_alu_ctrl};
            IdEx_bru_ctrl <= Id_bru_ctrl;
            IdEx_JALR     <= (IfId_op[6:2]==5'b11001);
            IdEx_st_we[0] <= ((w_bmis | w_stall) ? 0 :IfId_mem_we) & (IfId_funct3[1:0]==0);
            IdEx_st_we[1] <= ((w_bmis | w_stall) ? 0 :IfId_mem_we) & IfId_funct3[0];
            IdEx_st_we[2] <= ((w_bmis | w_stall) ? 0 :IfId_mem_we) & IfId_funct3[1];
            IdEx_s1       <= {32{Id_s1}};
            IdEx_s2       <= {32{Id_s2}};
            IdEx_u1       <= {32{!Id_s1 & w_fwd_s1}};
            IdEx_u2       <= {32{!Id_s2 & w_fwd_s2}};
            IdEx_alu_imm  <= (IfId_im_s[0]) ? {IfId_ir[31:12], 12'b0}           :   
                             (IfId_im_s[1]) ? IfId_pc + {IfId_ir[31:12], 12'b0} :   
                             (IfId_im_s[2]) ? IfId_pc + 4                       : 0;
        end
    end

    always @(posedge CLK) begin
        if (!D_STALL) begin
            IdEx_rrs1     <= (Id_s1 | w_fwd_s1) ? 0 : w_rrs1;
            IdEx_rrs2     <= (Id_s2 | w_fwd_s2) ? 0 : (IfId_op_im) ? Id_imm : w_rrs2;
        end
    end
    /**************************** EX  *******************************************************/
    wire [31:0] Ex_rrs1 = ((IdEx_s1) & ExMa_rslt) ^ ((IdEx_u1) & MaWb_rslt) ^ IdEx_rrs1;
    wire [31:0] Ex_rrs2 = ((IdEx_s2) & ExMa_rslt) ^ ((IdEx_u2) & MaWb_rslt) ^ IdEx_rrs2;
    
    wire    [6:0]  w_b_rslt;  // BRU result
    wire    [31:0] w_a_rslt;  // ALU result
    wire    [17:0] w_tkn_pc;  // Taken PC

    assign w_tkn_pc = (IdEx_JALR) ? Ex_rrs1+IdEx_imm : IdEx_pc+IdEx_imm; // using rrs1
    assign D_ADDR = Ex_rrs1 + IdEx_imm;                                  // using rrs1
    assign D_OUT  = (IdEx_funct3[0]) ? {2{Ex_rrs2[15:0]}} :              // using rrs2
                    (IdEx_funct3[1]) ? Ex_rrs2 : {4{Ex_rrs2[7:0]}};      // using rrs2
    
    m_ALU alu0(Ex_rrs1, Ex_rrs2, IdEx_alu_imm, IdEx_alu_ctrl, w_a_rslt, 
               IdEx_bru_ctrl, w_b_rslt);

    always @(posedge CLK) begin
        if (!D_STALL) begin
            ExMa_v        <= (w_bmis) ? 0 : IdEx_v;
            ExMa_reg_we   <= (w_bmis) ? 0 : IdEx_reg_we;
            ExMa_b        <= (!RST_X || w_bmis || IdEx_v==0) ? 0 : (IdEx_bru_ctrl!=0);
            ExMa_rslt     <= w_a_rslt;
            ExMa_b_rslt   <= w_b_rslt;
            ExMa_ir       <= IdEx_ir;
            ExMa_pc       <= IdEx_pc;   // pc of this instruction
            ExMa_ppc      <= IdEx_pc-4;
            ExMa_npc      <= IdEx_pc+4; // next pc
            ExMa_pc_n     <= IdEx_pc_n; // predicted_next pc
            ExMa_tkn_pc   <= w_tkn_pc;  // taken pc
            ExMa_op       <= IdEx_op;
            ExMa_rd       <= IdEx_rd;
            ExMa_op_ld    <= IdEx_op_ld;
            ExMa_addr     <= D_ADDR[1:0];
            ExMa_wdata    <= D_OUT;
            ExMa_b_rslt_t1<= (w_tkn_pc   !=IdEx_pc_n); // to detect branch pred miss
            ExMa_b_rslt_t2<= ((IdEx_pc+4)!=IdEx_pc_n); // to detect branch pred miss
            ExMa_bru_ctrl <= IdEx_bru_ctrl;
            ExMa_funct3   <= IdEx_funct3;
        end
    end

    /***** for store instruction *****/
    wire [3:0] w_we_sb = (IdEx_st_we[0]) ? (4'b0001 << D_ADDR[1:0])       : 0;
    wire [3:0] w_we_sh = (IdEx_st_we[1]) ? (4'b0011 << {D_ADDR[1], 1'b0}) : 0;
    wire [3:0] w_we_sw = (IdEx_st_we[2]) ? 4'b1111                        : 0;
    assign D_WE = {4{!w_bmis}} & (w_we_sh ^ w_we_sw ^ w_we_sb);
    assign D_RE = (IdEx_op_ld)? 1 : 0;
    
    always @(posedge CLK) begin
        if (!D_STALL) begin
            ExMa_lds <= (!IdEx_op_ld) ? 0 :
                        (IdEx_funct3==3'b000) ? 5'b01001 :
                        (IdEx_funct3==3'b001) ? 5'b01010 :
                        (IdEx_funct3==3'b010) ? 5'b00100 :
                        (IdEx_funct3==3'b100) ? 5'b00001 : 5'b00010 ;
        end
    end
    /**************************** MEM *******************************************************/
    wire [1:0]  w_adr  = ExMa_addr;
    wire [7:0]  w_lb_t = D_IN >> ({w_adr, 3'd0});
    wire [15:0] w_lh_t = (w_adr[1]) ? D_IN[31:16] : D_IN[15:0];

    wire [31:0] w_ld_lb  = (ExMa_lds[0]) ? {{24{w_lb_t[ 7] & ExMa_lds[3]}}, w_lb_t[ 7:0]} : 0;
    wire [31:0] w_ld_lh  = (ExMa_lds[1]) ? {{16{w_lh_t[15] & ExMa_lds[3]}}, w_lh_t[15:0]} : 0;
    wire [31:0] w_ld_lw  = (ExMa_lds[2]) ? D_IN                             : 0;
    wire [31:0] Ma_rslt = w_ld_lb ^ w_ld_lh ^ w_ld_lw ^ ExMa_rslt;
    
    always @(posedge CLK) begin
        if (!D_STALL) begin
            MaWb_v     <= ExMa_v;
            MaWb_pc    <= ExMa_pc;
            MaWb_ir    <= ExMa_ir;
            MaWb_wdata <= ExMa_wdata;
            MaWb_rd    <= (ExMa_v) ? ExMa_rd : 0;
            MaWb_rslt  <= Ma_rslt;
        end
    end

    /**************************** others ****************************************************/
    initial r_halt = 0;
    always @(posedge CLK) begin
        if (!D_STALL) begin
            if (ExMa_op==`OPCODE_HALT____) r_halt <= 1; /// Note
        end
    end

    initial r_rout = 0;
    always @(posedge CLK) begin
        if (!D_STALL) begin
            r_rout <= (MaWb_v) ? MaWb_pc : r_rout; /// Note
        end
    end
endmodule

/***** Instraction decoder, see RV32I opcode map                                        *****/
/********************************************************************************************/
module decoder_id(ir, alu_ctrl, bru_ctrl, imm);
    input  wire [31:0] ir;
    output reg  [ 9:0] alu_ctrl;
    output reg  [ 6:0] bru_ctrl;
    output wire [31:0] imm;
    
    wire [4:0] op     = ir[ 6: 2]; // use 5-bit, cause lower 2-bit are always 2'b11
    wire [2:0] funct3 = ir[14:12];
    wire [6:0] funct7 = ir[31:25];

    wire r_type = (op==5'b01100);
    wire s_type = (op[4:2]==3'b010); // (op==5'b01000);
    wire b_type = (op==5'b11000);
    wire j_type = (op==5'b11011);
    wire u_type = ({op[4], op[2:0]} ==4'b0101);
    wire i_type = (op==5'b11001 || op==5'b00000 || op==5'b00100);

    wire [31:0] imm_U = (u_type) ? {ir[31:12], 12'b0} : 0;
    wire [31:0] imm_I = (i_type) ? {{21{ir[31]}}, ir[30:20]} : 0;
    wire [31:0] imm_S = (s_type) ? {{21{ir[31]}}, ir[30:25], ir[11:7]} : 0;
    wire [31:0] imm_B = (b_type) ? {{20{ir[31]}}, ir[7], ir[30:25] ,ir[11:8], 1'b0} : 0;
    wire [31:0] imm_J = (j_type) ? {{12{ir[31]}}, ir[19:12], ir[20], ir[30:21], 1'b0} : 0;
    assign imm = imm_U ^ imm_I ^ imm_S ^ imm_B ^ imm_J;

    reg [3:0] r_alu_ctrl;
    always @(*) begin
        case(op)
            5'b01100 : r_alu_ctrl = {funct7[5], funct3}; 
            5'b00100 : r_alu_ctrl = (funct3==3'h5) ? {funct7[5], funct3} : {1'b0, funct3};
            default  : r_alu_ctrl = 4'b1111;
        endcase
    end

    always @(*) begin /***** one-hot encoding *****/
        case(r_alu_ctrl)
            `ALU_CTRL_SLTU__ : alu_ctrl = 10'b0000000001;
            `ALU_CTRL_SLT___ : alu_ctrl = 10'b0000000010;
            `ALU_CTRL_ADD___ : alu_ctrl = 10'b0000000100;
            `ALU_CTRL_SUB___ : alu_ctrl = 10'b0000001000;
            `ALU_CTRL_XOR___ : alu_ctrl = 10'b0000010000;
            `ALU_CTRL_OR____ : alu_ctrl = 10'b0000100000;
            `ALU_CTRL_AND___ : alu_ctrl = 10'b0001000000;
            `ALU_CTRL_SLL___ : alu_ctrl = 10'b0010000000;
            `ALU_CTRL_SRL___ : alu_ctrl = 10'b0100000000;
            `ALU_CTRL_SRA___ : alu_ctrl = 10'b1000000000;
            default          : alu_ctrl = 10'b0000000000;
        endcase
    end
    
    always @(*) begin /***** one-hot encoding *****/
        case(op)
            5'b11011 : bru_ctrl =                    7'b1000000;     // JAL  -> taken
            5'b11001 : bru_ctrl =                    7'b1000000;     // JALR -> taken
            5'b11000 : bru_ctrl = (funct3==3'b000) ? 7'b0000001 :    // BEQ
                                  (funct3==3'b001) ? 7'b0000010 :    // BNE
                                  (funct3==3'b100) ? 7'b0000100 :    // BLT
                                  (funct3==3'b101) ? 7'b0001000 :    // BGE
                                  (funct3==3'b110) ? 7'b0010000 :    // BLTU
                                  (funct3==3'b111) ? 7'b0100000 : 0; // BGEU
            default : bru_ctrl = 0;
        endcase
    end
endmodule

/***** Instraction decoder, see RV32I opcode map                                        *****/
/********************************************************************************************/
module decoder_if(ir, rd, rs1, rs2, mem_we, reg_we, op_ld, op_imm);
    input  wire [31:0] ir;
    output wire [ 4:0] rd, rs1, rs2;
    output wire        mem_we, reg_we, op_ld, op_imm;
    
    wire [4:0] op     = ir[ 6: 2]; // use 5-bit, cause lower 2-bit are always 2'b11
    wire [2:0] funct3 = ir[14:12];
    wire [6:0] funct7 = ir[31:25];

    wire r_type = (op==5'b01100);
    wire s_type = (op[4:2]==3'b010); // (op==5'b01000);
    wire b_type = (op==5'b11000);
    wire j_type = (op==5'b11011);
    wire u_type = ({op[4], op[2:0]} ==4'b0101);
    wire i_type = (op==5'b11001 || op==5'b00000 || op==5'b00100);

    assign reg_we = (ir[11:7]!=0) & (op[3:0]!=4'b1000);  //!s_type && !b_type;
    assign mem_we = s_type;
    assign op_ld  = (op==5'b00000);
    assign op_imm = (op==5'b00100);
    assign rd     = (reg_we) ? ir[11:7] : 5'd0;
    assign rs1    = ir[19:15]; // (!u_type && !j_type)       ? ir[19:15] : 5'd0;
    assign rs2    = (!op_imm) ? ir[24:20] : 5'd0;
endmodule
