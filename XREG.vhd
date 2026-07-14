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
    reset        : in std_logic := '1'; -- limpa todos os registradores (ver CPU.vhd)
    rs1, rs2, rd : in std_logic_vector(RADRR-1 downto 0);
    data         : in std_logic_vector(WSIZE-1 downto 0);
    ro1, ro2     : out std_logic_vector(WSIZE-1 downto 0);
    ro_a0, ro_a7 : out std_logic_vector(WSIZE-1 downto 0);
    -- porta de depuração (temporária): leitura combinacional de QUALQUER
    -- registrador por número, usada só para trace/debug (ver CPU.vhd)
    dbg_rnum     : in  std_logic_vector(RADRR-1 downto 0) := (others => '0');
    dbg_rval     : out std_logic_vector(WSIZE-1 downto 0)
  );
end XREGS;
-- clk      : clock
-- wren     : write enable
-- reset    : limpa todos os registradores (x1..x31) de forma assíncrona
-- rs1, rs2 : register 1/2 for reading
-- rd       : register for writing
-- data     : data for writing
-- ro1, ro2 : output of register 1/2
-- ro_a0, ro_a7 : leitura combinacional (independente de rs1/rs2) dos
--                registradores a0 (x10) e a7 (x17), usada pelo ecall
-- dbg_rnum/dbg_rval : porta de depuração (ver acima)


architecture xreg of XREGS is

-- Endereços ABI fixos usados pela convenção de chamada de sistema (ecall)
constant A0_REG : natural := 10;
constant A7_REG : natural := 17;

component REG is
  port (
    d            : in std_logic_vector(WSIZE-1 downto 0);
    clk, clr, ld : in std_logic;
    q            : out std_logic_vector(WSIZE-1 downto 0)
  );
end component;

signal xld : std_logic_vector(0 to RAMNT-1) := (others => '0');

type out_vec is array(0 to RAMNT-1) of std_logic_vector(WSIZE-1 downto 0);
signal out_q : out_vec := (others => (others => '0'));

signal dr1, dr2 : std_logic_vector(WSIZE-1 downto 0);

begin

  -- gera banco de registradores
  -- todos conectados ao mesmo data/clk
  -- barramento RAMNT para clr e ld
  -- array RAMNT para saida
  GENREGS:
  for I in 1 to RAMNT-1 generate
    REGX: REG port map (data, clk, reset, xld(I), out_q(I));
  end generate GENREGS;

  -- processa valor de rs1 pendente. IMPORTANTE: sensível também a "out_q"
  -- (não só a "rs1") -- senão, sempre que a instrução ATUAL ler o mesmo
  -- registrador que a instrução anterior acabou de escrever (ex.: "addi
  -- sp,sp,-20" seguido de "sw ra,16(sp)", ambos com rs1=sp), "rs1" não
  -- muda de valor entre as duas instruções e este processo não é
  -- reativado -- "dr1" continua mostrando o conteúdo ANTIGO de out_q(rs1),
  -- de antes da escrita mais recente (o mesmo tipo de bug documentado em
  -- log/06-porta-depuracao-sensibilidade-incompleta.md, desta vez no
  -- próprio caminho de leitura de registradores, não numa porta de
  -- depuração).
  settleR1: process(rs1, out_q)
  begin
    if to_integer(unsigned(rs1)) = 0 then
      -- x0 eh constante zero
      dr1 <= (others => '0');
    else
      dr1 <= out_q(to_integer(unsigned(rs1)));
    end if;
  end process settleR1;

  -- processa valor de rs2 pendente (mesmo raciocínio de settleR1)
  settleR2: process(rs2, out_q)
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

  -- x0 (índice 0) nunca é gerado como REG; mantém a
  -- posição zerada por conta própria
  out_q(0) <= (others => '0');

  -- leitura combinacional de rd1/rd2: numa CPU uniciclo, rd1/rd2 precisam
  -- refletir rs1/rs2 DA INSTRUÇÃO ATUAL, no MESMO ciclo (não da instrução
  -- anterior). Antes, isso estava dentro de um processo síncrono
  -- (`if rising_edge(clk) then ro1<=dr1; ...`), o que atrasava rd1/rd2 em
  -- 1 ciclo -- todo ALU/branch/etc. acabava operando com os operandos da
  -- instrução ANTERIOR em vez da atual (bug real, confirmado simulando a
  -- CPU: os valores de registrador chegavam sempre um ciclo atrasados).
  ro1 <= dr1;
  ro2 <= dr2;

  -- leitura combinacional de a0/a7, independente dos campos rs1/rs2 da
  -- instrução corrente (necessária para o ecall, cuja codificação não
  -- referencia esses registradores através de rs1/rs2)
  ro_a0 <= out_q(A0_REG);
  ro_a7 <= out_q(A7_REG);

  dbg_rval <= out_q(to_integer(unsigned(dbg_rnum)));

end xreg;
