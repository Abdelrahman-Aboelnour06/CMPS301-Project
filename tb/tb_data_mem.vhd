-------------------------------------------------------------------------------
-- tb_data_mem.vhd -- directed self-checking testbench for data_mem.vhd
-- INIT image, Port-A / Port-B reads, Port-B write, write-first on the same
-- port, mixed-port write-first (fetch sees the store), Port-A enable hold,
-- simultaneous independent accesses, boundary addresses 0 and 4095.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cpu_pkg.all;
use work.tb_pkg.all;

entity tb_data_mem is
end entity tb_data_mem;

architecture sim of tb_data_mem is
  function init_img return mem_t is
    variable m : mem_t := MEM_ZERO;
  begin
    m(0)    := x"00000010";
    m(1)    := x"11111111";
    m(100)  := x"CAFEBABE";
    m(4095) := x"FFFFFFFF";
    return m;
  end function;

  signal clk    : std_logic := '0';
  signal addr_a : maddr_t := (others => '0');
  signal en_a   : std_logic := '1';
  signal q_a    : word_t;
  signal addr_b : maddr_t := (others => '0');
  signal we_b   : std_logic := '0';
  signal din_b  : word_t := (others => '0');
  signal q_b    : word_t;

  function a12(i : natural) return maddr_t is
  begin
    return std_logic_vector(to_unsigned(i, 12));
  end function;
begin
  clk <= not clk after 5 ns;

  dut : entity work.data_mem
    generic map (INIT => init_img)
    port map (clk => clk, addr_a => addr_a, en_a => en_a, q_a => q_a,
              addr_b => addr_b, we_b => we_b, din_b => din_b, q_b => q_b);

  stim : process
    variable errs : natural := 0;
    procedure tick is
    begin
      wait until rising_edge(clk);
      wait for 1 ns;
    end procedure;
  begin
    -- initial contents through both ports
    addr_a <= a12(0); addr_b <= a12(4095); tick;
    check_eq(q_a, x"00000010", "A reads M[0]", errs);
    check_eq(q_b, x"FFFFFFFF", "B reads M[4095]", errs);
    addr_a <= a12(100); addr_b <= a12(1); tick;
    check_eq(q_a, x"CAFEBABE", "A reads M[100]", errs);
    check_eq(q_b, x"11111111", "B reads M[1]", errs);

    -- write through B, same-port write-first
    addr_b <= a12(200); din_b <= x"12345678"; we_b <= '1'; tick;
    check_eq(q_b, x"12345678", "B write-first", errs);
    we_b <= '0'; tick;
    check_eq(q_b, x"12345678", "B reads back", errs);

    -- mixed-port write-first: A fetches the address B writes
    addr_a <= a12(300); addr_b <= a12(300); din_b <= x"0BADF00D"; we_b <= '1'; tick;
    check_eq(q_a, x"0BADF00D", "A sees new data (write-first)", errs);
    we_b <= '0'; tick;
    check_eq(q_a, x"0BADF00D", "A reads stored", errs);

    -- independent simultaneous accesses
    addr_a <= a12(100); addr_b <= a12(4095); din_b <= x"00000000"; we_b <= '1'; tick;
    check_eq(q_a, x"CAFEBABE", "A unaffected by other-address write", errs);
    check_eq(q_b, x"00000000", "B wrote M[4095]=0", errs);
    we_b <= '0';

    -- Port A enable low holds its output
    addr_a <= a12(1); en_a <= '0'; tick;
    check_eq(q_a, x"CAFEBABE", "en_a=0 holds q_a", errs);
    en_a <= '1'; tick;
    check_eq(q_a, x"11111111", "en_a=1 reads M[1]", errs);

    -- boundary address 0 written and read via A
    addr_b <= a12(0); din_b <= x"80000000"; we_b <= '1'; tick;
    we_b <= '0'; addr_a <= a12(0); tick;
    check_eq(q_a, x"80000000", "M[0] rewritten", errs);

    finish_tb("tb_data_mem", errs);
    wait;
  end process;
end architecture sim;
