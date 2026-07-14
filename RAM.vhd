-- Random-Access Memory
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use std.textio.all;

-- RAM
entity RAM is
  generic (
    BSIZE     : integer := 8;
    WSIZE     : integer := 4*BSIZE;
    ASIZE     : integer := 13;
    RAMDP     : integer := (2**ASIZE);
    INIT_FILE : string  := ""
  );
  port (
    clk      : in std_logic;
    we       : in std_logic;
    byte_en  : in std_logic;
    sgn_en   : in std_logic;
    addr     : in std_logic_vector(ASIZE-1 downto 0);
    datain   : in std_logic_vector(WSIZE-1 downto 0);
    dataout  : out std_logic_vector(WSIZE-1 downto 0);
    -- porta de depuração (byte): leitura combinacional de 1 byte, sem
    -- efeito colateral no datapath principal. Usada pelo ecall PrintString.
    dbg_addr : in std_logic_vector(ASIZE-1 downto 0) := (others => '0');
    dbg_byte : out std_logic_vector(BSIZE-1 downto 0);
    -- porta de depuração (palavra): leitura combinacional de 1 palavra de
    -- 32 bits, independente da porta acima. Usada pelo testbench para ler
    -- o conteúdo final da RAM sem precisar de "external names" (que se
    -- mostraram frágeis quanto à ordem de elaboração em algumas versões
    -- do ModelSim/Questa).
    tb_addr  : in std_logic_vector(ASIZE-1 downto 0) := (others => '0');
    tb_word  : out std_logic_vector(WSIZE-1 downto 0);
    -- porta de depuração (palavra, temporária): igual a tb_addr/tb_word,
    -- mas de uso exclusivo do trace interno da CPU (ver CPU.vhd/tracePr)
    -- -- uma porta separada evita qualquer disputa de driver com
    -- dump_addr/dump_word (dirigida de fora, pelo testbench).
    trc_addr : in std_logic_vector(ASIZE-1 downto 0) := (others => '0');
    trc_word : out std_logic_vector(WSIZE-1 downto 0)
  );
end RAM;
--  BSIZE   : byte size
--  WSIZE   : word size
--  ASIZE   : address size
--  RAMDP   : ram depth (amount of vectors in memory)
--  INIT_FILE : arquivo com o estado inicial da RAM (1 palavra de 32 bits em
--              hexadecimal por linha, big-endian, começando no endereço 0).
--              Se for uma string vazia, a RAM começa toda zerada.
--  clk     : clock
--  we      : write enable
--  byte_en : byte access enable
--  sgn_en  : signal (+/-) enable (read only)
--  addr    : address
--  datain  : data in
--  dataout : data out
--  dbg_addr/dbg_byte : porta de depuração (ver acima)

architecture aram of RAM is

type out_vec is array(0 to RAMDP-1) of std_logic_vector(BSIZE-1 downto 0);

-- Lê INIT_FILE (1 palavra de 32 bits por linha, big-endian) e carrega os
-- bytes sequencialmente a partir do endereço 0. Lê até o fim do arquivo OU
-- até preencher toda a RAM, o que ocorrer primeiro. Se INIT_FILE for uma
-- string vazia, nada é lido e a RAM permanece zerada
impure function init_mem return out_vec is
  variable ram_data  : out_vec := (others => (others => '0'));
  variable idx       : integer := 0;
  variable text_line : line;
  variable w         : std_logic_vector(31 downto 0);
  file text_file     : text;
  variable fstatus   : file_open_status;
begin
  if INIT_FILE'length > 0 then
    file_open(fstatus, text_file, INIT_FILE, read_mode);
    if fstatus = open_ok then
      while (idx + 3 <= RAMDP - 1) and not endfile(text_file) loop
        readline(text_file, text_line);
        hread(text_line, w);
        ram_data(idx + 0) := w(31 downto 24);
        ram_data(idx + 1) := w(23 downto 16);
        ram_data(idx + 2) := w(15 downto  8);
        ram_data(idx + 3) := w(7  downto  0);
        idx := idx + 4;
      end loop;
      file_close(text_file);
    end if;
  end if;
  return ram_data;
end function;

signal mem : out_vec := init_mem;

