-------------------------------------------------------------------------------
-- x1_x2.vhd -- X1/X2 pipeline register.
-- flush (X2 mispredict kills the X1 instruction) loads CTRL_NOP and has
-- priority over en.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.cpu_pkg.all;

entity x1_x2 is
  port (
    clk   : in  std_logic;
    reset : in  std_logic;
    en    : in  std_logic;
    flush : in  std_logic;
    d_in  : in  x1_x2_t;
    d_out : out x1_x2_t
  );
end entity x1_x2;

architecture rtl of x1_x2 is
  signal reg : x1_x2_t := X1_X2_NOP;
begin
  process (clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        reg <= X1_X2_NOP;
      elsif flush = '1' or en = '1' then
        reg <= d_in;
        if flush = '1' then
          reg.control <= CTRL_NOP;
        end if;
      end if;
    end if;
  end process;

  d_out <= reg;
end architecture rtl;
