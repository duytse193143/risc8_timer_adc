#!/usr/bin/env python3
"""
sw/soc_asm.py - small assembler for the RISC-8 CPU (same ISA as project 2)

Usage:   python sw/soc_asm.py sw/soc_demo.s soc_demo.hex

Syntax:  label:   OPCODE operands   ; comment
         LDI R1, 0x3C | ADD R1, R2, R3 | SHL R1, R2 | LD R1, [R2] | ST R1, [R2]
         JMP/BZ/BNZ label_or_number | NOP | HLT
Output:  256 lines of 4 hex digits, with "// addr: source" comments,
         the same format as program.hex (read by $readmemh in imem.v).
"""
import re
import sys

OPS = {"NOP": 0x0, "ADD": 0x1, "SUB": 0x2, "AND": 0x3, "OR": 0x4, "XOR": 0x5,
       "SHL": 0x6, "SHR": 0x7, "LDI": 0x8, "ADDI": 0x9, "LD": 0xA, "ST": 0xB,
       "JMP": 0xC, "BZ": 0xD, "BNZ": 0xE, "HLT": 0xF}


def reg(tok):
    m = re.fullmatch(r"\[?R([0-7])\]?", tok.strip().upper())
    if not m:
        raise ValueError(f"bad register '{tok}'")
    return int(m.group(1))


def num(tok, labels):
    tok = tok.strip()
    if tok in labels:
        return labels[tok]
    v = int(tok, 0)
    if not 0 <= v <= 255:
        raise ValueError(f"value out of range '{tok}'")
    return v


def parse(lines):
    prog, labels = [], {}
    for line in lines:
        code = line.split(";")[0].strip()
        if not code:
            continue
        m = re.match(r"^(\w+):\s*(.*)$", code)
        if m:
            labels[m.group(1)] = len(prog)
            code = m.group(2).strip()
            if not code:
                continue
        prog.append(code)
    return prog, labels


def encode(text, labels):
    parts = text.split(None, 1)
    op = parts[0].upper()
    args = [a.strip() for a in parts[1].split(",")] if len(parts) > 1 else []
    oc = OPS[op] << 12
    if op in ("NOP", "HLT"):
        return oc
    if op in ("ADD", "SUB", "AND", "OR", "XOR"):
        return oc | reg(args[0]) << 9 | reg(args[1]) << 6 | reg(args[2]) << 3
    if op in ("SHL", "SHR", "LD", "ST"):
        return oc | reg(args[0]) << 9 | reg(args[1]) << 6
    if op in ("LDI", "ADDI"):
        return oc | reg(args[0]) << 9 | num(args[1], labels)
    if op in ("JMP", "BZ", "BNZ"):
        return oc | num(args[0], labels)
    raise ValueError(f"unknown instruction '{text}'")


def main():
    src, dst = sys.argv[1], sys.argv[2]
    with open(src) as f:
        prog, labels = parse(f.readlines())
    if len(prog) > 256:
        sys.exit("program too long (max 256 instructions)")
    out = []
    for i, text in enumerate(prog):
        out.append(f"{encode(text, labels):04X}  // {i:02X}: {' '.join(text.split())}")
    out += ["0000"] * (256 - len(prog))
    with open(dst, "w") as f:
        f.write("\n".join(out) + "\n")
    print(f"{src}: {len(prog)} instructions -> {dst}")


if __name__ == "__main__":
    main()
