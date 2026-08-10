/*
 * Minimal header for Musashi 68000 disassembler
 * For use in MacLC Verilator simulation
 */

#ifndef M68K_DASM_H
#define M68K_DASM_H

#ifdef __cplusplus
extern "C" {
#endif

/* CPU types - matches Musashi m68k.h */
enum {
    M68K_CPU_TYPE_INVALID,
    M68K_CPU_TYPE_68000,
    M68K_CPU_TYPE_68010,
    M68K_CPU_TYPE_68EC020,
    M68K_CPU_TYPE_68020,
    M68K_CPU_TYPE_68EC030,
    M68K_CPU_TYPE_68030,
    M68K_CPU_TYPE_68EC040,
    M68K_CPU_TYPE_68LC040,
    M68K_CPU_TYPE_68040,
    M68K_CPU_TYPE_SCC68070
};

/* Disassembler functions */
unsigned int m68k_disassemble(char* str_buff, unsigned int pc, unsigned int cpu_type);
unsigned int m68k_disassemble_raw(char* str_buff, unsigned int pc,
    const unsigned char* opdata, const unsigned char* argdata,
    unsigned int cpu_type);

/* Memory read callbacks - must be provided by the application */
unsigned int m68k_read_disassembler_8(unsigned int address);
unsigned int m68k_read_disassembler_16(unsigned int address);
unsigned int m68k_read_disassembler_32(unsigned int address);

#ifdef __cplusplus
}

/* C++ helper functions for easy disassembly */

/* Disassemble a single instruction given just the first opcode word.
 * Works correctly for single-word instructions.
 * Multi-word instructions will show mnemonic but may have incomplete operands.
 */
const char* disassemble_68k(unsigned int pc, unsigned short opcode_word);

/* Extended disassembly with multiple opcode words for complete decoding.
 * opwords: array of up to 5 16-bit words
 * num_words: number of valid words in the array
 */
const char* disassemble_68k_ext(unsigned int pc, const unsigned short* opwords, int num_words);

/* Disassemble and also return instruction length in bytes (2, 4, 6, ...).
 * out_len receives the Musashi-reported length.
 */
const char* disassemble_68k_ext_len(unsigned int pc, const unsigned short* opwords, int num_words, unsigned int* out_len);

#endif /* __cplusplus */

#endif /* M68K_DASM_H */
