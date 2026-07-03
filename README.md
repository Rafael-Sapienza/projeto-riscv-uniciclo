# projeto-riscv-uniciclo

Implementação de um processador **RISC-V RV32I uniciclo** em **VHDL**.

## Objetivo

Este projeto tem como objetivo implementar um processador RISC-V uniciclo, incluindo o caminho de dados (datapath), unidade de controle, controle da ULA e os demais componentes necessários para executar programas compatíveis com a ISA RV32I.

## Status do projeto

### ✅ Implementado

- Unidade de Controle Principal (Control Unit)
- Unidade de Controle da ULA (ALU Control)

## Instruções suportadas

| Instrução | Opcode      |  funct3 |    funct7    |
| --------- | ----------- | :-----: | :----------: |
| ADD       | 0110011     |   000   |    0000000   |
| SUB       | 0110011     |   000   |    0100000   |
| AND       | 0110011     |   111   |    0000000   |
| OR        | 0110011     |   110   |    0000000   |
| XOR       | 0110011     |   100   |    0000000   |
| SLL       | 0110011     |   001   |    0000000   |
| SRL       | 0110011     |   101   |    0000000   |
| SRA       | 0110011     |   101   |    0100000   |
| ADDI      | 0010011     |   000   |   imm[11:5]  |
| ANDI      | 0010011     |   111   |   imm[11:5]  |
| ORI       | 0010011     |   110   |   imm[11:5]  |
| XORI      | 0010011     |   100   |   imm[11:5]  |
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

## Decodificação da Unidade de Controle

A Unidade de Controle Principal utiliza apenas o **opcode** da instrução para gerar os sinais de controle do processador.

| Classe da instrução |   Opcode  | Instruções                              | Branch | JumpAndLink | IsJalr | IsLUI | IsAuipc | MemRead | MemWrite | MemToReg | RegWrite | ALUSrc | ALUOp |
| ------------------- | :-------: | --------------------------------------- | :----: | :---------: | :----: | :---: | :-----: | :-----: | :------: | :------: | :------: | :----: | :---: |
| Tipo R              | `0110011` | ADD, SUB, AND, OR, XOR, SLL, SRL, SRA   |    0   |      0      |    0   |   0   |    0    |    0    |     0    |     0    |     1    |    0   |   10  |
| Tipo I (aritmético) | `0010011` | ADDI, ANDI, ORI, XORI, SLLI, SRLI, SRAI |    0   |      0      |    0   |   0   |    0    |    0    |     0    |     0    |     1    |    1   |   10  |
| Load                | `0000011` | LW                                      |    0   |      0      |    0   |   0   |    0    |    1    |     0    |     1    |     1    |    1   |   00  |
| Store               | `0100011` | SW                                      |    0   |      0      |    0   |   0   |    0    |    0    |     1    |     0    |     0    |    1   |   00  |
| Branch              | `1100011` | BEQ, BNE                                |    1   |      0      |    0   |   0   |    0    |    0    |     0    |     0    |     0    |    0   |   01  |
| JAL                 | `1101111` | JAL                                     |    0   |      1      |    0   |   0   |    0    |    0    |     0    |     0    |     1    |    0   |   00  |
| JALR                | `1100111` | JALR                                    |    0   |      1      |    1   |   0   |    0    |    0    |     0    |     0    |     1    |    1   |   00  |
| LUI                 | `0110111` | LUI                                     |    0   |      0      |    0   |   1   |    0    |    0    |     0    |     0    |     1    |    1   |   00  |
| AUIPC               | `0010111` | AUIPC                                   |    0   |      0      |    0   |   0   |    1    |    0    |     0    |     0    |     1    |    1   |   00  |

## Próximos passos

- Implementar a ULA.
- Implementar o banco de registradores.
- Implementar o gerador de imediatos.
- Implementar as memórias de instruções e de dados.
- Integrar o datapath completo.