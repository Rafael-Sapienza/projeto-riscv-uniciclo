-- Gerador de imediatos
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- Imediato 32-bit
entity genImm32 is
  port (
    instr : in std_logic_vector(31 downto 0);
    imm32 : out signed(31 downto 0)
  );
end genImm32;

architecture rtl of genImm32 is

type format_rV is (RT,IT,ITS,ST,SBT,UT,UJT,INVALID);

signal curr_type : format_rV;

alias opcode : std_logic_vector(6 downto 0) is instr(6 downto 0);
alias rd     : std_logic_vector(4 downto 0) is instr(11 downto 7);
alias funct3 : std_logic_vector(2 downto 0) is instr(14 downto 12);
alias rs1    : std_logic_vector(4 downto 0) is instr(19 downto 15);
alias rs2    : std_logic_vector(4 downto 0) is instr(24 downto 20);
alias funct7 : std_logic_vector(6 downto 0) is instr(31 downto 25);

begin

  discover: process(instr)
  begin

    case opcode is
      when "0110011" =>
        curr_type <= RT;
      when "0000011" =>
        curr_type <= IT;
      when "1100111" =>
        curr_type <= IT;
      when "0010011" =>
        -- IT vs IT*
        if instr(30) = '1' and funct3 = "101" then
          curr_type <= ITS;
        else
          curr_type <= IT;
        end if;
      when "0100011" =>
        curr_type <= ST;
      when "1100011" =>
        curr_type <= SBT;
      when "0110111" =>
        curr_type <= UT;
      when "1101111" =>
        curr_type <= UJT;
      when others =>
        curr_type <= INVALID;
    end case;

  end process discover;

  compute: process(instr, curr_type)
  begin
    case curr_type is
      when RT =>
        imm32 <= (others => '0');
      when IT =>
        imm32 <= resize(signed(funct7 & rs2), imm32'length);
      when ITS =>
        imm32 <= signed(X"000000" & "000" & rs2);
      when ST =>
        imm32 <= resize(signed(funct7 & rd), imm32'length);
      when SBT =>
        imm32 <= resize(signed(funct7(6) & rd(0) & funct7(5 downto 0) & rd(4 downto 1) & '0'), imm32'length);
      when UT =>
        imm32 <= resize(signed(funct7 & rs2 & rs1 & funct3 & X"000"), imm32'length);
      when UJT =>
        imm32 <= resize(signed(funct7(6) & rs1 & funct3 & rs2(0) & funct7(5 downto 0) & rs2(4 downto 1) & '0'), imm32'length);
      when others =>
        imm32 <= (others => '0');
    end case;
  end process compute;

end rtl;
