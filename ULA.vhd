-- Unidade Logica Aritmetica
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- ULA
entity ulaRV is
  generic (
    WSIZE : integer := 32
  );
  port (
    opcode : in std_logic_vector(3 downto 0);
    A, B   : in std_logic_vector(WSIZE-1 downto 0);
    Z      : out std_logic_vector(WSIZE-1 downto 0);
    cond   : out std_logic
  );
end ulaRV;

architecture ula of ulaRV is

CONSTANT uADD  : std_logic_vector(3 downto 0) := "0000";
CONSTANT uSUB  : std_logic_vector(3 downto 0) := "0001";
CONSTANT uAND  : std_logic_vector(3 downto 0) := "0010";
CONSTANT uOR   : std_logic_vector(3 downto 0) := "0011";
CONSTANT uXOR  : std_logic_vector(3 downto 0) := "0100";
CONSTANT uSLL  : std_logic_vector(3 downto 0) := "0101";
CONSTANT uSRL  : std_logic_vector(3 downto 0) := "0110";
CONSTANT uSRA  : std_logic_vector(3 downto 0) := "0111";
CONSTANT uSLT  : std_logic_vector(3 downto 0) := "1000";
CONSTANT uSLTU : std_logic_vector(3 downto 0) := "1001";
CONSTANT uSGE  : std_logic_vector(3 downto 0) := "1010";
CONSTANT uSGEU : std_logic_vector(3 downto 0) := "1011";
CONSTANT uSEQ  : std_logic_vector(3 downto 0) := "1100";
CONSTANT uSNE  : std_logic_vector(3 downto 0) := "1101";

signal a32 : std_logic_vector(WSIZE-1 downto 0);

begin

  ula_cond: process(a32)
  begin

    Z <= a32;
    if (a32 = X"00000000") then
      cond <= '1';
    else
      cond <= '0';
    end if;

  end process ula_cond;

  ula_pr: process(opcode, A, B)
  begin

    case opcode is
      when uADD  => a32 <= std_logic_vector(signed(A) + signed(B));
      when uSUB  => a32 <= std_logic_vector(signed(A) - signed(B));
      when uAND  => a32 <= A and B;
      when uOR   => a32 <= A or B;
      when uXOR  => a32 <= A xor B;
      -- RV32I so considera os 5 bits menos significativos de B como
      -- quantidade de deslocamento (shamt), mesmo quando B vem de um
      -- registrador (SLL/SRL/SRA tipo R, com qualquer valor de 32 bits).
      -- Sem o corte para B(4 downto 0), to_integer(unsigned(B)) recebe o
      -- valor de 32 bits inteiro: se o bit mais alto de B estiver ligado
      -- (valor sem sinal >= 2^31), a conversao estoura o intervalo de
      -- NATURAL e o ModelSim acusa "TO_INTEGER: Value ... is not in
      -- bounds of subtype NATURAL". Para SLLI/SRLI/SRAI (B = imediato)
      -- isso e inofensivo, pois o genImm32 ja entrega o shamt isolado e
      -- zero-estendido (ver ImmGen.vhd, tipo ITS) -- o corte so muda o
      -- resultado de fato no caso tipo R.
      when uSLL  => a32 <= std_logic_vector(shift_left(unsigned(A), to_integer(unsigned(B(4 downto 0)))));
      when uSRL  => a32 <= std_logic_vector(shift_right(unsigned(A), to_integer(unsigned(B(4 downto 0)))));
      when uSRA  => a32 <= std_logic_vector(shift_right(signed(A), to_integer(unsigned(B(4 downto 0)))));
      when uSLT  =>
        if (signed(A) < signed(B)) then
          a32 <= X"00000001";
        else
          a32 <= X"00000000";
        end if;
      when uSLTU =>
        if (unsigned(A) < unsigned(B)) then
          a32 <= X"00000001";
        else
          a32 <= X"00000000";
        end if;
      when uSGE  =>
        if (signed(A) >= signed(B)) then
          a32 <= X"00000001";
        else
          a32 <= X"00000000";
        end if;
      when uSGEU =>
        if (unsigned(A) >= unsigned(B)) then
          a32 <= X"00000001";
        else
          a32 <= X"00000000";
        end if;
      when uSEQ =>
        if (A = B) then
          a32 <= X"00000001";
        else
          a32 <= X"00000000";
        end if;
      when uSNE =>
        if (A /= B) then
          a32 <= X"00000001";
        else
          a32 <= X"00000000";
        end if;
      when others => a32 <= X"00000000";
    end case;

  end process;

end ula;
