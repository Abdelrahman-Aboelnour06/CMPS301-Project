// CMPS 301 assembler: prog.s -> prog.mem, prog.mif, prog.golden
// build:  gcc -o asm asm.c
// usage:  asm prog.s [IN_hex ...]
//   IN_hex : IN.PORT value used for the golden (default 0000ABCD). One value = constant.
//            Several values = the 1st IN instruction executed reads the 1st value, the 2nd reads the 2nd, ...
//            and the last value repeats.
// a taken JZ/JN/JC clears the tested flag, as the spec says
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#define MEMSIZE 4096
#define MAXLABELS 1024
#define MAXTOKENS 8
#define MAXSTEPS 1000000

enum opcodes {
    OP_NOP = 0x00, OP_NOT = 0x01, OP_INC = 0x02, OP_OUT = 0x04, OP_IN = 0x05, OP_SETC = 0x06, OP_HLT = 0x07,
    OP_MOV = 0x10, OP_SWAP = 0x11, OP_ADD = 0x12, OP_SUB = 0x13, OP_AND = 0x14, OP_CMP = 0x15,
    OP_SHR = 0x16, OP_SHL = 0x17, OP_IADD = 0x18,
    OP_PUSH = 0x20, OP_POP = 0x21, OP_LDM = 0x22, OP_LDD = 0x23, OP_STD = 0x24,
    OP_JMP = 0x30, OP_JZ = 0x31, OP_JN = 0x32, OP_JC = 0x33, OP_CALL = 0x34, OP_RET = 0x35,
    OP_RTI = 0x36, OP_INT = 0x37
};

enum forms { NONE, RD, RS, RD_RS, REG3, CMPF, SHIFT, IADDF, LDMF, MEMF, JUMP, INTF };

struct mnemonic {
    char name[8];
    int opcode;
    int form;
};

struct mnemonic table[] = {
    {"NOP", OP_NOP, NONE}, {"NOT", OP_NOT, RD}, {"INC", OP_INC, RD}, {"OUT", OP_OUT, RS},
    {"IN", OP_IN, RD}, {"SETC", OP_SETC, NONE}, {"HLT", OP_HLT, NONE},
    {"MOV", OP_MOV, RD_RS}, {"SWAP", OP_SWAP, RD_RS}, {"ADD", OP_ADD, REG3}, {"SUB", OP_SUB, REG3},
    {"AND", OP_AND, REG3}, {"CMP", OP_CMP, CMPF}, {"SHR", OP_SHR, SHIFT}, {"SHL", OP_SHL, SHIFT},
    {"IADD", OP_IADD, IADDF},
    {"PUSH", OP_PUSH, RS}, {"POP", OP_POP, RD}, {"LDM", OP_LDM, LDMF}, {"LDD", OP_LDD, MEMF},
    {"STD", OP_STD, MEMF},
    {"JMP", OP_JMP, JUMP}, {"JZ", OP_JZ, JUMP}, {"JN", OP_JN, JUMP}, {"JC", OP_JC, JUMP},
    {"CALL", OP_CALL, JUMP}, {"RET", OP_RET, NONE}, {"RTI", OP_RTI, NONE}, {"INT", OP_INT, INTF}
};
#define TABLESIZE (int)(sizeof(table) / sizeof(table[0]))

// assembler state
unsigned int memory[MEMSIZE];
int used[MEMSIZE];
char text[MEMSIZE][64];
char labelname[MAXLABELS][32];
int labeladdr[MAXLABELS];
int labelcount = 0;
int address = 0;
int linenumber = 0;
char *filename;

// emulator state
unsigned int ram[MEMSIZE];
unsigned int reg[8];
unsigned int sp, pc, outport;
unsigned int inlist[64] = {0xABCD};
int incount = 1;
int inreads = 0;
int flagZ, flagN, flagC;
int shadowZ, shadowN, shadowC;


void error(char *msg, char *what) {
    fprintf(stderr, "%s:%d: %s %s\n", filename, linenumber, msg, what);
    exit(-1);
}

