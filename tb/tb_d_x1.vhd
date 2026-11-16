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
  signal ctrl_in, ctrl_out : ctrl_t := CTRL_NOP;
  signal a_in, b_in, imm_in, link_in     : word_t := (others => '0');
  signal a_out, b_out, imm_out, link_out : word_t;
  signal ra1_in, ra2_in, wa1_in, wa2_in     : raddr_t := "000";
  signal ra1_out, ra2_out, wa1_out, wa2_out : raddr_t;
  signal c_add : ctrl_t;
begin
  clk <= not clk after 5 ns;

  dut : entity work.d_x1
    port map (clk => clk, reset => reset, en => en, flush => flush,
              ctrl_in => ctrl_in, a_in => a_in, b_in => b_in,
              ra1_in => ra1_in, ra2_in => ra2_in, wa1_in => wa1_in,
              wa2_in => wa2_in, imm_in => imm_in, link_in => link_in,
              ctrl_out => ctrl_out, a_out => a_out, b_out => b_out,
              ra1_out => ra1_out, ra2_out => ra2_out, wa1_out => wa1_out,
              wa2_out => wa2_out, imm_out => imm_out, link_out => link_out);

  -- an ADD control word
  process
    variable c : ctrl_t;
  begin
    c := CTRL_NOP;
    c.valid := '1'; c.alu_op := ALU_ADD; c.use_a := '1'; c.use_b := '1';
    c.we1 := '1'; c.zn_we := '1'; c.c_we := '1';
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
    ctrl_in <= c_add; a_in <= x"11111111"; b_in <= x"22222222";
    ra1_in <= "001"; ra2_in <= "010"; wa1_in <= "011"; wa2_in <= "100";
    imm_in <= x"FFFF8000"; link_in <= x"00000ABC";
    tick;
    check(ctrl_out = CTRL_NOP, "reset -> bubble", errs);
    check_eq(a_out, x"00000000", "reset a", errs);

    reset <= '0'; tick;
    check(ctrl_out = c_add, "capture ctrl", errs);
    check_eq(a_out, x"11111111", "capture a", errs);
    check_eq(b_out, x"22222222", "capture b", errs);
    check_eq(ra1_out, "001", "capture ra1", errs);
    check_eq(ra2_out, "010", "capture ra2", errs);
    check_eq(wa1_out, "011", "capture wa1", errs);
    check_eq(wa2_out, "100", "capture wa2", errs);
    check_eq(imm_out, x"FFFF8000", "capture imm (min)", errs);
    check_eq(link_out, x"00000ABC", "capture link", errs);

    -- hold
    en <= '0'; a_in <= x"FFFFFFFF"; ctrl_in <= CTRL_NOP; tick;
    check(ctrl_out = c_add, "hold ctrl", errs);
    check_eq(a_out, x"11111111", "hold a", errs);

    -- flush while en = 0: bubble inserted anyway
    flush <= '1'; tick;
    check(ctrl_out = CTRL_NOP, "flush beats hold", errs);
    check_eq(a_out, x"FFFFFFFF", "data captured on flush", errs);

    -- flush with en = 1 and a valid control word
    en <= '1'; ctrl_in <= c_add; tick;
    check(ctrl_out = CTRL_NOP, "flush -> bubble", errs);
    check_sl(ctrl_out.we1, '0', "bubble does not write", errs);

    flush <= '0'; tick;
    check(ctrl_out = c_add, "normal again", errs);
    check_eq(a_out, x"FFFFFFFF", "max a", errs);

    reset <= '1'; tick;
    check(ctrl_out = CTRL_NOP, "reset again", errs);
    finish_tb("tb_d_x1", errs);
    wait;
  end process;
end architecture sim;
