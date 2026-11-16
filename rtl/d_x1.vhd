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
    clk      : in  std_logic;
    reset    : in  std_logic;
    en       : in  std_logic;
    flush    : in  std_logic;
    ctrl_in  : in  ctrl_t;
    a_in     : in  word_t;      -- RF read port 1
    b_in     : in  word_t;      -- RF read port 2
    ra1_in   : in  raddr_t;
    ra2_in   : in  raddr_t;
    wa1_in   : in  raddr_t;     -- Rdst
    wa2_in   : in  raddr_t;     -- Rsrc1 (SWAP second destination)
    imm_in   : in  word_t;      -- sign-extended immediate
    link_in  : in  word_t;      -- PC+1 (PC for the IRQ micro-op)
    ctrl_out : out ctrl_t;
    a_out    : out word_t;
    b_out    : out word_t;
    ra1_out  : out raddr_t;
    ra2_out  : out raddr_t;
    wa1_out  : out raddr_t;
    wa2_out  : out raddr_t;
    imm_out  : out word_t;
    link_out : out word_t
  );
end entity d_x1;

architecture rtl of d_x1 is
  signal ctrl_r : ctrl_t  := CTRL_NOP;
  signal a_r    : word_t  := (others => '0');
  signal b_r    : word_t  := (others => '0');
  signal ra1_r  : raddr_t := (others => '0');
  signal ra2_r  : raddr_t := (others => '0');
  signal wa1_r  : raddr_t := (others => '0');
  signal wa2_r  : raddr_t := (others => '0');
  signal imm_r  : word_t  := (others => '0');
  signal link_r : word_t  := (others => '0');
begin
  process (clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        ctrl_r <= CTRL_NOP;
        a_r    <= (others => '0');
        b_r    <= (others => '0');
        ra1_r  <= (others => '0');
        ra2_r  <= (others => '0');
        wa1_r  <= (others => '0');
        wa2_r  <= (others => '0');
        imm_r  <= (others => '0');
        link_r <= (others => '0');
      elsif flush = '1' or en = '1' then
        if flush = '1' then
          ctrl_r <= CTRL_NOP;
        else
          ctrl_r <= ctrl_in;
        end if;
        a_r    <= a_in;
        b_r    <= b_in;
        ra1_r  <= ra1_in;
        ra2_r  <= ra2_in;
        wa1_r  <= wa1_in;
        wa2_r  <= wa2_in;
        imm_r  <= imm_in;
        link_r <= link_in;
      end if;
    end if;
  end process;

  ctrl_out <= ctrl_r;
  a_out    <= a_r;
  b_out    <= b_r;
  ra1_out  <= ra1_r;
  ra2_out  <= ra2_r;
  wa1_out  <= wa1_r;
  wa2_out  <= wa2_r;
  imm_out  <= imm_r;
  link_out <= link_r;
end architecture rtl;
