-------------------------------------------------------------------------------
-- tb_d_x1.vhd -- directed self-checking testbench for d_x1.vhd
-- Reset to bubble, capture of every field, hold (en = 0), flush -> bubble
-- (load-use stall / mispredict), flush priority over hold, max values.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.cpu_pkg.all;
use work.tb_pkg.all;

entity tb_d_x1 is
end entity tb_d_x1;

architecture sim of tb_d_x1 is
  signal clk, reset : std_logic := '1';
  signal en, flush  : std_logic := '0';
  signal d_in       : d_x1_t := D_X1_NOP;
  signal d_out      : d_x1_t;
  signal c_add      : ctrl_t;
begin
  clk <= not clk after 5 ns;

  dut : entity work.d_x1
    port map (clk => clk, reset => reset, en => en, flush => flush,
              d_in => d_in, d_out => d_out);

  -- an ADD control word
  process
    variable c : ctrl_t;
  begin
    c := CTRL_NOP;
    c.is_real_instruction := '1';
    c.alu_operation := ALU_ADD;
    c.reads_operand_a := '1';
    c.reads_operand_b := '1';
    c.write_port_1_enable := '1';
    c.update_zero_negative_flags := '1';
    c.update_carry_flag := '1';
    c_add <= c;
    wait;
  end process;

  stim : process
    variable errs : natural := 0;
    procedure tick is
    begin
      wait until rising_edge(clk);
      wait for 1 ns;
    end procedure;
  begin
    en <= '1';
    wait for 1 ns;
    d_in.ctrl <= c_add; d_in.a <= x"11111111"; d_in.b <= x"22222222";
    d_in.ra1 <= "001"; d_in.ra2 <= "010"; d_in.wa1 <= "011"; d_in.wa2 <= "100";
    d_in.imm <= x"FFFF8000"; d_in.link <= x"00000ABC";
    tick;
    check(d_out.ctrl = CTRL_NOP, "reset -> bubble", errs);
    check_eq(d_out.a, x"00000000", "reset a", errs);

    reset <= '0'; tick;
    check(d_out.ctrl = c_add, "capture ctrl", errs);
    check_eq(d_out.a, x"11111111", "capture a", errs);
    check_eq(d_out.b, x"22222222", "capture b", errs);
    check_eq(d_out.ra1, "001", "capture ra1", errs);
    check_eq(d_out.ra2, "010", "capture ra2", errs);
    check_eq(d_out.wa1, "011", "capture wa1", errs);
    check_eq(d_out.wa2, "100", "capture wa2", errs);
    check_eq(d_out.imm, x"FFFF8000", "capture imm (min)", errs);
    check_eq(d_out.link, x"00000ABC", "capture link", errs);

    -- hold
    en <= '0'; d_in.a <= x"FFFFFFFF"; d_in.ctrl <= CTRL_NOP; tick;
    check(d_out.ctrl = c_add, "hold ctrl", errs);
    check_eq(d_out.a, x"11111111", "hold a", errs);

    -- flush while en = 0: bubble inserted anyway
    flush <= '1'; tick;
    check(d_out.ctrl = CTRL_NOP, "flush beats hold", errs);
    check_eq(d_out.a, x"FFFFFFFF", "data captured on flush", errs);

    -- flush with en = 1 and a valid control word
    en <= '1'; d_in.ctrl <= c_add; tick;
    check(d_out.ctrl = CTRL_NOP, "flush -> bubble", errs);
    check_sl(d_out.ctrl.write_port_1_enable, '0', "bubble does not write", errs);

    flush <= '0'; tick;
    check(d_out.ctrl = c_add, "normal again", errs);
    check_eq(d_out.a, x"FFFFFFFF", "max a", errs);

    reset <= '1'; tick;
    check(d_out.ctrl = CTRL_NOP, "reset again", errs);
    finish_tb("tb_d_x1", errs);
    wait;
  end process;
end architecture sim;
