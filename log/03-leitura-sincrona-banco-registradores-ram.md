# 03 — Leituras síncronas no banco de registradores e na RAM

## Contexto

Um processador uniciclo executa uma instrução completa por ciclo de
clock: busca, decodificação, execução, acesso à memória e escrita de
resultado ocorrem todos dentro do mesmo ciclo, de forma combinacional,
com apenas os registradores de estado (PC, banco de registradores,
memória) atualizando-se de forma síncrona, na borda do clock. Isso implica
que qualquer **leitura** de registrador ou de memória usada por uma
instrução precisa refletir o estado **atual** (já resolvido no início do
ciclo), e não um valor atrasado de um ciclo.

## Sintoma

Esse problema não foi observado diretamente a partir de uma mensagem de
erro do simulador, mas identificado por meio de uma simulação de
referência (GHDL) do mesmo código, que apontou que o valor lido de volta
por uma instrução `lw` não correspondia ao valor recém-escrito na RAM, e
que reforçou a suspeita de que os operandos usados pela ULA nem sempre
correspondiam aos registradores da instrução em execução.

## Diagnóstico

### Banco de registradores (`XREG.vhd`)

As saídas `ro1`/`ro2` (usadas pelo resto do datapath como os valores dos
registradores-fonte `rs1`/`rs2`) eram atualizadas dentro de um processo
síncrono:

```vhdl
mainp: process(clk)
begin
  out_q(0) <= (others => '0');
  if rising_edge(clk) then
    ro1 <= dr1;
    ro2 <= dr2;
  end if;
end process mainp;
```

Como `dr1`/`dr2` já refletiam `rs1`/`rs2` da instrução atual de forma
combinacional, mas só eram copiados para `ro1`/`ro2` na borda de clock
seguinte, o valor de `ro1`/`ro2` visível durante um dado ciclo
correspondia, na verdade, à seleção de `rs1`/`rs2` feita **no ciclo
anterior** — ou seja, os operandos usados pela ULA, pelos desvios etc.
eram sempre os operandos da instrução anterior, e não da instrução
corrente.

### RAM (`RAM.vhd`)

De forma análoga, a leitura de dados (`dataout`) só era atualizada dentro
de um bloco síncrono:

```vhdl
if rising_edge(clk) then
  ...
  dataout <= mem(INTaddr) & mem(INTaddr+1) & mem(INTaddr+2) & mem(INTaddr+3);
  ...
end if;
```

Isso significa que, ao executar um `lw`, o valor entregue por `dataout`
correspondia ao endereço que estava presente na entrada da RAM no ciclo
**anterior**, não ao endereço calculado pela instrução `lw` em execução —
incompatível com o requisito de leitura no mesmo ciclo de um processador
uniciclo.

## Correção

Em ambos os casos, a correção consistiu em separar claramente o que deve
ser síncrono (escrita) do que deve ser combinacional (leitura):

- Em `XREG.vhd`, `ro1`/`ro2` passaram a ser atribuições concorrentes
  diretas (`ro1 <= dr1; ro2 <= dr2;`), sem registrador intermediário. A
  escrita no banco de registradores continua síncrona, através dos
  componentes `REG` já existentes.
- Em `RAM.vhd`, a leitura foi movida para um processo combinacional
  separado (`read_pr`, sensível a `INTaddr`, `byte_en`, `sgn_en`, `addr` e
  `mem`), enquanto a escrita permaneceu em um processo síncrono
  (`write_pr`, sensível a `clk`).

Com essa separação, tanto os operandos lidos do banco de registradores
quanto os dados lidos da RAM passaram a refletir o estado atual da
memória correspondente já no mesmo ciclo da instrução que os utiliza,
compatível com a semântica de um processador uniciclo.
