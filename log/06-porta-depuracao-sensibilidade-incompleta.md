# 06 — Porta de depuração com lista de sensibilidade incompleta

## Contexto

Após as correções anteriores, a simulação passou a executar corretamente
do início ao fim, encerrando por meio da instrução `ecall` (Exit2). A
comparação automática entre o estado final da RAM e o arquivo de saída
esperada, no entanto, ainda apontava uma única divergência: o endereço 0
permanecia com o valor original (anterior à ordenação), enquanto todos os
demais endereços verificados batiam com o esperado.

## Sintoma

```
** Error: divergencia no endereco 0: esperado=00000001 obtido=0000001D
** Error: 1 divergencia(s) entre a RAM final e a saida esperada.
```

Um trace de execução ciclo a ciclo (comparado com um emulador de
referência em Python) mostrou que a CPU, internamente, já havia lido o
valor correto (`3`) no endereço 0 em uma leitura anterior durante a
execução do programa — ou seja, o dado correto chegou a estar presente na
RAM em algum momento da simulação. A divergência só aparecia na leitura
feita pelo testbench **após** o fim da execução, através da porta de
depuração `dump_addr`/`dump_word` (ver
[01-nomes-externos-na-elaboracao.md](01-nomes-externos-na-elaboracao.md)).

## Diagnóstico

O processo combinacional que implementa a porta de depuração de leitura
de palavra completa (`tb_pr`, em `RAM.vhd`) estava definido como:

```vhdl
tb_pr: process(tb_addr)
  variable idx : integer;
begin
  idx := to_integer(unsigned(tb_addr));
  tb_word <= mem(idx) & mem(idx+1) & mem(idx+2) & mem(idx+3);
end process tb_pr;
```

A lista de sensibilidade contém apenas `tb_addr`, e não `mem`. Em VHDL, um
processo só é reavaliado quando ocorre um evento (uma mudança de valor)
em algum sinal de sua lista de sensibilidade. Isso significa que, se
`mem` for alterado (por uma escrita da CPU) enquanto `tb_addr` permanece
com o mesmo valor, o processo não é reativado, e `tb_word` continua
refletindo o conteúdo de `mem` de quando o processo foi avaliado pela
última vez — não o conteúdo atual.

O sinal `dump_addr`, no testbench, tem valor inicial `(others => '0')`
(endereço 0) e é justamente o primeiro endereço consultado, tanto na
comparação com o arquivo esperado quanto na gravação do despejo completo
da RAM. Como o valor atribuído a `dump_addr` nessa primeira consulta
(`0`) é idêntico ao valor que o sinal já possuía desde a elaboração, essa
atribuição não constitui um evento — e o processo `tb_pr` nunca chega a
ser reavaliado para refletir as escritas ocorridas durante a execução do
programa. Todas as demais consultas (endereços 4, 8, 12, ...) alteram o
valor de `tb_addr` de fato, disparando corretamente o processo e
retornando o conteúdo atualizado — o que explica por que a divergência
ficou restrita exclusivamente ao endereço 0.

O mesmo defeito estava presente na porta de depuração por byte
(`dbg_pr`), usada pela chamada de sistema `PrintString`, embora sem
manifestação observada nos testes realizados até então.

## Correção

Ambos os processos passaram a incluir `mem` em sua lista de
sensibilidade, garantindo que sejam reavaliados sempre que o conteúdo da
memória mudar, independentemente de o endereço de consulta ter mudado ou
não:

```vhdl
dbg_pr: process(dbg_addr, mem)
...
tb_pr: process(tb_addr, mem)
```

Vale registrar que esse defeito era exclusivo das portas de depuração
adicionadas para dar suporte ao testbench e à chamada `PrintString`; a
porta principal de leitura de dados da RAM (`read_pr`, usada pelo restante
do datapath) já incluía `mem` em sua lista de sensibilidade desde a
correção descrita em
[03-leitura-sincrona-banco-registradores-ram.md](03-leitura-sincrona-banco-registradores-ram.md).
