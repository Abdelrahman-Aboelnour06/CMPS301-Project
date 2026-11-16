-------------------------------------------------------------------------------
-- x2_m.vhd -- X2/M pipeline register.
-- Note: the X2 stage is never flushed (older than any mispredicting branch); flush exists for completeness.
-- flush loads CTRL_NOP and has priority over en.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.cpu_pkg.all;

entity x2_m is
  port (
    clk      : in  std_logic;
    reset    : in  std_logic;
    en       : in  std_logic;
    flush    : in  std_logic;
    ctrl_in  : in  ctrl_t;
    res1_in  : in  word_t;
    res2_in  : in  word_t;
    wa1_in   : in  raddr_t;
    wa2_in   : in  raddr_t;
    ctrl_out : out ctrl_t;
    res1_out : out word_t;
    res2_out : out word_t;
    wa1_out  : out raddr_t;
    wa2_out  : out raddr_t
  );
end entity x2_m;

architecture rtl of x2_m is
  signal ctrl_r : ctrl_t  := CTRL_NOP;
  signal res1_r : word_t  := (others => '0');
  signal res2_r : word_t  := (others => '0');
  signal wa1_r  : raddr_t := (others => '0');
  signal wa2_r  : raddr_t := (others => '0');
begin
  process (clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        ctrl_r <= CTRL_NOP;
        res1_r <= (others => '0');
        res2_r <= (others => '0');
        wa1_r  <= (others => '0');
        wa2_r  <= (others => '0');
      elsif flush = '1' or en = '1' then
        if flush = '1' then
          ctrl_r <= CTRL_NOP;
        else
          ctrl_r <= ctrl_in;
        end if;
        res1_r <= res1_in;
        res2_r <= res2_in;
        wa1_r  <= wa1_in;
        wa2_r  <= wa2_in;
      end if;
    end if;
  end process;

  ctrl_out <= ctrl_r;
  res1_out <= res1_r;
  res2_out <= res2_r;
  wa1_out  <= wa1_r;
  wa2_out  <= wa2_r;
end architecture rtl;
