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
  signal x2_we1, x2_we2, x2_swap : std_logic := '0';
  signal x2_wa1, x2_wa2 : raddr_t := "000";
  signal x2_res1      : word_t := x"22220001";
  signal x2_res2      : word_t := x"22220002";
  signal m_we1, m_we2, m_swap, m_mem_rd : std_logic := '0';
  signal m_wa1, m_wa2 : raddr_t := "000";
  signal m_res1       : word_t := x"33330001";
  signal m_res2       : word_t := x"33330002";
  signal m_q          : word_t := x"3333DA7A";
  signal w_we1, w_we2, w_swap : std_logic := '0';
  signal w_wa1, w_wa2 : raddr_t := "000";
  signal w_res1       : word_t := x"44440001";
  signal w_res2       : word_t := x"44440002";
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
      x2_we1 => x2_we1, x2_we2 => x2_we2, x2_swap => x2_swap,
      x2_wa1 => x2_wa1, x2_wa2 => x2_wa2, x2_res1 => x2_res1, x2_res2 => x2_res2,
      m_we1 => m_we1, m_we2 => m_we2, m_swap => m_swap, m_wa1 => m_wa1,
      m_wa2 => m_wa2, m_mem_rd => m_mem_rd, m_res1 => m_res1, m_res2 => m_res2,
      m_q => m_q,
      w_we1 => w_we1, w_we2 => w_we2, w_swap => w_swap, w_wa1 => w_wa1,
      w_wa2 => w_wa2, w_res1 => w_res1, w_res2 => w_res2,
      fa => fa, fb => fb, sel_a => sel_a, sel_b => sel_b);

  stim : process
    variable errs : natural := 0;
    procedure clear is
    begin
      x2_we1 <= '0'; x2_we2 <= '0'; x2_swap <= '0';
      m_we1  <= '0'; m_we2  <= '0'; m_swap  <= '0'; m_mem_rd <= '0';
      w_we1  <= '0'; w_we2  <= '0'; w_swap  <= '0';
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

    -- SWAP in X2: wa1 = R1 (Rdst), wa2 = R2 (Rsrc), swap = '1'
    --   effective: R2 <- res1, R1 <- res2
    x2_we1 <= '1'; x2_we2 <= '1'; x2_swap <= '1';
    x2_wa1 <= r(1); x2_wa2 <= r(2);
    wait for 1 ns;
    check_eq(fa, x"22220002", "swap: R1 gets res2", errs);
    check_eq(fb, x"22220001", "swap: R2 gets res1", errs);
    -- same without swap
    x2_swap <= '0';
    wait for 1 ns;
    check_eq(fa, x"22220001", "no swap: R1 gets res1", errs);
    check_eq(fb, x"22220002", "no swap: R2 gets res2", errs);
    clear;

    -- SWAP Rx,Rx in M: both ports hit -> port 2 wins (same value in HW)
    m_we1 <= '1'; m_we2 <= '1'; m_swap <= '1'; m_wa1 <= r(1); m_wa2 <= r(1);
    wait for 1 ns;
    check_eq(fa, x"33330002", "same address: port 2 priority", errs);
    clear;

    -- SWAP in W hitting operand B
    w_we1 <= '1'; w_we2 <= '1'; w_swap <= '1'; w_wa1 <= r(2); w_wa2 <= r(5);
    wait for 1 ns;
    check_eq(fb, x"44440002", "W swap -> B", errs);
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
    w_we2  <= '1'; w_wa2  <= r(7);
    wait for 1 ns;
    check_eq(fa, x"22220001", "R0 forward", errs);
    check_eq(fb, x"44440002", "R7 forward via port 2", errs);
    clear;

    finish_tb("tb_forward_unit", errs);
    wait;
  end process;
end architecture sim;
