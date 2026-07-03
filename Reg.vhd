-- Registrador
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- Reg
entity REG is
  generic ( WSIZE : natural := 32 );
  port (
    d            : in std_logic_vector(WSIZE-1 downto 0);
    clk, clr, ld : in std_logic;
    q            : out std_logic_vector(WSIZE-1 downto 0)
  );
end REG;
-- d   : data in
-- q   : data out
-- clk : clock
-- clr : async clear
-- ld  : load/enable


architecture rtl of REG is
begin

  xreg: process(clk, clr)
  begin
    if (clr = '1') then
      -- clear assincrono
      q <= (others => '0');
    elsif rising_edge(clk) then
      -- carregar valor
      if (ld = '1') then
        q <= d;
      end if;
    end if;
  end process xreg;

end rtl;
