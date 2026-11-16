-------------------------------------------------------------------------------
-- tb_instr_mem.vhd -- directed self-checking testbench for instr_mem.vhd
-- Checked alone (address truncation PC[11:0], enable = not hold, data
-- pass-through) and together with data_mem Port A to show a real fetch,
-- the hold behaviour on a stall, and the 4095 / 4096-wrap boundaries.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cpu_pkg.all;
use work.tb_pkg.all;

entity tb_instr_mem is
end entity tb_instr_mem;

architecture sim of tb_instr_mem is
  function init_img return mem_t is
    variable m : mem_t := MEM_ZERO;
  begin
    for i in 0 to MEMDEPTH-1 loop
      m(i) := std_logic_vector(to_unsigned(i * 3 + 7, 32));
    end loop;
    return m;
  end function;
  constant IMG : mem_t := init_img;

  signal clk      : std_logic := '0';
  signal pc       : word_t := (others => '0');
  signal hold     : std_logic := '0';
  signal ram_addr : maddr_t;
  signal ram_en   : std_logic;
  signal ram_q    : word_t;
  signal instr    : word_t;
  signal addr_b   : maddr_t := (others => '0');
  signal din_b    : word_t := (others => '0');
  signal we_b     : std_logic := '0';
  signal q_b      : word_t;
begin
  clk <= not clk after 5 ns;

  dut : entity work.instr_mem
    port map (pc => pc, hold => hold, ram_addr => ram_addr, ram_en => ram_en,
              ram_q => ram_q, instr => instr);

  ram : entity work.data_mem
    generic map (INIT => IMG)
    port map (clk => clk, addr_a => ram_addr, en_a => ram_en, q_a => ram_q,
              addr_b => addr_b, we_b => we_b, din_b => din_b, q_b => q_b);

  stim : process
    variable errs : natural := 0;
    procedure tick is
    begin
      wait until rising_edge(clk);
      wait for 1 ns;
    end procedure;
  begin
    -- combinational wrapper behaviour
    pc <= x"00001234"; hold <= '0';
    wait for 1 ns;
    check_eq(ram_addr, x"234", "PC[11:0]", errs);
    check_sl(ram_en, '1', "enable when not held", errs);
    hold <= '1';
    wait for 1 ns;
    check_sl(ram_en, '0', "disable when held", errs);
    check_eq(instr, ram_q, "instr = ram_q", errs);

    -- fetch sequence through the real RAM
    hold <= '0';
    pc <= x"00000000"; tick;
    check_eq(instr, IMG(0), "fetch M[0]", errs);
    pc <= x"00000001"; tick;
    check_eq(instr, IMG(1), "fetch M[1]", errs);
    pc <= x"00000FFF"; tick;
    check_eq(instr, IMG(4095), "fetch M[4095]", errs);
    pc <= x"00001000"; tick;
    check_eq(instr, IMG(0), "PC=4096 wraps to M[0]", errs);

    -- hold: word stays while PC changes
    pc <= x"00000005"; tick;
    check_eq(instr, IMG(5), "fetch M[5]", errs);
    hold <= '1'; pc <= x"00000006"; tick;
    check_eq(instr, IMG(5), "held M[5]", errs);
    tick;
    check_eq(instr, IMG(5), "still held", errs);
    hold <= '0'; tick;
    check_eq(instr, IMG(6), "released -> M[6]", errs);

    finish_tb("tb_instr_mem", errs);
    wait;
  end process;
end architecture sim;
