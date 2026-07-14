-- Read-Only Memory
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use std.textio.all;

-- ROM
entity ROM is
  generic (
    WSIZE     : integer := 32;
    ASIZE     : integer := 11;
    ROMDP     : integer := (2**ASIZE);
    INIT_FILE : string  := "data.txt"
  );
  port (
    addr : in std_logic_vector(ASIZE-1 downto 0);
    outw : out std_logic_vector(WSIZE-1 downto 0)
  );
end ROM;

architecture arom of ROM is

type out_vec is array(0 to ROMDP-1) of std_logic_vector(WSIZE-1 downto 0);

-- Função para ler o arquivo de instruções (INIT_FILE) e retornar um vetor
-- memória. Lê uma palavra (linha) por endereço, começando em 0, até
-- encontrar o fim do arquivo ou até preencher todos os ROMDP endereços —
-- o que ocorrer primeiro. Os endereços não preenchidos permanecem
-- zerados (valor inicial de rom_data), então o arquivo de entrada não
-- precisa mais ser preenchido com zeros até a profundidade da ROM.
impure function init_rom_hex return out_vec is
  file text_file     : text open read_mode is INIT_FILE;
  variable text_line : line;
  variable rom_data  : out_vec := (others => (others => '0'));
  variable idx       : integer := 0;
begin
  while idx < ROMDP and not endfile(text_file) loop
    readline(text_file, text_line);
    hread(text_line, rom_data(idx));
    idx := idx + 1;
  end loop;

  return rom_data;
end function;

-- Memória ROM
signal romemory : out_vec := init_rom_hex;

begin

  rom_pr: process(addr)
  begin
    outw <= romemory(to_integer(unsigned(addr)));
  end process;

end arom;
