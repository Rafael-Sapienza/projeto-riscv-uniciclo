# teste2.asm - Quicksort de um vetor de 25 inteiros
#
# Ao contrário de teste1.asm (bubble sort, sem chamadas de função), este
# programa é recursivo: quicksort(lo, hi) chama partition(lo, hi) e a si
# mesma duas vezes, usando uma pilha real em RAM (registrador sp = x2) e
# a convenção padrão de chamada do RISC-V (ra salvo pelo chamado, s0-s3
# preservados entre chamadas). Isso exercita call/ret (auipc+jalr, jalr)
# e auipc de forma muito mais completa do que teste1.asm.
#
# Lista desordenada de entrada (arr), 25 inteiros:
#   88, 3, 45, 12, 67, 90, 5, 34, 76, 21, 9, 58, 41, 2, 99, 14, 63, 27,
#   80, 6, 52, 19, 71, 38, 1
# Saída esperada, em ordem crescente (ver expected2.txt):
#   1, 2, 3, 5, 6, 9, 12, 14, 19, 21, 27, 34, 38, 41, 45, 52, 58, 63, 67,
#   71, 76, 80, 88, 90, 99

.data
arr: .word 88, 3, 45, 12, 67, 90, 5, 34, 76, 21, 9, 58, 41, 2, 99, 14, 63, 27, 80, 6, 52, 19, 71, 38, 1

.text
main:
    li   sp, 4096       # topo da pilha: bem acima do vetor (100 bytes), com folga
    li   a0, 0          # lo = 0
    li   a1, 24          # hi = n-1 = 24  (25 elementos)
    call quicksort

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