int findlabel(char *name) {
    for (int i = 0; i < labelcount; i++)
        if (strcmp(labelname[i], name) == 0)
            return i;
    return -1;
}

void addlabel(char *name) {
    if (findlabel(name) != -1)
        error("label defined twice:", name);
    if (labelcount == MAXLABELS)
        error("too many labels", "");
    strncpy(labelname[labelcount], name, 31);
    labeladdr[labelcount] = address;
    labelcount++;
}

long long getvalue(char *token) {
    int index = findlabel(token);
    if (index != -1)
        return labeladdr[index];
    char *end;
    long long value = strtoll(token, &end, 16);
    if (*end != '\0' || end == token)
        error("bad number or unknown label:", token);
    return value;
}

int getreg(char *token) {
    if (token[0] != 'R' || token[1] < '0' || token[1] > '7' || token[2] != '\0')
        error("bad register:", token);
    return token[1] - '0';
}

unsigned int getimm(char *token) {
    long long value = getvalue(token);
    if (value >= 0xFFFF8000LL && value <= 0xFFFFFFFFLL)
        value -= 0x100000000LL;  // 32-bit negative like 0FFFFFFF9
    if (value < -32768 || value > 65535)
        error("immediate does not fit in 16 bits:", token);
    return (unsigned int)value & 0xFFFF;
}

// LDM zero-extends its 16-bit immediate, so only 0000..FFFF is meaningful.
unsigned int getimm_unsigned(char *token) {
    long long value = getvalue(token);
    if (value < 0 || value > 0xFFFF)
        error("LDM immediate must be 0..FFFF (it is zero-extended):", token);
    return (unsigned int)value;
}

int findmnemonic(char *name) {
    for (int i = 0; i < TABLESIZE; i++)
        if (strcmp(table[i].name, name) == 0)
            return i;
    return -1;
}

int ishex(char *token) {
    for (int i = 0; token[i] != '\0'; i++)
        if (!isxdigit((unsigned char)token[i]))
            return 0;
    return 1;
}

int needed(int form) {
    if (form == NONE) return 1;
    if (form == RD || form == RS || form == JUMP || form == INTF) return 2;
    if (form == RD_RS || form == CMPF || form == SHIFT || form == LDMF) return 3;
    return 4;  // REG3, IADDF, MEMF
}

unsigned int encode(struct mnemonic m, char *t[], int count) {
    unsigned int word = (unsigned int)m.opcode << 26;
    if (count < needed(m.form))
        error("missing operands for", t[0]);

    if (m.form == RD)
        word |= getreg(t[1]) << 23;
    else if (m.form == RS)
        word |= getreg(t[1]) << 20;
    else if (m.form == RD_RS) {
        word |= getreg(t[1]) << 23;
        word |= getreg(t[2]) << 20;
    }
    else if (m.form == REG3) {
        word |= getreg(t[1]) << 23;
        word |= getreg(t[2]) << 20;
        word |= getreg(t[3]) << 17;
    }
    else if (m.form == CMPF) {
        word |= getreg(t[1]) << 20;
        word |= getreg(t[2]) << 17;
    }
    else if (m.form == SHIFT) {
        word |= getreg(t[1]) << 23;
        word |= getimm(t[2]) & 31;
    }
    else if (m.form == IADDF) {
        word |= getreg(t[1]) << 23;
        word |= getreg(t[2]) << 20;
        word |= getimm(t[3]);
    }
    else if (m.form == LDMF) {
        word |= getreg(t[1]) << 23;
        word |= getimm_unsigned(t[2]);
    }
    else if (m.form == MEMF) {
        // LDD Rd, off(Rs)  -> Rdst, Rsrc1 (base)      STD Rs1, off(Rs2) -> Rsrc1 (data), Rsrc2 (base)
        if (m.opcode == OP_LDD) {
            word |= getreg(t[1]) << 23;
            word |= getreg(t[3]) << 20;
        }
        else {
            word |= getreg(t[1]) << 20;
            word |= getreg(t[3]) << 17;
        }
        word |= getimm(t[2]);
    }
    else if (m.form == JUMP)
        word |= getimm(t[1]);
    else if (m.form == INTF) {
        long long index = getvalue(t[1]);
        if (index != 0 && index != 1)
            error("INT index must be 0 or 1:", t[1]);
        word |= (unsigned int)index << 16;
    }
    return word;
}

