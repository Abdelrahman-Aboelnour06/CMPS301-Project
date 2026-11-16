-------------------------------------------------------------------------------
-- alu.vhd -- X1 ALU: 33-bit adder/subtractor, logic unit, single barrel
-- shifter (right shifter; SHL is done by bit-reversing input and output).
--
--   op         y                 z  n  c                     cv
--   PASSA      a                 *  *  -                     0
--   NOT        not a             *  *  -                     0
--   INC        a + 1             *  *  carry out             1
--   ADD        a + b             *  *  carry out             1
--   SUB        a - b             *  *  borrow (a < b, unsig) 1
--   AND        a and b           *  *  -                     0
--   SHL        a << s            *  *  last bit out a(32-s)  1 if s/=0
--   SHR        a >> s (logical)  *  *  last bit out a(s-1)   1 if s/=0
--   PASSB      b                 *  *  -                     0
--   SETC       a                 *  *  1                     1
-- z = (y = 0), n = y(31). cv = '1' means c is meaningful (C may be written).
-- s = shamt = Imm[4:0].
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cpu_pkg.all;

entity alu is
  port (
    a     : in  word_t;
    b     : in  word_t;
    shamt : in  std_logic_vector(4 downto 0);
    op    : in  aluop_t;
    y     : out word_t;
    z     : out std_logic;
    n     : out std_logic;
    c     : out std_logic;
    cv    : out std_logic
  );
end entity alu;

architecture rtl of alu is

  function reverse(v : unsigned(WIDTH-1 downto 0)) return unsigned is
    variable r : unsigned(WIDTH-1 downto 0);
  begin
    for i in 0 to WIDTH-1 loop
      r(i) := v(WIDTH-1-i);
    end loop;
    return r;
  end function;

  signal y_i : word_t;

begin

  process (a, b, shamt, op)
    variable s33 : unsigned(WIDTH downto 0);
    variable r   : word_t;
    variable x   : unsigned(WIDTH-1 downto 0);
    variable sh  : unsigned(WIDTH-1 downto 0);
    variable cc  : std_logic;
    variable cvv : std_logic;
    variable k   : natural range 0 to 31;
  begin
    s33 := (others => '0');
    r   := a;
    cc  := '0';
    cvv := '0';
    x   := (others => '0');
    sh  := (others => '0');
    k   := to_integer(unsigned(shamt));

    case op is
      when ALU_PASSA =>
        r := a;
      when ALU_NOT =>
        r := not a;
      when ALU_INC =>
        s33 := ('0' & unsigned(a)) + 1;
        r   := std_logic_vector(s33(WIDTH-1 downto 0));
        cc  := s33(WIDTH);
        cvv := '1';
      when ALU_ADD =>
        s33 := ('0' & unsigned(a)) + ('0' & unsigned(b));
        r   := std_logic_vector(s33(WIDTH-1 downto 0));
        cc  := s33(WIDTH);
        cvv := '1';
      when ALU_SUB =>
        s33 := ('0' & unsigned(a)) - ('0' & unsigned(b));
        r   := std_logic_vector(s33(WIDTH-1 downto 0));
        cc  := s33(WIDTH);          -- borrow
        cvv := '1';
      when ALU_AND =>
        r := a and b;
      when ALU_SHL | ALU_SHR =>
        if op = ALU_SHL then
          x := reverse(unsigned(a));
        else
          x := unsigned(a);
        end if;
        sh := shift_right(x, k);
        if k > 0 then
          cc  := x(k-1);
          cvv := '1';
        end if;
        if op = ALU_SHL then
          r := std_logic_vector(reverse(sh));
        else
          r := std_logic_vector(sh);
        end if;
      when ALU_PASSB =>
        r := b;
      when ALU_SETC =>
        r   := a;
        cc  := '1';
        cvv := '1';
      when others =>
        r := a;
    end case;

    y_i <= r;
    c   <= cc;
    cv  <= cvv;
  end process;

  y <= y_i;
  z <= '1' when y_i = WORD_ZERO else '0';
  n <= y_i(WIDTH-1);

end architecture rtl;
