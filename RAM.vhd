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
    -- 32 bits, independente da porta acima. Usada pelo TESTBENCH para ler
    -- o conteúdo final da RAM sem precisar de "external names" (que se
    -- mostraram frágeis quanto à ordem de elaboração em algumas versões
    -- do ModelSim/Questa).
    tb_addr  : in std_logic_vector(ASIZE-1 downto 0) := (others => '0');
    tb_word  : out std_logic_vector(WSIZE-1 downto 0)
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
-- string vazia, nada é lido e a RAM permanece zerada (comportamento
-- padrão, compatível com o uso anterior sem arquivo de entrada).
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
signal INTaddr : integer := 0;

begin

  ram_ad: process(addr)
  begin
    INTaddr <= to_integer(unsigned(addr));
  end process ram_ad;

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

  -- leitura combinacional (assíncrona): numa CPU uniciclo, o dado do "lw"
  -- precisa estar disponível no MESMO ciclo em que o endereço é calculado,
  -- não no ciclo seguinte. Antes, esta leitura estava dentro de
  -- `if rising_edge(clk)`, ou seja, "dataout" só refletia o endereço do
  -- ciclo ANTERIOR -- bug real, confirmado simulando a CPU (lw lia o
  -- valor de um ciclo atrás em vez do endereço atual).
  read_pr: process(INTaddr, byte_en, sgn_en, addr, mem)
  begin
    if (byte_en = '1') then
      -- read byte
      if (sgn_en = '1') then
        -- signed byte
        dataout <= std_logic_vector(resize(signed(mem(INTaddr)), WSIZE));
      else
        -- unsigned byte
        dataout <= std_logic_vector(resize(unsigned(mem(INTaddr)), WSIZE));
      end if;
    else
      -- read word, verificar addr antes de operar. A checagem extra
      -- "INTaddr <= RAMDP-4" evita estourar o array em avaliações
      -- transitórias (delta-cycle) de "addr" ainda não completamente
      -- assentado -- embora o endereço final de qualquer instrução real
      -- nunca ultrapasse os limites da RAM (verificado por simulação de
      -- referência), o processo é reavaliado a cada mudança em "mem", e
      -- um valor intermediário/transitório de "addr" pode, por uma
      -- fração de delta-cycle, aparentar estar alinhado sem realmente
      -- estar dentro dos limites (ver log/09-estouro-transitorio-do-indice-da-ram.md)
      if addr(0) = '0' and addr(1) = '0' and INTaddr <= RAMDP - 4 then
        -- little-endian
        dataout <= mem(INTaddr) & mem(INTaddr+1) & mem(INTaddr+2) & mem(INTaddr+3);
      end if;
    end if;
  end process read_pr;

  -- escrita síncrona (correta: escritas devem acontecer na borda de clock)
  write_pr: process(clk)
  begin
    if rising_edge(clk) then
      if (we = '1') then
        if (byte_en = '1') then
          -- byte write
          mem(INTaddr) <= datain(BSIZE-1 downto 0);
        else
          -- word write, verificar addr antes de operar (mesma guarda
          -- extra de limites usada em read_pr)
          if addr(0) = '0' and addr(1) = '0' and INTaddr <= RAMDP - 4 then
            -- little-endian
            mem(INTaddr+0) <= datain(BSIZE*4-1 downto BSIZE*3);
            mem(INTaddr+1) <= datain(BSIZE*3-1 downto BSIZE*2);
            mem(INTaddr+2) <= datain(BSIZE*2-1 downto BSIZE*1);
            mem(INTaddr+3) <= datain(BSIZE*1-1 downto BSIZE*0);
          end if;
        end if;
      end if;
    end if;
  end process write_pr;

end aram;
