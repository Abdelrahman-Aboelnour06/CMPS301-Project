-------------------------------------------------------------------------------
-- tb_m_w.vhd -- directed self-checking testbench for m_w.vhd
-- Reset, capture of every field, hold (en = 0), flush -> bubble, flush
-- priority over hold, boundary data values.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.cpu_pkg.all;
use work.tb_pkg.all;

entity tb_m_w is
end entity tb_m_w;

architecture sim of tb_m_w is
  signal clk, reset : std_logic := '1';
  signal en, flush  : std_logic := '0';
  signal d_in       : m_w_t := M_W_NOP;
  signal d_out      : m_w_t;
  signal c_swap     : ctrl_t;
begin
  clk <= not clk after 5 ns;

  dut : entity work.m_w
    port map (clk => clk, reset => reset, en => en, flush => flush,
              d_in => d_in, d_out => d_out);

  -- a SWAP control word (both write ports)
  process
    variable c : ctrl_t;
  begin
    c := CTRL_NOP;
    c.is_real_instruction := '1';
    c.reads_operand_a := '1';
    c.reads_operand_b := '1';
    c.read_port_1_uses_rdst := '1';
    c.read_port_2_uses_rsrc1 := '1';
    c.write_port_1_enable := '1';
    c.write_port_1_enable := '1';
    c.write_port_1_enable := '1';
    c_swap <= c;
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
    d_in.control <= c_swap; d_in.result_1 <= x"80000000";
    d_in.write_addr_1 <= "000";
    tick;
    check(d_out.control = CTRL_NOP, "reset bubble", errs);
    reset <= '0'; tick;
    check(d_out.control = c_swap, "capture ctrl", errs);
    check_eq(d_out.result_1, x"80000000", "res1 min", errs);
    check_eq(d_out.write_addr_1, "000", "wa1 R0", errs);

    en <= '0'; d_in.result_1 <= x"00000000"; d_in.control <= CTRL_NOP; tick;
    check(d_out.control = c_swap, "hold ctrl", errs);
    check_eq(d_out.result_1, x"80000000", "hold res1", errs);

    flush <= '1'; tick;
    check(d_out.control = CTRL_NOP, "flush beats hold", errs);

    flush <= '0'; en <= '1'; d_in.control <= c_swap; tick;
    check(d_out.control = c_swap, "resume", errs);
    check_eq(d_out.result_1, x"00000000", "zero res1", errs);

    reset <= '1'; tick;
    check(d_out.control = CTRL_NOP, "reset again", errs);
    finish_tb("tb_m_w", errs);
    wait;
  end process;
end architecture sim;
