-------------------------------------------------------------------------------
-- tb_forward_unit.vhd -- directed self-checking testbench for forward_unit
-- No hazard, each single source (X2, M, W), priority when several stages
-- write the same register (youngest wins), M-stage load data (RAM q),
-- SWAP effective destinations, port-2 priority, use_a/use_b gating,
-- and register 0 / register 7 boundaries.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cpu_pkg.all;
use work.tb_pkg.all;

entity tb_forward_unit is
end entity tb_forward_unit;

architecture sim of tb_forward_unit is
  signal ra1, ra2     : raddr_t := "000";
  signal use_a, use_b : std_logic := '0';
  signal rf_a         : word_t := x"AAAA0000";
  signal rf_b         : word_t := x"BBBB0000";
  signal x2_we1 : std_logic := '0';
  signal x2_wa1       : raddr_t := "000";
  signal x2_res1      : word_t := x"22220001";
  signal m_we1, m_mem_rd : std_logic := '0';
  signal m_wa1        : raddr_t := "000";
  signal m_res1       : word_t := x"33330001";
  signal m_q          : word_t := x"3333DA7A";
  signal w_we1 : std_logic := '0';
  signal w_wa1        : raddr_t := "000";
  signal w_res1       : word_t := x"44440001";
  signal fa, fb       : word_t;
  signal sel_a, sel_b : std_logic_vector(1 downto 0);

  function r(i : natural) return raddr_t is
  begin
    return std_logic_vector(to_unsigned(i, 3));
  end function;
begin
  dut : entity work.forward_unit
    port map (
      ra1 => ra1, ra2 => ra2, use_a => use_a, use_b => use_b,
      rf_a => rf_a, rf_b => rf_b,
      x2_we1 => x2_we1,       x2_wa1 => x2_wa1, x2_res1 => x2_res1,
      m_we1 => m_we1, m_wa1 => m_wa1,
      m_mem_rd => m_mem_rd, m_res1 => m_res1,
      m_q => m_q,
      w_we1 => w_we1, w_wa1 => w_wa1,
      w_res1 => w_res1,
      fa => fa, fb => fb, sel_a => sel_a, sel_b => sel_b);

  stim : process
    variable errs : natural := 0;
    procedure clear is
    begin
      x2_we1 <= '0';
      m_we1  <= '0'; m_mem_rd <= '0';
      w_we1  <= '0';
    end procedure;
  begin
    use_a <= '1'; use_b <= '1';
    ra1 <= r(1); ra2 <= r(2);

    -- no producer writes anything
    wait for 1 ns;
    check_eq(fa, x"AAAA0000", "no hazard A", errs);
    check_eq(fb, x"BBBB0000", "no hazard B", errs);
    check_eq(sel_a, "00", "sel_a none", errs);

    -- single source X2 (distance 1)
    x2_we1 <= '1'; x2_wa1 <= r(1);
    wait for 1 ns;
    check_eq(fa, x"22220001", "X2 -> A", errs);
    check_eq(sel_a, "01", "sel_a X2", errs);
    check_eq(fb, x"BBBB0000", "X2 does not hit B", errs);
    clear;

    -- single source M (distance 2), ALU result
    m_we1 <= '1'; m_wa1 <= r(2);
    wait for 1 ns;
    check_eq(fb, x"33330001", "M -> B", errs);
    check_eq(sel_b, "10", "sel_b M", errs);
    -- M source is a load: data comes from RAM q
    m_mem_rd <= '1';
    wait for 1 ns;
    check_eq(fb, x"3333DA7A", "M load q -> B", errs);
    clear;

    -- single source W (distance 3)
    w_we1 <= '1'; w_wa1 <= r(1);
    wait for 1 ns;
    check_eq(fa, x"44440001", "W -> A", errs);
    check_eq(sel_a, "11", "sel_a W", errs);
    clear;

    -- priority: all three write R1 -> X2 wins, then M, then W
    x2_we1 <= '1'; x2_wa1 <= r(1);
    m_we1  <= '1'; m_wa1  <= r(1);
    w_we1  <= '1'; w_wa1  <= r(1);
    wait for 1 ns;
    check_eq(fa, x"22220001", "prio X2", errs);
    x2_we1 <= '0';
    wait for 1 ns;
    check_eq(fa, x"33330001", "prio M over W", errs);
    m_we1 <= '0';
    wait for 1 ns;
    check_eq(fa, x"44440001", "prio W", errs);
    clear;

    -- use_a / use_b = '0' disables forwarding
    x2_we1 <= '1'; x2_wa1 <= r(1); use_a <= '0';
    wait for 1 ns;
    check_eq(fa, x"AAAA0000", "use_a=0 no forward", errs);
    check_eq(sel_a, "00", "use_a=0 sel", errs);
    use_a <= '1';
    clear;

    -- write enable low with matching address: no forward
    x2_wa1 <= r(1); m_wa1 <= r(1); w_wa1 <= r(1);
    wait for 1 ns;
    check_eq(fa, x"AAAA0000", "we=0 no forward", errs);

    -- register boundaries R0 and R7
    ra1 <= r(0); ra2 <= r(7);
    x2_we1 <= '1'; x2_wa1 <= r(0);
    w_we1  <= '1'; w_wa1  <= r(7);
    wait for 1 ns;
    check_eq(fa, x"22220001", "R0 forward", errs);
    check_eq(fb, x"44440001", "R7 forward", errs);
    clear;

    finish_tb("tb_forward_unit", errs);
    wait;
  end process;
end architecture sim;
