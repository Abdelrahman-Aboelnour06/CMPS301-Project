Python 3 models used for this audit (no dependencies). These are NOT a simulator of the VHDL;
they are an independent ISA model plus a hand transliteration of rtl/top.vhd.
  python3 run_tbs.py          # TB programs: RTL model vs ISA model vs TB expected values
  python3 fuzz.py 2000 0.05   # random differential test, 5% INTR.IN pulse rate
  python3 targeted.py         # BUG-001 / BUG-002 reproductions
  python3 trace.py            # load-use pipeline traces (distance 1..3)
run_tbs.py reads ../cmps301/programs/demo.mem via an absolute path; edit load_mem_file() path if needed.
Fix flags in Rtl(..., fix=...): 'starve' = BUG-001 fix, 'irqlatch2' = BUG-002 fix as in the patch.
