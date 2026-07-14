# projeto-riscv-uniciclo

Implementação de um processador **RISC-V RV32I uniciclo** em **VHDL**.

## Objetivo

Este projeto tem como objetivo implementar um processador RISC-V uniciclo, incluindo o caminho de dados (datapath), unidade de controle, controle da ULA e os demais componentes necessários para executar programas compatíveis com a ISA RV32I.

## Status do projeto

### ✅ Implementado

- Unidade de Controle Principal (`Control.vhdl`)
- Unidade de Controle da ULA (`ALUCtrl.vhdl`)
- ULA (`ULA.vhd`)
- Banco de registradores (`XREG.vhd`)
- Gerador de imediatos (`ImmGen.vhd`)
- Memória de instruções — ROM (`ROM.vhd`)
- Memória de dados — RAM (`RAM.vhd`)
- Datapath completo (`CPU.vhd`, entidade `uRV`)
- Chamada de sistema (`ecall`): `PrintInt`, `PrintString`, `Exit2`
- Assembler (`assembler.py`) para o subconjunto de RV32I suportado
- Testbench (`tb_uRV.vhd`)

### 🚧 Não implementado / fora de escopo atual

- CSRs, EBREAK, e as demais chamadas de sistema do RARS além de
  PrintInt/PrintString/Exit2.

### Compatibilidade com o modelo de memória compacto do RARS

