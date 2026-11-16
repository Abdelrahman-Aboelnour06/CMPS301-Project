-------------------------------------------------------------------------------
-- pc_mux.vhd -- next-PC source select.
-- Priority (highest first):
--   1. boot   : reset FSM loads PC from M[0]              (src = "100")
--   2. W      : RET / RTI load the popped PC in W         (src = "011")
--   3. X2     : Jcc mispredict, reload saved PC+1         (src = "010")
--   4. D      : JMP/CALL/Jcc(predicted)/INT/vector        (src = "001")
--   5. PC+1   : sequential                                (src = "000")
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.cpu_pkg.all;

entity pc_mux is
  port (
    pc_plus1    : in  word_t;
    boot_target : in  word_t;
    w_target    : in  word_t;
    x2_target   : in  word_t;
    d_target    : in  word_t;
    sel_boot    : in  std_logic;
    sel_w       : in  std_logic;
    sel_x2      : in  std_logic;
    sel_d       : in  std_logic;
    pc_next     : out word_t;
    src         : out std_logic_vector(2 downto 0)
  );
end entity pc_mux;

architecture rtl of pc_mux is
begin
  pc_next <= boot_target when sel_boot = '1' else
             w_target    when sel_w    = '1' else
             x2_target   when sel_x2   = '1' else
             d_target    when sel_d    = '1' else
             pc_plus1;

  src <= "100" when sel_boot = '1' else
         "011" when sel_w    = '1' else
         "010" when sel_x2   = '1' else
         "001" when sel_d    = '1' else
         "000";
end architecture rtl;
