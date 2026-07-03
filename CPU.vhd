-- Processador Uniciclo
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity uRV is

end uRV;



architecture CPU of uRV is

-- Registrador básico
component REG is
  port (
    d            : in std_logic_vector(WSIZE-1 downto 0);
    clk, clr, ld : in std_logic;
    q            : out std_logic_vector(WSIZE-1 downto 0)
  );
end component;


begin

  -- Registrador PC e PC+4
  regPC: REG port map();
  regPCp4: REG port map();




end CPU;
