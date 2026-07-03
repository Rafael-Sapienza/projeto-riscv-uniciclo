-- Banco de registradores
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- XREG
entity XREGS is
  generic (
    WSIZE : natural := 32;
    RAMNT : natural := 32;
    RADRR : natural := 5
  );
  port (
    clk, wren    : in std_logic;
    rs1, rs2, rd : in std_logic_vector(RADRR-1 downto 0);
    data         : in std_logic_vector(WSIZE-1 downto 0);
    ro1, ro2     : out std_logic_vector(WSIZE-1 downto 0)
  );
end XREGS;
-- clk      : clock
-- wren     : write enable
-- rs1, rs2 : register 1/2 for reading
-- rd       : register for writing
-- data     : data for writing
-- ro1, ro2 : output of register 1/2


architecture xreg of XREGS is

component REG is
  port (
    d            : in std_logic_vector(WSIZE-1 downto 0);
    clk, clr, ld : in std_logic;
    q            : out std_logic_vector(WSIZE-1 downto 0)
  );
end component;

signal xclr, xld : std_logic_vector(0 to RAMNT-1) := (others => '0');

type out_vec is array(0 to RAMNT-1) of std_logic_vector(WSIZE-1 downto 0);
signal out_q : out_vec := (others => (others => '0'));

signal dr1, dr2 : std_logic_vector(WSIZE-1 downto 0);

begin

  -- gera banco de registradores
  -- todos conectados ao mesmo data/clk
  -- barramento RAMNT para clr e ld
  -- array RAMNT para saida
  -- x0 nao gera, caso desejavel troque (1 to RAMNT-1) por (0 to RAMNT-1)
  GENREGS:
  for I in 1 to RAMNT-1 generate
    REGX: REG port map (data, clk, xclr(I), xld(I), out_q(I));
  end generate GENREGS;

  -- processa valor de rs1 pendente
  settleR1: process(rs1, xclr)
  begin
    if to_integer(unsigned(rs1)) = 0 then
      -- x0 eh constante zero
      dr1 <= (others => '0');
    else
      dr1 <= out_q(to_integer(unsigned(rs1)));
    end if;
  end process settleR1;

  -- processa valor de rs2 pendente
  settleR2: process(rs2, xclr)
  begin
    if to_integer(unsigned(rs2)) = 0 then
      -- x0 eh constante zero
      dr2 <= (others => '0');
    else
      dr2 <= out_q(to_integer(unsigned(rs2)));
    end if;
  end process settleR2;

  -- processa se escrita deve ocorrer, e onde
  settleWr: process(wren, rd)
  begin
    xld <= (others => '0');
    if (wren = '1') then
      -- x0 eh constante zero, ignora escrita
      if to_integer(unsigned(rd)) /= 0 then
        xld(to_integer(unsigned(rd))) <= '1';
      end if;
    end if;
  end process settleWr;

  -- batida do clock troca saida
  mainp: process(clk)
  begin
    out_q(0) <= (others => '0');
    if rising_edge(clk) then
      ro1 <= dr1;
      ro2 <= dr2;
    end if;
  end process mainp;

end xreg;
