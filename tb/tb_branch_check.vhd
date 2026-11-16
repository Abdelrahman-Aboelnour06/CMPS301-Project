-------------------------------------------------------------------------------
-- tb_branch_check.vhd -- directed self-checking testbench for branch_check
-- Every condition (Z, N, C) against every flag combination, plus is_jcc=0
-- (no branch: never mispredicts) and the reserved cond "00".
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cpu_pkg.all;
use work.tb_pkg.all;

entity tb_branch_check is
end entity tb_branch_check;

architecture sim of tb_branch_check is
  signal is_jcc     : std_logic := '0';
  signal cond       : std_logic_vector(1 downto 0) := "00";
  signal ccr        : std_logic_vector(3 downto 0) := "0000";
  signal taken      : std_logic;
  signal mispredict : std_logic;
begin
  dut : entity work.branch_check
    port map (is_jcc => is_jcc, cond => cond, ccr => ccr,
              taken => taken, mispredict => mispredict);

  stim : process
    variable errs : natural := 0;
    variable f    : std_logic;
  begin
    for j in 0 to 1 loop
      for cd in 0 to 3 loop
        for fl in 0 to 7 loop
          is_jcc <= '1' when j = 1 else '0';
          cond   <= std_logic_vector(to_unsigned(cd, 2));
          ccr    <= '0' & std_logic_vector(to_unsigned(fl, 3));
          wait for 1 ns;
          case cd is
            when 1 => f := ccr(CCR_Z);
            when 2 => f := ccr(CCR_N);
            when 3 => f := ccr(CCR_C);
            when others => f := '0';
          end case;
          if j = 1 then
            check_sl(taken, f, "taken cond=" & integer'image(cd) &
                     " flags=" & integer'image(fl), errs);
            check_sl(mispredict, not f, "mispredict cond=" & integer'image(cd) &
                     " flags=" & integer'image(fl), errs);
          else
            check_sl(taken, '0', "no jcc taken", errs);
            check_sl(mispredict, '0', "no jcc mispredict", errs);
          end if;
          check_sl(taken and mispredict, '0', "exclusive", errs);
        end loop;
      end loop;
    end loop;
    -- reserved CCR bit 3 must not influence the result
    is_jcc <= '1'; cond <= COND_Z; ccr <= "1000";
    wait for 1 ns;
    check_sl(mispredict, '1', "bit3 ignored", errs);
    finish_tb("tb_branch_check", errs);
    wait;
  end process;
end architecture sim;
