# 08 — Porta de saída do registrador sem valor padrão

## Contexto

Após as correções anteriores (em particular a adição do sinal de `reset`,
descrita nos documentos 05 e 07), a simulação já executava corretamente
do início ao fim. Ainda assim, avisos de valor indeterminado continuavam
aparecendo nos primeiros ciclos delta da simulação (tempo 0 ps):

```
** Warning: NUMERIC_STD.TO_INTEGER: metavalue detected, returning 0
   Time: 0 ps  Iteration: 0  Instance: /tb_urv/dut/ramDM
** Warning: NUMERIC_STD.TO_INTEGER: metavalue detected, returning 0
   Time: 0 ps  Iteration: 0  Instance: /tb_urv/dut/regBANK
** Warning: NUMERIC_STD.TO_INTEGER: metavalue detected, returning 0
   Time: 0 ps  Iteration: 0  Instance: /tb_urv/dut/romIM
```

Esses avisos não impediam mais a simulação de prosseguir corretamente
(diferentemente do defeito descrito no documento 02), mas ainda indicavam
uma janela de estado indeterminado logo no início da simulação.

## Diagnóstico

O componente `REG` (`Reg.vhd`), usado tanto para o registrador do PC
quanto para cada um dos registradores do banco de registradores, declara
sua porta de saída sem nenhum valor padrão:

```vhdl
q : out std_logic_vector(WSIZE-1 downto 0)
```

O sinal de `reset` (documentos 05 e 07) garante que, assim que o processo
interno de `REG` for avaliado com `clr = '1'`, `q` recebe um valor
definido. No entanto, a simulação de um projeto VHDL não garante uma
ordem específica entre a primeira avaliação de processos distintos: é
possível que outros processos que dependem de `q` (como a conversão de
endereço em `ROM.vhd`, `RAM.vhd` ou `XREG.vhd`) sejam avaliados pela
primeira vez antes de o processo de `REG` ter processado o `reset` e
publicado um valor definido para `q`. Nessa janela — tipicamente um único
ciclo delta, no tempo 0 ps — `q` ainda carrega o valor padrão da própria
porta, que, por não ter sido declarado explicitamente, é o valor mais à
esquerda do tipo (`'U'`, indeterminado).

## Correção

Foi adicionado um valor padrão explícito à porta `q`:

```vhdl
q : out std_logic_vector(WSIZE-1 downto 0) := (others => '0')
```

Com isso, `q` já nasce definido (zero) desde a elaboração do projeto,
antes mesmo de qualquer processo ser avaliado pela primeira vez —
eliminando a dependência da ordem de avaliação inicial dos processos e,
com ela, os avisos de metavalor observados no início da simulação.
