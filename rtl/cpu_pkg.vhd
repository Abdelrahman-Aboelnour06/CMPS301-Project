-------------------------------------------------------------------------------
-- cpu_pkg.vhd
-- Global parameters, types, opcodes, ALU operation codes and the decoded
-- control record shared by every RTL module of the CMPS 301 six-stage
-- pipelined processor.
-- Language: VHDL-93 (also compiles as VHDL-2008).
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package cpu_pkg is

  -- -------------------------------------------------------------------------
  -- Global design parameters
  -- -------------------------------------------------------------------------
  constant WIDTH      : natural := 32;    -- datapath width
  constant REGADDR    : natural := 3;     -- 2^3 = 8 registers
  constant NREGS      : natural := 8;
  constant MEMINDEX   : natural := 12;    -- 2^12 = 4096 words
  constant MEMDEPTH   : natural := 4096;
  constant ALUOP      : natural := 4;     -- ALU operation select width
  constant PIPESTAGES : natural := 6;     -- F, D, X1, X2, M, W

  subtype word_t  is std_logic_vector(WIDTH-1 downto 0);
  subtype raddr_t is std_logic_vector(REGADDR-1 downto 0);
  subtype maddr_t is std_logic_vector(MEMINDEX-1 downto 0);
  subtype aluop_t is std_logic_vector(ALUOP-1 downto 0);
  subtype opcode_t is std_logic_vector(5 downto 0);

  type reg_array_t is array (0 to NREGS-1) of word_t;
  type mem_t       is array (0 to MEMDEPTH-1) of word_t;

  constant WORD_ZERO : word_t := (others => '0');
  constant MEM_ZERO  : mem_t  := (others => (others => '0'));
  constant SP_RESET  : word_t := x"00000FFF";   -- 4095

  -- -------------------------------------------------------------------------
  -- Opcodes (instruction bits [31:26])
  -- -------------------------------------------------------------------------
  constant OP_NOP  : opcode_t := "000000";
  constant OP_NOT  : opcode_t := "000001";
  constant OP_INC  : opcode_t := "000010";
  constant OP_OUT  : opcode_t := "000100";
  constant OP_IN   : opcode_t := "000101";
  constant OP_SETC : opcode_t := "000110";
  constant OP_HLT  : opcode_t := "000111";
  constant OP_MOV  : opcode_t := "010000";
  constant OP_SWAP : opcode_t := "010001";
  constant OP_ADD  : opcode_t := "010010";
  constant OP_SUB  : opcode_t := "010011";
  constant OP_AND  : opcode_t := "010100";
  constant OP_CMP  : opcode_t := "010101";
  constant OP_SHR  : opcode_t := "010110";
  constant OP_SHL  : opcode_t := "010111";
  constant OP_IADD : opcode_t := "011000";
  constant OP_PUSH : opcode_t := "100000";
  constant OP_POP  : opcode_t := "100001";
  constant OP_LDM  : opcode_t := "100010";
  constant OP_LDD  : opcode_t := "100011";
  constant OP_STD  : opcode_t := "100100";
  constant OP_JMP  : opcode_t := "110000";
  constant OP_JZ   : opcode_t := "110001";
  constant OP_JN   : opcode_t := "110010";
  constant OP_JC   : opcode_t := "110011";
  constant OP_CALL : opcode_t := "110100";
  constant OP_RET  : opcode_t := "110101";
  constant OP_RTI  : opcode_t := "110110";
  constant OP_INT  : opcode_t := "110111";

  -- -------------------------------------------------------------------------
  -- ALU operation codes
  -- -------------------------------------------------------------------------
  constant ALU_PASSA : aluop_t := "0000";  -- y = a
  constant ALU_NOT   : aluop_t := "0001";  -- y = not a
  constant ALU_INC   : aluop_t := "0010";  -- y = a + 1
  constant ALU_ADD   : aluop_t := "0011";  -- y = a + b
  constant ALU_SUB   : aluop_t := "0100";  -- y = a - b
  constant ALU_AND   : aluop_t := "0101";  -- y = a and b
  constant ALU_SHL   : aluop_t := "0110";  -- y = a << shamt
  constant ALU_SHR   : aluop_t := "0111";  -- y = a >> shamt (logical)
  constant ALU_PASSB : aluop_t := "1000";  -- y = b
  constant ALU_SETC  : aluop_t := "1001";  -- y = a, c = 1

  -- Jcc condition codes (= opcode bits [1:0])
  constant COND_Z : std_logic_vector(1 downto 0) := "01";
  constant COND_N : std_logic_vector(1 downto 0) := "10";
  constant COND_C : std_logic_vector(1 downto 0) := "11";

  -- CCR bit positions
  constant CCR_Z : natural := 0;
  constant CCR_N : natural := 1;
  constant CCR_C : natural := 2;

  -- -------------------------------------------------------------------------
  -- Decoded control record. Every pipeline register carries one of these.
  -- A bubble is CTRL_NOP (all zeros).
  -- -------------------------------------------------------------------------
  type ctrl_t is record
    valid    : std_logic;                     -- a real instruction / micro-op
    alu_op   : aluop_t;
    b_imm    : std_logic;                     -- ALU B input = sign-ext imm
    use_a    : std_logic;                     -- reads register via port 1
    use_b    : std_logic;                     -- reads register via port 2
    ra1_dst  : std_logic;                     -- port-1 address = Rdst
    ra2_src1 : std_logic;                     -- port-2 address = Rsrc1
    we1      : std_logic;                     -- RF write port 1
    we2      : std_logic;                     -- RF write port 2
    swap     : std_logic;                     -- RF swap of write addresses
    zn_we    : std_logic;                     -- update Z and N
    c_we     : std_logic;                     -- update C
    in_sel   : std_logic;                     -- result = IN.PORT
    out_we   : std_logic;                     -- OUT.PORT <- result in W
    mem_rd   : std_logic;                     -- RAM port-B read
    mem_wr   : std_logic;                     -- RAM port-B write
    addr_sp  : std_logic;                     -- RAM address from SP unit
    sp_dec   : std_logic;                     -- push: SP <- SP-1, addr=SP-1
    sp_inc   : std_logic;                     -- pop : addr=SP, SP <- SP+1
    st_link  : std_logic;                     -- store data = link (PC+1/PC)
    base_b   : std_logic;                     -- LDD/STD base = operand B
    is_jmp   : std_logic;
    is_call  : std_logic;
    is_jcc   : std_logic;
    is_int   : std_logic;                     -- software INT
    is_hw    : std_logic;                     -- injected hardware-IRQ micro-op
    is_ret   : std_logic;
    is_rti   : std_logic;
    is_hlt   : std_logic;
    cond     : std_logic_vector(1 downto 0);  -- Jcc condition
  end record;

  constant CTRL_NOP : ctrl_t := (
    valid    => '0',
    alu_op   => ALU_PASSA,
    b_imm    => '0',
    use_a    => '0',
    use_b    => '0',
    ra1_dst  => '0',
    ra2_src1 => '0',
    we1      => '0',
    we2      => '0',
    swap     => '0',
    zn_we    => '0',
    c_we     => '0',
    in_sel   => '0',
    out_we   => '0',
    mem_rd   => '0',
    mem_wr   => '0',
    addr_sp  => '0',
    sp_dec   => '0',
    sp_inc   => '0',
    st_link  => '0',
    base_b   => '0',
    is_jmp   => '0',
    is_call  => '0',
    is_jcc   => '0',
    is_int   => '0',
    is_hw    => '0',
    is_ret   => '0',
    is_rti   => '0',
    is_hlt   => '0',
    cond     => "00");

  -- -------------------------------------------------------------------------
  -- Helpers
  -- -------------------------------------------------------------------------
  function sext16(v : std_logic_vector(15 downto 0)) return word_t;
  function zext16(v : std_logic_vector(15 downto 0)) return word_t;

end package cpu_pkg;

package body cpu_pkg is

  function sext16(v : std_logic_vector(15 downto 0)) return word_t is
  begin
    return std_logic_vector(resize(signed(v), WIDTH));
  end function;

  function zext16(v : std_logic_vector(15 downto 0)) return word_t is
  begin
    return std_logic_vector(resize(unsigned(v), WIDTH));
  end function;

end package body cpu_pkg;
