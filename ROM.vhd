-- Read-Only Memory
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use std.textio.all;

-- ROM
entity ROM is
  generic (
    WSIZE : integer := 32;
    ASIZE : integer := 11;
    ROMDP : integer := (2**ASIZE)
  );
  port (
    addr : in std_logic_vector(ASIZE-1 downto 0);
    outw : out std_logic_vector(WSIZE-1 downto 0)
  );
end ROM;

architecture arom of ROM is

type out_vec is array(0 to ROMDP-1) of std_logic_vector(WSIZE-1 downto 0);

-- Função para ler "data.txt" e retornar um vetor memória
impure function init_rom_hex return out_vec is
  file text_file     : text open read_mode is "data.txt";
  variable text_line : line;
  variable rom_data  : out_vec;
begin

  for II in 0 to ROMDP - 1 loop
    readline(text_file, text_line);
    hread(text_line, rom_data(II));
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
