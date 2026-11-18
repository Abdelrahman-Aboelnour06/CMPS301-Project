-------------------------------------------------------------------------------
-- tb_branch_check.vhd -- directed self-checking testbench for branch_check
-- Every condition (Z, N, C) against every flag combination, plus is_jcc=0
-- (no branch: never mispredicts), clr_mask on taken Jcc, and reserved "00".
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
  signal clr_mask   : std_logic_vector(2 downto 0);
begin
  dut : entity work.branch_check
    port map (is_jcc => is_jcc, cond => cond, ccr => ccr,
              taken => taken, mispredict => mispredict, clr_mask => clr_mask);

  stim : process
    variable errs     : natural := 0;
    variable f        : std_logic;
    variable exp_mask : std_logic_vector(2 downto 0);
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
          exp_mask := "000";
          if j = 1 and f = '1' then
            case cd is
              when 1 => exp_mask := "001";
              when 2 => exp_mask := "010";
              when 3 => exp_mask := "100";
              when others => exp_mask := "000";
            end case;
          end if;
          if j = 1 then
            check_sl(taken, f, "taken cond=" & integer'image(cd) &
                     " flags=" & integer'image(fl), errs);
            check_sl(mispredict, not f, "mispredict cond=" & integer'image(cd) &
                     " flags=" & integer'image(fl), errs);
          else
            check_sl(taken, '0', "no jcc taken", errs);
            check_sl(mispredict, '0', "no jcc mispredict", errs);
          end if;
          check_eq(clr_mask, exp_mask, "clr_mask cond=" & integer'image(cd) &
                   " flags=" & integer'image(fl), errs);
          check_sl(taken and mispredict, '0', "exclusive", errs);
        end loop;
      end loop;
    end loop;
    -- reserved CCR bit 3 must not influence the result
    is_jcc <= '1'; cond <= COND_Z; ccr <= "1000";
    wait for 1 ns;
    check_sl(mispredict, '1', "bit3 ignored", errs);
    check_eq(clr_mask, "000", "bit3 clr_mask", errs);
    finish_tb("tb_branch_check", errs);
    wait;
  end process;
end architecture sim;
