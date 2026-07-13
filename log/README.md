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

## Metodologia

A confirmação de cada problema e de cada correção foi feita comparando a
execução real no simulador (ModelSim/Questa) com um emulador de referência
escrito em Python, que reproduz o conjunto de instruções implementado pela
CPU (incluindo a codificação de imediatos de desvio/salto usada pelo
projeto). Esse emulador foi usado como oráculo para verificar, ciclo a
ciclo, se o comportamento observado no simulador correspondia ao
comportamento esperado do programa executado — um programa de ordenação
(bubble sort) sobre um vetor de 10 inteiros, descrito em `teste1/`.
