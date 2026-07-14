#!/usr/bin/env python3
"""rars_import.py - Converte um dump de memória "compacta" do RARS
(Memory Segment .text e .data, dump format "Hexadecimal Text") para os
arquivos de ROM/RAM que ROM.vhd/RAM.vhd já sabem ler -- o mesmo formato
que assembler.py produz (1 palavra hex de 32 bits por linha, sem
prefixo, começando do endereço 0).

Por que um script Python separado, em vez de mexer no testbench (VHDL)
-----------------------------------------------------------------------
O modelo de memória compacto do RARS já separa instruções e dados em
espaços de endereço diferentes, como este projeto (arquitetura Harvard),
então a única diferença real está no FORMATO dos arquivos exportados:

  - .text: 1 palavra hex de 32 bits por linha, sem prefixo, começando do
    endereço 0x00000000 -- ou seja, já é EXATAMENTE o formato que
    ROM.vhd espera. Este script só valida e copia (não faz nenhuma
    conversão de endereço).

  - .data: cada linha traz um endereço absoluto na frente (a partir de
    0x00002000 no modelo compacto) seguido de várias palavras "0x..."
    na mesma linha -- bem diferente do formato "1 palavra por linha,
    sem prefixo, relativo ao endereço 0" que RAM.vhd/assembler.py usam.
    Este script extrai o endereço e as palavras de cada linha e
    reescreve como um arquivo de RAM no formato nativo.

Fazer esse parsing (endereços com prefixo "0x", número variável de
palavras por linha) em VHDL puro via std.textio seria bem mais frágil e
verboso do que em Python (HREAD não entende o prefixo "0x" nem lida bem
com "N campos por linha, N variável"). Por isso a conversão foi feita
aqui, como uma etapa separada ANTES de rodar o testbench -- que continua
funcionando exatamente como antes, sem nenhuma mudança, apontando
ROM_FILE/RAM_FILE para os arquivos gerados por este script.

Uso:
    python rars_import.py --text prog_text.txt --data prog_data.txt \\
        -o prog_rom.txt --ram prog_ram.txt

Depois, rode o testbench normalmente (ver README.md), com
-gROM_FILE="prog_rom.txt" -gRAM_FILE="prog_ram.txt".

ATENÇÃO -- branch/JAL usam uma codificação de imediato diferente daqui
-----------------------------------------------------------------------
Este processador NÃO usa a codificação padrão de imediato de BRANCH/JAL
do RV32I (ver item 2 do cabeçalho de assembler.py): o hardware sempre
multiplica por 2 o deslocamento decodificado (`shift_left(imm32OUT, 1)`
em CPU.vhd), então o assembler deste projeto grava offset/2 no lugar do
offset de verdade (`PC_REL_HALVED = True`). O RARS, sendo um simulador
RV32I padrão, gera o offset de verdade (sem dividir por 2). Importar um
dump do RARS sem ajustar isso faria todo desvio/salto pousar 2x mais
longe do que deveria.

Por isso, `import_rom_words` abaixo decodifica o offset de BRANCH/JAL de
cada instrução assumindo a codificação PADRÃO (a que o RARS realmente
usa) e recodifica com `encode_b`/`encode_j` de `assembler.py` -- que já
aplicam a divisão por 2 (`PC_REL_HALVED`, ligado por padrão neste
módulo). Nenhuma outra instrução muda: JALR usa o imediato "cru" (soma
direto na ULA, sem o `shift_left`), então seu offset já é idêntico nos
dois esquemas; R/I/S/U/ECALL nem têm imediato PC-relativo.
"""
import argparse
import sys

from assembler import (
    AssemblerError,
    DEFAULT_RAM_DEPTH,
    DEFAULT_ROM_DEPTH,
    OPCODE_BRANCH,
    OPCODE_JAL,
    encode_b,
    encode_j,
    write_intermediate_listing,
    write_ram_file,
    write_rom_file,
)

# Endereço base de .data no modelo de memória compacto do RARS. Fixo pela
# própria definição do modelo (não é algo que o usuário escolhe no RARS),
# mas fica configurável aqui por segurança/flexibilidade.
DEFAULT_DATA_BASE = 0x00002000


