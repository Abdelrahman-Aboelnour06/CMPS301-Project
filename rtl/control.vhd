-------------------------------------------------------------------------------
-- control.vhd -- opcode -> decoded control record.
--   ctrl_raw : decode of the fetched instruction (bubble if valid = '0').
--   ctrl     : ctrl_raw, or the hardware-interrupt micro-op when inject='1'.
-- Register-field usage (fixed by this design):
--   port-1 address = Rdst  for NOT, INC, SHR, SHL, SWAP; Rsrc1 otherwise
--   port-2 address = Rsrc1 for SWAP;                     Rsrc2 otherwise
--   OUT/MOV/IADD/PUSH/LDD use Rsrc1; STD data = Rsrc1, base = Rsrc2.
-- Undefined opcodes decode as NOP.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.cpu_pkg.all;

entity control is
  port (
    opcode   : in  opcode_t;
    valid    : in  std_logic;
    inject   : in  std_logic;
    ctrl_raw : out ctrl_t;
    ctrl     : out ctrl_t
  );
end entity control;

architecture rtl of control is
  signal raw : ctrl_t;
  signal hw  : ctrl_t;
begin
  process (opcode, valid)
    variable c : ctrl_t;
  begin
    c := CTRL_NOP;
    if valid = '1' then
      c.valid := '1';
      case opcode is
        when OP_NOP =>
          null;
        when OP_NOT =>
          c.alu_op := ALU_NOT;  c.use_a := '1'; c.ra1_dst := '1';
          c.we1 := '1'; c.zn_we := '1';
        when OP_INC =>
          c.alu_op := ALU_INC;  c.use_a := '1'; c.ra1_dst := '1';
          c.we1 := '1'; c.zn_we := '1'; c.c_we := '1';
        when OP_OUT =>
          c.alu_op := ALU_PASSA; c.use_a := '1'; c.out_we := '1';
        when OP_IN =>
          c.in_sel := '1'; c.we1 := '1';
        when OP_SETC =>
          c.alu_op := ALU_SETC; c.c_we := '1';
        when OP_HLT =>
          c.is_hlt := '1';
        when OP_MOV =>
          c.alu_op := ALU_PASSA; c.use_a := '1'; c.we1 := '1';
        when OP_SWAP =>
          c.alu_op := ALU_PASSA; c.use_a := '1'; c.use_b := '1';
          c.ra1_dst := '1'; c.ra2_src1 := '1';
          c.we1 := '1'; c.we2 := '1'; c.swap := '1';
        when OP_ADD =>
          c.alu_op := ALU_ADD; c.use_a := '1'; c.use_b := '1';
          c.we1 := '1'; c.zn_we := '1'; c.c_we := '1';
        when OP_SUB =>
          c.alu_op := ALU_SUB; c.use_a := '1'; c.use_b := '1';
          c.we1 := '1'; c.zn_we := '1'; c.c_we := '1';
        when OP_AND =>
          c.alu_op := ALU_AND; c.use_a := '1'; c.use_b := '1';
          c.we1 := '1'; c.zn_we := '1';
        when OP_CMP =>
          c.alu_op := ALU_SUB; c.use_a := '1'; c.use_b := '1';
          c.zn_we := '1'; c.c_we := '1';
        when OP_SHR =>
          c.alu_op := ALU_SHR; c.use_a := '1'; c.ra1_dst := '1';
          c.we1 := '1'; c.zn_we := '1'; c.c_we := '1';
        when OP_SHL =>
          c.alu_op := ALU_SHL; c.use_a := '1'; c.ra1_dst := '1';
          c.we1 := '1'; c.zn_we := '1'; c.c_we := '1';
        when OP_IADD =>
          c.alu_op := ALU_ADD; c.b_imm := '1'; c.use_a := '1';
          c.we1 := '1'; c.zn_we := '1'; c.c_we := '1';
        when OP_PUSH =>
          c.use_a := '1'; c.mem_wr := '1'; c.addr_sp := '1'; c.sp_dec := '1';
        when OP_POP =>
          c.mem_rd := '1'; c.addr_sp := '1'; c.sp_inc := '1'; c.we1 := '1';
        when OP_LDM =>
          c.alu_op := ALU_PASSB; c.b_imm := '1'; c.we1 := '1';
        when OP_LDD =>
          c.use_a := '1'; c.mem_rd := '1'; c.we1 := '1';
        when OP_STD =>
          c.use_a := '1'; c.use_b := '1'; c.mem_wr := '1'; c.base_b := '1';
        when OP_JMP =>
          c.is_jmp := '1';
        when OP_JZ | OP_JN | OP_JC =>
          c.is_jcc := '1'; c.cond := opcode(1 downto 0);
        when OP_CALL =>
          c.is_call := '1'; c.mem_wr := '1'; c.addr_sp := '1';
          c.sp_dec := '1'; c.st_link := '1';
        when OP_RET =>
          c.is_ret := '1'; c.mem_rd := '1'; c.addr_sp := '1'; c.sp_inc := '1';
        when OP_RTI =>
          c.is_rti := '1'; c.mem_rd := '1'; c.addr_sp := '1'; c.sp_inc := '1';
        when OP_INT =>
          c.is_int := '1'; c.mem_wr := '1'; c.addr_sp := '1';
          c.sp_dec := '1'; c.st_link := '1';
        when others =>
          null;                       -- undefined opcode: NOP
      end case;
    end if;
    raw <= c;
  end process;

  -- Hardware-interrupt micro-op: push PC of the displaced D instruction,
  -- redirect fetch to vector M[1], save CCR to shadow, set in_ISR (X2).
  hw <= (valid    => '1',
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
         mem_wr   => '1',
         addr_sp  => '1',
         sp_dec   => '1',
         sp_inc   => '0',
         st_link  => '1',
         base_b   => '0',
         is_jmp   => '0',
         is_call  => '0',
         is_jcc   => '0',
         is_int   => '0',
         is_hw    => '1',
         is_ret   => '0',
         is_rti   => '0',
         is_hlt   => '0',
         cond     => "00");

  ctrl_raw <= raw;
  ctrl     <= hw when inject = '1' else raw;
end architecture rtl;
