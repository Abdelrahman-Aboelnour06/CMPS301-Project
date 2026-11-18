-------------------------------------------------------------------------------
-- d_x1.vhd -- D/X1 pipeline register.
-- flush (load-use bubble or mispredict) loads CTRL_NOP; it has priority over
-- en. Data fields are still captured on flush (they are don't-care under a
-- NOP control word).
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.cpu_pkg.all;

entity d_x1 is
  port (
    clk   : in  std_logic;
    reset : in  std_logic;
    en    : in  std_logic;
    flush : in  std_logic;
    d_in  : in  d_x1_t;
    d_out : out d_x1_t
  );
end entity d_x1;

architecture rtl of d_x1 is
  signal reg : d_x1_t := D_X1_NOP;
begin
  process (clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        reg <= D_X1_NOP;
      elsif flush = '1' or en = '1' then
        reg <= d_in;
        if flush = '1' then
          reg.ctrl <= CTRL_NOP;
        end if;
      end if;
    end if;
  end process;

  d_out <= reg;
end architecture rtl;
