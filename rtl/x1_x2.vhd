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
    clk      : in  std_logic;
    reset    : in  std_logic;
    en       : in  std_logic;
    flush    : in  std_logic;
    ctrl_in  : in  ctrl_t;
    res1_in  : in  word_t;      -- ALU / IN result
    res2_in  : in  word_t;      -- second result (SWAP)
    a_in     : in  word_t;      -- forwarded operand A (store data / base)
    b_in     : in  word_t;      -- forwarded operand B (STD base)
    imm_in   : in  word_t;
    wa1_in   : in  raddr_t;
    wa2_in   : in  raddr_t;
    link_in  : in  word_t;
    ctrl_out : out ctrl_t;
    res1_out : out word_t;
    res2_out : out word_t;
    a_out    : out word_t;
    b_out    : out word_t;
    imm_out  : out word_t;
    wa1_out  : out raddr_t;
    wa2_out  : out raddr_t;
    link_out : out word_t
  );
end entity x1_x2;

architecture rtl of x1_x2 is
  signal ctrl_r : ctrl_t  := CTRL_NOP;
  signal res1_r : word_t  := (others => '0');
  signal res2_r : word_t  := (others => '0');
  signal a_r    : word_t  := (others => '0');
  signal b_r    : word_t  := (others => '0');
  signal imm_r  : word_t  := (others => '0');
  signal wa1_r  : raddr_t := (others => '0');
  signal wa2_r  : raddr_t := (others => '0');
  signal link_r : word_t  := (others => '0');
begin
  process (clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        ctrl_r <= CTRL_NOP;
        res1_r <= (others => '0');
        res2_r <= (others => '0');
        a_r    <= (others => '0');
        b_r    <= (others => '0');
        imm_r  <= (others => '0');
        wa1_r  <= (others => '0');
        wa2_r  <= (others => '0');
        link_r <= (others => '0');
      elsif flush = '1' or en = '1' then
        if flush = '1' then
          ctrl_r <= CTRL_NOP;
        else
          ctrl_r <= ctrl_in;
        end if;
        res1_r <= res1_in;
        res2_r <= res2_in;
        a_r    <= a_in;
        b_r    <= b_in;
        imm_r  <= imm_in;
        wa1_r  <= wa1_in;
        wa2_r  <= wa2_in;
        link_r <= link_in;
      end if;
    end if;
  end process;

  ctrl_out <= ctrl_r;
  res1_out <= res1_r;
  res2_out <= res2_r;
  a_out    <= a_r;
  b_out    <= b_r;
  imm_out  <= imm_r;
  wa1_out  <= wa1_r;
  wa2_out  <= wa2_r;
  link_out <= link_r;
end architecture rtl;
