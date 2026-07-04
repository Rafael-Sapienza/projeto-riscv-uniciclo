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

        ------------------------------------------------------------------
        -- Tipo R
        ------------------------------------------------------------------
        when "0110011" =>
            RegWrite <= '1';
            ALUOp    <= "10";

        ------------------------------------------------------------------
        -- Tipo I aritmético
        ------------------------------------------------------------------
        when "0010011" =>
            RegWrite <= '1';
            ALUSrc   <= '1';
            ALUOp    <= "10";

        ------------------------------------------------------------------
        -- LW
        ------------------------------------------------------------------
        when "0000011" =>
            MemRead  <= '1';
            MemToReg <= '1';
            RegWrite <= '1';
            ALUSrc   <= '1';

        ------------------------------------------------------------------
        -- SW
        ------------------------------------------------------------------
        when "0100011" =>
            MemWrite <= '1';
            ALUSrc   <= '1';

        ------------------------------------------------------------------
        -- Branch (BEQ/BNE)
        ------------------------------------------------------------------
        when "1100011" =>
            Branch   <= '1';
            ALUOp    <= "01";

        ------------------------------------------------------------------
        -- JAL
        ------------------------------------------------------------------
        when "1101111" =>
            JumpAndLink <= '1';
            RegWrite    <= '1';

        ------------------------------------------------------------------
        -- JALR
        ------------------------------------------------------------------
        when "1100111" =>
            JumpAndLink <= '1';
            IsJalr      <= '1';
            RegWrite    <= '1';
            ALUSrc      <= '1';

        ------------------------------------------------------------------
        -- LUI
        ------------------------------------------------------------------
        when "0110111" =>
            IsLUI    <= '1';
            RegWrite <= '1';
            ALUSrc   <= '1';

        ------------------------------------------------------------------
        -- AUIPC
        ------------------------------------------------------------------
        when "0010111" =>
            IsAuipc  <= '1';
            RegWrite <= '1';
            ALUSrc   <= '1';

        ------------------------------------------------------------------
        -- Instrução inválida
        ------------------------------------------------------------------
        when others =>
            null;

    end case;

end process;

end Behavioral;