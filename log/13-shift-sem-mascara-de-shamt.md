# 13 — SLL/SRL/SRA (tipo R) sem máscara no shamt

## Contexto

Ao rodar `testes/teste4` (ver [12-addi-confundido-com-sub.md](12-addi-confundido-com-sub.md)
para o defeito principal encontrado por esse teste), o ModelSim também
acusou, uma única vez, durante a execução:

```
** Warning: (vsim-151) NUMERIC_STD.TO_INTEGER: Value -1296 is not in
   bounds of subtype NATURAL.
   Time: 30015 ns  Iteration: 4  Instance: /tb_urv/dut/aluULA
```

Diferente dos demais itens deste registro, este **não foi confirmado**
como a causa exata desse warning específico (não foi possível isolar,
por trace, qual instrução exatamente o disparou, e o resultado final da
RAM bateu perfeitamente com o esperado em todos os endereços exceto o do
item 12 — ou seja, se este defeito chegou a se manifestar, foi de forma
transitória, sem corromper nenhum resultado armazenado). Ainda assim, o
defeito abaixo é real e foi corrigido, por ser o candidato mais provável
para esse tipo de warning e um desvio de especificação genuíno.

## Diagnóstico

Em `ULA.vhd`, as instruções de deslocamento tipo R (`SLL`/`SRL`/`SRA`)
usavam o registrador `B` inteiro (32 bits) como quantidade de
deslocamento:

```vhdl
when uSLL  => a32 <= std_logic_vector(shift_left(unsigned(A), to_integer(unsigned(B))));
when uSRL  => a32 <= std_logic_vector(shift_right(unsigned(A), to_integer(unsigned(B))));
when uSRA  => a32 <= std_logic_vector(shift_right(signed(A), to_integer(unsigned(B))));
```

A especificação RV32I define que apenas os 5 bits menos significativos de
`rs2` (`B`) valem como quantidade de deslocamento (`shamt`) — o restante
deveria ser ignorado. Como o código usava `B` inteiro, dois problemas
concretos existem:

1. **Resultado errado**: se um programa fizer `sll`/`srl`/`sra` com um
   registrador contendo, por exemplo, 33, o hardware deslocaria por 33
   posições (resultado sempre zero, ou só o bit de sinal repetido no caso
   de SRA) em vez dos 33 mod 32 = 1 posição esperados.
2. **Estouro de `NATURAL`**: se o bit mais alto de `B` estiver ligado
   (ou seja, `B`, sem sinal, valer 2³¹ ou mais), `to_integer(unsigned(B))`
   tenta representar um valor fora do intervalo de `NATURAL`
   (0 a 2³¹-1), o que o ModelSim acusa como o warning acima.

Nenhuma instrução `sll`/`srl`/`sra` tipo R usada em `teste1`-`teste4` tem
essa característica (o único `sra` de `teste4` usa quantidade de
deslocamento 4, vindo de um registrador com valor pequeno e conhecido) —
por isso o defeito nunca chegou a corromper um resultado final, apesar de
genuíno.

## Correção

`ULA.vhd` agora corta `B` para os 5 bits menos significativos antes de
converter para inteiro, tanto em SLL quanto em SRL/SRA:

```vhdl
when uSLL  => a32 <= std_logic_vector(shift_left(unsigned(A), to_integer(unsigned(B(4 downto 0)))));
when uSRL  => a32 <= std_logic_vector(shift_right(unsigned(A), to_integer(unsigned(B(4 downto 0)))));
when uSRA  => a32 <= std_logic_vector(shift_right(signed(A), to_integer(unsigned(B(4 downto 0)))));
```

Isso não muda o resultado das instruções de deslocamento imediato
(`slli`/`srli`/`srai`), já que `genImm32` já entrega, nesses casos, o
`shamt` isolado e zero-estendido (ver `ImmGen.vhd`, tipo `ITS`) — o corte
só passa a importar, de fato, quando `B` vem de um registrador de
propósito geral (tipo R), que pode conter qualquer valor de 32 bits.
