# Log de depuração

Este diretório documenta os problemas identificados durante a criação e a
primeira execução do testbench (`tb_uRV.vhd`) do processador, bem como as
correções aplicadas. A maior parte dos problemas descritos aqui é anterior
ao testbench em si: são defeitos que já existiam no datapath (`CPU.vhd`,
`RAM.vhd`, `XREG.vhd`) e que nunca haviam sido exercitados por uma
simulação real antes deste trabalho.

Os documentos estão numerados na ordem cronológica em que os problemas
foram encontrados, uma vez que a resolução de um problema costuma revelar
o próximo (por exemplo, a simulação só conseguiu avançar além do primeiro
ciclo depois que o laço combinacional descrito no documento 02 foi
eliminado, o que por sua vez permitiu observar que o PC permanecia
indeterminado, problema descrito no documento 05).

| Documento | Resumo |
| --------- | ------ |
| [01-nomes-externos-na-elaboracao.md](01-nomes-externos-na-elaboracao.md) | Falha de elaboração ao usar "external names" (VHDL-2008) para ler a RAM final a partir do testbench. |
| [02-loop-combinacional-pc-mais-4.md](02-loop-combinacional-pc-mais-4.md) | Laço combinacional entre o PC e o registrador de "PC+4", causando `Iteration limit reached` em 0 ps. |
| [03-leitura-sincrona-banco-registradores-ram.md](03-leitura-sincrona-banco-registradores-ram.md) | Leituras do banco de registradores e da RAM implementadas de forma síncrona, incompatíveis com um processador uniciclo. |
| [04-bne-tratado-como-beq.md](04-bne-tratado-como-beq.md) | A instrução BNE se comportava como BEQ, por falta de diferenciação na lógica de desvio. |
| [05-pc-indeterminado-sem-reset.md](05-pc-indeterminado-sem-reset.md) | Após a correção do item 02, o PC permanecia indefinido (`XXXXXXXX`) durante toda a simulação, por falta de um sinal de reset. |
| [06-porta-depuracao-sensibilidade-incompleta.md](06-porta-depuracao-sensibilidade-incompleta.md) | A porta de depuração usada para ler a RAM final ao término da simulação retornava, em um endereço específico, o conteúdo inicial da RAM em vez do conteúdo atualizado. |
| [07-reset-banco-registradores.md](07-reset-banco-registradores.md) | O banco de registradores não possuía reset, gerando avisos de valor indeterminado em comparações antes da primeira escrita em cada registrador. |
| [08-registrador-sem-valor-padrao-na-porta.md](08-registrador-sem-valor-padrao-na-porta.md) | A porta de saída do componente `REG` não tinha valor padrão, causando avisos residuais de metavalor em 0 ps mesmo após a adição do reset. |
| [09-condicao-de-corrida-indice-ram.md](09-condicao-de-corrida-indice-ram.md) | Condição de corrida entre o endereço da RAM e um sinal derivado por outro processo causava, em um caso de borda, estouro do array de memória. |
| [10-leitura-registradores-sensibilidade-incompleta.md](10-leitura-registradores-sensibilidade-incompleta.md) | A leitura de `rs1`/`rs2` no banco de registradores não era sensível ao conteúdo dos registradores, apenas ao número lido — mesma classe de defeito do documento 06, agora no caminho principal de leitura. |
| [11-verificacao-de-zero-incompativel-com-pilha.md](11-verificacao-de-zero-incompativel-com-pilha.md) | Limitação do testbench (não um defeito do processador): a verificação de que o restante da RAM está zerado gera falsos positivos em programas que usam pilha de chamadas. |
| [12-addi-confundido-com-sub.md](12-addi-confundido-com-sub.md) | `addi` com imediato entre 1024 e 1055 era confundido com `sub` pela ALUControl, por reaproveitar o campo de funct7 do tipo R. |
| [13-shift-sem-mascara-de-shamt.md](13-shift-sem-mascara-de-shamt.md) | `sll`/`srl`/`sra` (tipo R) usavam o registrador inteiro como quantidade de deslocamento, em vez de só os 5 bits menos significativos. |
| [14-suporte-a-blt-bge-bltu-bgeu.md](14-suporte-a-blt-bge-bltu-bgeu.md) | Não é um bug, e sim uma extensão: BLT/BGE/BLTU/BGEU passaram a ser decodificadas como instruções reais (antes só BEQ/BNE), necessário para executar código gerado pelo RARS. |

## Metodologia

A confirmação de cada problema e de cada correção foi feita comparando a
execução real no simulador (ModelSim/Questa) com um emulador de referência
escrito em Python, que reproduz o conjunto de instruções implementado pela
CPU (incluindo a codificação de imediatos de desvio/salto usada pelo
projeto e, posteriormente, JALR/AUIPC/LUI). Esse emulador foi usado como
oráculo para verificar, ciclo a ciclo, se o comportamento observado no
simulador correspondia ao comportamento esperado dos programas de teste:
`testes/teste1` (bubble sort, 10 inteiros), `testes/teste2`/`testes/teste3`
(quicksort recursivo, 25 inteiros) e `testes/teste4` (quicksort de 40
inteiros combinado com hash, CRC-32 e um bloco de cobertura de
instruções — ver itens 12 e 13, os únicos dois defeitos deste registro
encontrados por um teste desenhado deliberadamente para achá-los, em vez
de por acaso durante a depuração de um programa comum).
