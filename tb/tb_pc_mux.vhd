-------------------------------------------------------------------------------
-- tb_pc_mux.vhd -- directed self-checking testbench for pc_mux.vhd
-- Exhaustive over the 16 select combinations: priority boot > W > X2 > D >
-- sequential, and the src code.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cpu_pkg.all;
use work.tb_pkg.all;

entity tb_pc_mux is
end entity tb_pc_mux;

architecture sim of tb_pc_mux is
  signal pc_plus1    : word_t := x"00000011";
  signal boot_target : word_t := x"000000B0";
  signal w_target    : word_t := x"000000AA";
  signal x2_target   : word_t := x"00000022";
  signal d_target    : word_t := x"0000DDDD";
  signal sel_boot, sel_w, sel_x2, sel_d : std_logic := '0';
  signal pc_next     : word_t;
  signal src         : std_logic_vector(2 downto 0);
begin
  dut : entity work.pc_mux
    port map (pc_plus1 => pc_plus1, boot_target => boot_target,
              w_target => w_target, x2_target => x2_target,
              d_target => d_target, sel_boot => sel_boot, sel_w => sel_w,
              sel_x2 => sel_x2, sel_d => sel_d, pc_next => pc_next, src => src);

  stim : process
    variable errs : natural := 0;
    variable v    : std_logic_vector(3 downto 0);
    variable ev   : word_t;
    variable es   : std_logic_vector(2 downto 0);
  begin
    for i in 0 to 15 loop
      v := std_logic_vector(to_unsigned(i, 4));
      sel_boot <= v(3); sel_w <= v(2); sel_x2 <= v(1); sel_d <= v(0);
      wait for 1 ns;
      if v(3) = '1' then    ev := boot_target; es := "100";
      elsif v(2) = '1' then ev := w_target;    es := "011";
      elsif v(1) = '1' then ev := x2_target;   es := "010";
      elsif v(0) = '1' then ev := d_target;    es := "001";
      else                  ev := pc_plus1;    es := "000";
      end if;
      check_eq(pc_next, ev, "pc_next sel=" & integer'image(i), errs);
      check_eq(src, es, "src sel=" & integer'image(i), errs);
    end loop;
    -- boundary values pass through unchanged
    sel_boot <= '0'; sel_w <= '0'; sel_x2 <= '0'; sel_d <= '0';
    pc_plus1 <= x"00000000";
    wait for 1 ns;
    check_eq(pc_next, x"00000000", "pc+1 wrapped to 0", errs);
    sel_d <= '1'; d_target <= x"0000FFFF";
    wait for 1 ns;
    check_eq(pc_next, x"0000FFFF", "max 16-bit target", errs);
    finish_tb("tb_pc_mux", errs);
    wait;
  end process;
end architecture sim;
