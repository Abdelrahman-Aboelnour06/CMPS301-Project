-------------------------------------------------------------------------------
-- regfile.vhd -- 8 x 32 flip-flop register file.
--   * two asynchronous read ports with write-through bypass (a write in W
--     is visible to a read in D in the same cycle),
--   * two synchronous write ports (port 2 exists permanently, used by SWAP),
--     If both ports address the same register, port 2 wins (for SWAP Rx,Rx
--     both carry the same value, so the instruction is a no-op).
--   * synchronous reset clears all registers.
-- Implemented in logic (ramstyle "logic"), never in M10K blocks.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cpu_pkg.all;

entity regfile is
  port (
    clk      : in  std_logic;
    reset    : in  std_logic;
    ra1      : in  raddr_t;
    ra2      : in  raddr_t;
    rd1      : out word_t;
    rd2      : out word_t;
    wa1      : in  raddr_t;
    wd1      : in  word_t;
    we1      : in  std_logic;
    regs_out : out reg_array_t
  );
end entity regfile;

architecture rtl of regfile is
  signal regs : reg_array_t := (others => (others => '0'));
  attribute ramstyle : string;
  attribute ramstyle of regs : signal is "logic";
begin

  process (clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        regs <= (others => (others => '0'));
      else
        if we1 = '1' then
          regs(to_integer(unsigned(wa1))) <= wd1;
        end if;
      end if;
    end if;
  end process;

  rd1 <= wd1 when (we1 = '1' and wa1 = ra1) else
         regs(to_integer(unsigned(ra1)));

  rd2 <= wd1 when (we1 = '1' and wa1 = ra2) else
         regs(to_integer(unsigned(ra2)));

  regs_out <= regs;
end architecture rtl;