void place(unsigned int word, char *src) {
    if (address < 0 || address >= MEMSIZE)
        error("address out of range:", src);
    if (used[address])
        error("two words at the same address:", src);
    used[address] = 1;
    memory[address] = word;
    strncpy(text[address], src, 63);
    address++;
}

void parseline(char *line, int pass) {
    char code[256];
    char *tokens[MAXTOKENS];
    int count = 0;

    strncpy(code, line, 255);
    code[255] = '\0';
    for (int i = 0; code[i] != '\0'; i++) {
        if (code[i] == '#' || code[i] == ';') {
            code[i] = '\0';
            break;
        }
    }
    for (int i = 0; code[i] != '\0'; i++)
        code[i] = toupper((unsigned char)code[i]);

    // label: "name:" at the start, optional instruction after it
    char *start = code;
    char *colon = strchr(code, ':');
    if (colon != NULL) {
        *colon = '\0';
        char *name = strtok(code, " \t\r\n");
        if (name == NULL)
            error("empty label", "");
        if (pass == 1)
            addlabel(name);
        start = colon + 1;
    }

    // keep the instruction text for the .mem comments
    char src[64];
    while (*start == ' ' || *start == '\t')
        start++;
    strncpy(src, start, 63);
    src[63] = '\0';
    for (int i = (int)strlen(src) - 1; i >= 0 && isspace((unsigned char)src[i]); i--)
        src[i] = '\0';

    for (int i = 0; start[i] != '\0'; i++)
        if (start[i] == ',' || start[i] == '(' || start[i] == ')')
            start[i] = ' ';
    char *token = strtok(start, " \t\r\n");
    while (token != NULL && count < MAXTOKENS) {
        tokens[count++] = token;
        token = strtok(NULL, " \t\r\n");
    }
    if (count == 0)
        return;

    int index = findmnemonic(tokens[0]);
    if (strcmp(tokens[0], ".ORG") == 0) {
        if (count < 2)
            error("missing address for", ".ORG");
        address = (int)getvalue(tokens[1]);
    }
    else if (strcmp(tokens[0], ".WORD") == 0) {
        if (count < 2)
            error("missing value for", ".WORD");
        unsigned int word = 0;
        if (pass == 2)
            word = (unsigned int)getvalue(tokens[1]);
        place(word, src);
    }
    else if (index != -1) {
        unsigned int word = 0;
        if (pass == 2)
            word = encode(table[index], tokens, count);
        place(word, src);
    }
    else if (count == 1 && ishex(tokens[0]))
        place((unsigned int)strtoul(tokens[0], NULL, 16), src);
    else
        error("unknown instruction:", tokens[0]);
}

void readfile(FILE *f, int pass) {
    char line[256];
    address = 0;
    linenumber = 0;
    for (int i = 0; i < MEMSIZE; i++)
        used[i] = 0;
    rewind(f);
    while (fgets(line, sizeof(line), f) != NULL) {
        linenumber++;
        parseline(line, pass);
    }
}


// ---------------- emulator (golden model) ----------------

unsigned int sext16(unsigned int x) {
    x &= 0xFFFF;
    if (x & 0x8000)
        return x | 0xFFFF0000;
    return x;
}

unsigned int setZN(unsigned int y) {
    flagZ = (y == 0);
    flagN = (y >> 31) & 1;
    return y;
}

unsigned int addflags(unsigned int a, unsigned int b) {
    unsigned long long sum = (unsigned long long)a + b;
    flagC = (int)((sum >> 32) & 1);
    return setZN((unsigned int)sum);
}

