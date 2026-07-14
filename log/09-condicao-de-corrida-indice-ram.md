# 09 — Condição de corrida no índice de leitura/escrita da RAM

## Contexto

Este defeito só se manifestou ao rodar `testes/teste2` (quicksort), um
programa mais longo e com muito mais acessos a memória do que
`testes/teste1` (bubble sort) — em particular, o primeiro a exercitar
extensivamente uma pilha de chamadas (`sp`) crescendo e decrescendo em
sequência rápida de instruções `sw`/`lw`.

## Sintoma

```
** Fatal: (vsim-3734) Index value 8192 is out of range 0 to 8191.
   Time: 295 ns  Iteration: 7  Process: /tb_urv/dut/ramDM/read_pr
```

A RAM é declarada com 8192 posições (endereços 0 a 8191); o simulador
reportou uma tentativa de acessar a posição 8192.

## Descartando a hipótese óbvia

A leitura mais direta desse erro é a de um endereço realmente calculado
fora dos limites da memória — por um bug no programa em assembly, por um
deslocamento de bits incorreto na conversão de endereço, ou por um PC
descontrolado. Antes de alterar qualquer código, essa hipótese foi
verificada de forma exaustiva: o programa foi executado do início ao fim
num emulador de referência (a mesma ferramenta usada para validar todos
os problemas anteriores deste log), estendido para também computar, a
cada instrução — não só nas de `lw`/`sw`, mas em **todas**, já que o
endereço da RAM (`dmAddr`, em `CPU.vhd`) é um alias direto da saída da
ULA, independente de a instrução ser ou não um acesso à memória — qual
seria o valor entregue à RAM. Em nenhuma das 2764 instruções executadas
pelo programa esse valor ultrapassa os limites válidos (0 a 8191). Ou
seja: a última instrução a produzir um resultado de ULA em uma posição
delicada (`addi s2, s0, -1`, calculando `0 - 1`, cujo resultado truncado
aos 13 bits do endereço da RAM fica exatamente no maior valor possível,
8191) é corretamente descartada pela verificação de alinhamento (8191 não
é múltiplo de 4). O programa em si — e a codificação gerada pelo
assembler — estão corretos. A causa do erro está na descrição do
hardware, não no software executado.

## Diagnóstico

Antes desta correção, `RAM.vhd` calculava o índice usado para acessar o
vetor `mem` (o array que representa a memória) em um sinal separado,
atualizado por um processo à parte:

```vhdl
signal INTaddr : integer := 0;

ram_ad: process(addr)
begin
  INTaddr <= to_integer(unsigned(addr));
end process ram_ad;

read_pr: process(INTaddr, byte_en, sgn_en, addr, mem)
begin
  ...
  if addr(0) = '0' and addr(1) = '0' then
    dataout <= mem(INTaddr) & mem(INTaddr+1) & mem(INTaddr+2) & mem(INTaddr+3);
  end if;
  ...
```

O teste de alinhamento usa os bits de `addr` diretamente, mas o índice
usado para acessar `mem` vem de `INTaddr` — um sinal calculado por **outro
processo**. Um sinal atualizado por um processo separado carrega,
estruturalmente, um ciclo delta de atraso em relação à sua fonte: quando
`addr` muda, `read_pr` é reativado imediatamente (está em sua lista de
sensibilidade), mas `INTaddr` só reflete esse novo valor de `addr` depois
que o processo `ram_ad` também for reativado e concluir sua própria
atribuição — um ciclo delta depois. Existe, portanto, uma janela em que
`read_pr` é avaliado com o valor **novo** de `addr` (usado no teste de
alinhamento) combinado com o valor **antigo** de `INTaddr` (usado para
indexar `mem`) — uma combinação que nunca ocorre em regime permanente, mas
que pode ocorrer transitoriamente durante o acomodamento dos sinais em um
mesmo instante de tempo. Se, nessa janela, os bits de alinhamento do novo
`addr` também formarem coincidentemente `"00"`, o teste de alinhamento
passa enquanto `INTaddr` (defasado) aponta para um valor de uma instrução
anterior — que pode estar próximo do limite do array, produzindo o
estouro observado.

É significativo que as demais portas de leitura da RAM (`tb_pr`, usada
pelo testbench, e `dbg_pr`, usada pelo `ecall` `PrintString`) **não**
apresentaram esse problema: ambas já calculavam seu índice em uma
variável local, dentro do próprio processo, sem depender de um sinal
calculado externamente — não havendo, portanto, nenhum atraso de ciclo
delta entre a leitura do endereço e o cálculo do índice.

## Correção

O sinal `INTaddr` e o processo `ram_ad` foram eliminados. Em seu lugar,
tanto `read_pr` quanto `write_pr` passaram a calcular o índice em uma
variável local, seguindo o mesmo padrão já usado em `tb_pr`/`dbg_pr`:

```vhdl
read_pr: process(addr, byte_en, sgn_en, mem)
  variable idx : integer;
begin
  idx := to_integer(unsigned(addr));
  ...
  if addr(0) = '0' and addr(1) = '0' and idx <= RAMDP - 4 then
    dataout <= mem(idx) & mem(idx+1) & mem(idx+2) & mem(idx+3);
  end if;
  ...
```

Como uma variável é recalculada por inteiro, do zero, toda vez que o
processo é executado — sem nenhum estado retido entre execuções e sem
depender de outro processo —, não existe mais nenhuma janela em que o
teste de alinhamento e o índice usado para acessar `mem` possam
corresponder a instantes diferentes.

Como segunda linha de defesa — e não como a correção principal —, também
foi adicionada uma checagem explícita de limite (`idx <= RAMDP - 4`) antes
de qualquer acesso a `mem` com deslocamento (`idx+1`, `idx+2`, `idx+3`),
tanto em `read_pr` quanto em `write_pr` e em `tb_pr`. Essa checagem não
substitui a correção da condição de corrida — sem ela, o problema
persistiria porque o valor incorreto do índice continuaria sendo
calculado, só não seria mais indexado no array —, mas protege contra
qualquer outra situação, ainda não identificada, em que um índice
transitório fora dos limites venha a ser calculado.