begin

  -- IMPORTANTE: sensível também a "mem" (não só ao endereço) -- senão,
  -- sempre que o endereço de depuração NÃO mudar de valor entre duas
  -- consultas (ex.: o endereço 0 coincide com o valor padrão do sinal e é
  -- consultado antes de qualquer outro), o processo não é reativado e a
  -- porta continua mostrando o conteúdo ANTIGO de "mem", mesmo depois de
  -- escritas mais recentes (bug real, encontrado comparando o dump final
  -- da RAM com a execução real da CPU).
  dbg_pr: process(dbg_addr, mem)
  begin
    dbg_byte <= mem(to_integer(unsigned(dbg_addr)));
  end process dbg_pr;

  tb_pr: process(tb_addr, mem)
    variable idx : integer;
  begin
    idx := to_integer(unsigned(tb_addr));
    if idx <= RAMDP - 4 then
      tb_word <= mem(idx) & mem(idx+1) & mem(idx+2) & mem(idx+3);
    end if;
  end process tb_pr;

  trc_pr: process(trc_addr, mem)
    variable idx : integer;
  begin
    idx := to_integer(unsigned(trc_addr));
    if idx <= RAMDP - 4 then
      trc_word <= mem(idx) & mem(idx+1) & mem(idx+2) & mem(idx+3);
    end if;
  end process trc_pr;

  -- leitura combinacional (assíncrona): numa CPU uniciclo, o dado do "lw"
  -- precisa estar disponível no mesmo ciclo em que o endereço é calculado,
  -- não no ciclo seguinte. Antes, esta leitura estava dentro de
  -- `if rising_edge(clk)`, ou seja, "dataout" só refletia o endereço do
  -- ciclo ANTERIOR -- bug real, confirmado simulando a CPU (lw lia o
  -- valor de um ciclo atrás em vez do endereço atual).
  --
  -- O índice é calculado numa VARIÁVEL local (idx), não num sinal
  -- separado computado por outro processo (como havia antes, em
  -- "INTaddr"/"ram_ad"): um sinal derivado por um processo à parte
  -- sempre carrega um ciclo delta de atraso em relação à sua fonte, o
  -- que abre uma janela onde este processo pode ser reativado por causa
  -- de "addr" ter mudado, mas ainda enxergar o valor ANTIGO do sinal
  -- derivado -- combinação inconsistente que, num caso de borda, chegou
  -- a passar no teste de alinhamento com um índice fora dos limites do
  -- array (ver log/09-condicao-de-corrida-indice-ram.md). Uma variável
  -- local não tem esse atraso: é recalculada por inteiro a cada vez que
  -- o processo roda.
  read_pr: process(addr, byte_en, sgn_en, mem)
    variable idx : integer;
  begin
    idx := to_integer(unsigned(addr));
    if (byte_en = '1') then
      -- read byte
      if (sgn_en = '1') then
        -- signed byte
        dataout <= std_logic_vector(resize(signed(mem(idx)), WSIZE));
      else
        -- unsigned byte
        dataout <= std_logic_vector(resize(unsigned(mem(idx)), WSIZE));
      end if;
    else
      -- read word, verificar addr antes de operar. A checagem extra
      -- "idx <= RAMDP-4" é uma segunda linha de defesa contra qualquer
      -- estouro do array, mesmo que o endereço final de toda instrução
      -- real já tenha sido verificado (por simulação de referência) como
      -- sempre dentro dos limites da RAM.
      if addr(0) = '0' and addr(1) = '0' and idx <= RAMDP - 4 then
        -- little-endian
        dataout <= mem(idx) & mem(idx+1) & mem(idx+2) & mem(idx+3);
      end if;
    end if;
  end process read_pr;

  -- escrita síncrona (correta: escritas devem acontecer na borda de clock).
  -- Mesmo raciocínio de "read_pr": índice calculado localmente, sem
  -- depender de um sinal derivado por outro processo.
  write_pr: process(clk)
    variable idx : integer;
  begin
    if rising_edge(clk) then
      idx := to_integer(unsigned(addr));
      if (we = '1') then
        if (byte_en = '1') then
          -- byte write
          mem(idx) <= datain(BSIZE-1 downto 0);
        else
          -- word write, verificar addr antes de operar (mesma guarda
          -- extra de limites usada em read_pr)
          if addr(0) = '0' and addr(1) = '0' and idx <= RAMDP - 4 then
            -- little-endian
            mem(idx+0) <= datain(BSIZE*4-1 downto BSIZE*3);
            mem(idx+1) <= datain(BSIZE*3-1 downto BSIZE*2);
            mem(idx+2) <= datain(BSIZE*2-1 downto BSIZE*1);
            mem(idx+3) <= datain(BSIZE*1-1 downto BSIZE*0);
          end if;
        end if;
      end if;
    end if;
  end process write_pr;

end aram;
