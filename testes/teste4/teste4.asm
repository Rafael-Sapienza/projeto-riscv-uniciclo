# teste4.asm - Teste de cobertura de instrucoes / stress test
#
# Os testes anteriores (teste1: bubble sort; teste2/teste3: quicksort
# recursivo) usam, na pratica, um subconjunto pequeno do datapath: apenas
# add/addi (inclusive via slt interno das pseudo-instrucoes de desvio
# bge/blt/bgt/ble), lw/sw, beq/bne, jal/jalr/auipc. Nenhum deles chega a
# gerar, no ROM final, uma instrucao real "and", "or", "xor", "sub", "sll",
# "srl", "sra" (R-type) nem "andi"/"ori"/"xori"/"slli"/"srli"/"srai"/
# "slti"/"sltiu" (I-type) -- ou seja, boa parte da tabela de ALUControl
# nunca foi de fato exercitada por uma simulacao real.
#
# Este teste combina:
#   1. Um quicksort recursivo maior (40 inteiros, com negativos, zero,
#      duplicatas e os extremos de 32 bits com sinal: 2147483647 e
#      -2147483648) -- mais profundidade de pilha que teste2/teste3 e
#      casos de borda para comparacao com sinal.
#   2. Um hash simples (hash = hash*31 + palavra, calculado como
#      (hash<<5 - hash) + palavra, sem instrucao de multiplicacao) sobre
#      o vetor ja ordenado.
#   3. Um CRC-32 "bit a bit" (variante por palavra de 32 bits, nao por
#      byte) sobre o mesmo vetor ordenado -- 40 * 32 = 1280 iteracoes do
#      laco interno, cada uma com xor/andi/srli/beq, uma cobertura muito
#      mais profunda do caminho de desvio/ALU do que qualquer teste
#      anterior.
#   4. Um bloco de "cobertura de instrucoes": executa explicitamente cada
#      instrucao R-type/I-type que os testes anteriores nunca geraram
#      (and, or, xor, sub [via neg], sra, slt, sltu, slti, sltiu, ori,
#      xori, srai, srli) sobre valores conhecidos, gravando cada
#      resultado num endereco fixo de RAM para conferencia em
#      expected4.txt.
#   5. Um caso de teste dirigido a um bug suspeito encontrado por
#      inspecao de codigo: em ALUCtrl.vhdl, o campo funct7 usado para
#      distinguir SUB de ADD (quando funct3="000") vem incondicionalmente
#      de imOUT(31 downto 25) (ver CPU.vhd, alias Ifunct7), tanto para
#      instrucoes R-type quanto I-type. Para "addi", esses mesmos bits
#      NAO sao um funct7 de verdade: sao os 7 bits mais altos do
#      imediato de 12 bits (imm[11:5]). Se esse campo, para um dado
#      imediato, calhar de valer exatamente "0100000" (ou seja, um
#      imediato entre 1024 e 1055), a ALUControl pode interpretar
#      erroneamente a instrucao como SUB em vez de ADD. O teste abaixo
#      executa "addi t3, t3, 1030" (1030 esta dentro dessa faixa) a
#      partir de um valor conhecido e grava o resultado em RAM: o valor
#      correto e 500+1030=1530; se o bug existir, o hardware real vai
#      calcular 500-1030=-530 em vez disso.
#   6. Limpeza da regiao de pilha usada (mesma tecnica de teste3), para
#      permitir rodar com CHECK_TAIL_ZERO=true e verificar a RAM inteira.
#
# Vetor de entrada (arr), 40 inteiros, com negativos, duplicata (7,7) e
# os extremos de 32 bits com sinal:
#   17, -5, 42, 100, -100, 0, 7, 7, -1, 2147483647,
#   -2147483648, 33, -33, 256, -256, 8, 9, -9, 15, -15,
#   23, 1000, -1000, 3, -3, 500, -500, 64, -64, 12,
#   -12, 45, -45, 99, -99, 200, -200, 1, -123456, 123456

.data
arr: .word 17, -5, 42, 100, -100, 0, 7, 7, -1, 2147483647
     -2147483648, 33, -33, 256, -256, 8, 9, -9, 15, -15
     23, 1000, -1000, 3, -3, 500, -500, 64, -64, 12
     -12, 45, -45, 99, -99, 200, -200, 1, -123456, 123456
# results: 15 palavras, todas zeradas antes do programa gravar nelas
#   0:hash  4:crc  8:and  12:or  16:xor  20:sra  24:slt  28:sltu
#   32:slti 36:sltiu 40:ori 44:xori 48:srai 52:srli(negativo) 56:addi(bug?)
results: .word 0:15

