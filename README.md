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

- Modelo de memória compacto do RARS (memória única, não Harvard) — este
  processador usa ROM/RAM separadas; compatibilidade com código gerado
  pelo RARS nesse modelo exigiria mudanças estruturais no datapath.
- CSRs, EBREAK, e as demais chamadas de sistema do RARS além de
  PrintInt/PrintString/Exit2.
- BLT/BGE/BLTU/BGEU como instruções reais (disponíveis apenas como
  pseudo-instruções no assembler, montadas em cima de SLT/SLTU + BEQ/BNE).

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
| Tipo I (aritmético) | `0010011` | ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 1 | 10 |
| Load                | `0000011` | LW                                      |    0   |      0      |    0   |   0   |    0    |   0   |    1    |     0    |     1    |     1    |    1   |   00  |
| Store               | `0100011` | SW                                      |    0   |      0      |    0   |   0   |    0    |   0   |    0    |     1    |     0    |     0    |    1   |   00  |
| Branch              | `1100011` | BEQ, BNE                                |    1   |      0      |    0   |   0   |    0    |   0   |    0    |     0    |     0    |     0    |    0   |   01  |
| JAL                 | `1101111` | JAL                                     |    0   |      1      |    0   |   0   |    0    |   0   |    0    |     0    |     0    |     1    |    0   |   00  |
| JALR                | `1100111` | JALR                                    |    0   |      1      |    1   |   0   |    0    |   0   |    0    |     0    |     0    |     1    |    1   |   00  |
| LUI                 | `0110111` | LUI                                     |    0   |      0      |    0   |   1   |    0    |   0   |    0    |     0    |     0    |     1    |    1   |   00  |
| AUIPC               | `0010111` | AUIPC                                   |    0   |      0      |    0   |   0   |    1    |   0   |    0    |     0    |     0    |     1    |    1   |   00  |
| ECALL (SYSTEM)      | `1110011` | ECALL                                   |    0   |      0      |    0   |   0   |    0    |   1   |    0    |     0    |     0    |     0    |    0   |   00  |

Nota: BEQ e BNE compartilham o mesmo `ALUOp` (a ULA sempre calcula `A-B`);
a diferenciação entre "desvia se igual" e "desvia se diferente" é feita em
`CPU.vhd` (processo `lgmuxPC`), invertendo a condição de desvio com o bit 0
de `funct3` quando a instrução é BNE.

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
| `1000`     | SLT (com sinal)      |
| `1001`     | SLTU (sem sinal)     |
| `1010`     | SGE (não usado por nenhuma instrução real; disponível para uso futuro) |
| `1011`     | SGEU (idem)          |
| `1100`     | SEQ (idem)           |
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
| `instrucoes_asm/`     | Programas de exemplo em assembly                                  |
| `instrucoes_hex/`, `ram_input/` | Saída do assembler para os exemplos em `instrucoes_asm/` |
| `testes/teste1/`      | Programa de teste (bubble sort, 10 inteiros), sem chamadas de função |
| `testes/teste2/`      | Programa de teste (quicksort recursivo, 25 inteiros), exercita call/ret/auipc/jalr |
| `log/`                | Registro formal dos erros encontrados durante a depuração e como foram corrigidos |

## Assembler (`assembler.py`)

Monta um subconjunto de RV32I (exatamente as instruções da tabela acima,
mais pseudo-instruções como `li`, `la`, `mv`, `j`, `blt`/`bge`/`bgt`/`ble`,
`call`/`tail` etc.) a partir de um arquivo `.asm`. Gera três arquivos:

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

(troque os caminhos por `testes/teste2/...` para rodar o quicksort no lugar
do bubble sort.)

O veredito final é sempre a última linha impressa pelo testbench, logo
após a gravação do `DUMP_FILE`: `Sucesso!!! :) ...` em caso de sucesso, ou
`Falha! ...` com a contagem de divergências, caso contrário.

## Histórico de depuração

O processo de depuração deste testbench (rodado pela primeira vez neste
projeto) encontrou e corrigiu vários problemas reais no datapath, não
relacionados ao testbench em si. Ver a pasta [`log/`](log/) para o registro
completo, incluindo o motivo exato de cada erro observado no ModelSim
(loop combinacional, PC indeterminado, etc.) e a correção aplicada.
