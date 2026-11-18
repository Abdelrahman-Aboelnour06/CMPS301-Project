-------------------------------------------------------------------------------
-- branch_check.vhd -- X2 resolution of JZ / JN / JC.
-- Every Jcc is statically predicted TAKEN and redirected in D. Here the
-- condition is evaluated against the CCR:
--   * if NOT taken: mispredict = '1' flushes F/D/X1 and reloads saved PC+1.
--   * if TAKEN    : clr_mask clears the tested flag (spec semantics).
--   cond "01" -> Z, "10" -> N, "11" -> C, "00" -> never (not a Jcc).
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.cpu_pkg.all;

entity branch_check is
  port (
    is_jcc     : in  std_logic;
    cond       : in  std_logic_vector(1 downto 0);
    ccr        : in  std_logic_vector(3 downto 0);
    taken      : out std_logic;
    mispredict : out std_logic;
    clr_mask   : out std_logic_vector(2 downto 0)
  );
end entity branch_check;

architecture rtl of branch_check is
  signal t : std_logic;
begin
  t <= ccr(CCR_Z) when cond = COND_Z else
       ccr(CCR_N) when cond = COND_N else
       ccr(CCR_C) when cond = COND_C else
       '0';

  taken      <= is_jcc and t;
  mispredict <= is_jcc and not t;

  clr_mask <= "001" when (is_jcc = '1' and t = '1' and cond = COND_Z) else
              "010" when (is_jcc = '1' and t = '1' and cond = COND_N) else
              "100" when (is_jcc = '1' and t = '1' and cond = COND_C) else
              "000";
end architecture rtl;
