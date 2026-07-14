# 11 — Verificação de zero incompatível com programas que usam pilha

## Contexto

Diferentemente dos demais itens deste registro, o problema aqui descrito
não é um defeito do processador, mas uma limitação de projeto do
testbench (`tb_uRV.vhd`), identificada ao rodar `testes/teste2`
(quicksort) já com todos os defeitos anteriores corrigidos.

## Sintoma

Com a CPU executando corretamente e terminando via `ecall` Exit2 em um
número de ciclos condizente com o esperado, o testbench ainda reportava
diversas divergências, todas do tipo:

```
** Error: endereco 4068 deveria estar zerado, mas contem 00000018
```

Nenhuma divergência ocorreu nos endereços do vetor ordenado (0 a 96);
todas estavam em endereços de pilha (a partir de 4056), usados por
`quicksort`/`partition` para salvar e restaurar registradores durante as
chamadas recursivas.

## Diagnóstico

O testbench, após comparar a RAM com o arquivo `EXPECTED_FILE`, verifica
se todo o restante da memória (além do que esse arquivo cobre) está
zerado — uma verificação adequada para `testes/teste1` (bubble sort),
que não usa pilha de chamadas e portanto não escreve em nenhum endereço
fora do vetor.

`testes/teste2`, por usar uma pilha (`sp`) para implementar chamadas de
função recursivas, escreve legitimamente em endereços além do vetor
durante a execução. Encerrar uma chamada de função ("dar pop" no quadro
de pilha) apenas move `sp` de volta para o valor anterior — não apaga o
conteúdo que estava naqueles endereços. Ao final de uma execução
inteiramente correta, é esperado que a região de pilha utilizada
contenha resíduo não-zerado (valores de registradores salvos e
endereços de retorno de chamadas já concluídas). A verificação "deve
estar zerado", portanto, não é aplicável a programas que usam pilha, e
gerava falsos positivos.

## Correção

Foi adicionado um generic booleano, `CHECK_TAIL_ZERO` (padrão `true`,
preservando o comportamento anterior para `teste1`), que controla se
essa verificação é executada:

```vhdl
if CHECK_TAIL_ZERO then
  while addr <= RAMDP_C - 4 loop
    ...
  end loop;
end if;
```

Para `testes/teste2` (e qualquer outro programa que use pilha de
chamadas), a verificação deve ser desativada passando
`-gCHECK_TAIL_ZERO=false` ao `vsim`. A comparação da RAM com
`EXPECTED_FILE` continua ocorrendo normalmente em ambos os casos — apenas
a checagem do restante da memória é que se torna opcional.
