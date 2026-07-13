# 07 — Reset estendido ao banco de registradores

## Contexto

Após a correção descrita em
[05-pc-indeterminado-sem-reset.md](05-pc-indeterminado-sem-reset.md), o
registrador do PC passou a receber um valor definido logo no início da
simulação. O banco de registradores (`XREG.vhd`), no entanto, continuava
sem nenhum mecanismo de reset: cada registrador `x1`–`x31` só recebe um
valor definido quando é escrito pela primeira vez pelo programa em
execução (a exceção é `x0`, tratado à parte como constante zero em
`XREG.vhd`).

## Sintoma

Embora a execução do programa de teste estivesse correta do início ao
fim (ver documentos anteriores), a simulação ainda produzia avisos do
tipo:

```
** Warning: NUMERIC_STD."<": metavalue detected, returning FALSE
   Time: ... Instance: /tb_urv/dut/aluULA
```

Esses avisos ocorrem sempre que uma comparação (`SLT`/`SLTU`, usada
inclusive pelas pseudo-instruções `blt`/`bge`/`ble`/`bgt`) envolve um
registrador que ainda não foi inicializado pelo programa — por exemplo,
nos primeiros ciclos de execução, antes das instruções `li`/`la` de
inicialização serem executadas. O valor indeterminado (`'U'`) desse
registrador impede que o operador de comparação (`<`) produza um
resultado definido, e a biblioteca `NUMERIC_STD` reporta o aviso e adota
`FALSE` como resultado de segurança.

Embora esses avisos não tenham chegado a afetar o resultado final do
programa de teste utilizado (nenhuma comparação relevante ocorre antes de
os registradores envolvidos serem inicializados), sua presença é um
indício de estado indeterminado desnecessário e dificulta a leitura do
log de simulação.

## Correção

A porta de `reset`, já existente na entidade `uRV` para o PC (ver
documento 05), foi propagada também ao banco de registradores:

```vhdl
-- XREG.vhd
component REG ...
signal xld : std_logic_vector(0 to RAMNT-1) := (others => '0');
...
GENREGS:
for I in 1 to RAMNT-1 generate
  REGX: REG port map (data, clk, reset, xld(I), out_q(I));
end generate GENREGS;
```

Anteriormente, a entrada de limpeza (`clr`) de cada registrador do banco
era ligada a um sinal (`xclr`) que nunca era escrito por nenhum processo,
permanecendo sempre em seu valor padrão (`'0'`) — ou seja, nenhum
registrador do banco jamais era limpo. Com a mudança, o mesmo pulso de
reset que zera o PC no início da simulação (gerado pelo testbench) agora
zera também todos os registradores `x1`–`x31`, eliminando qualquer leitura
de valor indeterminado antes da primeira escrita feita pelo programa.
