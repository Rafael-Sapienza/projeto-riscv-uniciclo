# 04 — BNE se comportava como BEQ

## Contexto

O RV32I define duas instruções de desvio condicional simples testadas
neste processador: BEQ (desvia se os dois registradores forem iguais) e
BNE (desvia se forem diferentes). Ambas usam o mesmo opcode
(`1100011`), diferenciando-se apenas pelo campo `funct3` (`000` para BEQ,
`001` para BNE).

## Sintoma

Identificado por revisão de código, não por um sintoma observado
diretamente no simulador: o programa de teste utilizado até então usava
apenas comparações equivalentes a BEQ (via pseudo-instruções `bge`/`ble`),
de modo que esse defeito não chegou a se manifestar nos testes realizados.
Ainda assim, trata-se de um defeito real, que afetaria qualquer programa
que utilizasse BNE diretamente ou pseudo-instruções que dependem dela
(`blt`, `bgt`).

## Diagnóstico

A Unidade de Controle da ULA (`ALUCtrl.vhdl`) mapeia o `ALUOp` de
qualquer instrução de desvio (`"01"`) para a operação de subtração,
independentemente do valor de `funct3`:

```vhdl
when "01" =>
    ALUControl <= "0001";  -- SUB, usado tanto por BEQ quanto por BNE
```

A ULA, por sua vez, sinaliza a condição de desvio (`cond`, chamada de
`aluZERO` em `CPU.vhd`) sempre com o mesmo critério, independente da
operação realizada:

```vhdl
if (a32 = X"00000000") then
  cond <= '1';
else
  cond <= '0';
end if;
```

Ou seja, `aluZERO` vale `'1'` sempre que os dois registradores comparados
são iguais — o que é exatamente a condição de desvio de BEQ, mas o
**oposto** da condição de desvio de BNE. Como a lógica que decide se o
desvio é tomado (`lgmuxPC`, em `CPU.vhd`) usava `aluZERO` diretamente,
sem nenhum ajuste para o caso de BNE, as duas instruções acabavam
produzindo exatamente o mesmo comportamento (desviar quando os
registradores são iguais).

## Correção

A correção foi aplicada exclusivamente em `CPU.vhd`, sem alterar
`ALUCtrl.vhdl` nem `ULA.vhd`: o bit menos significativo de `funct3` da
instrução (`Ifunct3(0)`), que já é exatamente o bit que distingue BEQ
(`0`) de BNE (`1`) na codificação do RV32I, passou a ser usado para
inverter a condição de desvio quando necessário:

```vhdl
lgmuxPC: process(ctrlBranch, aluZERO, ctrlJAL, Ifunct3)
begin
  if ctrlBranch = '1' then
    ctrlMpc <= aluZERO xor Ifunct3(0);
  else
    ctrlMpc <= ctrlJAL;
  end if;
end process lgmuxPC;
```

Com essa mudança, BEQ (`Ifunct3(0) = '0'`) continua desviando quando
`aluZERO = '1'` (registradores iguais), e BNE (`Ifunct3(0) = '1'`) passa a
desviar quando `aluZERO = '0'` (registradores diferentes), sem exigir
nenhuma operação adicional da ULA.