O RARS, no modelo de memória compacto, usa um único espaço de endereços
(`.text` em `0x00000000`, `.data` em `0x00002000`), diferente da
arquitetura Harvard (ROM/RAM separadas) deste processador. Em vez de
reestruturar o datapath/testbench para unificar as memórias, a
compatibilidade é resolvida com uma etapa de **importação** separada
(`rars_import.py`) que converte um dump de memória exportado pelo RARS
(`.text`/`.data`, formato "Hexadecimal Text") para os arquivos de
ROM/RAM que este processador já sabe carregar — ver seção
["Importando código do RARS"](#importando-código-do-rars) abaixo.

Duas diferenças reais de codificação de máquina entre o RARS (RV32I
padrão) e este processador precisaram ser tratadas nessa importação (ou,
no caso da segunda, corrigidas no próprio hardware):

1. **Offset de BRANCH/JAL "pela metade"** (`PC_REL_HALVED`, ver
   cabeçalho de `assembler.py`): o hardware sempre multiplica por 2 o
   deslocamento decodificado, então o offset de verdade (o que o RARS
   gera) precisa ser dividido por 2 antes de virar máquina. `rars_import.py`
   decodifica e recodifica automaticamente todo BRANCH/JAL importado.
2. **BLT/BGE/BLTU/BGEU como instruções reais**: até pouco tempo atrás,
   este processador só decodificava BEQ/BNE de verdade (o próprio
   assembler tratava blt/bge/bltu/bgeu como pseudo-instruções, montadas
   em cima de SLT/SLTU + BEQ/BNE). Como o RARS é um assembler RV32I
   padrão, ele gera essas 4 como instruções reais — então foi necessário
   **estender o hardware** (`ALUCtrl.vhdl`, `CPU.vhd`) para decodificá-las
   de verdade, em vez de tratar isso só na importação (ver
   [log/14-suporte-a-blt-bge-bltu-bgeu.md](log/14-suporte-a-blt-bge-bltu-bgeu.md)).
   O assembler deste projeto também passou a gerar essas 4 como
   instruções reais (antes eram pseudo), então o hardware já era exigido
   mesmo para programas montados localmente.

## Instruções suportadas

| Instrução | Opcode      |  funct3 |    funct7    |
| --------- | ----------- | :-----: | :----------: |
| ADD       | 0110011     |   000   |    0000000   |
| SUB       | 0110011     |   000   |    0100000   |
| SLL       | 0110011     |   001   |    0000000   |
| SLT       | 0110011     |   010   |    0000000   |
| SLTU      | 0110011     |   011   |    0000000   |
| XOR       | 0110011     |   100   |    0000000   |
| SRL       | 0110011     |   101   |    0000000   |
| SRA       | 0110011     |   101   |    0100000   |
| OR        | 0110011     |   110   |    0000000   |
| AND       | 0110011     |   111   |    0000000   |
| ADDI      | 0010011     |   000   |   imm[11:5]  |
| SLTI      | 0010011     |   010   |   imm[11:5]  |
| SLTIU     | 0010011     |   011   |   imm[11:5]  |
| XORI      | 0010011     |   100   |   imm[11:5]  |
| ORI       | 0010011     |   110   |   imm[11:5]  |
| ANDI      | 0010011     |   111   |   imm[11:5]  |
| SLLI      | 0010011     |   001   |    0000000   |
| SRLI      | 0010011     |   101   |    0000000   |
| SRAI      | 0010011     |   101   |    0100000   |
| LW        | 0000011     |   010   |   imm[11:5]  |
| SW        | 0100011     |   010   |   imm[11:5]  |
| BEQ       | 1100011     |   000   | imm[12\|10:5] |
| BNE       | 1100011     |   001   | imm[12\|10:5] |
| BLT       | 1100011     |   100   | imm[12\|10:5] |
| BGE       | 1100011     |   101   | imm[12\|10:5] |
| BLTU      | 1100011     |   110   | imm[12\|10:5] |
| BGEU      | 1100011     |   111   | imm[12\|10:5] |
| JAL       | 1101111     |    —    |       —      |
| JALR      | 1100111     |   000   |   imm[11:5]  |
| LUI       | 0110111     |    —    |  imm[31:25]  |
| AUIPC     | 0010111     |    —    |  imm[31:25]  |
| ECALL     | 1110011     |   000   |       —      |

### ECALL (chamada de sistema)

Subconjunto dos syscalls do RARS, decodificado pela própria CPU (a7 = x17, a0 = x10):

| a7  | Nome        | Efeito                                                        |
| --- | ----------- | -------------------------------------------------------------- |
| 1   | PrintInt    | Imprime a0 (inteiro com sinal) no console da simulação          |
| 4   | PrintString | Imprime a string terminada em `\0` a partir do endereço em a0   |
| 93  | Exit2       | Encerra o programa; `halt='1'` e `exit_code=a0` na saída da CPU |

`PrintInt`/`PrintString` são efeitos apenas de simulação (não sintetizáveis),
implementados via `std.textio` em `CPU.vhd`.

## Decodificação da Unidade de Controle

A Unidade de Controle Principal utiliza apenas o **opcode** da instrução para gerar os sinais de controle do processador.

| Classe da instrução |   Opcode  | Instruções                              | Branch | JumpAndLink | IsJalr | IsLUI | IsAuipc | Ecall | MemRead | MemWrite | MemToReg | RegWrite | ALUSrc | ALUOp |
| ------------------- | :-------: | --------------------------------------- | :----: | :---------: | :----: | :---: | :-----: | :---: | :-----: | :------: | :------: | :------: | :----: | :---: |
| Tipo R              | `0110011` | ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 10 |
| Tipo I (aritmético) | `0010011` | ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 1 | 11 |
| Load                | `0000011` | LW                                      |    0   |      0      |    0   |   0   |    0    |   0   |    1    |     0    |     1    |     1    |    1   |   00  |
| Store               | `0100011` | SW                                      |    0   |      0      |    0   |   0   |    0    |   0   |    0    |     1    |     0    |     0    |    1   |   00  |
| Branch              | `1100011` | BEQ, BNE, BLT, BGE, BLTU, BGEU          |    1   |      0      |    0   |   0   |    0    |   0   |    0    |     0    |     0    |     0    |    0   |   01  |
| JAL                 | `1101111` | JAL                                     |    0   |      1      |    0   |   0   |    0    |   0   |    0    |     0    |     0    |     1    |    0   |   00  |
| JALR                | `1100111` | JALR                                    |    0   |      1      |    1   |   0   |    0    |   0   |    0    |     0    |     0    |     1    |    1   |   00  |
| LUI                 | `0110111` | LUI                                     |    0   |      0      |    0   |   1   |    0    |   0   |    0    |     0    |     0    |     1    |    1   |   00  |
| AUIPC               | `0010111` | AUIPC                                   |    0   |      0      |    0   |   0   |    1    |   0   |    0    |     0    |     0    |     1    |    1   |   00  |
| ECALL (SYSTEM)      | `1110011` | ECALL                                   |    0   |      0      |    0   |   0   |    0    |   1   |    0    |     0    |     0    |     0    |    0   |   00  |

Nota: todo branch usa o mesmo `ALUOp` (`01`); `ALUControl.vhdl` decide,
a partir de `funct3`, qual comparador da ULA usar -- SUB para BEQ/BNE
(a igualdade é `A-B=0`), e os comparadores dedicados SLT/SGE/SLTU/SGEU
(que já produzem 0/1 diretamente) para BLT/BGE/BLTU/BGEU. Em `CPU.vhd`
(processo `lgmuxPC`), o desvio é tomado quando `aluZERO='1'` (para BEQ)
ou quando `aluZERO='0'` (para todos os outros -- tanto para "A/=B" quanto
para "condição de SLT/SGE/SLTU/SGEU satisfeita").

Nota: Tipo R e Tipo I (aritmético) usam `ALUOp`s diferentes (`10` e `11`)
apesar de ambos dependerem de `funct3`/`funct7` em `ALUControl.vhdl`. Isso
existe por causa de `ADD`/`SUB`: no Tipo R, `funct7` realmente diferencia
as duas; no Tipo I, a mesma posição de bits (`imm[11:5]`) é só parte do
imediato de `ADDI` (RV32I não tem "SUBI"), então usar o mesmo `ALUOp` do
Tipo R fazia `ADDI` ser confundido com `SUB` sempre que esse imediato
estivesse entre 1024 e 1055 — ver
[log/12-addi-confundido-com-sub.md](log/12-addi-confundido-com-sub.md).

## Controle da ULA

`ALUControl.vhdl` traduz `(ALUOp, funct3, funct7)` no código de operação
interno da ULA (`ULA.vhd`):

| Código ULA | Operação            |
| :--------: | -------------------- |
| `0000`     | ADD                  |
| `0001`     | SUB (também usado por BEQ/BNE) |
| `0010`     | AND                  |
| `0011`     | OR                   |
| `0100`     | XOR                  |
| `0101`     | SLL                  |
| `0110`     | SRL                  |
| `0111`     | SRA                  |
| `1000`     | SLT (com sinal, também usado por BLT) |
| `1001`     | SLTU (sem sinal, também usado por BLTU) |
| `1010`     | SGE (com sinal, usado por BGE) |
| `1011`     | SGEU (sem sinal, usado por BGEU) |
| `1100`     | SEQ (não usado por nenhuma instrução real; disponível para uso futuro) |
| `1101`     | SNE (idem)           |

## Estrutura do repositório

| Caminho              | Conteúdo                                                        |
| --------------------- | ---------------------------------------------------------------- |
| `CPU.vhd`             | Datapath completo (entidade `uRV`)                                |
| `Control.vhdl`        | Unidade de Controle Principal                                     |
| `ALUCtrl.vhdl`        | Controle da ULA                                                   |
| `ULA.vhd`             | ULA                                                                |
| `XREG.vhd`            | Banco de registradores                                            |
| `ImmGen.vhd`          | Gerador de imediatos                                               |
| `ROM.vhd` / `RAM.vhd` | Memórias de instrução e de dados                                   |
| `Reg.vhd`             | Registrador básico (usado pelo PC e pelo banco de registradores)   |
| `tb_uRV.vhd`          | Testbench                                                          |
| `assembler.py`        | Assembler RV32I (subconjunto) → arquivos hex para ROM/RAM          |
| `rars_import.py`      | Converte um dump de memória compacta do RARS (.text/.data) para os arquivos de ROM/RAM |
| `instrucoes_asm/`     | Programas de exemplo em assembly                                  |
| `instrucoes_hex/`, `ram_input/` | Saída do assembler para os exemplos em `instrucoes_asm/` |
| `testes/teste1/`      | Programa de teste (bubble sort, 10 inteiros), sem chamadas de função |
| `testes/teste2/`      | Programa de teste (quicksort recursivo, 25 inteiros), exercita call/ret/auipc/jalr |
| `testes/teste3/`      | Mesmo quicksort de `teste2`, mas zera a região de pilha usada antes do `ecall` — permite `CHECK_TAIL_ZERO=true` |
| `testes/teste4/`      | Teste de cobertura/stress: quicksort de 40 inteiros (com negativos e os extremos de 32 bits), hash e CRC-32 sobre o resultado, e um bloco que exercita todas as instruções ALU nunca usadas pelos testes anteriores — ver nota sobre bug suspeito abaixo |
| `log/`                | Registro formal dos erros encontrados durante a depuração e como foram corrigidos |

## Assembler (`assembler.py`)

Monta um subconjunto de RV32I (exatamente as instruções da tabela acima,
mais pseudo-instruções como `li`, `la`, `mv`, `j`, `bgt`/`ble`,
`call`/`tail` etc. — `blt`/`bge`/`bltu`/`bgeu` são instruções REAIS, não
pseudo) a partir de um arquivo `.asm`. Gera três arquivos:

```
python assembler.py programa.asm -o rom.txt --ram ram.txt --intermediate listagem.txt
```

- `rom.txt`: instruções em hexadecimal (1 palavra de 32 bits por linha,
  só até a última instrução real — sem preenchimento de zeros).
- `ram.txt`: estado inicial da RAM a partir da seção `.data` (1 palavra de
  32 bits por linha, big-endian, a partir do endereço 0).
- `listagem.txt`: programa desmontado, com pseudo-instruções expandidas e
  rótulos resolvidos — útil para conferir a codificação gerada.

Ver o cabeçalho de `assembler.py` para a sintaxe completa suportada.

## Importando código do RARS (`rars_import.py`)

Converte um dump de memória exportado pelo RARS (modelo de memória
compacto: `.text` em `0x00000000`, `.data` em `0x00002000`, dump format
"Hexadecimal Text") para os arquivos de ROM/RAM que este processador já
sabe carregar:

```
python rars_import.py --text prog_text.txt --data prog_data.txt -o prog_rom.txt --ram prog_ram.txt
```

Depois, é só rodar o testbench normalmente (ver seção "Testbench"
abaixo), apontando `ROM_FILE`/`RAM_FILE` para os arquivos gerados aqui —
nenhuma mudança adicional é necessária.

O `.text` do RARS já vem, praticamente, no formato que `ROM.vhd` espera
(1 palavra hex por linha, sem prefixo, a partir do endereço 0); o `.data`
precisa de conversão real (cada linha do RARS traz um endereço absoluto
e várias palavras "0x..." na mesma linha). Além do formato, duas
diferenças de codificação de máquina entre o RARS e este processador
são tratadas automaticamente — ver a explicação em ["Compatibilidade com
o modelo de memória compacto do RARS"](#compatibilidade-com-o-modelo-de-memória-compacto-do-rars),
mais acima. Nenhuma outra instrução (R, I, S, U, JALR, ECALL) precisa de
ajuste: só BRANCH/JAL têm o deslocamento recodificado.

## Testbench

`tb_uRV.vhd` carrega um programa montado pelo `assembler.py`, roda a CPU
até ela sinalizar fim de execução (`ecall` Exit2) ou até um limite de
ciclos, e compara o estado final da RAM com um arquivo de saída esperada.

Requer **VHDL-2008** (usa a instrução `report` "solta", sem `assert false`
na frente, e `std.env.stop`). A leitura da RAM final é feita por uma porta
de depuração dedicada (`dump_addr`/`dump_word`, ver `RAM.vhd`/`CPU.vhd`) —
não usa mais "external names" (ver `log/01-nomes-externos-na-elaboracao.md`
para o motivo).

Generics principais:

| Generic         | Efeito                                                                 |
| ---------------- | ----------------------------------------------------------------------- |
| `ROM_FILE`       | Arquivo de instruções (gerado pelo assembler)                           |
| `RAM_FILE`       | Estado inicial da RAM (gerado pelo assembler)                           |
| `EXPECTED_FILE`  | Saída esperada da RAM (1 palavra hex/linha); `""` pula a verificação    |
| `DUMP_FILE`      | Se não vazio, grava a RAM final inteira nesse arquivo (1 palavra/linha) |
| `MAX_STEPS`      | Limite de ciclos caso o programa não chame `ecall` Exit2                |
| `TRACE_CYCLES`   | Se > 0, imprime PC/instrução/registradores a cada ciclo (depuração)     |
| `CHECK_TAIL_ZERO`| `true` (padrão) exige que todo endereço além de `EXPECTED_FILE` esteja zerado. A verificação não tem noção de "onde começa a pilha": ela simplesmente continua, a partir do endereço em que `EXPECTED_FILE` parou, até o último endereço da RAM. Isso funciona sem ajustes em programas sem pilha de chamadas (ex.: `teste1`); programas recursivos que não limpam a própria pilha (ex.: `teste2`) deixam resíduo legítimo em endereços de pilha e precisam passar `false`. `teste3` mostra a alternativa: o próprio programa zera a região de pilha usada antes do `ecall`, permitindo manter `CHECK_TAIL_ZERO=true` e verificar a RAM inteira. |

O testbench pulsa `reset='1'` por um ciclo antes de liberar o clock — sem
isso, o registrador do PC nunca sai do estado indeterminado (ver
`log/05-pc-indeterminado-sem-reset.md`).

### Como rodar (ModelSim/Questa)

Compilar na ordem de dependência e simular:

```tcl
vcom Reg.vhd
vcom ROM.vhd
vcom RAM.vhd
vcom XREG.vhd
vcom ImmGen.vhd
vcom ULA.vhd
vcom Control.vhdl
vcom ALUCtrl.vhdl
vcom CPU.vhd
vcom -2008 tb_uRV.vhd

vsim -gROM_FILE="testes/teste1/teste1_rom.txt" -gRAM_FILE="testes/teste1/teste1_ram.txt" ^
     -gEXPECTED_FILE="testes/teste1/expected1.txt" -gDUMP_FILE="testes/teste1/teste1_ram_final.txt" ^
     work.tb_uRV
run -all
```

Para rodar o quicksort (`testes/teste2`) no lugar do bubble sort, troque
os caminhos e adicione `-gCHECK_TAIL_ZERO=false` (o quicksort usa uma
pilha de chamadas, então legitimamente deixa resíduo não-zerado além do
vetor ordenado — ver tabela de generics acima):

```tcl
vsim -gROM_FILE="testes/teste2/teste2_rom.txt" -gRAM_FILE="testes/teste2/teste2_ram.txt" ^
     -gEXPECTED_FILE="testes/teste2/expected2.txt" -gDUMP_FILE="testes/teste2/teste2_ram_final.txt" ^
     -gCHECK_TAIL_ZERO=false work.tb_uRV
run -all
```

`testes/teste3` roda o mesmo algoritmo de `teste2` (mesma entrada de 25
inteiros), mas o próprio programa zera a região de pilha usada logo antes
do `ecall` de saída — por isso dispensa `-gCHECK_TAIL_ZERO=false` e permite
verificar a RAM inteira com o valor padrão do generic:

```tcl
vsim -gROM_FILE="testes/teste3/teste3_rom.txt" -gRAM_FILE="testes/teste3/teste3_ram.txt" ^
     -gEXPECTED_FILE="testes/teste3/expected3.txt" -gDUMP_FILE="testes/teste3/teste3_ram_final.txt" ^
     work.tb_uRV
run -all
```

`testes/teste4` é um teste de cobertura/stress: quicksort de 40 inteiros
(com negativos, duplicata e os extremos de 32 bits com sinal), seguido de
um hash e um CRC-32 sobre o vetor ordenado e de um bloco que executa
diretamente todas as instruções ALU que `teste1`/`teste2`/`teste3` nunca
chegavam a gerar (`and`, `or`, `xor`, `sub`, `sra`, `slt`, `sltu`, `slti`,
`sltiu`, `ori`, `xori`, `srai`, `srli`). Também zera sua própria região de
pilha antes do `ecall`, então roda com `CHECK_TAIL_ZERO=true` (padrão):

```tcl
vsim -gROM_FILE="testes/teste4/teste4_rom.txt" -gRAM_FILE="testes/teste4/teste4_ram.txt" ^
     -gEXPECTED_FILE="testes/teste4/expected4.txt" -gDUMP_FILE="testes/teste4/teste4_ram_final.txt" ^
     work.tb_uRV
run -all
```

**Bugs encontrados e corrigidos graças a este teste:** o bloco de
cobertura de `teste4` inclui deliberadamente `addi t3, t3, 1030` a partir
de um valor conhecido (resultado correto: 1530, gravado em
`expected4.txt`) — e, rodando no ModelSim, essa instrução realmente
divergiu (`FFFFFDEE` = -530, em vez do 1530 esperado), confirmando um
defeito real na ALUControl: `funct7` era reaproveitado para distinguir
ADD de SUB também em instruções `addi`, mas nesses casos aqueles bits são
parte do imediato, não um funct7 de verdade (ver
[log/12-addi-confundido-com-sub.md](log/12-addi-confundido-com-sub.md)).
O mesmo teste também expôs, por inspeção de código motivada por um
warning do ModelSim, uma segunda falha: `sll`/`srl`/`sra` (tipo R) usavam
o registrador inteiro como quantidade de deslocamento em vez de só os 5
bits menos significativos (ver
[log/13-shift-sem-mascara-de-shamt.md](log/13-shift-sem-mascara-de-shamt.md)).
Ambos já foram corrigidos.

O veredito final é sempre a última linha impressa pelo testbench, logo
após a gravação do `DUMP_FILE`: `Sucesso!!! :) ...` em caso de sucesso, ou
`Falha! ...` com a contagem de divergências, caso contrário.

## Histórico de depuração

O processo de depuração deste testbench (rodado pela primeira vez neste
projeto) encontrou e corrigiu vários problemas reais no datapath, não
relacionados ao testbench em si. Ver a pasta [`log/`](log/) para o registro
completo, incluindo o motivo exato de cada erro observado no ModelSim
(loop combinacional, PC indeterminado, etc.) e a correção aplicada.
