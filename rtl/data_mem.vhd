-------------------------------------------------------------------------------
-- data_mem.vhd -- unified 4096 x 32 true dual-port RAM (M10K-inferrable).
--
--   Port A : read-only instruction fetch, with clock enable en_a.
--   Port B : load / store from the M stage. Address, data and write enable
--            are driven by the X2 stage and captured by the RAM input
--            registers at the X2->M clock edge; q_b is valid during M.
--
-- Read-during-write behaviour is WRITE-FIRST on both ports:
--   * Port B same-port: q_b returns the data being written.
--   * Mixed port: if Port A reads the address Port B writes in the same
--     cycle, q_a returns the NEW data (fetch sees the store).
--     On Cyclone V Quartus implements this with bypass logic around the
--     M10K, which is documented in the specification.
--
-- Initial contents: generic INIT (simulation; MEM_ZERO by default) and the
-- Quartus ram_init_file attribute "program.mif" (synthesis).
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cpu_pkg.all;

entity data_mem is
  generic (
    INIT : mem_t := MEM_ZERO
  );
  port (
    clk    : in  std_logic;
    -- Port A (fetch)
    addr_a : in  maddr_t;
    en_a   : in  std_logic;
    q_a    : out word_t;
    -- Port B (load / store)
    addr_b : in  maddr_t;
    we_b   : in  std_logic;
    din_b  : in  word_t;
    q_b    : out word_t
  );
end entity data_mem;

architecture rtl of data_mem is
  signal ram : mem_t := INIT;
  attribute ram_init_file : string;
  attribute ram_init_file of ram : signal is "program.mif";
  attribute ram_style : string;
  attribute ram_style of ram : signal is "block";
  attribute ramstyle : string;
  attribute ramstyle of ram : signal is "M10K, no_rw_check";

  signal qa_raw     : word_t    := (others => '0');
  signal qb_r       : word_t    := (others => '0');
  signal bypass_a_r : std_logic := '0';
  signal bypass_d_r : word_t    := (others => '0');
begin
  process (clk)
  begin
    if rising_edge(clk) then
      -- Port A: pure BRAM read
      if en_a = '1' then
        qa_raw <= ram(to_integer(unsigned(addr_a)));
        if we_b = '1' and addr_a = addr_b then
          bypass_a_r <= '1';
          bypass_d_r <= din_b;
        else
          bypass_a_r <= '0';
        end if;
      end if;

      -- Port B: pure BRAM write-first
      if we_b = '1' then
        ram(to_integer(unsigned(addr_b))) <= din_b;
        qb_r <= din_b;
      else
        qb_r <= ram(to_integer(unsigned(addr_b)));
      end if;
    end if;
  end process;

  q_a <= bypass_d_r when bypass_a_r = '1' else qa_raw;
  q_b <= qb_r;
end architecture rtl;