unsigned int subflags(unsigned int a, unsigned int b) {
    flagC = (a < b);
    return setZN(a - b);
}

void push(unsigned int value) {
    sp--;
    ram[sp & 0xFFF] = value;
}

unsigned int pop() {
    unsigned int value = ram[sp & 0xFFF];
    sp++;
    return value;
}

void branch(int *flag, unsigned int target) {
    if (*flag) {
        pc = target;
        *flag = 0;
    }
}

unsigned int readin() {
    int k = inreads;
    if (k >= incount)
        k = incount - 1;
    inreads++;
    return inlist[k];
}

int runprogram() {
    for (int steps = 0; steps < MAXSTEPS; steps++) {
        unsigned int w = ram[pc & 0xFFF];
        int op = w >> 26;
        int rd = (w >> 23) & 7;
        int rs1 = (w >> 20) & 7;
        int rs2 = (w >> 17) & 7;
        int index = (w >> 16) & 1;
        unsigned int imm = w & 0xFFFF;
        int shift = imm & 31;
        unsigned int next = pc + 1;
        unsigned int y;

        pc = next;  // jumps overwrite it below
        switch (op) {
        case OP_HLT:
            return 1;
        case OP_NOT:
            reg[rd] = setZN(~reg[rd]);
            break;
        case OP_INC:
            reg[rd] = addflags(reg[rd], 1);
            break;
        case OP_OUT:
            outport = reg[rs1];
            break;
        case OP_IN:
            reg[rd] = readin();
            break;
        case OP_SETC:
            flagC = 1;
            break;
        case OP_MOV:
            reg[rd] = reg[rs1];
            break;
        case OP_SWAP:
            y = reg[rd];
            reg[rd] = reg[rs1];
            reg[rs1] = y;
            break;
        case OP_ADD:
            reg[rd] = addflags(reg[rs1], reg[rs2]);
            break;
        case OP_SUB:
            reg[rd] = subflags(reg[rs1], reg[rs2]);
            break;
        case OP_AND:
            reg[rd] = setZN(reg[rs1] & reg[rs2]);
            break;
        case OP_CMP:
            subflags(reg[rs1], reg[rs2]);
            break;
        case OP_SHR:
            if (shift > 0)
                flagC = (reg[rd] >> (shift - 1)) & 1;
            reg[rd] = setZN(reg[rd] >> shift);
            break;
        case OP_SHL:
            if (shift > 0)
                flagC = (reg[rd] >> (32 - shift)) & 1;
            reg[rd] = setZN(reg[rd] << shift);
            break;
        case OP_IADD:
            reg[rd] = addflags(reg[rs1], sext16(imm));
            break;
        case OP_PUSH:
            push(reg[rs1]);
            break;
        case OP_POP:
            reg[rd] = pop();
            break;
        case OP_LDM:
            reg[rd] = imm;                // zero-extended (matches rtl/top.vhd d_imm)
            break;
        case OP_LDD:
            reg[rd] = ram[(reg[rs1] + sext16(imm)) & 0xFFF];
            break;
        case OP_STD:
            ram[(reg[rs2] + sext16(imm)) & 0xFFF] = reg[rs1];
            break;
        case OP_JMP:
            pc = imm;
            break;
        case OP_JZ:
            branch(&flagZ, imm);
            break;
        case OP_JN:
            branch(&flagN, imm);
            break;
        case OP_JC:
            branch(&flagC, imm);
            break;
        case OP_CALL:
            push(next);
            pc = imm;
            break;
        case OP_RET:
            pc = pop();
            break;
        case OP_RTI:
            pc = pop();
            flagZ = shadowZ;
            flagN = shadowN;
            flagC = shadowC;
            break;
        case OP_INT:
            push(next);
            shadowZ = flagZ;
            shadowN = flagN;
            shadowC = flagC;
            pc = ram[2 + index];
            break;
        default:
            break;  // undefined opcode = NOP
        }
    }
    return 0;
}


// ---------------- output files ----------------

