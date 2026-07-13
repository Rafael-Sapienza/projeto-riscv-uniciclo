#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
assembler.py — Assembler RV32I (subset) para o processador uniciclo
=====================================================================

Converte um arquivo assembly (sintaxe próxima da usada pelo RARS) em:
  - um arquivo hexadecimal para a ROM (memória de instruções), pronto para
    ser lido pela função `init_rom_hex` do componente ROM via `hread`.
  - opcionalmente, um arquivo hexadecimal para inicialização da RAM
    (memória de dados), a partir de uma seção `.data`. Este projeto usa
    memória Harvard (ROM/RAM separadas); a própria entidade RAM (RAM.vhd)
    sabe carregar esse arquivo sozinha através do generic INIT_FILE — ver
    comentário no final deste arquivo para o detalhe de como ligar isso
    no testbench.
  - opcionalmente, um arquivo "intermediário" (--intermediate) com o
    programa já desmontado: pseudo-instruções expandidas em instruções
    reais e rótulos resolvidos em imediatos/endereços numéricos. Esse
    arquivo é gerado desmontando o próprio código de máquina produzido
    (não é uma cópia do fonte), então serve também como conferência de
    que a codificação está correta.

------------------------------------------------------------------------
IMPORTANTE — leia antes de usar
------------------------------------------------------------------------
1. O ISA suportado é EXATAMENTE o subconjunto RV32I implementado pela sua
   ControlUnit/ALUControl (ver tabela no README do projeto):
       ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU,
       ADDI, ANDI, ORI, XORI, SLLI, SRLI, SRAI, SLTI, SLTIU,
       LW, SW, BEQ, BNE, JAL, JALR, LUI, AUIPC, ECALL
   Não há BLT/BGE/BLTU/BGEU/CSR/EBREAK como instrução REAL nessa CPU (a
   ULA já tem os comparadores — uSGE/uSGEU/uSEQ/uSNE — mas o
   ControlUnit/ALUControl atual não decodifica esses branches, só
   BEQ/BNE). Ainda assim, blt/bge/bltu/bgeu/bgt/ble são suportados como
   PSEUDO-instruções, montadas em cima de slt/sltu + beq/bne (ver seção
   de pseudo-instruções abaixo) — o mesmo resultado, só que em 2
   instruções reais em vez de 1.

   ECALL é suportado como instrução real (opcode SYSTEM, sem operandos) e
   implementa um subconjunto dos syscalls do ambiente RARS, decodificado
   pela própria CPU (ver Control.vhdl/CPU.vhd): a7=1 (PrintInt, a0=valor),
   a7=4 (PrintString, a0=endereço da string terminada em '\\0' na RAM) e
   a7=93/Exit2 (a0=código de saída, sinaliza o bit de saída `halt` da CPU
   e congela o PC — é assim que o testbench sabe que o programa terminou).

2. Codificação de imediatos de B-type e J-type (branch/jal) — CONFIRMADO
   contra o `genImm32.vhd` real do projeto:
   O `genImm32` já monta o imediato de branch/jal no formato padrão RV32I
   (incluindo o bit 0 implícito = 0, ou seja, o valor que ele entrega já
   é um deslocamento par). O topo do processador (`uRV.vhd`) faz
   `shift_left(imm32OUT, 1)` antes de somar ao PC — isso NÃO é um bug:
   como toda instrução aqui ocupa exatamente 4 bytes, esse deslocamento
   "de fábrica" já é sempre múltiplo de 4, então dividir por 2 antes de
   codificar e deixar o hardware multiplicar de volta não perde nenhuma
   precisão — e ainda dobra o alcance de branch/jal em relação ao RV32I
   padrão. Por isso `PC_REL_HALVED = True` é o modo usado por padrão
   neste assembler (ver função `encode_b`/`encode_j` para o detalhe
   bit a bit, já validado contra o `genImm32.vhd`).

3. A RAM (RAM.vhd) agora sabe ler sozinha o arquivo gerado por `--ram`:
   basta passar o caminho do arquivo no generic `INIT_FILE` da entidade
   RAM (propagado pelo generic `RAM_FILE` da entidade uRV/CPU) na hora de
   instanciá-la no testbench. O carregamento é feito 1 palavra de 32 bits
   por linha, a partir do endereço 0, na mesma ordem em que este script
   escreve o arquivo. Se `RAM_FILE`/`INIT_FILE` for uma string vazia
   (padrão), a RAM continua zerada como antes.

------------------------------------------------------------------------
Sintaxe suportada
------------------------------------------------------------------------
Comentários:      '#' ou '//' até o final da linha.
Rótulos:           `LOOP:` (em linha própria ou antes de uma instrução)
Seções:            `.text` e `.data` (podem se repetir, mas cada rótulo
                    é resolvido dentro do seu próprio espaço de endereço:
                    ROM para `.text`, RAM para `.data` — são memórias
                    fisicamente separadas nessa CPU, então não existe
                    endereçamento unificado como no RARS "de verdade").

Diretivas de dado (`.data`):
    .word v1, v2, ...      -> palavras de 32 bits (auto-alinhadas em 4 bytes,
                               igual ao RARS: se o ponteiro de dados atual
                               não estiver alinhado, insere padding de zeros)
    .half v1, v2, ...      -> meias-palavras de 16 bits (auto-alinhadas em 2 bytes)
    .byte v1, v2, ...      -> bytes individuais
    .asciz "texto"         -> string terminada em '\\0'
    .string "texto"        -> idem a .asciz
    .space n                -> reserva n bytes zerados
    .align n                 -> preenche com zeros até múltiplo de 2^n bytes

    Sintaxe "valor:quantidade" (estilo RARS), válida em .word/.half/.byte:
        .byte 0:255          -> 255 bytes, todos com valor 0
        .word -1:10           -> 10 palavras, todas com valor -1

    Continuação em múltiplas linhas: se a diretiva não tiver nenhum valor
    na mesma linha, os valores são lidos das linhas seguintes (separados
    por espaço e/ou vírgula), até encontrar um novo rótulo, uma nova
    diretiva, ou uma nova seção. Exemplo:

        mat1: .byte
        0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        mat2: .byte 0:255

Registradores — aceita nomes formais e ABI, case-insensitive:
    x0..x31
    zero, ra, sp, gp, tp
    t0-t2, s0/fp, s1, a0-a7, s2-s11, t3-t6

------------------------------------------------------------------------
Pseudo-instruções suportadas
------------------------------------------------------------------------
    nop                  -> addi x0, x0, 0
    mv   rd, rs          -> addi rd, rs, 0
    not  rd, rs          -> xori rd, rs, -1
    neg  rd, rs          -> sub  rd, x0, rs
    li   rd, imm32       -> addi rd, x0, imm            (se cabe em 12 bits)
                          -> lui rd, %hi(imm) ; addi rd, rd, %lo(imm)  (caso geral)
    la   rd, label       -> mesmo esquema do `li`, usando o endereço do
                             rótulo no espaço de dados (RAM)
    j    label           -> jal  x0, label
    jal  label           -> jal  x1, label   (1 operando -> usa ra)
    jr   rs               -> jalr x0, rs, 0
    ret                   -> jalr x0, x1, 0
    beqz rs, label        -> beq rs, x0, label
    bnez rs, label        -> bne rs, x0, label
    sgt  rd, rs1, rs2     -> slt  rd, rs2, rs1     (troca os operandos)
    sgtu rd, rs1, rs2     -> sltu rd, rs2, rs1
    sltz rd, rs           -> slt  rd, rs, x0        (rd = (rs <  0))
    sgtz rd, rs           -> slt  rd, x0, rs        (rd = (rs >  0))
    seqz rd, rs           -> sltiu rd, rs, 1        (rd = (rs == 0))
    snez rd, rs           -> sltu rd, x0, rs        (rd = (rs != 0))

    blt  rs1,rs2,label    -> slt x31,rs1,rs2 ; bne x31,x0,label  (*)
    bge  rs1,rs2,label    -> slt x31,rs1,rs2 ; beq x31,x0,label  (*)
    bltu rs1,rs2,label    -> sltu x31,rs1,rs2 ; bne x31,x0,label (*)
    bgeu rs1,rs2,label    -> sltu x31,rs1,rs2 ; beq x31,x0,label (*)
    bgt  rs1,rs2,label    -> blt  rs2,rs1,label     (troca os operandos)
    ble  rs1,rs2,label    -> bge  rs2,rs1,label     (troca os operandos)
        (*) usam x31 (t6) como registrador temporário — essa CPU não
            decodifica BLT/BGE/BLTU/BGEU como instrução real (só BEQ/BNE),
            então a comparação é feita "na mão" com slt/sltu antes do
            desvio. Evite usar t6 logo antes de uma dessas.

    call label            -> auipc ra, %hi(label-pc) ; jalr ra, %lo(label-pc)(ra)
    tail label            -> auipc t1, %hi(label-pc) ; jalr x0, %lo(label-pc)(t1)
        (call/tail sempre geram 2 instruções, mesmo quando um `jal` só já
        alcançaria o rótulo — é assim que o RISC-V "de verdade" define
        essas pseudo-instruções. tail usa t1 em vez de ra de propósito,
        para não sobrescrever o endereço de retorno da função atual.)

