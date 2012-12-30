module j1(
   // Inputs
   sys_clk_i, sys_rst_i, io_din,
   // Outputs
   io_rd, io_wr, io_addr, io_dout);

  input sys_clk_i;              // main clock
  input sys_rst_i;              // reset
  input  [15:0] io_din;         // io data in
  output io_rd;                 // io read
  output io_wr;                 // io write
  output [15:0] io_addr;        // io address
  output [15:0] io_dout;        // io data out

  wire [15:0] insn;
  wire [15:0] immediate = { 1'b0, insn[14:0] };

  wire [15:0] ramrd;

  reg [4:0] dsp;
  reg [4:0] _dsp;
  reg [15:0] st0;
  reg [15:0] _st0;
  wire [15:0] st1;
  wire _dstkW;     // D stack write

  reg [12:0] pc;
  reg [12:0] _pc;
  reg [4:0] rsp;
  reg [4:0] _rsp;
  wire [15:0] rst0;
  reg _rstkW;     // R stack write
  reg [15:0] _rstkD;
  wire _ramWE;     // RAM write enable

  wire [15:0] pc_plus_1;
  assign pc_plus_1 = pc + 1;

`define RAMS 3

  genvar i;

`define w (16 >> `RAMS)
`define w1 (`w - 1)

  generate 
    for (i = 0; i < (1 << `RAMS); i=i+1) begin : ram
      // RAMB16_S18_S18
      RAMB16BWER #(
    .DATA_WIDTH_A(36),
    .DATA_WIDTH_B(9),
    .DOA_REG(0),
    .DOB_REG(0),
    .EN_RSTRAM_A("FALSE"),
    .EN_RSTRAM_B("FALSE"),
    .SIM_DEVICE("SPARTAN6"),
    .WRITE_MODE_A("WRITE_FIRST"),
    .WRITE_MODE_B("WRITE_FIRST")
)
      ram(
        .DIA(0),
        .DIPA(0),
        .DOA(insn[`w*i+`w1:`w*i]),
        .WEA(0),
        .ENA(1),
	.RSTA(1'b0),
        .CLKA(sys_clk_i),
        .ADDRA({_pc}),

        .DIB(st1[`w*i+`w1:`w*i]),
        .DIPB(0),
        .WEB(_ramWE & (_st0[15:14] == 0)),
        .ENB(|_st0[15:14] == 0),
	.RSTB(1'b0),
        .CLKB(sys_clk_i),
        .ADDRB(_st0[15:1]),
        .DOB(ramrd[`w*i+`w1:`w*i]));
    end
  endgenerate

  reg [15:0] dstack[0:31];
  reg [15:0] rstack[0:31];
  always @(posedge sys_clk_i)
  begin
    if (_dstkW)
      dstack[_dsp] = st0;
    if (_rstkW)
      rstack[_rsp] = _rstkD;
  end
  assign st1 = dstack[dsp];
  assign rst0 = rstack[rsp];
  
  reg [3:0] st0sel;
  always @*
  begin
    case (insn[14:13])
      2'b00: st0sel = 0;          // ubranch
      2'b01: st0sel = 1;          // 0branch
      2'b10: st0sel = 0;          // call
      2'b11: st0sel = insn[11:8]; // ALU
      default: st0sel = 4'bxxxx;
    endcase
  end

  always @*
  begin
    if (insn[15])
      _st0 = immediate;
    else
      case (st0sel)
        4'b0000: _st0 = st0;
        4'b0001: _st0 = st1;
        4'b0010: _st0 = st0 + st1;
        4'b0011: _st0 = st0 & st1;
        4'b0100: _st0 = st0 | st1;
        4'b0101: _st0 = st0 ^ st1;
        4'b0110: _st0 = ~st0;
        4'b0111: _st0 = {16{(st1 == st0)}};
        4'b1000: _st0 = {16{($signed(st1) < $signed(st0))}};
        4'b1001: _st0 = st1 >> st0[3:0];
        4'b1010: _st0 = st0 - 1;
        4'b1011: _st0 = rst0;
        4'b1100: _st0 = |st0[15:14] ? io_din : ramrd;
        4'b1101: _st0 = st1 << st0[3:0];
        4'b1110: _st0 = {rsp, 3'b000, dsp};
        4'b1111: _st0 = {16{(st1 < st0)}};
        default: _st0 = 16'hxxxx;
      endcase
  end

  wire is_alu = (insn[15:13] == 3'b011);
  wire is_lit = (insn[15]);

  assign io_rd = (is_alu & (insn[11:8] == 4'hc) & (|st0[15:14]));
  assign io_wr = _ramWE;
  assign io_addr = st0;
  assign io_dout = st1;

  assign _ramWE = is_alu & insn[5];
  assign _dstkW = is_lit | (is_alu & insn[7]);

  wire [1:0] dd = insn[1:0];  // D stack delta
  wire [1:0] rd = insn[3:2];  // R stack delta

  always @*
  begin
    if (is_lit) begin                       // literal
      _dsp = dsp + 1;
      _rsp = rsp;
      _rstkW = 0;
      _rstkD = _pc;
    end else if (is_alu) begin
      _dsp = dsp + {dd[1], dd[1], dd[1], dd};
      _rsp = rsp + {rd[1], rd[1], rd[1], rd};
      _rstkW = insn[6];
      _rstkD = st0;
    end else begin                          // jump/call
      // predicated jump is like DROP
      if (insn[15:13] == 3'b001) begin
        _dsp = dsp - 1;
      end else begin
        _dsp = dsp;
      end
      if (insn[15:13] == 3'b010) begin // call
        _rsp = rsp + 1;
        _rstkW = 1;
        _rstkD = {pc_plus_1[14:0], 1'b0};
      end else begin
        _rsp = rsp;
        _rstkW = 0;
        _rstkD = _pc;
      end
    end
  end

  always @*
  begin
    if (sys_rst_i)
      _pc = pc;
    else
      if ((insn[15:13] == 3'b000) |
          ((insn[15:13] == 3'b001) & (|st0 == 0)) |
          (insn[15:13] == 3'b010))
        _pc = insn[12:0];
      else if (is_alu & insn[12])
        _pc = rst0[15:1];
      else
        _pc = pc_plus_1;
  end

  always @(posedge sys_clk_i)
  begin
    if (sys_rst_i) begin
      pc <= 0;
      dsp <= 0;
      st0 <= 0;
      rsp <= 0;
    end else begin
      dsp <= _dsp;
      pc <= _pc;
      st0 <= _st0;
      rsp <= _rsp;
    end
  end

endmodule // j1
module reset_gen(/*AUTOARG*/
   // Outputs
   sys_rst_i,
   // Inputs
   trig_reset, sys_clk_i
   );
  parameter RESET_CYCLES = 0;
  output sys_rst_i;
  input trig_reset;
  input sys_clk_i;

  reg [13:0] reset_count = RESET_CYCLES;
  wire sys_rst_i = |reset_count;

  always @(posedge sys_clk_i) begin
    if (trig_reset)
      reset_count <= RESET_CYCLES;
    else if (sys_rst_i)
      reset_count <= reset_count - 1;
  end
endmodule
`define hdl_version 12'h600

module soc(
   // Outputs
   led,
   // Inputs
   clk
   );
   
   localparam RESET_CYCLES   = 10000;
   
   // Clock, reset and configuration signals
   input clk;

   // Debug signals

   output 		led;
   reg                  trig_reconf;            // From dio of dio.v
   reg                  trig_reset;             // From dio of dio.v

   wire                 sys_rst_i;              // From reset_gen of reset_gen.v

   wire                 j1_io_rd;
   wire                 j1_io_wr;
   wire                 [15:0] j1_io_addr;
   reg                  [15:0] j1_io_din;
   wire                 [15:0] j1_io_dout;

   // Reset generation
   
   reset_gen #(/*AUTOINSTPARAM*/
               // Parameters
               .RESET_CYCLES            (RESET_CYCLES)) 
   reset_gen(/*AUTOINST*/
             // Outputs
             .sys_rst_i                 (sys_rst_i),
             // Inputs
             .trig_reset                (trig_reset),
             .sys_clk_i                 (clk));
`ifdef 0
  assign sys_rst_i = trig_reset;
`endif
   
   // J1

   j1 j1(/*AUTOINST*/
             // Inputs
             .sys_clk_i                 (clk),
             .sys_rst_i                 (sys_rst_i),

        // Inputs

        .io_rd(j1_io_rd),
        .io_wr(j1_io_wr),
        .io_addr(j1_io_addr),
        .io_din(j1_io_din),
        .io_dout(j1_io_dout)
        );

  // ================================================

  reg  [31:0]     clock;
  reg  [8:0]      clockus;
  wire [8:0]      _clockus;
  assign _clockus = (clockus != 67) ? (clockus + 1) : 0;

  always @(posedge clk)
  begin
    if (sys_rst_i) begin
      clock <= 0;
      clockus <= 0;
    end else begin
      clockus <= _clockus;
      if (_clockus == 0)
        clock <= clock + 1;
    end
  end

  // ================================================
  // XOR line

  wire [15:0] xorline_rd;
  wire [15:0] xorline_prev;
  reg [15:0] xorline_addr;

  RAMB16BWER #(
    .DATA_WIDTH_A(36),
    .DATA_WIDTH_B(9),
    .DOA_REG(0),
    .DOB_REG(0),
    .EN_RSTRAM_A("FALSE"),
    .EN_RSTRAM_B("FALSE"),
    .SIM_DEVICE("SPARTAN6"),
    .WRITE_MODE_A("WRITE_FIRST"),
    .WRITE_MODE_B("WRITE_FIRST")
)
 xorline_ram(   
    .DIA(0),
    .DIPA(0),
    .DOA(xorline_rd),
    .WEA(0),
    .ENA(1),
    .RSTA(1'b0),
    .CLKA(clk),
    .ADDRA(j1_io_addr[15:1]),

    .DIB(xorline_prev ^ j1_io_dout),
    .DIPB(2'b00),
    .WEB((j1_io_addr == 16'h5f00) & j1_io_wr),
    .ENB(1),
    .RSTB(1'b0),
    .CLKB(clk),
    .ADDRB(xorline_addr),
    .DOB(xorline_prev));

  always @(posedge clk)
  begin
    if ((j1_io_addr == 16'h5f00) & j1_io_wr)
      xorline_addr = xorline_addr + 1;
    else if ((j1_io_addr == 16'h5f02) & j1_io_wr)
      xorline_addr = 0;
  end

  // ================================================
  // LED

  reg led;

  // ================================================
  // J1's Memory Mapped I/O

  // ============== J1 READS ========================
  always @*
  begin
    if (j1_io_addr[15:12] == 5)
      j1_io_din = xorline_rd;
    else 
      case (j1_io_addr)

        16'h6302: j1_io_din = `hdl_version;

        //16'hfff0: j1_io_din = clock[15:0];
        //16'hfff2: j1_io_din = clock[31:16];

        default: j1_io_din = 16'h0666;
      endcase
  end

  // ============== J1 WRITES =======================
  reg [15:0] slow_io_dout;
  reg [15:0] slow_io_addr;

  // latch addr+data to reduce fanout load on the J1
  always @(posedge clk)
  begin
    if (j1_io_wr) begin
      slow_io_addr <= j1_io_addr;
      slow_io_dout <= j1_io_dout;
    end
  end

  always @(posedge clk)
  begin
    if (sys_rst_i) begin
      trig_reconf <= 0;
      trig_reset <= 0;
    end else begin
      case (slow_io_addr)
        16'h6300: led <= slow_io_dout[0];

      endcase
    end
  end

endmodule // top
