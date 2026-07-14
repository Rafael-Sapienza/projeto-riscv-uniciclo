library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity ALUControl is
    Port (
        ALUOp      : in  STD_LOGIC_VECTOR(1 downto 0);
        funct3     : in  STD_LOGIC_VECTOR(2 downto 0);
        funct7     : in  STD_LOGIC_VECTOR(6 downto 0);
        ALUControl : out STD_LOGIC_VECTOR(3 downto 0)
    );
end ALUControl;

architecture Behavioral of ALUControl is
begin
process(ALUOp, funct3, funct7)
begin
    case ALUOp is
        ------------------------------------------------------------------
        -- ADD
        ------------------------------------------------------------------
        when "00" =>
            ALUControl <= "0000";
        ------------------------------------------------------------------
        -- BRANCH (BEQ/BNE/BLT/BGE/BLTU/BGEU) -- funct3 decide o
        -- comparador. BEQ/BNE usam SUB (o resto do datapath olha
        -- aluZERO, ver CPU.vhd/lgmuxPC); BLT/BGE/BLTU/BGEU usam os
        -- comparadores da ULA que ja produzem 0/1 diretamente
        -- (uSLT/uSGE/uSLTU/uSGEU).
        ------------------------------------------------------------------
        when "01" =>
            case funct3 is
                when "000" =>
                    ALUControl <= "0001";      -- BEQ (SUB)
                when "001" =>
                    ALUControl <= "0001";      -- BNE (SUB)
                when "100" =>
                    ALUControl <= "1000";      -- BLT (uSLT)
                when "101" =>
                    ALUControl <= "1010";      -- BGE (uSGE)
                when "110" =>
                    ALUControl <= "1001";      -- BLTU (uSLTU)
                when "111" =>
                    ALUControl <= "1011";      -- BGEU (uSGEU)
                when others =>
                    ALUControl <= "0001";      -- SUB
            end case;
        ------------------------------------------------------------------
        -- Tipo R (ADD/SUB/AND/OR/XOR/SLL/SRL/SRA/SLT/SLTU) -- Tipo I
        -- aritmetico usa ALUOp "11" (ver mais abaixo), nao este caso
        ------------------------------------------------------------------
        when "10" =>
            case funct3 is
                ----------------------------------------------------------
                -- ADD / SUB
                ----------------------------------------------------------
                when "000" =>
                    if funct7 = "0100000" then
                        ALUControl <= "0001";      -- SUB
                    else
                        ALUControl <= "0000";      -- ADD
                    end if;
                ----------------------------------------------------------
                -- SLL
                ----------------------------------------------------------
                when "001" =>
                    ALUControl <= "0101";
                ----------------------------------------------------------
                -- SLT  (Set Less Than, com sinal)
                ----------------------------------------------------------
                when "010" =>
                    ALUControl <= "1000";      -- uSLT
                ----------------------------------------------------------
                -- SLTU  (Set Less Than, sem sinal)
                ----------------------------------------------------------
                when "011" =>
                    ALUControl <= "1001";      -- uSLTU
                ----------------------------------------------------------
                -- XOR
                ----------------------------------------------------------
                when "100" =>
                    ALUControl <= "0100";
                ----------------------------------------------------------
                -- SRL / SRA
                ----------------------------------------------------------
                when "101" =>
                    if funct7 = "0100000" then
                        ALUControl <= "0111";      -- SRA
                    else
                        ALUControl <= "0110";      -- SRL
                    end if;
                ----------------------------------------------------------
                -- OR
                ----------------------------------------------------------
                when "110" =>
                    ALUControl <= "0011";
                ----------------------------------------------------------
                -- AND
                ----------------------------------------------------------
                when "111" =>
                    ALUControl <= "0010";
                when others =>
                    ALUControl <= "0000";
            end case;
        ------------------------------------------------------------------
        -- Tipo I aritmetico (ADDI/ANDI/.../SLLI/SRLI/SRAI) -- ver
        -- comentario em Control.vhdl sobre por que este caso usa um ALUOp
        -- diferente do tipo R
        ------------------------------------------------------------------
        when "11" =>
            case funct3 is
                ----------------------------------------------------------
                -- ADDI -- SEMPRE soma. Ao contrario do tipo R, aqui
                -- imOUT(31 downto 25) e parte do imediato de 12 bits
                -- (imm[11:5]), nao um funct7 de verdade: nao ha "SUBI" em
                -- RV32I, entao checar funct7 aqui faria imediatos entre
                -- 1024 e 1055 (imm[11:5] = "0100000") serem confundidos
                -- com subtracao.
                ----------------------------------------------------------
                when "000" =>
                    ALUControl <= "0000";      -- ADD
                ----------------------------------------------------------
                -- SLLI (o shamt de SLLI/SRLI/SRAI ja vem isolado e
                -- zero-estendido pelo genImm32)
                ----------------------------------------------------------
                when "001" =>
                    ALUControl <= "0101";
                when "010" =>
                    ALUControl <= "1000";      -- SLTI
                when "011" =>
                    ALUControl <= "1001";      -- SLTIU
                when "100" =>
                    ALUControl <= "0100";      -- XORI
                ----------------------------------------------------------
                -- SRLI / SRAI -- aqui SIM imOUT(31 downto 25) e um funct7
                -- de verdade: SRLI/SRAI reservam esses bits (por definicao
                -- do formato de instrucao) exatamente para diferenciar as
                -- duas, do mesmo jeito que SRL/SRA no tipo R.
                ----------------------------------------------------------
                when "101" =>
                    if funct7 = "0100000" then
                        ALUControl <= "0111";  -- SRAI
                    else
                        ALUControl <= "0110";  -- SRLI
                    end if;
                when "110" =>
                    ALUControl <= "0011";      -- ORI
                when "111" =>
                    ALUControl <= "0010";      -- ANDI
                when others =>
                    ALUControl <= "0000";
            end case;
        when others =>
            ALUControl <= "0000";
    end case;
end process;
end Behavioral;