.text
main:
    li   sp, 4096       # topo da pilha
    li   a0, 0          # lo = 0
    li   a1, 39         # hi = n-1 = 39  (40 elementos)
    call quicksort

    # -------------------------------------------------------------
    # hash = hash*31 + arr[i], para i = 0..39, sobre o vetor ordenado
    # (hash*31 == (hash<<5) - hash -- evita precisar de multiplicacao)
    # -------------------------------------------------------------
    la   s4, arr        # s4 = ponteiro para arr (persiste ate o fim do CRC)
    li   s5, 0          # s5 = i
    li   s6, 0          # s6 = hash
hash_loop:
    li   t0, 40
    bge  s5, t0, hash_done
    slli t1, s5, 2
    add  t1, s4, t1
    lw   t2, 0(t1)          # t2 = arr[i]
    slli t3, s6, 5
    sub  t3, t3, s6         # t3 = hash*31
    add  s6, t3, t2         # hash = hash*31 + arr[i]
    addi s5, s5, 1
    j    hash_loop
hash_done:
    la   t0, results
    sw   s6, 0(t0)          # results[0] = hash

    # -------------------------------------------------------------
    # CRC-32 bit a bit (variante por palavra de 32 bits) sobre arr
    # -------------------------------------------------------------
    li   s6, -1         # crc = 0xFFFFFFFF
    li   s5, 0          # i = 0
crc_word_loop:
    li   t0, 40
    bge  s5, t0, crc_done
    slli t1, s5, 2
    add  t1, s4, t1
    lw   t2, 0(t1)          # t2 = arr[i]
    xor  s6, s6, t2         # crc ^= arr[i]

    li   s7, 0              # j = 0 (contador de bits)
crc_bit_loop:
    li   t0, 32
    bge  s7, t0, crc_bit_done
    andi t3, s6, 1           # t3 = crc & 1
    srli s6, s6, 1           # crc >>= 1 (logico, sem sinal)
    beq  t3, x0, crc_no_xor
    li   t4, 0xEDB88320      # polinomio CRC-32 (reverso)
    xor  s6, s6, t4
crc_no_xor:
    addi s7, s7, 1
    j    crc_bit_loop
crc_bit_done:
    addi s5, s5, 1
    j    crc_word_loop
crc_done:
    xori s6, s6, -1          # crc ^= 0xFFFFFFFF (imediato -1 = todos os bits 1)
    la   t0, results
    sw   s6, 4(t0)           # results[1] = crc

    # -------------------------------------------------------------
    # bloco de cobertura: instrucoes nunca exercitadas por teste1/2/3
    # -------------------------------------------------------------
    la   s4, results         # s4 = ponteiro para results (reaproveitado)
    li   t0, 0x0F0F0F0F      # A
    li   t1, 0x00FF00FF      # B

    and  t3, t0, t1          # A & B = 0x000F000F
    sw   t3, 8(s4)

    or   t3, t0, t1          # A | B = 0x0FFF0FFF
    sw   t3, 12(s4)

    xor  t3, t0, t1          # A ^ B = 0x0FF00FF0
    sw   t3, 16(s4)

    li   t4, 0x80000000      # NEG = -2147483648 (extremo com sinal)
    li   t5, 4
    sra  t3, t4, t5          # NEG >>a 4 (aritmetico, com sinal) = 0xF8000000
    sw   t3, 20(s4)

    slt  t3, t4, t0          # NEG < A (com sinal)?  sim -> 1
    sw   t3, 24(s4)

    sltu t3, t4, t0          # NEG < A (sem sinal, NEG vira 0x80000000)? nao -> 0
    sw   t3, 28(s4)

    slti t3, t0, 100         # A < 100 (com sinal)? nao (A e grande e positivo) -> 0
    sw   t3, 32(s4)

    sltiu t3, x0, 1          # 0 < 1 (sem sinal)? sim -> 1
    sw   t3, 36(s4)

    ori  t3, x0, 0xFF        # 0 | 0xFF = 0x000000FF
    sw   t3, 40(s4)

    xori t3, t0, 0xFF        # A ^ 0xFF = 0x0F0F0FF0
    sw   t3, 44(s4)

    srai t3, t4, 4           # NEG >>a 4 (imediato) = 0xF8000000 (igual ao sra acima)
    sw   t3, 48(s4)

    srli t3, t4, 4           # NEG >>l 4 (logico, imediato) = 0x08000000 (NAO extende sinal)
    sw   t3, 52(s4)

    # addi com imediato na faixa suspeita (1024..1055): ver comentario no
    # topo do arquivo. Correto: 500 + 1030 = 1530.
    li   t3, 500
    addi t3, t3, 1030
    sw   t3, 56(s4)

    # -------------------------------------------------------------
    # limpa a regiao de pilha eventualmente usada pelo quicksort acima
    # (profundidade maxima bem menor que 1024 bytes para 40 elementos)
    # -------------------------------------------------------------
    li   t0, 2800
    li   t1, 4096
