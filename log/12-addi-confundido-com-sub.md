# 12 — ADDI confundido com SUB para certos imediatos

## Contexto

Diferentemente dos itens anteriores, este defeito não foi encontrado por
acaso durante a depuração de um programa de teste: foi previsto por
inspeção de código, ao planejar `testes/teste4` (um teste de cobertura
desenhado especificamente para exercitar instruções ALU que
`teste1`/`teste2`/`teste3` nunca chegavam a gerar), e só depois confirmado
rodando esse teste no ModelSim.

## Diagnóstico (previsto antes de rodar)

Em `ALUCtrl.vhdl`, a distinção entre ADD e SUB (quando `funct3 = "000"`)
era feita checando se `funct7 = "0100000"`:

```vhdl
when "000" =>
    if funct7 = "0100000" then
        ALUControl <= "0001";      -- SUB
    else
        ALUControl <= "0000";      -- ADD
    end if;
```

Em `CPU.vhd`, o sinal ligado a essa entrada (`Ifunct7`) é sempre
`imOUT(31 downto 25)`, sem diferenciar instruções tipo R de tipo I:

```vhdl
alias Ifunct7 : std_logic_vector(6 downto 0) is imOUT(31 downto 25);
...
ctrlULA: ALUControl port map(ctrlALUOp, Ifunct3, Ifunct7, ctrlALUmt);
```

Isso é correto para `add`/`sub` (tipo R), onde bits 31-25 são de fato o
funct7. Mas em `Control.vhdl`, `addi` (tipo I aritmético) usava o mesmo
`ALUOp` do tipo R, e para `addi` esses mesmos bits (31-25) não são um
funct7 — são os 7 bits mais altos do imediato de 12 bits (`imm[11:5]`).
RV32I não tem "SUBI"; qualquer imediato cujo `imm[11:5]` calhasse de valer
exatamente `"0100000"` (ou seja, um imediato entre 1024 e 1055) fazia a
ALUControl escolher SUB em vez de ADD para aquela instrução `addi`.

## Confirmação

`testes/teste4/teste4.asm` inclui deliberadamente:

```asm
li   t3, 500
addi t3, t3, 1030      # correto: 1530
```

Rodando no ModelSim:

```
** Error: divergencia no endereco 216: esperado=000005FA obtido=FFFFFDEE
```

`000005FA` = 1530 (decimal), o resultado correto de `500 + 1030`.
`FFFFFDEE` = -530 (decimal) = `500 - 1030` — exatamente o resultado que a
hipótese previa se a instrução fosse confundida com SUB. Nenhuma outra
divergência ocorreu (as outras 54 palavras de `expected4.txt`, incluindo
`srai`/`srli` com o mesmo tipo de imediato problemático em outra faixa,
bateram exatamente) — evidência de que o defeito é específico a esse
padrão de imediato em `addi`, não um erro geral de codificação.

Verificado também que nenhum imediato usado em `testes/teste1`,
`testes/teste2` ou `testes/teste3` cai na faixa 1024-1055; esse defeito
não afetou nenhum resultado desses testes anteriores.

## Correção

Foi introduzido um `ALUOp` próprio para o tipo I aritmético (`"11"`, antes
não utilizado), em vez de reaproveitar o `"10"` do tipo R:

```vhdl
-- Control.vhdl
when I_ARITH_OP =>
    RegWrite <= '1';
    ALUSrc   <= '1';
    ALUOp    <= "11";      -- antes: "10"
```

Em `ALUCtrl.vhdl`, o novo caso `ALUOp = "11"` repete a decodificação do
tipo R para os demais `funct3` (incluindo `SRLI`/`SRAI`, onde
`imOUT(31 downto 25)` É de fato um funct7 de verdade, por definição do
formato de instrução — só o caso ADDI muda), mas **sempre** escolhe ADD
para `funct3 = "000"`, sem checar `funct7`:

```vhdl
when "11" =>
    case funct3 is
        when "000" =>
            ALUControl <= "0000";      -- ADD, sempre
        ...
        when "101" =>
            if funct7 = "0100000" then
                ALUControl <= "0111";  -- SRAI
            else
                ALUControl <= "0110";  -- SRLI
            end if;
        ...
    end case;
```

Ver também [13-shift-sem-mascara-de-shamt.md](13-shift-sem-mascara-de-shamt.md),
segundo defeito encontrado pelo mesmo teste de cobertura.
