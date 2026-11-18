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
      c.is_real_instruction := '1';
      case opcode is
        when OP_NOP =>
          null;
        when OP_NOT =>
          c.alu_operation := ALU_NOT;
          c.reads_operand_a := '1';
          c.read_port_1_uses_rdst := '1';
          c.write_port_1_enable := '1';
          c.update_zero_negative_flags := '1';
        when OP_INC =>
          c.alu_operation := ALU_INC;
          c.reads_operand_a := '1';
          c.read_port_1_uses_rdst := '1';
          c.write_port_1_enable := '1';
          c.update_zero_negative_flags := '1';
          c.update_carry_flag := '1';
        when OP_OUT =>
          c.alu_operation := ALU_PASSA;
          c.reads_operand_a := '1';
          c.write_out_port := '1';
        when OP_IN =>
          c.result_from_in_port := '1';
          c.write_port_1_enable := '1';
        when OP_SETC =>
          c.alu_operation := ALU_SETC;
          c.update_carry_flag := '1';
        when OP_HLT =>
          c.is_halt := '1';
        when OP_MOV =>
          c.alu_operation := ALU_PASSA;
          c.reads_operand_a := '1';
          c.write_port_1_enable := '1';
        when OP_SWAP =>
          c.alu_operation := ALU_PASSA;
          c.reads_operand_a := '1';
          c.reads_operand_b := '1';
          c.read_port_1_uses_rdst := '1';
          c.read_port_2_uses_rsrc1 := '1';
          c.write_port_1_enable := '1';
          c.write_port_2_enable := '1';
          c.swap_write_addresses := '1';
        when OP_ADD =>
          c.alu_operation := ALU_ADD;
          c.reads_operand_a := '1';
          c.reads_operand_b := '1';
          c.write_port_1_enable := '1';
          c.update_zero_negative_flags := '1';
          c.update_carry_flag := '1';
        when OP_SUB =>
          c.alu_operation := ALU_SUB;
          c.reads_operand_a := '1';
          c.reads_operand_b := '1';
          c.write_port_1_enable := '1';
          c.update_zero_negative_flags := '1';
          c.update_carry_flag := '1';
        when OP_AND =>
          c.alu_operation := ALU_AND;
          c.reads_operand_a := '1';
          c.reads_operand_b := '1';
          c.write_port_1_enable := '1';
          c.update_zero_negative_flags := '1';
        when OP_CMP =>
          c.alu_operation := ALU_SUB;
          c.reads_operand_a := '1';
          c.reads_operand_b := '1';
          c.update_zero_negative_flags := '1';
          c.update_carry_flag := '1';
        when OP_SHR =>
          c.alu_operation := ALU_SHR;
          c.reads_operand_a := '1';
          c.read_port_1_uses_rdst := '1';
          c.write_port_1_enable := '1';
          c.update_zero_negative_flags := '1';
          c.update_carry_flag := '1';
        when OP_SHL =>
          c.alu_operation := ALU_SHL;
          c.reads_operand_a := '1';
          c.read_port_1_uses_rdst := '1';
          c.write_port_1_enable := '1';
          c.update_zero_negative_flags := '1';
          c.update_carry_flag := '1';
        when OP_IADD =>
          c.alu_operation := ALU_ADD;
          c.alu_b_uses_immediate := '1';
          c.reads_operand_a := '1';
          c.write_port_1_enable := '1';
          c.update_zero_negative_flags := '1';
          c.update_carry_flag := '1';
        when OP_PUSH =>
          c.reads_operand_a := '1';
          c.memory_write := '1';
          c.memory_address_from_sp := '1';
          c.stack_pointer_decrement := '1';
        when OP_POP =>
          c.memory_read := '1';
          c.memory_address_from_sp := '1';
          c.stack_pointer_increment := '1';
          c.write_port_1_enable := '1';
        when OP_LDM =>
          c.alu_operation := ALU_PASSB;
          c.alu_b_uses_immediate := '1';
          c.write_port_1_enable := '1';
        when OP_LDD =>
          c.reads_operand_a := '1';
          c.memory_read := '1';
          c.write_port_1_enable := '1';
        when OP_STD =>
          c.reads_operand_a := '1';
          c.reads_operand_b := '1';
          c.memory_write := '1';
          c.base_address_is_operand_b := '1';
        when OP_JMP =>
          c.is_jump := '1';
        when OP_JZ | OP_JN | OP_JC =>
          c.is_conditional_jump := '1';
          c.jump_condition := opcode(1 downto 0);
        when OP_CALL =>
          c.is_call := '1';
          c.memory_write := '1';
          c.memory_address_from_sp := '1';
          c.stack_pointer_decrement := '1';
          c.store_link_address := '1';
        when OP_RET =>
          c.is_return := '1';
          c.memory_read := '1';
          c.memory_address_from_sp := '1';
          c.stack_pointer_increment := '1';
        when OP_RTI =>
          c.is_return_from_interrupt := '1';
          c.memory_read := '1';
          c.memory_address_from_sp := '1';
          c.stack_pointer_increment := '1';
        when OP_INT =>
          c.is_software_interrupt := '1';
          c.memory_write := '1';
          c.memory_address_from_sp := '1';
          c.stack_pointer_decrement := '1';
          c.store_link_address := '1';
        when others =>
          null;                       -- undefined opcode: NOP
      end case;
    end if;
    raw <= c;
  end process;

  -- Hardware-interrupt micro-op: push PC of the displaced D instruction,
  -- redirect fetch to vector M[1], save CCR to shadow, set in_ISR (X2).
  hw <= (
         is_real_instruction           => '1',
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
         memory_write                  => '1',
         memory_address_from_sp        => '1',
         stack_pointer_decrement       => '1',
         stack_pointer_increment       => '0',
         store_link_address            => '1',
         base_address_is_operand_b     => '0',
         is_jump                       => '0',
         is_call                       => '0',
         is_conditional_jump           => '0',
         is_software_interrupt         => '0',
         is_hardware_interrupt         => '1',
         is_return                     => '0',
         is_return_from_interrupt      => '0',
         is_halt                       => '0',
         jump_condition                => "00");

  ctrl_raw <= raw;
  ctrl     <= hw when inject = '1' else raw;
end architecture rtl;
