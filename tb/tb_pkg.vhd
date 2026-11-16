-------------------------------------------------------------------------------
-- tb_pkg.vhd -- shared testbench helpers (VHDL-2008).
--   enc       : instruction encoder (assembler helper)
--   check*    : self-checking assertions that also count errors
--   finish_tb : prints "PASS <name>" and calls std.env.finish
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.cpu_pkg.all;

package tb_pkg is

  function enc(op  : opcode_t;
               rd  : natural := 0;
               rs1 : natural := 0;
               rs2 : natural := 0;
               imm : integer := 0;
               idx : natural := 0) return word_t;

  function hex(v : std_logic_vector) return string;

  procedure check(cond : boolean; msg : string; variable errs : inout natural);

  procedure check_eq(got : std_logic_vector; exp : std_logic_vector;
                     msg : string; variable errs : inout natural);

  procedure check_sl(got : std_logic; exp : std_logic;
                     msg : string; variable errs : inout natural);

  procedure finish_tb(name : string; errs : natural);

end package tb_pkg;

package body tb_pkg is

  function enc(op  : opcode_t;
               rd  : natural := 0;
               rs1 : natural := 0;
               rs2 : natural := 0;
               imm : integer := 0;
               idx : natural := 0) return word_t is
    variable w  : word_t;
    variable i  : std_logic_vector(15 downto 0);
  begin
    if imm < 0 then
      i := std_logic_vector(to_unsigned(imm + 65536, 16));
    else
      i := std_logic_vector(to_unsigned(imm mod 65536, 16));
    end if;
    w := op &
         std_logic_vector(to_unsigned(rd, 3)) &
         std_logic_vector(to_unsigned(rs1, 3)) &
         std_logic_vector(to_unsigned(rs2, 3)) &
         std_logic_vector(to_unsigned(idx, 1)) &
         i;
    return w;
  end function;

  function hex(v : std_logic_vector) return string is
  begin
    return to_hstring(v);
  end function;

  procedure check(cond : boolean; msg : string; variable errs : inout natural) is
  begin
    if not cond then
      errs := errs + 1;
    end if;
    assert cond report "CHECK FAILED: " & msg severity error;
  end procedure;

  procedure check_eq(got : std_logic_vector; exp : std_logic_vector;
                     msg : string; variable errs : inout natural) is
  begin
    if got /= exp then
      errs := errs + 1;
    end if;
    assert got = exp
      report "CHECK FAILED: " & msg & " got=0x" & to_hstring(got) &
             " exp=0x" & to_hstring(exp)
      severity error;
  end procedure;

  procedure check_sl(got : std_logic; exp : std_logic;
                     msg : string; variable errs : inout natural) is
  begin
    if got /= exp then
      errs := errs + 1;
    end if;
    assert got = exp
      report "CHECK FAILED: " & msg & " got=" & std_logic'image(got) &
             " exp=" & std_logic'image(exp)
      severity error;
  end procedure;

  procedure finish_tb(name : string; errs : natural) is
    variable l : line;
  begin
    if errs = 0 then
      write(l, string'("PASS " & name));
      writeline(output, l);
      std.env.finish;
    else
      write(l, string'("FAIL " & name & " errors=" & integer'image(errs)));
      writeline(output, l);
      assert false report "FAIL " & name severity failure;
    end if;
  end procedure;

end package body tb_pkg;
