-------------------------------------------------------------------------------
-- m_w.vhd -- M/W pipeline register.
-- Note: res1 in d_in is already the final result (RAM data for loads).
-- flush loads CTRL_NOP and has priority over en.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.cpu_pkg.all;

entity m_w is
  port (
    clk   : in  std_logic;
    reset : in  std_logic;
    en    : in  std_logic;
    flush : in  std_logic;
    d_in  : in  m_w_t;
    d_out : out m_w_t
  );
end entity m_w;

architecture rtl of m_w is
  signal reg : m_w_t := M_W_NOP;
begin
  process (clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        reg.control <= CTRL_NOP;
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
