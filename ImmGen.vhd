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

  -- Definição dos tipos de formatos internos
  type format_rV is (RT, IT, ITS, ST, SBT, UT, UJT, INVALID);
  signal curr_type : format_rV;

  -- =========================================================================
  -- CONSTANTES DE OPCODES
  -- =========================================================================
  constant R_TYPE_OP    : std_logic_vector(6 downto 0) := "0110011"; -- ADD, SUB, AND, etc.
  constant I_ARITH_OP   : std_logic_vector(6 downto 0) := "0010011"; -- ADDI, ANDI, SLLI, etc.
  constant LOAD_OP      : std_logic_vector(6 downto 0) := "0000011"; -- LW
  constant STORE_OP     : std_logic_vector(6 downto 0) := "0100011"; -- SW
  constant BRANCH_OP    : std_logic_vector(6 downto 0) := "1100011"; -- BEQ, BNE
  constant JAL_OP       : std_logic_vector(6 downto 0) := "1101111"; -- JAL
  constant JALR_OP      : std_logic_vector(6 downto 0) := "1100111"; -- JALR
  constant LUI_OP       : std_logic_vector(6 downto 0) := "0110111"; -- LUI
  constant AUIPC_OP     : std_logic_vector(6 downto 0) := "0010111"; -- AUIPC

  -- =========================================================================
  -- ALIASES PARA FATIAMENTO DA INSTRUÇÃO
  -- =========================================================================
  alias opcode : std_logic_vector(6 downto 0) is instr(6 downto 0);
  alias rd     : std_logic_vector(4 downto 0) is instr(11 downto 7);
  alias funct3 : std_logic_vector(2 downto 0) is instr(14 downto 12);
  alias rs1    : std_logic_vector(4 downto 0) is instr(19 downto 15);
  alias rs2    : std_logic_vector(4 downto 0) is instr(24 downto 20);
  alias funct7 : std_logic_vector(6 downto 0) is instr(31 downto 25);

begin
  discover: process(instr, opcode, funct3)
  begin
    case opcode is
      when R_TYPE_OP =>
        curr_type <= RT;
      when I_ARITH_OP =>
        -- Identifica se é uma instrução de Shift Imediato (SLLI, SRLI, SRAI)
        if funct3 = "001" or funct3 = "101" then
          curr_type <= ITS;
        else
          curr_type <= IT;
        end if;
      when LOAD_OP =>
        curr_type <= IT;
      when JALR_OP =>
        curr_type <= IT;
      when STORE_OP =>
        curr_type <= ST;
      when BRANCH_OP =>
        curr_type <= SBT;
      when LUI_OP =>
        curr_type <= UT;
      when AUIPC_OP =>
        curr_type <= UT;
      when JAL_OP =>
        curr_type <= UJT;
      when others =>
        curr_type <= INVALID;
    end case;
  end process discover;

  compute: process(instr, curr_type, funct7, rs2, rd, rs1, funct3)
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
        imm32 <= signed(instr(31 downto 12) & X"000");
      when UJT =>
        imm32 <= resize(signed(funct7(6) & rs1 & funct3 & rs2(0) & funct7(5 downto 0) & rs2(4 downto 1) & '0'), imm32'length);
      when others =>
        imm32 <= (others => '0');
    end case;
  end process compute;

end rtl;