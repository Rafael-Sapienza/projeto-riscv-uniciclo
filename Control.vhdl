library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity ControlUnit is
    Port (
        opcode      : in  STD_LOGIC_VECTOR(6 downto 0);
        Branch      : out STD_LOGIC;
        JumpAndLink : out STD_LOGIC;
        IsJalr      : out STD_LOGIC;
        IsLUI       : out STD_LOGIC;
        IsAuipc     : out STD_LOGIC;
        MemRead     : out STD_LOGIC;
        MemWrite    : out STD_LOGIC;
        MemToReg    : out STD_LOGIC;
        RegWrite    : out STD_LOGIC;
        ALUSrc      : out STD_LOGIC;
        ALUOp       : out STD_LOGIC_VECTOR(1 downto 0)
    );
end ControlUnit;

architecture Behavioral of ControlUnit is

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

begin

process(opcode)
begin
    -- Valores padrão
    Branch      <= '0';
    JumpAndLink <= '0';
    IsJalr      <= '0';
    IsLUI       <= '0';
    IsAuipc     <= '0';
    MemRead     <= '0';
    MemWrite    <= '0';
    MemToReg    <= '0';
    RegWrite    <= '0';
    ALUSrc      <= '0';
    ALUOp       <= "00";
    case opcode is
        when R_TYPE_OP =>
            RegWrite <= '1';
            ALUOp    <= "10";
        when I_ARITH_OP =>
            RegWrite <= '1';
            ALUSrc   <= '1';
            ALUOp    <= "10";
        when LOAD_OP =>
            MemRead  <= '1';
            MemToReg <= '1';
            RegWrite <= '1';
            ALUSrc   <= '1';
        when STORE_OP =>
            MemWrite <= '1';
            ALUSrc   <= '1';
        when BRANCH_OP =>
            Branch   <= '1';
            ALUOp    <= "01";
        when JAL_OP =>
            JumpAndLink <= '1';
            RegWrite    <= '1';
        when JALR_OP =>
            JumpAndLink <= '1';
            IsJalr      <= '1';
            RegWrite    <= '1';
            ALUSrc      <= '1';
        when LUI_OP =>
            IsLUI    <= '1';
            RegWrite <= '1';
            ALUSrc   <= '1';
        when AUIPC_OP =>
            IsAuipc  <= '1';
            RegWrite <= '1';
            ALUSrc   <= '1';
        -- Instrução inválida
        when others =>
            null;
    end case;
end process;

end Behavioral;