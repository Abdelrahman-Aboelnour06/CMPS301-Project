-------------------------------------------------------------------------------
-- sp_unit.vhd -- 32-bit stack pointer (X2).
--   reset : SP <- 4095
--   dec   : push  : addr = SP-1 ; SP <- SP-1   (pre-decrement)
--   inc   : pop   : addr = SP   ; SP <- SP+1   (post-increment)
--   dec has priority if both are asserted (never happens with valid decode).
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cpu_pkg.all;

entity sp_unit is
  port (
    clk   : in  std_logic;
    reset : in  std_logic;
    dec   : in  std_logic;
    inc   : in  std_logic;
    sp    : out word_t;
    addr  : out word_t
  );
end entity sp_unit;

architecture rtl of sp_unit is
  signal sp_r  : word_t := SP_RESET;
  signal sp_m1 : word_t;
  signal sp_p1 : word_t;
begin
  sp_m1 <= std_logic_vector(unsigned(sp_r) - 1);
  sp_p1 <= std_logic_vector(unsigned(sp_r) + 1);

  process (clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        sp_r <= SP_RESET;
      elsif dec = '1' then
        sp_r <= sp_m1;
      elsif inc = '1' then
        sp_r <= sp_p1;
      end if;
    end if;
  end process;

  sp   <= sp_r;
  addr <= sp_m1 when dec = '1' else sp_r;
end architecture rtl;
