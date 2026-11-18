-------------------------------------------------------------------------------
-- ccr.vhd -- 4-bit condition-code register + shadow register (INT/RTI).
--   bit 0 = Z, bit 1 = N, bit 2 = C, bit 3 reserved (always 0).
--   zn_we / c_we : write Z,N / C from the X1 ALU (already gated by flush).
--   save         : shadow <- CCR (INT or hardware-IRQ micro-op in X2).
--   restore      : CCR <- shadow (RTI in W). Has priority over zn_we/c_we.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.cpu_pkg.all;

entity ccr is
  port (
    clk        : in  std_logic;
    reset      : in  std_logic;
    z_in       : in  std_logic;
    n_in       : in  std_logic;
    c_in       : in  std_logic;
    zn_we      : in  std_logic;
    c_we       : in  std_logic;
    clr_mask   : in  std_logic_vector(2 downto 0) := "000"; -- NEW: bit0=Z, bit1=N, bit2=C
    save       : in  std_logic;
    restore    : in  std_logic;
    ccr_out    : out std_logic_vector(3 downto 0);
    shadow_out : out std_logic_vector(3 downto 0)
  );
end entity ccr;

architecture rtl of ccr is
  signal ccr_r    : std_logic_vector(2 downto 0) := (others => '0');
  signal shadow_r : std_logic_vector(2 downto 0) := (others => '0');
begin
  process (clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        ccr_r    <= (others => '0');
        shadow_r <= (others => '0');
      else
        if save = '1' then
          shadow_r <= ccr_r;
        end if;
        if restore = '1' then
          ccr_r <= shadow_r;
        else
          if clr_mask(CCR_Z) = '1' then ccr_r(CCR_Z) <= '0'; end if;
          if clr_mask(CCR_N) = '1' then ccr_r(CCR_N) <= '0'; end if;
          if clr_mask(CCR_C) = '1' then ccr_r(CCR_C) <= '0'; end if;

          if zn_we = '1' then
            ccr_r(CCR_Z) <= z_in;
            ccr_r(CCR_N) <= n_in;
          end if;
          if c_we = '1' then
            ccr_r(CCR_C) <= c_in;
          end if;
        end if;
      end if;
    end if;
  end process;

  ccr_out    <= '0' & ccr_r;
  shadow_out <= '0' & shadow_r;
end architecture rtl;