def parse_text_dump(path):
    """Lê o dump de .text do RARS: 1 palavra hex de 32 bits por linha, sem
    prefixo "0x", começando no endereço 0x00000000. Esse formato já é
    idêntico ao que ROM.vhd espera -- aqui só validamos e normalizamos
    (maiúsculas), linha por linha."""
    words = []
    with open(path, "r", encoding="utf-8") as f:
        for line_no, raw in enumerate(f, start=1):
            tok = raw.strip()
            if not tok:
                continue
            if len(tok) != 8 or any(c not in "0123456789abcdefABCDEF" for c in tok):
                raise AssemblerError(
                    f"linha {line_no} do dump de .text não parece uma palavra "
                    f"hexadecimal de 32 bits (8 dígitos): {raw!r}"
                )
            words.append(int(tok, 16))
    return words


def _sext(v, bits):
    if v & (1 << (bits - 1)):
        v -= (1 << bits)
    return v


def _decode_standard_branch_offset(word):
    """Decodifica o campo imediato de um B-type no formato PADRÃO RV32I
    (o que o RARS realmente grava) -- sem nenhuma divisão por 2."""
    b12 = (word >> 31) & 1
    b11 = (word >> 7) & 1
    b10_5 = (word >> 25) & 0x3F
    b4_1 = (word >> 8) & 0xF
    y = (b12 << 12) | (b11 << 11) | (b10_5 << 5) | (b4_1 << 1)
    return _sext(y, 13)


def _decode_standard_jal_offset(word):
    """Idem, para J-type (JAL)."""
    b20 = (word >> 31) & 1
    b19_12 = (word >> 12) & 0xFF
    b11 = (word >> 20) & 1
    b10_1 = (word >> 21) & 0x3FF
    y = (b20 << 20) | (b19_12 << 12) | (b11 << 11) | (b10_1 << 1)
    return _sext(y, 21)


def reencode_pc_relative(rom_words):
    """Recodifica o imediato de todo BRANCH/JAL de `rom_words` (assumidos
    no formato PADRÃO RV32I, como o RARS produz) para o formato que este
    processador realmente espera -- ver nota "ATENÇÃO" no cabeçalho deste
    arquivo. Todas as outras instruções (R, I, S, U, JALR, ECALL) saem
    idênticas: só BRANCH/JAL têm o deslocamento dobrado pelo hardware."""
    out = []
    for pc_words, word in enumerate(rom_words):
        pc = pc_words * 4
        opcode = word & 0x7F
        if opcode == OPCODE_BRANCH:
            funct3 = (word >> 12) & 0x7
            rs1 = (word >> 15) & 0x1F
            rs2 = (word >> 20) & 0x1F
            offset = _decode_standard_branch_offset(word)
            word = encode_b(offset, rs1, rs2, funct3, OPCODE_BRANCH)
        elif opcode == OPCODE_JAL:
            rd = (word >> 7) & 0x1F
            offset = _decode_standard_jal_offset(word)
            word = encode_j(offset, rd, OPCODE_JAL)
        out.append(word)
    return out


def parse_data_dump(path, data_base):
    """Lê o dump de .data do RARS: cada linha começa com um endereço
    absoluto ("0x...") seguido de 1 ou mais palavras ("0x..." cada,
    endereços consecutivos de 4 em 4 bytes). Devolve um dict
    {offset_da_palavra (bytes, relativo a data_base): valor (0 a
    0xFFFFFFFF)}."""
    words_by_offset = {}
    with open(path, "r", encoding="utf-8") as f:
        for line_no, raw in enumerate(f, start=1):
            tok = raw.strip()
            if not tok:
                continue
            parts = tok.split()
            if len(parts) < 2:
                raise AssemblerError(
                    f"linha {line_no} do dump de .data não tem o formato "
                    f"esperado (endereço seguido de 1 ou mais palavras): {raw!r}"
                )
            try:
                line_addr = int(parts[0], 16)
            except ValueError:
                raise AssemblerError(
                    f"linha {line_no} do dump de .data: endereço inválido "
                    f"'{parts[0]}'"
                )
            for i, word_tok in enumerate(parts[1:]):
                try:
                    value = int(word_tok, 16)
                except ValueError:
                    raise AssemblerError(
                        f"linha {line_no} do dump de .data: palavra inválida "
                        f"'{word_tok}'"
                    )
                abs_addr = line_addr + i * 4
                offset = abs_addr - data_base
                if offset < 0:
                    raise AssemblerError(
                        f"linha {line_no} do dump de .data: endereço {abs_addr:#x} "
                        f"é menor que a base de .data ({data_base:#x}) -- "
                        f"confira --data-base"
                    )
                words_by_offset[offset] = value & 0xFFFFFFFF
    return words_by_offset


