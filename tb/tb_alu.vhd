-------------------------------------------------------------------------------
-- tb_alu.vhd -- directed self-checking testbench for alu.vhd
-- Covers every ALU operation, zero/negative/max/min operands, carry out,
-- borrow, shift by 0/1/31 and the "last bit out" carry of both shifts.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cpu_pkg.all;
use work.tb_pkg.all;

entity tb_alu is
end entity tb_alu;

architecture sim of tb_alu is
  signal a, b, y   : word_t := (others => '0');
  signal shamt     : std_logic_vector(4 downto 0) := (others => '0');
  signal op        : aluop_t := ALU_PASSA;
  signal z, n, c, cv : std_logic := '0';
begin
  dut : entity work.alu
    port map (a => a, b => b, shamt => shamt, op => op,
              y => y, z => z, n => n, c => c, cv => cv);

  stim : process
    variable errs : natural := 0;

    procedure t(o : aluop_t; av, bv : word_t; s : natural; ey : word_t;
                ez, en, ec, ecv : std_logic; name : string) is
    begin
      op    <= o;
      a     <= av;
      b     <= bv;
      shamt <= std_logic_vector(to_unsigned(s, 5));
      wait for 1 ns;
      check_eq(y, ey, name & " y", errs);
      check_sl(z, ez, name & " z", errs);
      check_sl(n, en, name & " n", errs);
      check_sl(cv, ecv, name & " cv", errs);
      if ecv = '1' then
        check_sl(c, ec, name & " c", errs);
      end if;
    end procedure;
  begin
    t(ALU_PASSA, x"12345678", x"00000000",  0, x"12345678", '0', '0', '0', '0', "PASSA 12345678,00000000,0");
    t(ALU_PASSA, x"00000000", x"00000000",  0, x"00000000", '1', '0', '0', '0', "PASSA 00000000,00000000,0");
    t(ALU_PASSA, x"80000000", x"00000000",  0, x"80000000", '0', '1', '0', '0', "PASSA 80000000,00000000,0");
    t(ALU_NOT  , x"00000000", x"00000000",  0, x"FFFFFFFF", '0', '1', '0', '0', "NOT 00000000,00000000,0");
    t(ALU_NOT  , x"FFFFFFFF", x"00000000",  0, x"00000000", '1', '0', '0', '0', "NOT FFFFFFFF,00000000,0");
    t(ALU_NOT  , x"0F0F0F0F", x"00000000",  0, x"F0F0F0F0", '0', '1', '0', '0', "NOT 0F0F0F0F,00000000,0");
    t(ALU_INC  , x"00000000", x"00000000",  0, x"00000001", '0', '0', '0', '1', "INC 00000000,00000000,0");
    t(ALU_INC  , x"FFFFFFFF", x"00000000",  0, x"00000000", '1', '0', '1', '1', "INC FFFFFFFF,00000000,0");
    t(ALU_INC  , x"7FFFFFFF", x"00000000",  0, x"80000000", '0', '1', '0', '1', "INC 7FFFFFFF,00000000,0");
    t(ALU_INC  , x"00000001", x"00000000",  0, x"00000002", '0', '0', '0', '1', "INC 00000001,00000000,0");
    t(ALU_ADD  , x"00000001", x"00000001",  0, x"00000002", '0', '0', '0', '1', "ADD 00000001,00000001,0");
    t(ALU_ADD  , x"FFFFFFFF", x"00000001",  0, x"00000000", '1', '0', '1', '1', "ADD FFFFFFFF,00000001,0");
    t(ALU_ADD  , x"80000000", x"80000000",  0, x"00000000", '1', '0', '1', '1', "ADD 80000000,80000000,0");
    t(ALU_ADD  , x"7FFFFFFF", x"00000001",  0, x"80000000", '0', '1', '0', '1', "ADD 7FFFFFFF,00000001,0");
    t(ALU_ADD  , x"00000000", x"00000000",  0, x"00000000", '1', '0', '0', '1', "ADD 00000000,00000000,0");
    t(ALU_ADD  , x"FFFFFFFF", x"FFFFFFFF",  0, x"FFFFFFFE", '0', '1', '1', '1', "ADD FFFFFFFF,FFFFFFFF,0");
    t(ALU_SUB  , x"00000005", x"00000003",  0, x"00000002", '0', '0', '0', '1', "SUB 00000005,00000003,0");
    t(ALU_SUB  , x"00000003", x"00000005",  0, x"FFFFFFFE", '0', '1', '1', '1', "SUB 00000003,00000005,0");
    t(ALU_SUB  , x"00000007", x"00000007",  0, x"00000000", '1', '0', '0', '1', "SUB 00000007,00000007,0");
    t(ALU_SUB  , x"00000000", x"00000001",  0, x"FFFFFFFF", '0', '1', '1', '1', "SUB 00000000,00000001,0");
    t(ALU_SUB  , x"80000000", x"00000001",  0, x"7FFFFFFF", '0', '0', '0', '1', "SUB 80000000,00000001,0");
    t(ALU_SUB  , x"FFFFFFFF", x"FFFFFFFF",  0, x"00000000", '1', '0', '0', '1', "SUB FFFFFFFF,FFFFFFFF,0");
    t(ALU_SUB  , x"00000000", x"80000000",  0, x"80000000", '0', '1', '1', '1', "SUB 00000000,80000000,0");
    t(ALU_AND  , x"FF00FF00", x"0FF00FF0",  0, x"0F000F00", '0', '0', '0', '0', "AND FF00FF00,0FF00FF0,0");
    t(ALU_AND  , x"FFFFFFFF", x"00000000",  0, x"00000000", '1', '0', '0', '0', "AND FFFFFFFF,00000000,0");
    t(ALU_AND  , x"80000001", x"80000000",  0, x"80000000", '0', '1', '0', '0', "AND 80000001,80000000,0");
    t(ALU_SHL  , x"00000001", x"00000000",  0, x"00000001", '0', '0', '0', '0', "SHL 00000001,00000000,0");
    t(ALU_SHL  , x"00000001", x"00000000",  1, x"00000002", '0', '0', '0', '1', "SHL 00000001,00000000,1");
    t(ALU_SHL  , x"80000000", x"00000000",  1, x"00000000", '1', '0', '1', '1', "SHL 80000000,00000000,1");
    t(ALU_SHL  , x"40000000", x"00000000",  2, x"00000000", '1', '0', '1', '1', "SHL 40000000,00000000,2");
    t(ALU_SHL  , x"C0000001", x"00000000", 31, x"80000000", '0', '1', '0', '1', "SHL C0000001,00000000,31");
    t(ALU_SHL  , x"00000003", x"00000000", 31, x"80000000", '0', '1', '1', '1', "SHL 00000003,00000000,31");
    t(ALU_SHL  , x"12345678", x"00000000",  4, x"23456780", '0', '0', '1', '1', "SHL 12345678,00000000,4");
    t(ALU_SHR  , x"80000000", x"00000000",  0, x"80000000", '0', '1', '0', '0', "SHR 80000000,00000000,0");
    t(ALU_SHR  , x"00000001", x"00000000",  1, x"00000000", '1', '0', '1', '1', "SHR 00000001,00000000,1");
    t(ALU_SHR  , x"00000002", x"00000000",  1, x"00000001", '0', '0', '0', '1', "SHR 00000002,00000000,1");
    t(ALU_SHR  , x"80000000", x"00000000", 31, x"00000001", '0', '0', '0', '1', "SHR 80000000,00000000,31");
    t(ALU_SHR  , x"40000000", x"00000000", 31, x"00000000", '1', '0', '1', '1', "SHR 40000000,00000000,31");
    t(ALU_SHR  , x"FFFFFFFF", x"00000000", 16, x"0000FFFF", '0', '0', '1', '1', "SHR FFFFFFFF,00000000,16");
    t(ALU_SHR  , x"12345678", x"00000000",  4, x"01234567", '0', '0', '1', '1', "SHR 12345678,00000000,4");
    t(ALU_PASSB, x"00000000", x"DEADBEEF",  0, x"DEADBEEF", '0', '1', '0', '0', "PASSB 00000000,DEADBEEF,0");
    t(ALU_PASSB, x"00000000", x"00000000",  0, x"00000000", '1', '0', '0', '0', "PASSB 00000000,00000000,0");
    t(ALU_PASSB, x"00000001", x"FFFF8000",  0, x"FFFF8000", '0', '1', '0', '0', "PASSB 00000001,FFFF8000,0");
    t(ALU_SETC , x"0000ABCD", x"00000000",  0, x"0000ABCD", '0', '0', '1', '1', "SETC 0000ABCD,00000000,0");
    t(ALU_SETC , x"00000000", x"00000000",  0, x"00000000", '1', '0', '1', '1', "SETC 00000000,00000000,0");
    -- undefined op code behaves as PASSA
    t("1111", x"0000ABCD", x"00001111", 0, x"0000ABCD", '0', '0', '0', '0', "undefined op");

    finish_tb("tb_alu", errs);
    wait;
  end process;
end architecture sim;
