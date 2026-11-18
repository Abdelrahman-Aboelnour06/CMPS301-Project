#!/usr/bin/env python3
"""Rename inter-stage record fields and top.vhd internal signals to verbose,
self-documenting names.

Run from the repo root:   python rename_rtl_signals.py
Touches rtl/*.vhd, tb/*.vhd, and scripts/questa_run.do.
Safe to run twice (idempotent).
"""
import glob
import re

# 1. Inter-stage record fields (if_d_t, d_x1_t, x1_x2_t, x2_m_t, m_w_t)
RECORD_FIELD_RENAME = {
    "valid":   "is_valid",
    "is_vec":  "is_interrupt_vector",
    "pc":      "program_counter",
    "pc1":     "next_program_counter",
    "ctrl":    "control",
    "a":       "operand_a",
    "b":       "operand_b",
    "ra1":     "read_addr_1",
    "ra2":     "read_addr_2",
    "wa1":     "write_addr_1",
    "wa2":     "write_addr_2",
    "imm":     "immediate",
    "imm_u":   "immediate_unsigned",
    "link":    "link_address",
    "res1":    "result_1",
    "res2":    "result_2",
}

# 2. Internal signals in rtl/top.vhd (and wave paths in scripts/questa_run.do)
TOP_SIGNAL_RENAME = {
    "pc_q":           "current_pc",
    "pc_p1":          "pc_plus_1",
    "pc_next":        "next_pc",
    "pc_src":         "pc_select",
    "pc_en":          "pc_write_enable",
    "ram_addr_a":     "fetch_ram_addr",
    "ram_en_a":       "fetch_ram_enable",
    "q_a":            "fetch_ram_data",
    "q_b":            "mem_ram_data",
    "instr":          "instruction_word",
    "d_real":         "decode_is_real_instr",
    "d_vec_word":     "decode_is_vector_word",
    "d_inject":       "decode_inject_irq",
    "d_ra1":          "decode_read_addr_1",
    "d_ra2":          "decode_read_addr_2",
    "rf_rd1":         "regfile_read_data_1",
    "rf_rd2":         "regfile_read_data_2",
    "d_imm":          "decode_immediate",
    "d_imm_u":        "decode_immediate_unsigned",
    "d_imm_z":        "decode_jump_target_imm",
    "d_link":         "decode_link_address",
    "d_vec_int":      "decode_sw_int_vector_addr",
    "d_target":       "decode_branch_target",
    "d_redirect_req": "decode_redirect_request",
    "fa":             "forwarded_operand_a",
    "fb":             "forwarded_operand_b",
    "fsel_a":         "forward_select_a",
    "fsel_b":         "forward_select_b",
    "x1_res1":        "execute1_result_1",
    "x2_base":        "execute2_base_addr",
    "x2_ea":          "execute2_effective_addr",
    "sp_val":         "stack_pointer_value",
    "sp_addr":        "stack_pointer_mem_addr",
    "x2_maddr":       "execute2_mem_addr",
    "x2_sdata":       "execute2_store_data",
    "m_final":        "memory_stage_result",
    "ifd":            "if_d_reg",
    "dx1":            "d_x1_reg",
    "x1x2":           "x1_x2_reg",
    "x2m":            "x2_m_reg",
    "mw":             "m_w_reg",
}

REC_ALT = "|".join(sorted(RECORD_FIELD_RENAME, key=len, reverse=True))
TOP_ALT = "|".join(sorted(TOP_SIGNAL_RENAME, key=len, reverse=True))

member_re = re.compile(r"(?<!\bwork\.)(?<=\.)(" + REC_ALT + r")\b")
# For top.vhd signals, replace only on RHS/LHS identifiers (not port names before '=>')
top_ident_re = re.compile(r"\b(" + TOP_ALT + r")\b(?!\s*=>)")
wave_ident_re = re.compile(r"(?<=/dut/)(" + TOP_ALT + r")\b")

PAD = 22
ALL_REC_FIELDS = set(RECORD_FIELD_RENAME) | set(RECORD_FIELD_RENAME.values())


def region_rename_records(lines, start_pat, end_pat):
    out, inside = [], False
    for ln in lines:
        if not inside and re.search(start_pat, ln):
            inside = True
        if inside:
            m = re.match(r"^(\s+)(\w+)(\s*=>\s*)(.*)$", ln)
            d = re.match(r"^(\s+)(\w+)(\s*:\s*)(.*)$", ln)
            if m and m.group(2) in ALL_REC_FIELDS:
                name = RECORD_FIELD_RENAME.get(m.group(2), m.group(2))
                ln = f"{m.group(1)}{name:<{PAD}}=> {m.group(4)}"
            elif d and d.group(2) in ALL_REC_FIELDS:
                name = RECORD_FIELD_RENAME.get(d.group(2), d.group(2))
                ln = f"{d.group(1)}{name:<{PAD}}: {d.group(4)}"
            if re.search(end_pat, ln):
                inside = False
        out.append(ln)
    return out


def process_file(path):
    src = open(path, newline="").read()
    nl = "\r\n" if "\r\n" in src else "\n"
    lines = src.replace("\r\n", "\n").split("\n")

    if path.endswith(".do"):
        lines = [member_re.sub(lambda m: RECORD_FIELD_RENAME[m.group(1)], l) if not l.lstrip().startswith("--") else l for l in lines]
        lines = [wave_ident_re.sub(lambda m: TOP_SIGNAL_RENAME[m.group(1)], l) for l in lines]
    else:
        # Rename rec.field across all rtl/*.vhd and tb/*.vhd
        lines = [member_re.sub(lambda m: RECORD_FIELD_RENAME[m.group(1)], l) for l in lines]

        if path.endswith("cpu_pkg.vhd"):
            for rec in ("if_d_t", "d_x1_t", "x1_x2_t", "x2_m_t", "m_w_t"):
                lines = region_rename_records(lines, rf"type\s+{rec}\s+is\s+record", r"end\s+record")
            for cst in ("IF_D_NOP", "D_X1_NOP", "X1_X2_NOP", "X2_M_NOP", "M_W_NOP"):
                lines = region_rename_records(lines, rf"constant\s+{cst}\b", r"\);")

        if path.endswith("top.vhd"):
            for agg in ("ifd_in", "dx1_in", "x1x2_in", "x2m_in", "mw_in"):
                lines = region_rename_records(lines, rf"^\s*{agg}\s*<=\s*\(", r"\);")
            lines = [
                top_ident_re.sub(lambda m: TOP_SIGNAL_RENAME[m.group(1)], l)
                if not l.lstrip().startswith("--")
                else l
                for l in lines
            ]

    new = nl.join(lines)
    if new != src:
        open(path, "w", newline="").write(new)
        print("updated", path)


if __name__ == "__main__":
    targets = sorted(glob.glob("rtl/*.vhd") + glob.glob("tb/*.vhd"))
    if glob.glob("scripts/questa_run.do"):
        targets.append("scripts/questa_run.do")
    for p in targets:
        process_file(p)