def words_by_offset_to_bytes(words_by_offset):
    """Converte {offset: valor} num bytes() denso, do offset 0 até o
    último offset com valor != 0 (inclusive) -- mesma convenção de
    write_ram_file/assembler.py: não preenche com zeros além do último
    dado real, mas preenche buracos internos (offsets nunca vistos, ou
    vistos com valor 0) normalmente com zero."""
    nonzero_offsets = [off for off, val in words_by_offset.items() if val != 0]
    if not nonzero_offsets:
        return b""
    n_words = (max(nonzero_offsets) // 4) + 1
    out = bytearray(4 * n_words)
    for off, val in words_by_offset.items():
        word_idx = off // 4
        if word_idx < n_words:
            out[off:off + 4] = val.to_bytes(4, "big")
    return bytes(out)


def main():
    ap = argparse.ArgumentParser(
        description="Converte um dump de memória compacta do RARS (.text/.data, "
                     "dump format 'Hexadecimal Text') para os arquivos de ROM/RAM "
                     "que ROM.vhd/RAM.vhd já sabem ler (mesmo formato de assembler.py)."
    )
    ap.add_argument("--text", required=True, help="dump de Memory Segment .text exportado pelo RARS")
    ap.add_argument("--data", required=True, help="dump de Memory Segment .data exportado pelo RARS")
    ap.add_argument("-o", "--output", required=True, help="arquivo de saída para a ROM")
    ap.add_argument("--ram", required=True, help="arquivo de saída para a RAM")
    ap.add_argument("--intermediate", default=None, help="arquivo com o programa desmontado (opcional)")
    ap.add_argument("--data-base", type=lambda s: int(s, 0), default=DEFAULT_DATA_BASE,
                     help=f"endereço base de .data no dump (default: {DEFAULT_DATA_BASE:#x}, "
                          f"o do modelo de memória compacto do RARS)")
    ap.add_argument("--rom-depth", type=int, default=DEFAULT_ROM_DEPTH, help="profundidade da ROM em palavras")
    ap.add_argument("--ram-depth", type=int, default=DEFAULT_RAM_DEPTH, help="profundidade da RAM em bytes")
    args = ap.parse_args()

    try:
        rom_words = reencode_pc_relative(parse_text_dump(args.text))
        words_by_offset = parse_data_dump(args.data, args.data_base)
        ram_bytes = words_by_offset_to_bytes(words_by_offset)

        write_rom_file(args.output, rom_words, args.rom_depth)
        write_ram_file(args.ram, ram_bytes, args.ram_depth)
        if args.intermediate:
            write_intermediate_listing(args.intermediate, rom_words, {}, {})
    except AssemblerError as e:
        print(f"erro: {e}", file=sys.stderr)
        sys.exit(1)

    print(f"ROM: {len(rom_words)} instrução(ões) escrita(s) em '{args.output}' "
          f"(a partir do dump de .text)")
    print(f"RAM: {len(ram_bytes)} byte(s) de dado escrito(s) em '{args.ram}' "
          f"(a partir do dump de .data, base {args.data_base:#x})")
    if args.intermediate:
        print(f"Listagem intermediária escrita em '{args.intermediate}'")


if __name__ == "__main__":
    main()
