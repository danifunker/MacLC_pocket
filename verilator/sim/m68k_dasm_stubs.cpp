/*
 * Stub memory callbacks for Musashi 68000 disassembler
 * Used when disassembling with m68k_disassemble_raw() which provides its own data
 */

#include "m68k_dasm.h"

extern "C" {

/* These stubs are called when using m68k_disassemble() directly.
 * When using m68k_disassemble_raw(), the disassembler reads from
 * the provided opdata buffer instead, so these won't be called.
 * Return 0 as a safe fallback.
 */

unsigned int m68k_read_disassembler_8(unsigned int address) {
    (void)address;
    return 0;
}

unsigned int m68k_read_disassembler_16(unsigned int address) {
    (void)address;
    return 0;
}

unsigned int m68k_read_disassembler_32(unsigned int address) {
    (void)address;
    return 0;
}

} /* extern "C" */

/*
 * Helper function to disassemble a single instruction
 * opcode_word: the first 16-bit opcode word
 * pc: the program counter value
 * Returns: disassembled instruction string (static buffer)
 */
static char dasm_buffer[256];

const char* disassemble_68k(unsigned int pc, unsigned short opcode_word) {
    /* Build a small buffer with the opcode word followed by zeros
     * This handles single-word instructions correctly.
     * Multi-word instructions may show incomplete operands but
     * the mnemonic will still be correct.
     */
    unsigned char opdata[16] = {0};
    opdata[0] = (opcode_word >> 8) & 0xFF;  /* High byte */
    opdata[1] = opcode_word & 0xFF;         /* Low byte */

    m68k_disassemble_raw(dasm_buffer, pc, opdata, opdata, M68K_CPU_TYPE_68020);

    return dasm_buffer;
}

/*
 * Extended helper that accepts multiple opcode words for complete disassembly
 * opwords: array of up to 5 16-bit words (enough for any 68000 instruction)
 * num_words: number of valid words in the array
 * pc: the program counter value
 */
const char* disassemble_68k_ext(unsigned int pc, const unsigned short* opwords, int num_words) {
    unsigned char opdata[16] = {0};

    /* Convert 16-bit words to byte array (big-endian) */
    for (int i = 0; i < num_words && i < 5; i++) {
        opdata[i*2]     = (opwords[i] >> 8) & 0xFF;
        opdata[i*2 + 1] = opwords[i] & 0xFF;
    }

    m68k_disassemble_raw(dasm_buffer, pc, opdata, opdata, M68K_CPU_TYPE_68020);

    return dasm_buffer;
}

const char* disassemble_68k_ext_len(unsigned int pc, const unsigned short* opwords, int num_words, unsigned int* out_len) {
    unsigned char opdata[16] = {0};

    for (int i = 0; i < num_words && i < 5; i++) {
        opdata[i*2]     = (opwords[i] >> 8) & 0xFF;
        opdata[i*2 + 1] = opwords[i] & 0xFF;
    }

    unsigned int len = m68k_disassemble_raw(dasm_buffer, pc, opdata, opdata, M68K_CPU_TYPE_68020);
    if (out_len) *out_len = len;
    return dasm_buffer;
}
