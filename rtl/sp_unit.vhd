-------------------------------------------------------------------------------
-- sp_unit.vhd -- 32-bit stack pointer (X2), single shared adder.
--   reset : SP <- 4095
--   dec   : push uses addr = SP, then SP <- SP-1 (post-decrement).
--   inc   : pop uses addr = SP+1 and updates SP to SP+1 (pre-increment).
--   dec has priority if both are asserted.
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
  signal sp_r    : word_t := SP_RESET;
  signal sp_step : unsigned(WIDTH-1 downto 0);
  signal sp_next : word_t;
begin
  sp_step <= (others => '1') when dec = '1' else to_unsigned(1, WIDTH);
  sp_next <= std_logic_vector(unsigned(sp_r) + sp_step);

  process (clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        sp_r <= SP_RESET;
      elsif dec = '1' or inc = '1' then
        sp_r <= sp_next;
      end if;
    end if;
  end process;

  sp   <= sp_r;
  addr <= sp_next when inc = '1' and dec = '0' else sp_r;
end architecture rtl;