Pseudo-instruções NÃO suportadas (não há como emular sem hardware extra
nessa CPU): call/tail com registrador de retorno explícito diferente do
padrão, la absoluto com endereço de texto, csrr* etc.

------------------------------------------------------------------------
Uso
------------------------------------------------------------------------
    python3 assembler.py programa.asm -o data.txt --ram ram_init.txt \\
        --intermediate programa.expandido.txt

    Opções:
      -o / --output       arquivo de saída para a ROM (default: data.txt)
      --ram                arquivo de saída para a RAM (default: não gera)
      --intermediate        arquivo com o programa desmontado (pseudo
                             expandidas, rótulos resolvidos em números)
      --rom-depth          profundidade da ROM em palavras (default: 2048 = 2**11)
      --ram-depth          profundidade da RAM em bytes   (default: 8192 = 2**13)
      --pc-rel-standard     usa a codificação PADRÃO RV32I para branch/jal em
                             vez do modo "halved" (ver item 2 acima) — só use
                             isso se tiver certeza de que não é o seu caso
      -v / --verbose        imprime endereços e a tabela de símbolos
"""

import argparse
import re
import sys

# ======================================================================
# CONFIGURAÇÃO GLOBAL
# ======================================================================

# Ver item 2 do cabeçalho. Confirmado contra genImm32.vhd: True é o modo
# correto para este processador.
PC_REL_HALVED = True

TEXT_BASE = 0          # endereço inicial do segmento .text (ROM, em bytes)
DATA_BASE = 0          # endereço inicial do segmento .data (RAM, em bytes)

DEFAULT_ROM_DEPTH = 2 ** 11   # ROMSIZE = 11 (ver README)
DEFAULT_RAM_DEPTH = 2 ** 13   # RAMSIZE = 13 (ver README)


# ======================================================================
# REGISTRADORES
# ======================================================================

_ABI_NAMES = {
    "zero": 0, "ra": 1, "sp": 2, "gp": 3, "tp": 4,
    "t0": 5, "t1": 6, "t2": 7,
    "s0": 8, "fp": 8, "s1": 9,
    "a0": 10, "a1": 11, "a2": 12, "a3": 13, "a4": 14, "a5": 15, "a6": 16, "a7": 17,
    "s2": 18, "s3": 19, "s4": 20, "s5": 21, "s6": 22, "s7": 23, "s8": 24, "s9": 25,
    "s10": 26, "s11": 27,
    "t3": 28, "t4": 29, "t5": 30, "t6": 31,
}


def parse_register(tok: str, line_no: int) -> int:
    """Converte um token de registrador (formal ou ABI) em seu número (0-31)."""
    t = tok.strip().lower()
    if t in _ABI_NAMES:
        return _ABI_NAMES[t]
    m = re.fullmatch(r"x(\d{1,2})", t)
    if m:
        n = int(m.group(1))
        if 0 <= n <= 31:
            return n
    raise AssemblerError(f"registrador inválido: '{tok}'", line_no)


# ======================================================================
# ERROS
# ======================================================================

class AssemblerError(Exception):
    def __init__(self, msg, line_no=None):
        self.line_no = line_no
        if line_no is not None:
            super().__init__(f"linha {line_no}: {msg}")
        else:
            super().__init__(msg)


# ======================================================================
# TABELA DE INSTRUÇÕES "REAIS" (não-pseudo)
# formato: mnemonic -> (tipo, opcode, funct3, funct7)
# ======================================================================

INSTR_TABLE = {
    # R-type
    "add":  ("R", 0b0110011, 0b000, 0b0000000),
    "sub":  ("R", 0b0110011, 0b000, 0b0100000),
    "sll":  ("R", 0b0110011, 0b001, 0b0000000),
    "slt":  ("R", 0b0110011, 0b010, 0b0000000),
    "sltu": ("R", 0b0110011, 0b011, 0b0000000),
    "xor":  ("R", 0b0110011, 0b100, 0b0000000),
    "srl":  ("R", 0b0110011, 0b101, 0b0000000),
    "sra":  ("R", 0b0110011, 0b101, 0b0100000),
    "or":   ("R", 0b0110011, 0b110, 0b0000000),
    "and":  ("R", 0b0110011, 0b111, 0b0000000),
    # I-type aritmético
    "addi": ("I-arith", 0b0010011, 0b000, None),
    "slti": ("I-arith", 0b0010011, 0b010, None),
    "sltiu":("I-arith", 0b0010011, 0b011, None),
    "xori": ("I-arith", 0b0010011, 0b100, None),
    "ori":  ("I-arith", 0b0010011, 0b110, None),
    "andi": ("I-arith", 0b0010011, 0b111, None),
    # I-type shift (imediato = shamt de 5 bits)
    "slli": ("I-shift", 0b0010011, 0b001, 0b0000000),
    "srli": ("I-shift", 0b0010011, 0b101, 0b0000000),
    "srai": ("I-shift", 0b0010011, 0b101, 0b0100000),
    # Load
    "lw":   ("I-load", 0b0000011, 0b010, None),
    # Store
    "sw":   ("S", 0b0100011, 0b010, None),
    # Branch
    "beq":  ("B", 0b1100011, 0b000, None),
    "bne":  ("B", 0b1100011, 0b001, None),
    # Jump
    "jal":  ("J", 0b1101111, None, None),
    "jalr": ("I-jalr", 0b1100111, 0b000, None),
    # Upper immediate
    "lui":   ("U", 0b0110111, None, None),
    "auipc": ("U", 0b0010111, None, None),
    # System (chamada de sistema — ver ControlUnit.Ecall/CPU.vhd)
    "ecall": ("SYS", 0b1110011, 0b000, None),
}

PSEUDO_OPS = {
    "nop", "mv", "not", "neg", "li", "la", "j", "jr", "ret", "beqz", "bnez",
    "sgt", "sgtu", "sltz", "sgtz", "seqz", "snez",
    "blt", "bge", "bltu", "bgeu", "bgt", "ble",
    "call", "tail",
}
# 'jal' com 1 operando também é tratado como pseudo (ver expand_pseudo)


# ======================================================================
# CODIFICAÇÃO DE CAMPOS
# ======================================================================

def _fits_signed(value: int, bits: int) -> bool:
    lo = -(1 << (bits - 1))
    hi = (1 << (bits - 1)) - 1
    return lo <= value <= hi


def _to_field(value: int, bits: int) -> int:
    """Converte um inteiro (com sinal) para sua representação em complemento
    de dois de `bits` bits, como um inteiro sem sinal (para montar a palavra)."""
    return value & ((1 << bits) - 1)


def encode_r(funct7, rs2, rs1, funct3, rd, opcode):
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def encode_i(imm, rs1, funct3, rd, opcode, line_no=None):
    if not _fits_signed(imm, 12):
        raise AssemblerError(f"imediato {imm} fora do intervalo de 12 bits com sinal", line_no)
    imm_f = _to_field(imm, 12)
    return (imm_f << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def encode_i_shift(shamt, rs1, funct3, rd, opcode, funct7, line_no=None):
    if not (0 <= shamt <= 31):
        raise AssemblerError(f"shamt {shamt} fora do intervalo [0,31]", line_no)
    return (funct7 << 25) | (shamt << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def encode_s(imm, rs2, rs1, funct3, opcode, line_no=None):
    if not _fits_signed(imm, 12):
        raise AssemblerError(f"imediato {imm} fora do intervalo de 12 bits com sinal", line_no)
    imm_f = _to_field(imm, 12)
    imm_11_5 = (imm_f >> 5) & 0x7F
    imm_4_0 = imm_f & 0x1F
    return (imm_11_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (imm_4_0 << 7) | opcode


def encode_b(offset, rs1, rs2, funct3, opcode, line_no=None):
    """offset = endereço_alvo - endereço_da_instrução (em bytes, múltiplo de 2).

    Modo padrão (PC_REL_HALVED=False): o campo imediato é montado do jeito
    padrão RV32I, representando 'offset' diretamente (bit 0 implícito = 0).

    Modo PC_REL_HALVED=True: assume que o hardware vai multiplicar o valor
    decodificado por 2 (ver item 2 do cabeçalho do arquivo), então aqui
    gravamos offset/2 nos MESMOS bits em que normalmente iria 'offset' —
    ou seja, tratamos offset/2 como se fosse o próprio 'offset' padrão do
    RV32I para fins de shuffle de bits.
    """
    if offset % 2 != 0:
        raise AssemblerError(f"offset de branch {offset} não é múltiplo de 2", line_no)
    ref = (offset // 2) if PC_REL_HALVED else offset
    if not _fits_signed(ref, 13):
        raise AssemblerError(f"offset de branch {offset} fora do alcance", line_no)
    imm_f = _to_field(ref, 13)
    imm12 = (imm_f >> 12) & 0x1
    imm11 = (imm_f >> 11) & 0x1
    imm10_5 = (imm_f >> 5) & 0x3F
    imm4_1 = (imm_f >> 1) & 0xF
    word = (imm12 << 31) | (imm10_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) \
        | (imm4_1 << 8) | (imm11 << 7) | opcode
    return word


def encode_u(imm20, rd, opcode, line_no=None):
    # imm20 já deve vir como os 20 bits superiores (valor de 0 a 0xFFFFF,
    # ou negativo representando complemento de dois em 20 bits)
    if not (_fits_signed(imm20, 20) or (0 <= imm20 <= 0xFFFFF)):
        raise AssemblerError(f"imediato de 20 bits {imm20} fora do intervalo", line_no)
    imm_f = _to_field(imm20, 20)
    return (imm_f << 12) | (rd << 7) | opcode


def encode_j(offset, rd, opcode, line_no=None):
    """offset = endereço_alvo - endereço_da_instrução (em bytes, múltiplo de 2).
    Ver docstring de encode_b() para a semântica de PC_REL_HALVED."""
    if offset % 2 != 0:
        raise AssemblerError(f"offset de jal {offset} não é múltiplo de 2", line_no)
    ref = (offset // 2) if PC_REL_HALVED else offset
    if not _fits_signed(ref, 21):
        raise AssemblerError(f"offset de jal {offset} fora do alcance", line_no)
    imm_f = _to_field(ref, 21)
    imm20 = (imm_f >> 20) & 0x1
    imm10_1 = (imm_f >> 1) & 0x3FF
    imm11 = (imm_f >> 11) & 0x1
    imm19_12 = (imm_f >> 12) & 0xFF
    word = (imm20 << 31) | (imm19_12 << 12) | (imm11 << 20) | (imm10_1 << 21) | (rd << 7) | opcode
    return word


# ======================================================================
# PARSING DE OPERANDOS
# ======================================================================

def split_operands(s: str):
    """Divide uma lista de operandos separados por vírgula (ex: operandos de
    uma instrução, como 'a0, a1, 4') em uma lista de strings, ex: ['a0','a1','4'].

    Não usa um simples s.split(',') porque isso quebraria uma string entre
    aspas que contenha vírgula (ex: .asciz "a, b, c" tem que virar UM único
    operando, a string inteira, não três). Por isso percorremos caractere a
    caractere, alternando uma flag `in_str` a cada '"' encontrado, e só
    tratamos ',' como separador quando NÃO estamos dentro de uma string.
    """
    parts = []
    cur = ""
    in_str = False
    for ch in s:
        if ch == '"':
            in_str = not in_str  # alterna dentro/fora de string a cada aspas
            cur += ch
        elif ch == ',' and not in_str:
            parts.append(cur.strip())
            cur = ""
        else:
            cur += ch
    if cur.strip():
        parts.append(cur.strip())
    return parts


# Operando de memória no formato "imm(reg)", usado por lw/sw/jalr, ex: "-4(sp)", "0(t0)".
#   ^                 início estrito da string (junto com $ no final, garante
#                      que a string INTEIRA precisa bater com o padrão, não só um pedaço)
#   \s*               espaços opcionais antes do imediato (tolerância a "  -4(sp)")
#   (-?\w+)           grupo 1: o imediato — sinal de menos opcional + 1 ou mais
#                      caracteres "word" ([A-Za-z0-9_]). Aceita tanto números
#                      decimais/hex quanto (no futuro) um nome simbólico, já
#                      que \w não distingue dígito de letra nesse momento —
#                      quem valida se é realmente um número é parse_number(),
#                      chamado depois, fora do regex.
#   \s*\(\s*          parêntese de abertura, com espaços opcionais dos dois lados
#   ([a-zA-Z0-9]+)    grupo 2: o nome do registrador (ex: "sp", "t0", "x5")
#   \s*\)\s*          parêntese de fechamento, com espaços opcionais
#   $                 fim estrito da string
_MEM_OPERAND_RE = re.compile(r"^\s*(-?\w+)\s*\(\s*([a-zA-Z0-9]+)\s*\)\s*$")


def parse_mem_operand(tok: str, line_no: int):
    """Faz o parsing de 'imm(reg)', retornando (imm:int, reg:int)."""
    m = _MEM_OPERAND_RE.match(tok)
    if not m:
        raise AssemblerError(f"operando de memória inválido: '{tok}' (esperado imm(reg))", line_no)
    imm = parse_number(m.group(1), line_no)
    reg = parse_register(m.group(2), line_no)
    return imm, reg


def parse_number(tok: str, line_no: int) -> int:
    """Converte um token numérico (decimal ou hexadecimal, com sinal
    opcional) em int. Detecta hexadecimal pelo prefixo '0x'/'0X' (ou
    '-0x'/'-0X' para hex negativo) e delega para int(str, base) — não
    usamos _NUMBER_RE aqui porque essa função também é chamada em
    contextos onde o token já foi validado como número (ex: depois de
    is_number() retornar True), então a validação real é só uma rede de
    segurança contra erros de digitação."""
    t = tok.strip()
    try:
        if t.lower().startswith("0x") or t.lower().startswith("-0x"):
            return int(t, 16)
        return int(t, 10)
    except ValueError:
        raise AssemblerError(f"número inválido: '{tok}'", line_no)


# Reconhece um token que é PURAMENTE um número (decimal ou hexadecimal),
# usado para decidir se um operando é um imediato literal ou um rótulo a
# ser resolvido na tabela de símbolos (ver uso em is_number()).
#   ^                          início estrito
#   -?                         sinal de menos opcional
#   (                          grupo de captura (o valor em si, sem o sinal)
#     0[xX][0-9a-fA-F]+        forma hexadecimal: "0x"/"0X" + 1+ dígitos hex
#     |                        OU
#     \d+                      forma decimal: 1 ou mais dígitos
#   )
#   $                          fim estrito
# Note que isso NÃO aceita nomes de rótulo (mesmo que comecem com dígito,
# o que já seria inválido como rótulo de qualquer forma) — só dígitos e,
# no máximo, o prefixo "0x"/sinal de menos.
_NUMBER_RE = re.compile(r"^-?(0[xX][0-9a-fA-F]+|\d+)$")


def is_number(tok: str) -> bool:
    """True se `tok` é um literal numérico (não um nome de rótulo). Usado
    nos operandos de beq/bne/jal/li/la para decidir entre parse_number()
    (valor literal) e resolve_symbol() (procurar na tabela de símbolos)."""
    return bool(_NUMBER_RE.match(tok.strip()))


# ======================================================================
# ESTRUTURAS INTERMEDIÁRIAS
# ======================================================================

class TextItem:
    """Uma instrução 'real' (já sem pseudo) pronta para ser codificada."""
    __slots__ = ("mnemonic", "operands", "line_no", "label", "address")

    def __init__(self, mnemonic, operands, line_no, label=None):
        self.mnemonic = mnemonic
        self.operands = operands  # lista de tokens (strings) já separados
        self.line_no = line_no
        self.label = label
        self.address = None


class DataChunk:
    """Um pedaço de dado bruto (bytes) no segmento .data, opcionalmente rotulado."""
    __slots__ = ("data", "line_no", "label", "address", "align")

    def __init__(self, data: bytes, line_no, label=None, align=1):
        self.data = data
        self.line_no = line_no
        self.label = label
        self.address = None
        self.align = align  # 1, 2 ou 4 bytes — auto-alinhamento estilo RARS


# ======================================================================
# EXPANSÃO DE PSEUDO-INSTRUÇÕES (.text)
# ======================================================================

def expand_pseudo(mnemonic, operands, line_no):
    """Recebe uma instrução (real ou pseudo) e devolve uma lista de
    instruções REAIS equivalentes: [(mnemonic, operands), ...]."""
    m = mnemonic.lower()

    if m in INSTR_TABLE:
        return [(m, operands)]

    if m == "nop":
        return [("addi", ["x0", "x0", "0"])]

    if m == "mv":
        rd, rs = operands
        return [("addi", [rd, rs, "0"])]

    if m == "not":
        rd, rs = operands
        return [("xori", [rd, rs, "-1"])]

    if m == "neg":
        rd, rs = operands
        return [("sub", [rd, "x0", rs])]

    # --- pseudo-instruções de comparação (todas viram UMA única slt/sltu/
    # sltiu real — RISC-V não tem "set greater than" ou "set equal" como
    # instrução de verdade, só slt/sltu; o resto é convenção de montador) ---

    if m == "sgt":  # sgt rd, rs1, rs2  ==  slt rd, rs2, rs1  (troca os operandos)
        rd, rs1, rs2 = operands
        return [("slt", [rd, rs2, rs1])]

    if m == "sgtu":  # sgtu rd, rs1, rs2  ==  sltu rd, rs2, rs1
        rd, rs1, rs2 = operands
        return [("sltu", [rd, rs2, rs1])]

    if m == "sltz":  # sltz rd, rs  ==  rd = (rs < 0)  ==  slt rd, rs, x0
        rd, rs = operands
        return [("slt", [rd, rs, "x0"])]

    if m == "sgtz":  # sgtz rd, rs  ==  rd = (rs > 0)  ==  slt rd, x0, rs
        rd, rs = operands
        return [("slt", [rd, "x0", rs])]

    if m == "seqz":  # seqz rd, rs  ==  rd = (rs == 0)  ==  sltiu rd, rs, 1
        rd, rs = operands
        return [("sltiu", [rd, rs, "1"])]

    if m == "snez":  # snez rd, rs  ==  rd = (rs != 0)  ==  sltu rd, x0, rs
        rd, rs = operands
        return [("sltu", [rd, "x0", rs])]

    if m == "li":
        rd, imm_tok = operands
        return [("__LI__", [rd, imm_tok])]  # resolvido depois (precisa do valor final)

    if m == "la":
        rd, label_tok = operands
        return [("__LA__", [rd, label_tok])]  # idem, resolvido na 2a passada

    if m == "j":
        (label,) = operands
        return [("jal", ["x0", label])]

    if m == "jal" and len(operands) == 1:
        (label,) = operands
        return [("jal", ["x1", label])]

    if m == "jr":
        (rs,) = operands
        return [("jalr", ["x0", "0(" + rs + ")"])]

    if m == "ret":
        return [("jalr", ["x0", "0(x1)"])]

    if m == "beqz":
        rs, label = operands
        return [("beq", [rs, "x0", label])]

    if m == "bnez":
        rs, label = operands
        return [("bne", [rs, "x0", label])]

    # --- blt/bge/bltu/bgeu: essa CPU não decodifica esses branches como
    # instrução real (só BEQ/BNE), mas dá pra montar o mesmo efeito com
    # o que já existe: calcula a comparação com slt/sltu num registrador
    # temporário e desvia com base nesse resultado (0 ou 1) via beq/bne.
    #
    # ATENÇÃO: essas pseudo-instruções usam x31 (t6) como registrador
    # temporário/"scratch". Isso segue a mesma ideia do $at do MIPS: não
    # use t6 logo antes de um blt/bge/bltu/bgeu/bgt/ble, porque o valor
    # que estiver lá vai ser sobrescrito.
    _CMP_TEMP_REG = "x31"  # t6

    if m == "blt":  # blt rs1, rs2, label  ==  se (rs1 < rs2) desvia
        rs1, rs2, label = operands
        return [("slt", [_CMP_TEMP_REG, rs1, rs2]), ("bne", [_CMP_TEMP_REG, "x0", label])]

    if m == "bge":  # bge rs1, rs2, label  ==  se (rs1 >= rs2) desvia  (NOT blt)
        rs1, rs2, label = operands
        return [("slt", [_CMP_TEMP_REG, rs1, rs2]), ("beq", [_CMP_TEMP_REG, "x0", label])]

    if m == "bltu":  # idem a blt, comparação sem sinal
        rs1, rs2, label = operands
        return [("sltu", [_CMP_TEMP_REG, rs1, rs2]), ("bne", [_CMP_TEMP_REG, "x0", label])]

    if m == "bgeu":  # idem a bge, comparação sem sinal
        rs1, rs2, label = operands
        return [("sltu", [_CMP_TEMP_REG, rs1, rs2]), ("beq", [_CMP_TEMP_REG, "x0", label])]

    if m == "bgt":  # bgt rs1, rs2, label  ==  blt rs2, rs1, label  (troca operandos)
        rs1, rs2, label = operands
        return expand_pseudo("blt", [rs2, rs1, label], line_no)

    if m == "ble":  # ble rs1, rs2, label  ==  bge rs2, rs1, label  (troca operandos)
        rs1, rs2, label = operands
        return expand_pseudo("bge", [rs2, rs1, label], line_no)

    # --- call/tail: chamada de função "de longo alcance", igual ao RISC-V
    # de verdade — auipc pega os 20 bits superiores do deslocamento até o
    # rótulo, jalr completa com os 12 bits inferiores. Como jal/jalr já
    # tinham auipc e jalr prontos, isso é só reaproveitar. Resolvido em
    # duas etapas como li/la: aqui vira um placeholder (__CALL__/__TAIL__)
    # porque ainda não sabemos os endereços definitivos nesta fase; a
    # codificação de verdade acontece depois que os endereços de .text são
    # todos conhecidos (ver `far_jump_sequence` mais abaixo).
    if m == "call":  # call label  ==  auipc ra, %hi(label-pc) ; jalr ra, %lo(label-pc)(ra)
        (label,) = operands
        return [("__CALL__", [label])]

    if m == "tail":  # tail label  ==  auipc t1, %hi(...) ; jalr x0, %lo(...)(t1)
        # usa t1 (não ra!) de propósito: uma tail-call não deve mexer no
        # endereço de retorno da função atual, já que ela está "passando
        # adiante" a chamada em vez de empilhar um novo retorno.
        (label,) = operands
        return [("__TAIL__", [label])]

    raise AssemblerError(f"mnemônico desconhecido ou não suportado: '{mnemonic}'", line_no)


# ======================================================================
# PARSER PRINCIPAL
# ======================================================================

# Reconhece um RÓTULO no início de uma linha, ex: "LOOP:", "mat1: .byte 1,2",
# "main: la a0, x". Só é aplicado a linhas já sem comentário (strip_comment)
# e já sem espaços nas pontas (.strip()).
#
#   ^                       início estrito da linha
#   (                       grupo 1: o NOME do rótulo
#     [A-Za-z_.]              primeiro caractere: letra, '_' ou '.'
#                              ('.' é aceito para permitir rótulos "locais" no
#                              estilo GNU as, ex: ".L1:", ".loop_interno:")
#     [A-Za-z0-9_.]*           caracteres seguintes: letras, dígitos, '_' ou '.'
#                              — IMPORTANTE: espaço NÃO está nessa classe.
#   )
#   :                       o ':' que de fato marca "isto é um rótulo"
#   \s*                     espaços opcionais logo após o ':'
#   (.*)                    grupo 2: o resto da linha (a instrução/dado que
#                            vier depois do rótulo, se houver — pode ser "")
#   $                       fim estrito da linha
#
# POR QUE ISSO NÃO CONFUNDE DIRETIVAS (".data", ".byte 0:255" etc.) COM
# RÓTULOS, mesmo ambas começando com '.':
#   Como espaço não pertence à classe de caracteres do nome do rótulo, o
#   grupo 1 só consegue "esticar" por uma sequência CONTÍNUA de letras/
#   dígitos/'_'/'.' a partir da posição 0. Em ".byte 0:255", depois de
#   ".byte" vem um espaço — o regex exige que LOGO ATRÁS do nome capturado
#   venha um ':', mas o que vem é um espaço, então a tentativa falha; ele
#   backtracka para nomes mais curtos (".byt", ".by", ...) mas em nenhuma
#   posição intermediária o próximo caractere é ':' (é sempre outra letra
#   do próprio ".byte" ou o espaço). O ':' que realmente existe em "0:255"
#   está depois do espaço, fora do alcance do grupo 1 — logo NÃO HÁ MATCH
#   e a linha segue para o tratamento de diretiva normalmente (bloco
#   `if line.startswith(".")` mais abaixo). O mesmo raciocínio vale para
#   qualquer diretiva escrita com um espaço antes do nome (".text", ".data",
#   ".align 4", ".asciz "..."" etc.) — só uma diretiva colada teria risco
#   de bater aqui, e nenhuma diretiva suportada é escrita desse jeito.
_LABEL_RE = re.compile(r"^([A-Za-z_.][A-Za-z0-9_.]*):\s*(.*)$")


def strip_comment(line: str) -> str:
    """Remove tudo a partir de um comentário ('#' ou '//') até o final da
    linha, preservando qualquer '#'/'//' que apareça DENTRO de uma string
    entre aspas (ex: `.asciz "preco: R# 5"` não deve ter o '#' cortado).

    Não dá para usar um regex simples tipo `re.sub(r'#.*', '', line)`
    porque isso cortaria erroneamente o conteúdo de uma string; por isso
    percorremos caractere a caractere, com a mesma técnica de flag
    `in_str` usada em split_operands()."""
    out = []
    in_str = False
    i = 0
    while i < len(line):
        ch = line[i]
        if ch == '"':
            in_str = not in_str
            out.append(ch)
            i += 1
            continue
        if not in_str:
            if ch == '#':
                break  # comentário estilo '#': ignora o resto da linha
            if ch == '/' and i + 1 < len(line) and line[i + 1] == '/':
                break  # comentário estilo '//': idem
        out.append(ch)
        i += 1
    return "".join(out)


# Reconhece a sintaxe "valor:quantidade" (estilo RARS) usada em .byte/
# .half/.word, ex: "0:255" (255 bytes com valor 0), "-1:10" (10 palavras
# com valor -1). Só é testado token a token (já separados por espaço/
# vírgula em tokenize_values), então aqui não precisamos nos preocupar
# com espaços ao redor.
#   ^                                início estrito do token
#   (                                grupo 1: o VALOR a ser repetido
#     -?                               sinal de menos opcional
#     (?:0[xX][0-9a-fA-F]+|\d+)        hexadecimal OU decimal — mesmo padrão
#                                      usado em _NUMBER_RE, mas aqui como
#                                      grupo não-capturante (?:...) porque só
#                                      precisamos do valor inteiro combinado,
#                                      não de qual das duas alternativas bateu
#   )
#   :                                separador literal entre valor e quantidade
#   (\d+)                            grupo 2: a QUANTIDADE de repetições
#                                    (sempre decimal, sempre positiva — não
#                                    faz sentido repetir um valor "-3" vezes)
#   $                                fim estrito do token
# Se o token não bater aqui (ex: é só "42"), parse_value_list() cai no
# caso normal e trata o token inteiro como um valor único (não repetido).
_VALCOUNT_RE = re.compile(r"^(-?(?:0[xX][0-9a-fA-F]+|\d+)):(\d+)$")


def tokenize_values(s: str):
    """Divide uma linha de valores em tokens, aceitando tanto vírgula
    quanto espaço como separador (e uma mistura dos dois)."""
    s = s.replace(",", " ")
    return [t for t in s.split() if t]


def parse_value_list(tokens, line_no):
    """Expande uma lista de tokens numéricos, resolvendo a sintaxe
    'valor:quantidade' (estilo RARS) quando presente."""
    values = []
    for tok in tokens:
        m = _VALCOUNT_RE.match(tok.strip())
        if m:
            val = parse_number(m.group(1), line_no)
            count = int(m.group(2))
            values.extend([val] * count)
        else:
            values.append(parse_number(tok, line_no))
    return values


_DATA_ELEM_SIZE = {".byte": 1, ".half": 2, ".word": 4}


def parse_directive_data(directive, value_tokens, line_no):
    """Converte uma diretiva de dado (já tokenizada) em bytes crus.

    IMPORTANTE — endianness de .word/.half: usamos BIG-ENDIAN aqui (byte
    mais significativo no endereço mais baixo), não porque é "o padrão",
    mas porque é isso que o RAM.vhd realmente implementa na escrita/leitura
    de palavra:

        mem(INTaddr+0) <= datain(31 downto 24);  -- MSB no endereço mais baixo
        ...
        mem(INTaddr+3) <= datain(7 downto 0);    -- LSB no endereço mais alto

    (o comentário "-- little-endian" que está no RAM.vhd está errado — o
    código ali é big-endian de fato). Como esses bytes vão ser carregados
    DIRETAMENTE no sinal `mem` pelo testbench (byte a byte, por endereço),
    minha ordem de bytes aqui precisa bater com a ordem que o hardware
    realmente vai usar para reconstruir o valor num `lw` — senão o valor
    lido volta embaralhado. Reproduzo com to_bytes(size, "big").
    """
    if directive in _DATA_ELEM_SIZE:
        size = _DATA_ELEM_SIZE[directive]
        mask = (1 << (size * 8)) - 1
        values = parse_value_list(value_tokens, line_no)
        buf = b""
        for v in values:
            buf += (v & mask).to_bytes(size, "big")
        return buf
    if directive in (".asciz", ".string"):
        args = value_tokens
        if len(args) != 1 or not args[0].startswith('"'):
            raise AssemblerError(f"{directive} espera uma única string entre aspas", line_no)
        s = args[0]
        if not (s.startswith('"') and s.endswith('"')):
            raise AssemblerError(f"string malformada: {s}", line_no)
        text = s[1:-1].encode("utf-8").decode("unicode_escape").encode("latin-1")
        return text + b"\x00"
    if directive == ".space":
        if len(value_tokens) != 1:
            raise AssemblerError(".space espera 1 argumento (quantidade de bytes)", line_no)
        n = parse_number(value_tokens[0], line_no)
        return b"\x00" * n
    raise AssemblerError(f"diretiva de dado desconhecida: {directive}", line_no)


def assemble(source: str):
    """Faz o assembly completo. Retorna (rom_words: List[int], ram_bytes: bytearray,
    symtab_text: dict, symtab_data: dict)."""

    text_items = []   # list[TextItem]  (ainda com pseudo, antes da expansão final)
    data_chunks = []  # list[DataChunk]

    section = ".text"
    pending_label = None
    pending_data = None  # dict {directive, label, line_no, tokens} enquanto acumula
                          # valores de um .byte/.half/.word em múltiplas linhas

    def flush_pending_data():
        nonlocal pending_data
        if pending_data is not None:
            raw_bytes = parse_directive_data(
                pending_data["directive"], pending_data["tokens"], pending_data["line_no"]
            )
            align = _DATA_ELEM_SIZE.get(pending_data["directive"], 1)
            data_chunks.append(DataChunk(raw_bytes, pending_data["line_no"], pending_data["label"], align=align))
            pending_data = None

    for raw_line_no, raw_line in enumerate(source.splitlines(), start=1):
        line = strip_comment(raw_line).strip()
        if not line:
            continue

        # PASSO 1: verifica se a linha começa com um rótulo ("nome:").
        #
        # Isso é tentado ANTES de checar diretiva (`line.startswith(".")`
        # logo abaixo) de propósito: uma linha como "mat1: .byte 1,2,3" TEM
        # que ter o rótulo extraído primeiro, sobrando ".byte 1,2,3" para o
        # passo seguinte tratar como diretiva.
        #
        # Isso não gera ambiguidade com diretivas "puras" tipo ".data" ou
        # ".byte 0:255" (que também começam com '.', igual um rótulo pode
        # começar): o _LABEL_RE exige um ':' logo em seguida a um nome sem
        # espaços, e nenhuma diretiva é escrita assim (ver o comentário
        # detalhado acima da definição de _LABEL_RE para o porquê exato).
        # Ou seja: se `m` bateu aqui, a linha É de fato "rótulo:", nunca uma
        # diretiva disfarçada.
        m = _LABEL_RE.match(line)
        label_here = None
        if m:
            label_here = m.group(1)
            line = m.group(2).strip()  # sobra da linha, depois do "rótulo:"
            flush_pending_data()  # um novo rótulo sempre encerra qualquer .byte/.half/.word em aberto
            pending_label = label_here
            if not line:
                # rótulo sozinho na linha (ex: "loop:"), aguarda a próxima
                # linha para saber a que instrução/dado ele se refere
                continue

        # PASSO 2: o que sobrou da linha (ou a linha inteira, se não havia
        # rótulo) é uma diretiva se começar com '.'.
        if line.startswith("."):
            # diretiva
            parts = line.split(None, 1)
            directive = parts[0].lower()
            rest = parts[1] if len(parts) > 1 else ""

            if directive == ".text":
                flush_pending_data()
                section = ".text"
                continue
            if directive == ".data":
                flush_pending_data()
                section = ".data"
                continue
            if directive == ".align":
                flush_pending_data()
                if section != ".data":
                    raise AssemblerError(".align só é suportado em .data", raw_line_no)
                n = parse_number(rest.strip(), raw_line_no)
                data_chunks.append(("__ALIGN__", n, raw_line_no, pending_label))
                pending_label = None
                continue

            if section != ".data":
                raise AssemblerError(f"diretiva {directive} só é válida em .data", raw_line_no)

            if directive in _DATA_ELEM_SIZE:  # .byte / .half / .word: aceitam continuação
                flush_pending_data()
                pending_data = {
                    "directive": directive, "label": pending_label,
                    "line_no": raw_line_no, "tokens": tokenize_values(rest),
                }
                pending_label = None
                continue

            # .asciz / .string / .space: sempre em uma única linha
            flush_pending_data()
            raw_bytes = parse_directive_data(directive, split_operands(rest), raw_line_no)
            data_chunks.append(DataChunk(raw_bytes, raw_line_no, pending_label, align=1))
            pending_label = None
            continue

        # não é rótulo nem diretiva: ou é continuação de valores (.data) ou instrução (.text)
        if section == ".data":
            if pending_data is None:
                raise AssemblerError(
                    "valores de dado encontrados fora de uma diretiva (.byte/.half/.word)", raw_line_no
                )
            pending_data["tokens"].extend(tokenize_values(line))
            continue

        # instrução
        flush_pending_data()  # defensivo; não deveria haver nada pendente aqui
        parts = line.split(None, 1)
        mnemonic = parts[0]
        args_str = parts[1] if len(parts) > 1 else ""
        operands = split_operands(args_str) if args_str else []

        for real_mn, real_ops in expand_pseudo(mnemonic, operands, raw_line_no):
            text_items.append(TextItem(real_mn, real_ops, raw_line_no, pending_label))
            pending_label = None  # só a primeira instrução expandida recebe o rótulo

    flush_pending_data()
    if pending_label is not None:
        raise AssemblerError(f"rótulo '{pending_label}' no final do arquivo sem instrução/dado associado", 0)

    # ------------------------------------------------------------------
    # 2a etapa: atribuir endereços
    #
    # IMPORTANTE: .data é resolvido ANTES de .text porque `la` (e, em
    # tese, `li` com um rótulo) depende dos endereços de dados já
    # conhecidos para decidir se vai gerar 1 palavra (addi) ou 2
    # palavras (lui+addi) — e isso precisa ser sabido ANTES de fixar o
    # endereço das instruções seguintes, senão todo rótulo de .text
    # depois de um li/la "grande" fica desalinhado (bug real encontrado
    # e corrigido durante o desenvolvimento deste assembler).
    # ------------------------------------------------------------------
    addr = DATA_BASE
    symtab_data = {}
    resolved_chunks = []
    for chunk in data_chunks:
        if isinstance(chunk, tuple) and chunk[0] == "__ALIGN__":
            _, n, line_no, label = chunk
            align_to = 1 << n
            pad = (-addr) % align_to
            if pad:
                resolved_chunks.append(DataChunk(b"\x00" * pad, line_no, None))
                addr += pad
            if label:
                symtab_data[label] = addr
            continue
        if chunk.align > 1:
            pad = (-addr) % chunk.align
            if pad:
                resolved_chunks.append(DataChunk(b"\x00" * pad, chunk.line_no, None))
                addr += pad
        if chunk.label:
            if chunk.label in symtab_data:
                raise AssemblerError(f"rótulo duplicado: '{chunk.label}'", chunk.line_no)
            symtab_data[chunk.label] = addr
        chunk.address = addr
        resolved_chunks.append(chunk)
        addr += len(chunk.data)

    def resolve_symbol(tok, line_no, table, kind):
        if tok in table:
            return table[tok]
        raise AssemblerError(f"rótulo indefinido em {kind}: '{tok}'", line_no)

    def li_word_count(value):
        """Quantas palavras uma sequência li/la vai ocupar, para o valor dado."""
        if _fits_signed(value, 12):
            return 1
        upper = (value + 0x800) >> 12
        lower = value - (upper << 12)
        return 2 if lower != 0 else 1

    def li_sequence(rd_tok, value, line_no):
        rd = parse_register(rd_tok, line_no)
        if _fits_signed(value, 12):
            return [encode_i(value, 0, 0b000, rd, 0b0010011, line_no)]
        upper = (value + 0x800) >> 12
        lower = value - (upper << 12)
        words = [encode_u(upper, rd, 0b0110111, line_no)]
        if lower != 0:
            words.append(encode_i(lower, rd, 0b000, rd, 0b0010011, line_no))
        return words

    def far_jump_sequence(pc, target, link_rd, base_reg, line_no):
        """Gera a sequência auipc+jalr usada por call/tail. Diferente de
        li_sequence, aqui SEMPRE geramos as 2 palavras (mesmo que o
        deslocamento coubesse num jal só) — é assim que o `call`/`tail`
        de verdade do RISC-V funciona, de propósito: o tamanho fixo em
        2 instruções deixa a codificação previsível (importante se um dia
        você quiser fazer relocação/linkedição, por exemplo)."""
        offset = target - pc
        upper = (offset + 0x800) >> 12
        lower = offset - (upper << 12)
        return [
            encode_u(upper, base_reg, 0b0010111, line_no),          # auipc base_reg, upper
            encode_i(lower, base_reg, 0b000, link_rd, 0b1100111, line_no),  # jalr link_rd, lower(base_reg)
        ]

    # ------------------------------------------------------------------
    # agora que os endereços de dados já são conhecidos, calculamos os
    # endereços de .text considerando o tamanho real (1 ou 2 palavras)
    # de cada li/la, e o tamanho FIXO (sempre 2 palavras) de call/tail.
    #
    # Note que call/tail NÃO precisam do valor do rótulo resolvido nesta
    # etapa (diferente de li/la) — o tamanho deles não depende do valor,
    # então dá pra somar 8 bytes direto e resolver o endereço de verdade
    # só na etapa de codificação final, quando symtab_text já está
    # completo (inclusive rótulos definidos mais adiante no arquivo).
    # ------------------------------------------------------------------
    addr = TEXT_BASE
    symtab_text = {}
    for item in text_items:
        if item.label:
            if item.label in symtab_text:
                raise AssemblerError(f"rótulo duplicado: '{item.label}'", item.line_no)
            symtab_text[item.label] = addr
        item.address = addr

        if item.mnemonic == "__LI__":
            imm_tok = item.operands[1]
            value = parse_number(imm_tok, item.line_no) if is_number(imm_tok) else resolve_symbol(imm_tok, item.line_no, symtab_data, "li")
            addr += 4 * li_word_count(value)
        elif item.mnemonic == "__LA__":
            label_tok = item.operands[1]
            value = resolve_symbol(label_tok, item.line_no, symtab_data, "la")
            addr += 4 * li_word_count(value)
        elif item.mnemonic in ("__CALL__", "__TAIL__"):
            addr += 8  # sempre auipc + jalr, tamanho fixo
        else:
            addr += 4

    # ------------------------------------------------------------------
    # 3a etapa: codificar instruções
    # ------------------------------------------------------------------

    rom_words = []
    for item in text_items:
        mn = item.mnemonic
        ops = item.operands
        ln = item.line_no
        pc = item.address

        if mn == "__LI__":
            rd_tok, imm_tok = ops
            value = parse_number(imm_tok, ln) if is_number(imm_tok) else resolve_symbol(imm_tok, ln, symtab_data, "li")
            words = li_sequence(rd_tok, value, ln)
            rom_words.extend(words)
            continue

        if mn == "__LA__":
            rd_tok, label_tok = ops
            value = resolve_symbol(label_tok, ln, symtab_data, "la")
            words = li_sequence(rd_tok, value, ln)
            rom_words.extend(words)
            continue

        if mn == "__CALL__":
            (label_tok,) = ops
            target = resolve_symbol(label_tok, ln, symtab_text, "call")
            rom_words.extend(far_jump_sequence(pc, target, 1, 1, ln))  # auipc ra,.. ; jalr ra, ..(ra)
            continue

        if mn == "__TAIL__":
            (label_tok,) = ops
            target = resolve_symbol(label_tok, ln, symtab_text, "tail")
            rom_words.extend(far_jump_sequence(pc, target, 0, 6, ln))  # auipc t1,.. ; jalr x0, ..(t1)
            continue

        kind, opcode, funct3, funct7 = INSTR_TABLE[mn]

        if kind == "R":
            rd, rs1, rs2 = ops
            word = encode_r(funct7, parse_register(rs2, ln), parse_register(rs1, ln),
                             funct3, parse_register(rd, ln), opcode)

        elif kind == "I-arith":
            rd, rs1, imm_tok = ops
            imm = parse_number(imm_tok, ln)
            word = encode_i(imm, parse_register(rs1, ln), funct3, parse_register(rd, ln), opcode, ln)

        elif kind == "I-shift":
            rd, rs1, shamt_tok = ops
            shamt = parse_number(shamt_tok, ln)
            word = encode_i_shift(shamt, parse_register(rs1, ln), funct3, parse_register(rd, ln), opcode, funct7, ln)

        elif kind == "I-load":
            rd, mem_tok = ops
            imm, rs1 = parse_mem_operand(mem_tok, ln)
            word = encode_i(imm, rs1, funct3, parse_register(rd, ln), opcode, ln)

        elif kind == "I-jalr":
            rd, mem_tok = ops
            imm, rs1 = parse_mem_operand(mem_tok, ln)
            word = encode_i(imm, rs1, funct3, parse_register(rd, ln), opcode, ln)

        elif kind == "S":
            rs2, mem_tok = ops
            imm, rs1 = parse_mem_operand(mem_tok, ln)
            word = encode_s(imm, parse_register(rs2, ln), rs1, funct3, opcode, ln)

        elif kind == "B":
            rs1, rs2, label_tok = ops
            target = parse_number(label_tok, ln) if is_number(label_tok) else resolve_symbol(label_tok, ln, symtab_text, "branch")
            offset = target - pc
            word = encode_b(offset, parse_register(rs1, ln), parse_register(rs2, ln), funct3, opcode, ln)

        elif kind == "J":
            rd, label_tok = ops
            target = parse_number(label_tok, ln) if is_number(label_tok) else resolve_symbol(label_tok, ln, symtab_text, "jal")
            offset = target - pc
            word = encode_j(offset, parse_register(rd, ln), opcode, ln)

        elif kind == "U":
            rd, imm_tok = ops
            imm = parse_number(imm_tok, ln)
            word = encode_u(imm, parse_register(rd, ln), opcode, ln)

        elif kind == "SYS":
            if ops:
                raise AssemblerError(f"'{mn}' não recebe operandos", ln)
            word = opcode  # rd=rs1=imm=0

        else:
            raise AssemblerError(f"tipo de instrução não tratado: {kind}", ln)

        rom_words.append(word & 0xFFFFFFFF)

    ram_bytes = bytearray()
    for chunk in resolved_chunks:
        ram_bytes.extend(chunk.data)

    return rom_words, ram_bytes, symtab_text, symtab_data, text_items


# ======================================================================
# SAÍDA
# ======================================================================

def write_rom_file(path, rom_words, depth):
    """Escreve o arquivo hex da ROM: 1 palavra de 32 bits (8 dígitos hex)
    por linha.

    NÃO preenche mais o arquivo com zeros até `depth` linhas: o
    `init_rom_hex` do ROM.vhd agora lê com `while idx < ROMDP and not
    endfile(...) loop`, ou seja, para de ler assim que o arquivo acaba (ou
    assim que ROMDP endereços forem preenchidos, o que vier primeiro) e
    deixa os endereços restantes zerados por conta própria. `depth` aqui só
    serve como limite de validação (estoura erro se o programa não couber
    na ROM), igual já acontecia com `write_ram_file`.
    """
    if len(rom_words) > depth:
        raise AssemblerError(
            f"programa tem {len(rom_words)} palavras, maior que a profundidade "
            f"da ROM ({depth}); aumente --rom-depth ou o generic ROMSIZE"
        )
    with open(path, "w") as f:
        for w in rom_words:
            f.write(f"{w:08X}\n")


def write_ram_file(path, ram_bytes, depth):
    """Escreve o arquivo hex da RAM: 1 palavra de 32 bits (8 dígitos hex)
    por linha — NÃO mais 1 byte por linha.

    Diferente da ROM, isso NÃO é preenchido até `depth`: o arquivo para
    logo depois do último dado real. `depth` aqui só serve como um limite
    de validação (estoura erro se .data não couber na RAM), não como meta
    de preenchimento — já que quem vai carregar isso é o SEU testbench,
    com o laço que você escrever (ver sugestão no final deste arquivo);
    não há nenhum `for II in 0 to RAMDP-1` fixo forçando um tamanho exato
    como no ROM.vhd.

    Se os bytes de `ram_bytes` não forem múltiplos de 4, a ÚLTIMA palavra
    é completada com zeros à direita (endereços mais altos) — só o
    suficiente pra fechar essa última palavra, nada além disso.

    Sobre a ordem dos bytes dentro de cada palavra: usamos BIG-ENDIAN
    (byte mais significativo primeiro), porque é isso que o seu RAM.vhd
    realmente implementa na escrita/leitura de palavra (apesar do
    comentário "-- little-endian" que está lá, o código ali é big-endian
    de fato — ver parse_directive_data() para o detalhe). Ou seja, cada
    linha deste arquivo já é exatamente o valor de 32 bits que um `lw`
    devolveria, na ordem natural de leitura.
    """
    n_bytes = len(ram_bytes)
    if n_bytes > depth:
        raise AssemblerError(
            f".data ocupa {n_bytes} bytes, maior que a profundidade "
            f"da RAM ({depth}); aumente --ram-depth ou o generic RAMSIZE"
        )
    pad = (-n_bytes) % 4  # zeros só para completar a ÚLTIMA palavra, se preciso
    data = bytes(ram_bytes) + b"\x00" * pad
    with open(path, "w") as f:
        for i in range(0, len(data), 4):
            word = data[i:i + 4]  # já em ordem big-endian (ver docstring)
            f.write(word.hex().upper() + "\n")


# ======================================================================
# DESMONTADOR (usado só para gerar o arquivo --intermediate)
#
# Decodifica o próprio código de máquina já gerado (não o fonte), então
# além de servir de listagem legível, funciona como uma conferência
# extra de que a codificação bateu com o que a CPU vai realmente
# interpretar (inclusive o esquema PC_REL_HALVED de branch/jal).
# ======================================================================

_REG_NAMES_BY_NUM = [
    "zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2", "s0", "s1",
    "a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7",
    "s2", "s3", "s4", "s5", "s6", "s7", "s8", "s9", "s10", "s11",
    "t3", "t4", "t5", "t6",
]


def _sext(v, bits):
    if v & (1 << (bits - 1)):
        v -= (1 << bits)
    return v


def disassemble_word(word, pc):
    R = _REG_NAMES_BY_NUM
    opcode = word & 0x7F
    rd = (word >> 7) & 0x1F
    funct3 = (word >> 12) & 0x7
    rs1 = (word >> 15) & 0x1F
    rs2 = (word >> 20) & 0x1F
    funct7 = (word >> 25) & 0x7F

    if opcode == 0b0110011:
        names = {(0, 0): "add", (0, 0x20): "sub", (1, 0): "sll", (2, 0): "slt", (3, 0): "sltu",
                 (4, 0): "xor", (5, 0): "srl", (5, 0x20): "sra", (6, 0): "or", (7, 0): "and"}
        name = names.get((funct3, funct7), f"??R({funct3},{funct7:#x})")
        return f"{name} {R[rd]}, {R[rs1]}, {R[rs2]}"
    if opcode == 0b0010011:
        if funct3 in (1, 5):
            shamt = (word >> 20) & 0x1F
            name = {(1, 0): "slli", (5, 0): "srli", (5, 0x20): "srai"}.get((funct3, funct7), "??shift")
            return f"{name} {R[rd]}, {R[rs1]}, {shamt}"
        imm = _sext((word >> 20) & 0xFFF, 12)
        name = {0: "addi", 2: "slti", 3: "sltiu", 4: "xori", 6: "ori", 7: "andi"}.get(funct3, "??i")
        return f"{name} {R[rd]}, {R[rs1]}, {imm}"
    if opcode == 0b0000011:
        imm = _sext((word >> 20) & 0xFFF, 12)
        return f"lw {R[rd]}, {imm}({R[rs1]})"
    if opcode == 0b0100011:
        imm = _sext(((word >> 25) << 5) | ((word >> 7) & 0x1F), 12)
        return f"sw {R[rs2]}, {imm}({R[rs1]})"
    if opcode == 0b1100011:
        b12 = (word >> 31) & 1
        b11 = (word >> 7) & 1
        b10_5 = (word >> 25) & 0x3F
        b4_1 = (word >> 8) & 0xF
        y = (b12 << 12) | (b11 << 11) | (b10_5 << 5) | (b4_1 << 1)
        y = _sext(y, 13)
        off = y * 2 if PC_REL_HALVED else y
        name = {0: "beq", 1: "bne"}.get(funct3, "??b")
        return f"{name} {R[rs1]}, {R[rs2]}, {pc+off:#06x}  (offset={off})"
    if opcode == 0b1101111:
        b20 = (word >> 31) & 1
        b19_12 = (word >> 12) & 0xFF
        b11 = (word >> 20) & 1
        b10_1 = (word >> 21) & 0x3FF
        y = (b20 << 20) | (b19_12 << 12) | (b11 << 11) | (b10_1 << 1)
        y = _sext(y, 21)
        off = y * 2 if PC_REL_HALVED else y
        return f"jal {R[rd]}, {pc+off:#06x}  (offset={off})"
    if opcode == 0b1100111:
        imm = _sext((word >> 20) & 0xFFF, 12)
        return f"jalr {R[rd]}, {imm}({R[rs1]})"
    if opcode == 0b0110111:
        imm = (word >> 12) & 0xFFFFF
        return f"lui {R[rd]}, {imm:#x}"
    if opcode == 0b0010111:
        imm = (word >> 12) & 0xFFFFF
        return f"auipc {R[rd]}, {imm:#x}"
    if opcode == 0b1110011:
        return "ecall"
    return f"??? opcode={opcode:#04x} word={word:08x}"


def write_intermediate_listing(path, rom_words, symtab_text, symtab_data):
    """Escreve uma listagem legível do programa já montado: pseudo-instruções
    expandidas em instruções reais e rótulos resolvidos em endereços/offsets
    numéricos — exatamente o que a CPU vai executar."""
    with open(path, "w", encoding="utf-8") as f:
        f.write("; arquivo intermediário gerado automaticamente — NÃO é o fonte original.\n")
        f.write(f"; PC_REL_HALVED = {PC_REL_HALVED}\n")
        if symtab_text:
            f.write(";\n; símbolos de .text (ROM):\n")
            for name, a in sorted(symtab_text.items(), key=lambda x: x[1]):
                f.write(f";   {a:#06x}  {name}\n")
        if symtab_data:
            f.write(";\n; símbolos de .data (RAM):\n")
            for name, a in sorted(symtab_data.items(), key=lambda x: x[1]):
                f.write(f";   {a:#06x}  {name}\n")
        f.write(";\n\n")
        pc = 0
        for w in rom_words:
            f.write(f"{pc:#06x}:  {w:08X}   {disassemble_word(w, pc)}\n")
            pc += 4


# ======================================================================
# MAIN
# ======================================================================

def main():
    global PC_REL_HALVED

    ap = argparse.ArgumentParser(description="Assembler RV32I (subset) para o processador uniciclo")
    ap.add_argument("source", help="arquivo assembly de entrada (.asm/.s/.txt)")
    ap.add_argument("-o", "--output", default="data.txt", help="arquivo de saída para a ROM (default: data.txt)")
    ap.add_argument("--ram", default=None, help="arquivo de saída para a RAM (default: não gera)")
    ap.add_argument("--intermediate", default=None,
                     help="arquivo com o programa desmontado (pseudo expandidas, rótulos resolvidos)")
    ap.add_argument("--rom-depth", type=int, default=DEFAULT_ROM_DEPTH, help="profundidade da ROM em palavras")
    ap.add_argument("--ram-depth", type=int, default=DEFAULT_RAM_DEPTH, help="profundidade da RAM em bytes")
    ap.add_argument("--pc-rel-standard", action="store_true",
                     help="usa a codificação PADRÃO RV32I (não 'halved') para offsets de branch/jal — "
                          "só use se tiver certeza de que não é o seu caso (ver cabeçalho do arquivo)")
    ap.add_argument("-v", "--verbose", action="store_true", help="imprime endereços e contagem de instruções")
    args = ap.parse_args()

    if args.pc_rel_standard:
        PC_REL_HALVED = False

    with open(args.source, "r", encoding="utf-8") as f:
        source = f.read()

    try:
        rom_words, ram_bytes, symtab_text, symtab_data, text_items = assemble(source)
    except AssemblerError as e:
        print(f"Erro de assembly: {e}", file=sys.stderr)
        sys.exit(1)

    try:
        write_rom_file(args.output, rom_words, args.rom_depth)
    except AssemblerError as e:
        print(f"Erro de assembly: {e}", file=sys.stderr)
        sys.exit(1)
    print(f"ROM: {len(rom_words)} instrução(ões) escrita(s) em '{args.output}' "
          f"(profundidade total {args.rom_depth} palavras)")

    if args.ram is not None:
        try:
            write_ram_file(args.ram, ram_bytes, args.ram_depth)
        except AssemblerError as e:
            print(f"Erro de assembly: {e}", file=sys.stderr)
            sys.exit(1)
        print(f"RAM: {len(ram_bytes)} byte(s) de dado escrito(s) em '{args.ram}' "
              f"(profundidade total {args.ram_depth} bytes)")
    elif len(ram_bytes) > 0:
        print("Aviso: seção .data encontrada, mas nenhum --ram foi passado; "
              "os dados NÃO foram gravados em nenhum arquivo.", file=sys.stderr)

    if args.intermediate is not None:
        write_intermediate_listing(args.intermediate, rom_words, symtab_text, symtab_data)
        print(f"Listagem intermediária escrita em '{args.intermediate}'")

    if args.verbose:
        print("\n--- Símbolos (.text / ROM) ---")
        for name, a in sorted(symtab_text.items(), key=lambda x: x[1]):
            print(f"  {a:04X}: {name}")
        print("\n--- Símbolos (.data / RAM) ---")
        for name, a in sorted(symtab_data.items(), key=lambda x: x[1]):
            print(f"  {a:04X}: {name}")
        print(f"\nPC_REL_HALVED = {PC_REL_HALVED}")


if __name__ == "__main__":
    main()


# ======================================================================
# Como carregar o ram_init.txt no testbench
#
# A RAM (RAM.vhd) já carrega o arquivo sozinha, através do generic
# INIT_FILE (propagado pelo generic RAM_FILE da entidade uRV/CPU.vhd) —
# não é mais necessário nenhum código no testbench para a CARGA inicial.
# Basta instanciar a CPU assim:
#
#     dut: uRV
#       generic map(ROM_FILE => "instrucoes_hex/i1.txt",
#                   RAM_FILE => "ram_input/ram1.txt")
#       port map(clk => clk, halt => halt, exit_code => exit_code);
#
# O que o testbench ainda precisa fazer "na mão" é LER o conteúdo FINAL da
# RAM ao fim da simulação, para comparar com o arquivo de saída esperada —
# e isso sim exige "external names" (VHDL-2008), já que a RAM só expõe
# leitura de 1 endereço por vez através da porta normal (mais a porta de
# depuração dbg_addr/dbg_byte, também 1 byte por vez). Ver tb_uRV.vhd para
# o exemplo completo; a ideia central é:
#
#     type ram_bytes_t is array(0 to RAMDP-1) of std_logic_vector(7 downto 0);
#     alias ram_mem : ram_bytes_t is << signal .tb_uRV.dut.ramDM.mem : ram_bytes_t >>;
#
#     -- ram_mem(endereço) já reflete o estado atual da RAM, sem precisar
#     -- de nenhum ciclo de leitura adicional através da porta normal.
# ======================================================================