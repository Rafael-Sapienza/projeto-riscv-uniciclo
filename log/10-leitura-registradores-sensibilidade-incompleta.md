# 10 — Leitura de registradores com lista de sensibilidade incompleta

## Contexto

Este defeito só se manifestou ao rodar `testes/teste2` (quicksort), que
usa intensivamente uma pilha (`sp`, registrador `x2`) para salvar e
restaurar registradores em cada chamada de função. É comum, nesse
padrão, uma instrução ler o mesmo registrador que a instrução
imediatamente anterior acabou de escrever — por exemplo:

```asm
addi sp, sp, -20   ; escreve sp
sw   ra, 16(sp)    ; lê sp (mesmo registrador) logo em seguida
```

`testes/teste1` (bubble sort) não depende de chamadas de função e não
exercita esse padrão com a mesma frequência, o que explica por que o
defeito não havia aparecido antes.

## Sintoma

Um trace de execução (comparado com um emulador de referência) mostrou
que a instrução `sw ra, 16(sp)`, executada logo após `addi sp, sp, -20`
(que altera `sp` de 4080 para 4060), gravava no endereço 4096 em vez do
endereço correto, 4076 (`sp + 16`, usando o valor JÁ ATUALIZADO de `sp`).
4096 corresponde a `4080 + 16` — ou seja, a instrução usou o valor
**antigo** de `sp` (anterior à instrução imediatamente anterior), embora
o próprio registrador `sp`, quando consultado por uma via independente
(a porta de depuração `dbg_rnum`/`dbg_rval`), já mostrasse corretamente
4060 no mesmo ciclo. Essa contradição — dois caminhos de leitura do
mesmo registrador mostrando valores diferentes no mesmo instante — foi o
que permitiu isolar o problema no caminho de leitura usado pelo
datapath (`rd1`/`rd2`), e não em um erro de cálculo de endereço ou no
programa em si.

## Diagnóstico

Em `XREG.vhd`, os processos que calculam o valor lido de `rs1`/`rs2`
tinham lista de sensibilidade incompleta:

```vhdl
settleR1: process(rs1)
begin
  if to_integer(unsigned(rs1)) = 0 then
    dr1 <= (others => '0');
  else
    dr1 <= out_q(to_integer(unsigned(rs1)));
  end if;
end process settleR1;
```

O processo só é reativado quando `rs1` (o **número** do registrador a
ler) muda de valor — não quando o **conteúdo** do registrador
referenciado (`out_q`) muda. Se a instrução atual lê o mesmo registrador
que a instrução imediatamente anterior acabou de escrever, `rs1`
permanece com o mesmo valor entre as duas instruções, e o processo não é
reexecutado: `dr1` (e, por extensão, `rd1`, usado pelo resto do
datapath) continua refletindo o conteúdo **antigo** de `out_q(rs1)`, de
antes da escrita mais recente.

Esse é exatamente o mesmo tipo de defeito já documentado em
[06-porta-depuracao-sensibilidade-incompleta.md](06-porta-depuracao-sensibilidade-incompleta.md),
desta vez presente no próprio caminho principal de leitura de
registradores (`rd1`/`rd2`), e não em uma porta de depuração. Não foi
detectado antes porque a correção anterior (documento 06) tratou apenas
das portas de depuração da RAM (`tb_pr`/`dbg_pr`); o mesmo padrão de bug
em `XREG.vhd` só passou a se manifestar quando um programa começou a
reutilizar o mesmo registrador (`sp`) como fonte em instruções
consecutivas com a frequência que uma pilha de chamadas exige.

## Correção

`out_q` (o vetor com o conteúdo de todos os registradores) foi
adicionado à lista de sensibilidade de `settleR1` e `settleR2`:

```vhdl
settleR1: process(rs1, out_q)
...
settleR2: process(rs2, out_q)
```

Com isso, `dr1`/`dr2` são recalculados sempre que o conteúdo de
qualquer registrador mudar — não apenas quando `rs1`/`rs2` mudam —,
garantindo que uma leitura sempre reflita a escrita mais recente,
mesmo quando ambas se referem ao mesmo registrador em instruções
consecutivas.
