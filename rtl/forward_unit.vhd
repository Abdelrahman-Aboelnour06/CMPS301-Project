-------------------------------------------------------------------------------
-- forward_unit.vhd -- 3-way forwarding muxes for the two X1 operands.
-- Sources, highest priority first (youngest producer wins):
--   "01" X1/X2 register (instruction now in X2): res1 / res2
--   "10" X2/M  register (instruction now in M) : res1 (or RAM q_b if it is
--                                                a load) / res2
--   "11" M/W   register (instruction now in W) : res1 / res2
--   "00" no match: the value read from the register file in D.
-- Each producer can write two registers (wa1 <- res1, wa2 <- res2).
-- Within one producer, port 2 has priority (identical to the register file).
-- A load in X2 never needs forwarding (the hazard unit stalls instead).
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.cpu_pkg.all;

entity forward_unit is
  port (
    -- consumer (instruction in X1)
    ra1      : in  raddr_t;
    ra2      : in  raddr_t;
    use_a    : in  std_logic;
    use_b    : in  std_logic;
    rf_a     : in  word_t;
    rf_b     : in  word_t;
    -- producer in X2 (X1/X2 register)
    x2_we1   : in  std_logic;
    x2_wa1   : in  raddr_t;
    x2_res1  : in  word_t;
    -- producer in M (X2/M register)
    m_we1    : in  std_logic;
    m_wa1    : in  raddr_t;
    m_mem_rd : in  std_logic;
    m_res1   : in  word_t;
    m_q      : in  word_t;      -- RAM port-B data (valid during M)
    -- producer in W (M/W register)
    w_we1    : in  std_logic;
    w_wa1    : in  raddr_t;
    w_res1   : in  word_t;
    -- outputs
    fa       : out word_t;
    fb       : out word_t;
    sel_a    : out std_logic_vector(1 downto 0);
    sel_b    : out std_logic_vector(1 downto 0)
  );
end entity forward_unit;

architecture rtl of forward_unit is

  -- Does a producer write register r?  Returns '1' and the data.
  procedure lookup (
    r                  : in  raddr_t;
    we1                : in  std_logic;
    wa1                : in  raddr_t;
    d1                 : in  word_t;
    hit                : out std_logic;
    data               : out word_t) is
  begin
    if we1 = '1' and wa1 = r then
      hit := '1'; data := d1;
    else
      hit := '0'; data := d1;
    end if;
  end procedure;

  signal m_res1_eff : word_t;

begin

  m_res1_eff <= m_q when m_mem_rd = '1' else m_res1;

  process (ra1, ra2, use_a, use_b, rf_a, rf_b,
           x2_we1, x2_wa1, x2_res1,
           m_we1, m_wa1, m_res1_eff,
           w_we1, w_wa1, w_res1)
    variable h2, hm, hw : std_logic;
    variable d2, dm, dw : word_t;
  begin
    -- operand A
    lookup(ra1, x2_we1, x2_wa1, x2_res1, h2, d2);
    lookup(ra1, m_we1,  m_wa1,  m_res1_eff, hm, dm);
    lookup(ra1, w_we1,  w_wa1,  w_res1, hw, dw);
    if use_a = '1' and h2 = '1' then
      fa <= d2; sel_a <= "01";
    elsif use_a = '1' and hm = '1' then
      fa <= dm; sel_a <= "10";
    elsif use_a = '1' and hw = '1' then
      fa <= dw; sel_a <= "11";
    else
      fa <= rf_a; sel_a <= "00";
    end if;

    -- operand B
    lookup(ra2, x2_we1, x2_wa1, x2_res1, h2, d2);
    lookup(ra2, m_we1,  m_wa1,  m_res1_eff, hm, dm);
    lookup(ra2, w_we1,  w_wa1,  w_res1, hw, dw);
    if use_b = '1' and h2 = '1' then
      fb <= d2; sel_b <= "01";
    elsif use_b = '1' and hm = '1' then
      fb <= dm; sel_b <= "10";
    elsif use_b = '1' and hw = '1' then
      fb <= dw; sel_b <= "11";
    else
      fb <= rf_b; sel_b <= "00";
    end if;
  end process;

end architecture rtl;
