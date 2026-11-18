-------------------------------------------------------------------------------
-- x2_m.vhd -- X2/M pipeline register.
-- Note: the X2 stage is never flushed (older than any mispredicting branch);
-- flush exists for completeness and loads CTRL_NOP with priority over en.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.cpu_pkg.all;

entity x2_m is
  port (
    clk   : in  std_logic;
    reset : in  std_logic;
    en    : in  std_logic;
    flush : in  std_logic;
    d_in  : in  x2_m_t;
    d_out : out x2_m_t
  );
end entity x2_m;

architecture rtl of x2_m is
  signal reg : x2_m_t := X2_M_NOP;
begin
  process (clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        reg <= X2_M_NOP;
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