FILE *openout(char *base, char *ext) {
    char name[300];
    sprintf(name, "%s.%s", base, ext);
    FILE *f = fopen(name, "w");
    if (f == NULL) {
        perror(name);
        exit(-1);
    }
    return f;
}

void writemem(char *base) {
    FILE *f = openout(base, "mem");
    int last = -2;
    fprintf(f, "# %s.mem -- assembled from %s (all numbers hex)\n", base, filename);
    for (int a = 0; a < MEMSIZE; a++) {
        if (!used[a])
            continue;
        if (a != last + 1)
            fprintf(f, "@%03X\n", a);
        fprintf(f, "%08X    # %03X: %s\n", memory[a], a, text[a]);
        last = a;
    }
    fclose(f);
}

void writemif(char *base) {
    FILE *f = openout(base, "mif");
    fprintf(f, "-- %s.mif: Quartus memory initialisation file (4096 x 32)\n", base);
    fprintf(f, "WIDTH=32;\nDEPTH=4096;\nADDRESS_RADIX=HEX;\nDATA_RADIX=HEX;\nCONTENT BEGIN\n");
    fprintf(f, "  [000..FFF] : 00000000;\n");
    for (int a = 0; a < MEMSIZE; a++)
        if (used[a] && memory[a] != 0)
            fprintf(f, "  %03X : %08X;\n", a, memory[a]);
    fprintf(f, "END;\n");
    fclose(f);
}

void writegolden(char *base) {
    FILE *f = openout(base, "golden");
    fprintf(f, "# %s.golden -- expected final state of %s.mem (tb_system)\n", base, base);
    if (incount == 1)
        fprintf(f, "# Conditions: IN.PORT = %08X, IRQ_CYCLE = -1\n", inlist[0]);
    else {
        fprintf(f, "# Conditions: IRQ_CYCLE = -1, IN.PORT values in order:");
        for (int i = 0; i < incount; i++)
            fprintf(f, " %08X", inlist[i]);
        fprintf(f, "\n");
    }
    for (int i = 0; i < 8; i++)
        fprintf(f, "R%d  %08X\n", i, reg[i]);
    fprintf(f, "SP  %08X\n", sp);
    fprintf(f, "CCR %X\n", (flagC << 2) | (flagN << 1) | flagZ);
    fprintf(f, "OUT %08X\n", outport);
    fprintf(f, "PC  %08X\n", pc);
    fclose(f);
}

void removeextension(char *base) {
    int dot = -1;
    for (int i = 0; base[i] != '\0'; i++) {
        if (base[i] == '/' || base[i] == '\\')
            dot = -1;
        else if (base[i] == '.')
            dot = i;
    }
    if (dot != -1)
        base[dot] = '\0';
}

int main(int argc, char *argv[]) {
    char base[256];
    char *input = NULL;
    int given = 0;

    for (int i = 1; i < argc; i++) {
        if (input == NULL)
            input = argv[i];
        else if (incount < 64) {
            if (!given) {
                incount = 0;
                given = 1;
            }
            inlist[incount++] = (unsigned int)strtoull(argv[i], NULL, 16);
        }
    }
    if (input == NULL) {
        printf("usage: %s prog.s [IN_hex ...]\n", argv[0]);
        return -1;
    }

    filename = input;
    FILE *f = fopen(input, "r");
    if (f == NULL) {
        perror(input);
        exit(-1);
    }
    readfile(f, 1);
    readfile(f, 2);
    fclose(f);

    strncpy(base, input, 255);
    base[255] = '\0';
    removeextension(base);
    writemem(base);
    writemif(base);

    for (int a = 0; a < MEMSIZE; a++)
        ram[a] = memory[a];
    sp = 4095;
    pc = ram[0];
    if (!runprogram()) {
        printf("%s.mem and %s.mif written, but the program never halts: no golden\n", base, base);
        return 1;
    }
    writegolden(base);
    printf("wrote %s.mem, %s.mif, %s.golden\n", base, base, base);
    return 0;
}
