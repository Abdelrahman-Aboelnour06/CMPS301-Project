-------------------------------------------------------------------------------
-- tb_system.vhd -- system test: run an assembled program from a .mem file
-- to HLT and compare the final architectural state with a golden file.
--
-- Generics (override with ghdl -gNAME=VALUE or vsim -gNAME=VALUE):
--   MEM_FILE    : program image (.mem format, see README.md)
--   GOLDEN_FILE : expected state, lines "NAME HEX" with NAME in
--                 R0..R7, SP, CCR, OUT, PC (any subset; '#' = comment)
--   IN_VALUE    : constant value driven on IN.PORT (hex string, 8 digits)
--   IRQ_CYCLE   : cycle (after reset release) of a one-cycle INTR.IN pulse;
--                 a negative value disables the pulse
--   MAX_CYCLES  : timeout
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.cpu_pkg.all;
use work.tb_pkg.all;

entity tb_system is
  generic (
    MEM_FILE    : string  := "programs/demo.mem";
    GOLDEN_FILE : string  := "programs/demo.golden";
    IN_VALUE    : string  := "00000000";
    IRQ_CYCLE   : integer := -1;
    MAX_CYCLES  : natural := 200000
  );
end entity tb_system;

architecture sim of tb_system is

  function hexval(c : character) return integer is
  begin
    case c is
      when '0' to '9' => return character'pos(c) - character'pos('0');
      when 'a' to 'f' => return character'pos(c) - character'pos('a') + 10;
      when 'A' to 'F' => return character'pos(c) - character'pos('A') + 10;
      when others     => return -1;
    end case;
  end function;

  function hex2word(s : string) return word_t is
    variable v : unsigned(31 downto 0) := (others => '0');
    variable d : integer;
  begin
    for i in s'range loop
      d := hexval(s(i));
      if d >= 0 then
        v := v(27 downto 0) & to_unsigned(d, 4);
      end if;
    end loop;
    return std_logic_vector(v);
  end function;

  -- .mem loader: hex words, "@addr" directives, comments (#, /, ;)
  impure function load_mem(fname : string) return mem_t is
    file f       : text;
    variable st  : file_open_status;
    variable l   : line;
    variable m   : mem_t := MEM_ZERO;
    variable a   : natural := 0;
    variable ch  : character;
    variable ok  : boolean;
    variable v   : unsigned(31 downto 0);
    variable d   : integer;
    variable nd  : natural;
    variable isa : boolean;
  begin
    file_open(st, f, fname, read_mode);
    assert st = open_ok report "tb_system: cannot open " & fname severity failure;
    while not endfile(f) loop
      readline(f, l);
      v := (others => '0'); nd := 0; isa := false;
      loop
        read(l, ch, ok);
        exit when not ok;
        if nd = 0 and not isa and (ch = ' ' or ch = HT) then
          next;
        elsif nd = 0 and not isa and (ch = '#' or ch = '/' or ch = ';') then
          exit;
        elsif nd = 0 and not isa and ch = '@' then
          isa := true;
        else
          d := hexval(ch);
          exit when d < 0;
          v := v(27 downto 0) & to_unsigned(d, 4);
          nd := nd + 1;
        end if;
      end loop;
      if nd > 0 then
        if isa then
          a := to_integer(v(MEMINDEX-1 downto 0));
        else
          m(a) := std_logic_vector(v);
          a := (a + 1) mod MEMDEPTH;
        end if;
      end if;
      deallocate(l);
    end loop;
    file_close(f);
    return m;
  end function;

  constant PROG : mem_t := load_mem(MEM_FILE);

  signal clk      : std_logic := '0';
  signal reset    : std_logic := '1';
  signal intr_in  : std_logic := '0';
  signal in_port  : word_t := hex2word(IN_VALUE);
  signal out_port : word_t;
  signal regs     : reg_array_t;
  signal rmap     : rename_map_t;
  signal R_logical : reg_array_t;
  signal pc_out   : word_t;
  signal sp_out   : word_t;
  signal ccr_out  : std_logic_vector(3 downto 0);
  signal halted   : std_logic;
  signal cycle    : natural := 0;
begin
  clk <= not clk after 5 ns;

  rmap <= << signal dut.rename_map : rename_map_t >>;
  gen_logical_r : for i in 0 to 7 generate
    R_logical(i) <= regs(to_integer(unsigned(rmap(i))));
  end generate;

  dut : entity work.top
    generic map (PROG => PROG)
    port map (clk => clk, reset => reset, intr_in => intr_in, in_port => in_port,
              out_port => out_port, R_values => regs, pc_out => pc_out,
              sp_out => sp_out, ccr_out => ccr_out, halted => halted);

  process (clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        cycle <= 0;
      else
        cycle <= cycle + 1;
      end if;
    end if;
  end process;

  intr_in <= '1' when IRQ_CYCLE >= 0 and cycle = IRQ_CYCLE and reset = '0' else '0';

  stim : process
    file gf       : text;
    variable st   : file_open_status;
    variable l    : line;
    variable errs : natural := 0;
    variable n    : natural := 0;
    variable ch   : character;
    variable ok   : boolean;
    variable name : string(1 to 8);
    variable nl   : natural;
    variable hs   : string(1 to 8);
    variable hl   : natural;
    variable exp  : word_t;
    variable got  : word_t;
    variable known : boolean;
    variable nchk : natural := 0;
    variable o    : line;
  begin
    for i in 1 to 3 loop
      wait until rising_edge(clk);
    end loop;
    reset <= '0';
    while halted /= '1' and n < MAX_CYCLES loop
      wait until rising_edge(clk);
      n := n + 1;
    end loop;
    check(halted = '1', "program reached HLT within MAX_CYCLES", errs);
    for i in 1 to 8 loop
      wait until rising_edge(clk);
    end loop;
    wait for 1 ns;

    write(o, string'("tb_system: " & MEM_FILE & " halted after " &
                     integer'image(n) & " cycles"));
    writeline(output, o);

    file_open(st, gf, GOLDEN_FILE, read_mode);
    assert st = open_ok report "tb_system: cannot open " & GOLDEN_FILE severity failure;
    while not endfile(gf) loop
      readline(gf, l);
      name := (others => ' '); nl := 0;
      hs := (others => '0'); hl := 0;
      -- name token
      loop
        read(l, ch, ok);
        exit when not ok;
        if ch = '#' and nl = 0 then
          ok := false;
          exit;
        end if;
        if ch = ' ' or ch = HT then
          exit when nl > 0;
        elsif nl < name'length then
          nl := nl + 1;
          name(nl) := ch;
        end if;
      end loop;
      -- value token
      if nl > 0 then
        loop
          read(l, ch, ok);
          exit when not ok;
          if hexval(ch) >= 0 then
            if hl < hs'length then
              hl := hl + 1;
              hs(hl) := ch;
            end if;
          else
            exit when hl > 0;
          end if;
        end loop;
      end if;
      deallocate(l);

      if nl > 0 and hl > 0 then
        exp := hex2word(hs(1 to hl));
        known := true;
        if    name(1 to nl) = "R0" then got := regs(to_integer(unsigned(rmap(0))));
        elsif name(1 to nl) = "R1" then got := regs(to_integer(unsigned(rmap(1))));
        elsif name(1 to nl) = "R2" then got := regs(to_integer(unsigned(rmap(2))));
        elsif name(1 to nl) = "R3" then got := regs(to_integer(unsigned(rmap(3))));
        elsif name(1 to nl) = "R4" then got := regs(to_integer(unsigned(rmap(4))));
        elsif name(1 to nl) = "R5" then got := regs(to_integer(unsigned(rmap(5))));
        elsif name(1 to nl) = "R6" then got := regs(to_integer(unsigned(rmap(6))));
        elsif name(1 to nl) = "R7" then got := regs(to_integer(unsigned(rmap(7))));
        elsif name(1 to nl) = "SP" then got := sp_out;
        elsif name(1 to nl) = "CCR" then got := x"0000000" & ccr_out;
        elsif name(1 to nl) = "OUT" then got := out_port;
        elsif name(1 to nl) = "PC" then got := pc_out;
        else
          known := false;
          got := (others => '0');
        end if;
        check(known, "unknown golden key " & name(1 to nl), errs);
        if known then
          check_eq(got, exp, name(1 to nl), errs);
          nchk := nchk + 1;
        end if;
      end if;
    end loop;
    file_close(gf);
    check(nchk > 0, "golden file contained no checks", errs);
    finish_tb("tb_system", errs);
    wait;
  end process;
end architecture sim;
