# 05 — PC permanecia indeterminado (`XXXXXXXX`) por falta de reset

## Sintoma

Após a eliminação do laço combinacional (documento 02) e das leituras
síncronas indevidas (documentos 03 e 04), a simulação
passou a avançar no tempo, mas um trace de depuração (impressão do PC e de
registradores a cada ciclo, adicionado temporariamente à CPU para esse
fim) mostrava o valor do PC permanentemente indeterminado:

```
step=0 pc=XXXXXXXX instr=00000513 s0=0 s1=0 s2=XXXXXXXX ...
step=1 pc=XXXXXXXX instr=00000513 s0=0 s1=0 s2=XXXXXXXX ...
...
```

O valor de `instr` permanecia igual em todos os ciclos (sempre a primeira
instrução do programa), o que indicava que o processador nunca avançava
para a instrução seguinte, mesmo com o clock em execução normal.

## Diagnóstico

Em VHDL, um sinal do tipo `std_logic` (ou `std_logic_vector`) que nunca
recebe um valor definido permanece no estado `'U'` ("uninitialized"), que
se propaga por qualquer operação lógica ou aritmética que o utilize como
operando. Ao ser impresso em hexadecimal, um vetor com bits em `'U'` é
exibido como uma sequência de `X`, daí o `pc=XXXXXXXX` observado.

O registrador do PC (`regPC`, instanciado a partir do componente `REG` em
`CPU.vhd`) possui uma entrada de `clr` (limpeza assíncrona) que, antes da
correção, estava permanentemente amarrada a `'0'`:

```vhdl
regPC: REG port map(pcIN, clk, cnstZERO, cnstONE, pcOUT);
```

O componente `REG` só atribui um valor definido à sua saída em duas
situações: quando `clr = '1'` (a saída é forçada a zero) ou quando ocorre
uma borda de subida do clock com a entrada de carga (`ld`) ativa (a saída
recebe o valor da entrada `d`). Como `clr` nunca era ativado, a única fonte
de um valor definido para `pcOUT` seria a entrada `d` (isto é, `pcIN`) — mas
`pcIN` é calculado, no caso comum, a partir do próprio `pcOUT` (via
`pcp4OUT = pcOUT + 4`, e `pcIN <= pcp4OUT`). Ou seja, uma vez que `pcOUT`
começa indeterminado, esse valor indeterminado realimenta o cálculo de
`pcIN`, que é gravado de volta em `pcOUT` na borda seguinte do clock —
perpetuando o estado indeterminado indefinidamente. Diferentemente do
problema do documento 02, aqui não há um laço combinacional (o registrador
efetivamente atualiza seu valor a cada ciclo), mas sim a ausência de
qualquer mecanismo capaz de introduzir um valor definido nesse laço pela
primeira vez.

Chama-se a atenção para um detalhe que motivou parte da investigação: o
sinal `pcOUT`, em sua declaração, possui um valor inicial explícito
(`:= (others => '0')`). Ainda assim, esse valor inicial não se mostrou
suficiente para "resolver" o problema na prática: como `pcOUT` está
associado à saída de um componente (`REG`) cuja porta de saída não possui
valor padrão próprio, e cujo processo interno não atribui nenhum valor
definido enquanto `clr = '0'` e nenhuma borda de subida de clock ocorreu
ainda, o valor inicial declarado no sinal do lado de fora não se propaga
para dentro do componente da forma que seria esperada de uma inicialização
implícita. Isso reforça que, em VHDL, a única forma confiável de garantir
um valor definido para um registrador é através de um sinal de reset
explícito.

## Correção

Foi adicionada uma porta de `reset` à entidade `uRV`, conectada à entrada
`clr` de `regPC` (em substituição à constante `'0'` usada anteriormente):

```vhdl
regPC: REG port map(pcIN, clk, reset, cnstONE, pcOUT);
```

O testbench (`tb_uRV.vhd`) passou a gerar um pulso de reset antes de
liberar a execução do clock:

```vhdl
reset <= '1';
wait for CLK_PERIOD;
reset <= '0';
```

Esse pulso garante que `pcOUT` receba um valor definido (zero) antes do
primeiro ciclo de instrução, rompendo definitivamente a realimentação de
um estado indeterminado. O mesmo mecanismo foi posteriormente estendido ao
banco de registradores (ver
[07-reset-banco-registradores.md](07-reset-banco-registradores.md)),
de modo que nenhum registrador do processador dependa de inicialização
implícita.
