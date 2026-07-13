# 02 — Laço combinacional entre o PC e o "PC+4"

## Sintoma

Mesmo após a correção descrita no documento anterior, a simulação
continuava travando no instante inicial, sem avançar no tempo:

```
** Warning: NUMERIC_STD.TO_INTEGER: metavalue detected, returning 0
   Time: 0 ps  Iteration: 0  Instance: /tb_urv/dut/ramDM
** Warning: NUMERIC_STD.TO_INTEGER: metavalue detected, returning 0
   Time: 0 ps  Iteration: 0  Instance: /tb_urv/dut/regBANK
...
** Error (suppressible): (vsim-3601) Iteration limit 5000 reached at time 0 ps.
```

O ponto relevante é que a simulação não avançava do instante 0 ps para o
instante seguinte do relógio (por exemplo, 5 ns). O simulador VHDL resolve
toda a lógica combinacional de um instante de tempo antes de avançar para
o próximo instante, repetindo essa resolução em "ciclos delta" sucessivos
até que nenhum sinal mude de valor. O limite de 5000 ciclos delta existe
justamente para detectar quando essa resolução não converge — ou seja,
quando existe um laço de lógica puramente combinacional (sem nenhum
elemento de memória, como um registrador, interrompendo o laço).

## Diagnóstico

O sinal de "PC+4" (`pcp4IN`/`pcp4OUT`, em `CPU.vhd`) era calculado, antes
da correção, a partir do próprio `pcIN`:

```vhdl
addPC4: process(pcIN)
begin
  pcp4IN <= std_logic_vector(unsigned(pcIN) + 4);
end process addPC4;
```

Por sua vez, `pcIN` — o valor que será carregado no registrador do PC no
próximo pulso de clock — era calculado, no caso comum (instrução
sequencial, sem desvio nem salto), a partir do próprio `pcp4IN`:

```vhdl
muxPC: process(pcp4IN, pcTARGET, ctrlMpc, ...)
begin
  ...
  case ctrlMpc is
    when '0'    => pcIN <= pcp4IN;
    ...
```

Isso cria uma dependência circular sem nenhum registrador no meio:
`pcIN → pcp4IN → pcIN`. Como as duas atribuições são combinacionais (não
dependem de uma borda de clock), qualquer mudança em `pcIN` provoca
imediatamente uma mudança em `pcp4IN`, que por sua vez provoca
imediatamente uma nova mudança em `pcIN` — e assim por diante,
indefinidamente, sem que o tempo de simulação avance. É exatamente esse
laço que o simulador detecta ao esgotar o limite de ciclos delta.

Vale notar que esse é um problema estrutural do circuito descrito, não um
efeito de nenhum valor específico (`'0'`, `'1'` ou indeterminado) presente
nos sinais: mesmo que todos os sinais envolvidos partissem de valores
perfeitamente definidos, o laço ainda assim não convergiria, pois a cada
iteração o valor de `pcIN` muda (soma-se 4 a cada rodada), gerando um novo
evento indefinidamente.

## Correção

O sinal de "PC+4" não precisa ser um registrador separado: tanto o
endereço de retorno de JAL/JALR quanto o candidato a "próximo PC" no caso
sequencial precisam refletir o PC **atual** (`pcOUT`, a saída do registrador
do PC, já estável durante todo o ciclo em execução) somado a 4 — não o
"próximo PC" que ainda está sendo calculado. A correção elimina o
registrador `regPCp4` e recalcula `pcp4OUT` de forma puramente
combinacional a partir de `pcOUT`:

```vhdl
addPC4: process(pcOUT)
begin
  pcp4OUT <= std_logic_vector(unsigned(pcOUT) + 4);
end process addPC4;
```

Como `pcOUT` só muda na borda do clock (é a saída de um registrador), essa
mudança rompe o laço: `pcp4OUT` passa a depender apenas de um sinal que
permanece estável durante todo o ciclo combinacional, e a simulação passa
a convergir normalmente em cada instante de tempo.
