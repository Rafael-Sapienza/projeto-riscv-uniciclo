# teste1.asm - Bubble sort de um vetor de 10 inteiros
#
# Lista desordenada de entrada (arr): 29, 10, 14, 37, 3, 100, 5, 22, 68, 1
# Saída esperada, em ordem crescente:  1, 3, 5, 10, 14, 22, 29, 37, 68, 100
# (ver expected1.txt, com essas 10 palavras em hexadecimal)
#
# Ao final da ordenação, o programa chama "ecall" com a7=93 (Exit2, a0=0),
# sinalizando para o testbench que a execução terminou.

.data
arr: .word 29, 10, 14, 37, 3, 100, 5, 22, 68, 1

.text
main:
    la   a0, arr        # a0 = &arr[0]  (base do vetor)
    li   t0, 10         # t0 = n (tamanho do vetor)

    li   s0, 0          # s0 = i = 0
outer:
    li   t1, 9          # t1 = n - 1
    bge  s0, t1, end_outer   # if (i >= n-1) goto end_outer

    li   s1, 0          # s1 = j = 0
    mv   s2, a0         # s2 = &arr[0]  (ponteiro percorrendo a linha)
    sub  t2, t0, s0     # t2 = n - i
    addi t2, t2, -1     # t2 = n - i - 1  (limite do laço interno)

inner:
    bge  s1, t2, end_inner   # if (j >= n-i-1) goto end_inner

    lw   t3, 0(s2)      # t3 = arr[j]
    lw   t4, 4(s2)      # t4 = arr[j+1]
    ble  t3, t4, no_swap     # if (arr[j] <= arr[j+1]) goto no_swap

    sw   t4, 0(s2)      # arr[j]   = t4
    sw   t3, 4(s2)      # arr[j+1] = t3

no_swap:
    addi s2, s2, 4      # avança o ponteiro para o próximo par
    addi s1, s1, 1      # j++
    j    inner

end_inner:
    addi s0, s0, 1      # i++
    j    outer

end_outer:
    li   a0, 0          # código de saída = 0
    li   a7, 93         # a7 = 93 (Exit2)
    ecall
