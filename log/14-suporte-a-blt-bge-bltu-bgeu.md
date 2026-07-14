# 14 — BLT/BGE/BLTU/BGEU adicionadas como instruções reais

## Contexto

Diferente dos demais itens deste registro, este não é a correção de um
defeito: é uma extensão de hardware, motivada pela necessidade de
executar código gerado pelo RARS no modelo de memória compacto (ver
`rars_import.py` e a seção "Compatibilidade com o modelo de memória
compacto do RARS" do `README.md`).

## Situação anterior

Até este ponto, o processador só decodificava `BEQ`/`BNE` como
instruções reais de desvio. O próprio `assembler.py` tratava
`blt`/`bge`/`bltu`/`bgeu` como PSEUDO-instruções, montadas em cima de
`slt`/`sltu` + `beq`/`bne` (2 instruções reais em vez de 1) — uma
limitação documentada no `README.md` desde o início do projeto, não um
bug.

## Por que isso quebrava a importação de código do RARS

O RARS é um assembler RV32I padrão: ele não tem motivo para "evitar"
`blt`/`bge`/`bltu`/`bgeu`, então qualquer programa que os utilize
(a grande maioria de código real, incluindo os próprios programas de
teste deste projeto) é montado com essas 4 como instruções REAIS — com
`funct3` = 100/101/110/111, valores que a `ALUControl` deste processador
sempre traduzia genericamente para SUB (só olhava o bit 0 de `funct3`
para diferenciar BEQ de BNE). Ao testar `rars_import.py` com um dump real
do RARS para `testes/teste4`, o programa nunca decodificava corretamente
o primeiro `bge` de `quicksort` — o processador tentava executar aquilo
como se fosse BNE, com resultado sem sentido (o vetor nunca era
ordenado).

## Correção (extensão)

A ULA (`ULA.vhd`) já tinha os comparadores necessários havia tempo, sem
uso: `uSLT`/`uSLTU` (com/sem sinal, "A<B") e `uSGE`/`uSGEU` (com/sem
sinal, "A>=B"), todos produzindo `0` ou `1` diretamente em `a32`. Faltava
só ligar a fiação:

1. `ALUCtrl.vhdl`: o caso `ALUOp="01"` (branch) passou a decodificar por
   `funct3`, em vez de sempre escolher SUB:

   ```vhdl
   when "01" =>
       case funct3 is
           when "000" => ALUControl <= "0001";  -- BEQ (SUB)
           when "001" => ALUControl <= "0001";  -- BNE (SUB)
           when "100" => ALUControl <= "1000";  -- BLT (uSLT)
           when "101" => ALUControl <= "1010";  -- BGE (uSGE)
           when "110" => ALUControl <= "1001";  -- BLTU (uSLTU)
           when "111" => ALUControl <= "1011";  -- BGEU (uSGEU)
           when others => ALUControl <= "0001";
       end case;
   ```

2. `CPU.vhd` (`lgmuxPC`): antes, a condição de desvio era
   `aluZERO xor Ifunct3(0)` — um truque que só fazia sentido para
   BEQ/BNE (onde o bit 0 de `funct3` é exatamente o que diferencia as
   duas). Generalizado para: desvia quando `aluZERO='1'` só para BEQ;
   para todos os outros (`BNE`, `BLT`, `BGE`, `BLTU`, `BGEU`), desvia
   quando `aluZERO='0'`. Isso funciona porque `SLT`/`SGE`/`SLTU`/`SGEU`
   já entregam `a32=1` exatamente quando a condição de desvio é
   satisfeita, e `aluZERO` é definido como `a32=0` — ou seja,
   `aluZERO='0'` já significa "a comparação deu verdadeiro", sem precisar
   de nenhum tratamento por instrução:

   ```vhdl
   if ctrlBranch = '1' then
     if Ifunct3 = "000" then
       ctrlMpc <= aluZERO;       -- BEQ
     else
       ctrlMpc <= not aluZERO;   -- BNE, BLT, BGE, BLTU, BGEU
     end if;
   ...
   ```

`Control.vhdl` não precisou de nenhuma mudança: `BRANCH_OP` já ativava
`Branch<='1'` e `ALUOp<="01"` para qualquer `funct3` sob esse opcode.

`assembler.py` também passou a gerar `blt`/`bge`/`bltu`/`bgeu` como
instruções reais (removidas de `PSEUDO_OPS`, adicionadas à
`INSTR_TABLE`), em vez da expansão de 2 instruções — `bgt`/`ble`
continuam pseudo (RV32I não tem essas duas de verdade; seguem trocando
os operandos e chamando `blt`/`bge`, que agora resolvem direto).

## Validação

`testes/teste1` a `testes/teste4` foram re-montados com o assembler
atualizado (ROMs menores, já que `blt`/`bge`/`bgt`/`ble` viraram 1
instrução em vez de 2) e re-verificados com o emulador de referência em
Python (também atualizado para decodificar BLT/BGE/BLTU/BGEU) — todos
batem exatamente com `expectedN.txt`. A importação de um dump do RARS
para `teste4` foi validada de duas formas: (1) contra um dump real do
RARS (mostrou o defeito antes da correção); (2) de forma determinística,
montando o `teste4.asm` atual com `--pc-rel-standard` (mesma codificação
que o RARS produziria) e confirmando que `rars_import.py` reconstrói,
byte a byte, exatamente o mesmo `.rom` que o assembler deste projeto gera
por padrão.
