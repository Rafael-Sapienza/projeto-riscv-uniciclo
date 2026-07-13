# 01 — Falha de elaboração com "external names"

## Contexto

Para comparar o conteúdo final da RAM com um arquivo de saída esperada, a
primeira versão do testbench precisava ler o sinal interno `mem` da
instância da RAM (`ramDM`), que não é exposto por nenhuma porta da CPU.
A abordagem inicialmente adotada foi o recurso de "external names" do
VHDL-2008, que permite declarar um alias para um sinal em qualquer ponto
da hierarquia de instâncias a partir de um nome de caminho:

```vhdl
alias ram_mem : ram_bytes_t is << signal .dut.ramDM.mem : ram_bytes_t >>;
```

## Sintoma

Ao simular no ModelSim/Questa, a elaboração emitia avisos indicando que o
caminho absoluto do nome externo não era reconhecido:

```
** Warning: (vsim-1425) Absolute pathname for a VHDL external name does not
   start with an entity name that is a design root. Instead, an object with
   the name 'dut' was found in the scope of design root 'tb_urv'. This
   object was used as the starting point of the external name.
** Warning: (vsim-8523) Cannot reference the signal "/tb_urv/dut/ramDM/mem"
   before it has been elaborated.
```

Em seguida, a simulação travava com:

```
** Error (suppressible): (vsim-3601) Iteration limit 5000 reached at time 0 ps.
```

## Diagnóstico

O primeiro aviso indica uma diferença entre a interpretação do padrão pela
ferramenta e a suposição inicial de que o caminho absoluto de um nome
externo poderia começar diretamente pelo rótulo da primeira instância
(`.dut...`). No ModelSim/Questa, o caminho absoluto precisa começar
explicitamente pelo nome da própria entidade raiz do projeto de simulação
(`.tb_uRV.dut...`). Corrigir apenas essa sintaxe eliminou o primeiro aviso,
mas não o travamento da simulação — o que indicava a existência de um
segundo problema, tratado no documento seguinte
([02-loop-combinacional-pc-mais-4.md](02-loop-combinacional-pc-mais-4.md)).

Ainda assim, a estabilidade dos "external names" nessa ferramenta
mostrou-se frágil: mesmo com a sintaxe corrigida, a resolução do nome
externo dependia da ordem de elaboração das instâncias do projeto, o que é
um comportamento específico da ferramenta e não garantido de forma
uniforme por todos os simuladores compatíveis com VHDL-2008.

## Correção

A dependência de "external names" foi eliminada. Em seu lugar, foi
adicionada à RAM uma porta de depuração comum (dois novos sinais,
`tb_addr`/`tb_word`), de leitura combinacional e sem efeito colateral no
caminho de dados principal, exposta também na entidade `uRV` como
`dump_addr`/`dump_word`. O testbench passou a usar essa porta para ler
qualquer palavra da RAM final, dispensando completamente o recurso de
nomes externos:

```vhdl
procedure read_ram_word(byte_addr : in integer; w : out std_logic_vector(31 downto 0)) is
begin
  dump_addr <= std_logic_vector(to_unsigned(byte_addr, RAMSIZE));
  wait for 1 ns;
  w := dump_word;
end procedure read_ram_word;
```

Essa abordagem não depende de nenhum recurso específico de VHDL-2008 além
do já usado no restante do testbench, e funciona de forma idêntica em
qualquer simulador compatível.
