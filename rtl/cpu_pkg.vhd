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
  subtype imm16_t  is std_logic_vector(15 downto 0);

  type reg_array_t is array (0 to NREGS-1) of word_t;
  type mem_t       is array (0 to MEMDEPTH-1) of word_t;

  constant WORD_ZERO  : word_t  := (others => '0');
  constant IMM16_ZERO : imm16_t := (others => '0');
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
    is_real_instruction           : std_logic;                            -- a real instruction / micro-op
    alu_operation                 : aluop_t;
    alu_b_uses_immediate          : std_logic;                            -- ALU B input = sign-ext imm
    reads_operand_a               : std_logic;                            -- reads register via port 1
    reads_operand_b               : std_logic;                            -- reads register via port 2
    read_port_1_uses_rdst         : std_logic;                            -- port-1 address = Rdst
    read_port_2_uses_rsrc1        : std_logic;                            -- port-2 address = Rsrc1
    write_port_1_enable           : std_logic;                            -- RF write port 1
    write_port_2_enable           : std_logic;                            -- RF write port 2
    swap_write_addresses          : std_logic;                            -- RF swap of write addresses
    update_zero_negative_flags    : std_logic;                            -- update Z and N
    update_carry_flag             : std_logic;                            -- update C
    result_from_in_port           : std_logic;                            -- result = IN.PORT
    write_out_port                : std_logic;                            -- OUT.PORT <- result in W
    memory_read                   : std_logic;                            -- RAM port-B read
    memory_write                  : std_logic;                            -- RAM port-B write
    memory_address_from_sp        : std_logic;                            -- RAM address from SP unit
    stack_pointer_decrement       : std_logic;                            -- push: SP <- SP-1, addr=SP-1
    stack_pointer_increment       : std_logic;                            -- pop : addr=SP, SP <- SP+1
    store_link_address            : std_logic;                            -- store data = link (PC+1/PC)
    base_address_is_operand_b     : std_logic;                            -- LDD/STD base = operand B
    is_jump                       : std_logic;
    is_call                       : std_logic;
    is_conditional_jump           : std_logic;
    is_software_interrupt         : std_logic;                            -- software INT
    is_hardware_interrupt         : std_logic;                            -- injected hardware-IRQ micro-op
    is_return                     : std_logic;
    is_return_from_interrupt      : std_logic;
    is_halt                       : std_logic;
    jump_condition                : std_logic_vector(1 downto 0);         -- Jcc condition
  end record;

  constant CTRL_NOP : ctrl_t := (
    is_real_instruction           => '0',
    alu_operation                 => ALU_PASSA,
    alu_b_uses_immediate          => '0',
    reads_operand_a               => '0',
    reads_operand_b               => '0',
    read_port_1_uses_rdst         => '0',
    read_port_2_uses_rsrc1        => '0',
    write_port_1_enable           => '0',
    write_port_2_enable           => '0',
    swap_write_addresses          => '0',
    update_zero_negative_flags    => '0',
    update_carry_flag             => '0',
    result_from_in_port           => '0',
    write_out_port                => '0',
    memory_read                   => '0',
    memory_write                  => '0',
    memory_address_from_sp        => '0',
    stack_pointer_decrement       => '0',
    stack_pointer_increment       => '0',
    store_link_address            => '0',
    base_address_is_operand_b     => '0',
    is_jump                       => '0',
    is_call                       => '0',
    is_conditional_jump           => '0',
    is_software_interrupt         => '0',
    is_hardware_interrupt         => '0',
    is_return                     => '0',
    is_return_from_interrupt      => '0',
    is_halt                       => '0',
    jump_condition                => "00");

  -- -------------------------------------------------------------------------
  -- Inter-stage pipeline register bundles
  -- -------------------------------------------------------------------------
  type if_d_t is record
    is_valid              : std_logic;
    is_interrupt_vector   : std_logic;
    program_counter       : word_t;
    next_program_counter  : word_t;
  end record;

  constant IF_D_NOP : if_d_t := (
    is_valid              => '0',
    is_interrupt_vector   => '0',
    program_counter       => WORD_ZERO,
    next_program_counter  => WORD_ZERO);

  type d_x1_t is record
    control               : ctrl_t;
    operand_a             : word_t;
    operand_b             : word_t;
    read_addr_1           : raddr_t;
    read_addr_2           : raddr_t;
    write_addr_1          : raddr_t;
    write_addr_2          : raddr_t;
    immediate             : imm16_t;
    immediate_unsigned    : std_logic;
    link_address          : word_t;
  end record;

  constant D_X1_NOP : d_x1_t := (
    control               => CTRL_NOP,
    operand_a             => WORD_ZERO,
    operand_b             => WORD_ZERO,
    read_addr_1           => "000",
    read_addr_2           => "000",
    write_addr_1          => "000",
    write_addr_2          => "000",
    immediate             => IMM16_ZERO,
    immediate_unsigned    => '0',
    link_address          => WORD_ZERO);

  type x1_x2_t is record
    control               : ctrl_t;
    result_1              : word_t;
    result_2              : word_t;
    operand_a             : word_t;
    operand_b             : word_t;
    immediate             : imm16_t;
    write_addr_1          : raddr_t;
    write_addr_2          : raddr_t;
    link_address          : word_t;
  end record;

  constant X1_X2_NOP : x1_x2_t := (
    control               => CTRL_NOP,
    result_1              => WORD_ZERO,
    result_2              => WORD_ZERO,
    operand_a             => WORD_ZERO,
    operand_b             => WORD_ZERO,
    immediate             => IMM16_ZERO,
    write_addr_1          => "000",
    write_addr_2          => "000",
    link_address          => WORD_ZERO);

  type x2_m_t is record
    control               : ctrl_t;
    result_1              : word_t;
    result_2              : word_t;
    write_addr_1          : raddr_t;
    write_addr_2          : raddr_t;
  end record;

  constant X2_M_NOP : x2_m_t := (
    control               => CTRL_NOP,
    result_1              => WORD_ZERO,
    result_2              => WORD_ZERO,
    write_addr_1          => "000",
    write_addr_2          => "000");

  type m_w_t is record
    control               : ctrl_t;
    result_1              : word_t;
    result_2              : word_t;
    write_addr_1          : raddr_t;
    write_addr_2          : raddr_t;
  end record;

  constant M_W_NOP : m_w_t := (
    control               => CTRL_NOP,
    result_1              => WORD_ZERO,
    result_2              => WORD_ZERO,
    write_addr_1          => "000",
    write_addr_2          => "000");

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
