-- Random-Access Memory
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- RAM
entity RAM is
  generic (
    BSIZE : integer := 8;
    WSIZE : integer := 4*BSIZE;
    ASIZE : integer := 13;
    RAMDP : integer := (2**ASIZE)
  );
  port (
    clk     : in std_logic;
    we      : in std_logic;
    byte_en : in std_logic;
    sgn_en  : in std_logic;
    addr    : in std_logic_vector(ASIZE-1 downto 0);
    datain  : in std_logic_vector(WSIZE-1 downto 0);
    dataout : out std_logic_vector(WSIZE-1 downto 0);
  );
end RAM;
--  BSIZE   : byte size
--  WSIZE   : word size
--  ASIZE   : address size
--  RAMDP   : ram depth (amount of vectors in memory)
--  clk     : clock
--  we      : write enable
--  byte_en : byte access enable
--  sgn_en  : signal (+/-) enable (read only)
--  addr    : address
--  datain  : data in
--  dataout : data out

architecture aram of RAM is

type out_vec is array(0 to RAMDP-1) of std_logic_vector(BSIZE-1 downto 0);
signal mem : out_vec := (others => (others => '0'));
signal INTaddr : integer := 0;

begin

  ram_ad: process(addr)
  begin
    INTaddr <= to_integer(unsigned(addr));
  end process ram_ad;

  ram_pr: process(clk)
  begin
    if rising_edge(clk) then
      -- read logic
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
        -- read word, verificar addr antes de operar
          if addr(0) = '0' and addr(1) = '0' then
            -- little-endian
            dataout <= mem(INTaddr) & mem(INTaddr+1) & mem(INTaddr+2) & mem(INTaddr+3);
          end if;
      end if;

      -- write logic
      if (we = '1') then
        if (byte_en = '1') then
          -- byte write
          mem(INTaddr) <= datain(BSIZE-1 downto 0);
        else
          -- word write, verificar addr antes de operar
          if addr(0) = '0' and addr(1) = '0' then
            -- little-endian
            mem(INTaddr+0) <= datain(BSIZE*4-1 downto BSIZE*3);
            mem(INTaddr+1) <= datain(BSIZE*3-1 downto BSIZE*2);
            mem(INTaddr+2) <= datain(BSIZE*2-1 downto BSIZE*1);
            mem(INTaddr+3) <= datain(BSIZE*1-1 downto BSIZE*0);
          end if;
        end if;
      end if;

    end if;
  end process ram_pr;

end aram;