clean_loop:
    bge  t0, t1, clean_done
    sw   zero, 0(t0)
    addi t0, t0, 4
    j    clean_loop
clean_done:

    li   a0, 0          # codigo de saida = 0
    li   a7, 93         # Exit2
    ecall

# ---------------------------------------------------------------------
# quicksort(lo, hi): a0 = lo, a1 = hi (indices, nao enderecos)
# ---------------------------------------------------------------------
quicksort:
    bge  a0, a1, qs_ret      # if (lo >= hi) return

    addi sp, sp, -16
    sw   ra, 12(sp)
    sw   s0, 8(sp)
    sw   s1, 4(sp)
    sw   s2, 0(sp)

    mv   s0, a0              # s0 = lo
    mv   s1, a1              # s1 = hi

    call partition           # a0=lo, a1=hi ja setados; retorna p em a0
    mv   s2, a0              # s2 = p

    mv   a0, s0              # quicksort(lo, p-1)
    addi a1, s2, -1
    call quicksort

    addi a0, s2, 1           # quicksort(p+1, hi)
    mv   a1, s1
    call quicksort

    lw   s2, 0(sp)
    lw   s1, 4(sp)
    lw   s0, 8(sp)
    lw   ra, 12(sp)
    addi sp, sp, 16
qs_ret:
    ret

# ---------------------------------------------------------------------
# partition(lo, hi): a0 = lo, a1 = hi -- retorna o indice do pivo em a0
# pivo = arr[hi]; particiona [lo,hi] de forma que tudo <= pivo fique
# antes dele e tudo > pivo fique depois (particao de Lomuto).
# ---------------------------------------------------------------------
partition:
    addi sp, sp, -20
    sw   ra, 16(sp)
    sw   s0, 12(sp)          # s0 = lo
    sw   s1, 8(sp)           # s1 = hi
    sw   s2, 4(sp)           # s2 = i
    sw   s3, 0(sp)           # s3 = pivo (valor)

    mv   s0, a0
    mv   s1, a1

    la   t0, arr
    slli t1, s1, 2
    add  t1, t0, t1
    lw   s3, 0(t1)           # pivo = arr[hi]

    addi s2, s0, -1          # i = lo - 1
    mv   t2, s0              # j = lo

part_loop:
    bge  t2, s1, part_loop_end   # for (j = lo; j < hi; j++)

    la   t0, arr
    slli t1, t2, 2
    add  t1, t0, t1
    lw   t3, 0(t1)           # t3 = arr[j]

    bgt  t3, s3, part_skip   # if (arr[j] <= pivo) { i++; swap(arr[i],arr[j]) }
    addi s2, s2, 1
    la   t0, arr
    slli t4, s2, 2
    add  t4, t0, t4          # t4 = &arr[i]
    lw   t5, 0(t4)           # t5 = arr[i]
    sw   t3, 0(t4)           # arr[i] = arr[j]
    sw   t5, 0(t1)           # arr[j] = arr[i] (valor antigo)
part_skip:
    addi t2, t2, 1
    j    part_loop

part_loop_end:
    addi s2, s2, 1           # i++  (posicao final do pivo)
    la   t0, arr
    slli t1, s2, 2
    add  t1, t0, t1          # t1 = &arr[i]
    lw   t3, 0(t1)           # t3 = arr[i]
    slli t4, s1, 2
    add  t4, t0, t4          # t4 = &arr[hi]
    lw   t5, 0(t4)           # t5 = arr[hi] (= pivo)
    sw   t5, 0(t1)           # arr[i]  = pivo
    sw   t3, 0(t4)           # arr[hi] = valor antigo de arr[i]

    mv   a0, s2              # retorna i

    lw   s3, 0(sp)
    lw   s2, 4(sp)
    lw   s1, 8(sp)
    lw   s0, 12(sp)
    lw   ra, 16(sp)
    addi sp, sp, 20
    ret
