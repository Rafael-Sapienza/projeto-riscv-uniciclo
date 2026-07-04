-- Processador Uniciclo
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity uRV is
  generic (
    WSIZE : integer := 32;
    ROMSIZE : integer := 11;
    RAMSIZE : integer := 13;
    ROMDP : integer := (2**ROMSIZE);
    RADRR : natural := 5
  );
end uRV;



architecture CPU of uRV is

-- COMPONENTES

-- Registrador básico
component REG is
  port (
    d            : in std_logic_vector(WSIZE-1 downto 0);
    clk, clr, ld : in std_logic;
    q            : out std_logic_vector(WSIZE-1 downto 0)
  );
end component;

-- Memória ROM (IM)
component ROM is
  port (
    addr : in std_logic_vector(ROMSIZE-1 downto 0); -- 10:0
    outw : out std_logic_vector(WSIZE-1 downto 0)
  );
end component;

-- Memória RAM (DM)
component RAM is
  port (
    clk     : in std_logic;
    we      : in std_logic;
    byte_en : in std_logic;
    sgn_en  : in std_logic;
    addr    : in std_logic_vector(RAMSIZE-1 downto 0); -- 12:0
    datain  : in std_logic_vector(WSIZE-1 downto 0);
    dataout : out std_logic_vector(WSIZE-1 downto 0);
  );
end component;

-- Banco de registradores
component XREGS is
  port (
    clk, wren    : in std_logic;
    rs1, rs2, rd : in std_logic_vector(RADRR-1 downto 0);
    data         : in std_logic_vector(WSIZE-1 downto 0);
    ro1, ro2     : out std_logic_vector(WSIZE-1 downto 0)
  );
end component;

-- Gerador de Imediatos
component genImm32 is
  port (
    instr : in std_logic_vector(31 downto 0);
    imm32 : out signed(31 downto 0)
  );
end component;

-- ULA
component ulaRV is
  port (
    opcode : in std_logic_vector(3 downto 0);
    A, B   : in std_logic_vector(WSIZE-1 downto 0);
    Z      : out std_logic_vector(WSIZE-1 downto 0);
    cond   : out std_logic
  );
end component;

-- Controle
component ControlUnit is
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
end component;

-- ULA Controle
component ALUControl is
    Port (
        ALUOp      : in  STD_LOGIC_VECTOR(1 downto 0);
        funct3     : in  STD_LOGIC_VECTOR(2 downto 0);
        funct7     : in  STD_LOGIC_VECTOR(6 downto 0);
        ALUControl : out STD_LOGIC_VECTOR(3 downto 0)
    );
end component;



type vWsize is std_logic_vector(WSIZE-1 downto 0);


-- SINAIS

signal clk : std_logic;

signal pcIN, pcOUT     : vWsize := (others => '0'); -- PC in/out
signal pcDISPL         : vWsize := (others => '0'); -- PC displacement (pc+imm)
signal pcp4IN, pcp4OUT : vWsize := (others => '0'); -- PC+4 in/out

alias imIN is pcOUT(12 downto 2); -- Instruction Memory in
signal imOUT : vWsize := (others => '0'); -- Instruction Memory out

-- Separando a instrução
alias Iopcode : std_logic_vector(6 downto 0) is imOUT(6 downto 0);
alias Irr1    : std_logic_vector(4 downto 0) is imOUT(19 downto 15);
alias Irr2    : std_logic_vector(4 downto 0) is imOUT(24 downto 20);
alias Iwrd    : std_logic_vector(4 downto 0) is imOUT(11 downto 7);
alias Ifunct3 : std_logic_vector(2 downto 0) is imOUT(14 downto 12);
alias Ifunct7 : std_logic_vector(6 downto 0) is imOUT(31 downto 25);

signal wregdataIN : vWsize := (others => '0'); -- Write Data XREG
signal rd1, rd2   : vWsize := (others => '0'); -- Read registers XREG

signal imm32OUT : vWsize := (others => '0'); -- Immediate OUT

-- Sinais de controle
signal ctrlBranch  : std_logic := '0';
signal ctrlJAL     : std_logic := '0';
signal ctrlJALr    : std_logic := '0';
signal ctrlLUI     : std_logic := '0';
signal ctrlAUIPC   : std_logic := '0';
signal ctrlMemRead : std_logic := '0';
signal ctrlMemWr   : std_logic := '0';
signal ctrlMem2Reg : std_logic := '0';
signal ctrlRegWr   : std_logic := '0';
signal ctrlALUOp   : std_logic := '0';
signal ctrlALUSr   : std_logic := '0';
signal ctrlMpc     : std_logic := '0'; -- PC Mux control

-- ULA
signal aluZERO   : std_logic;
signal aluI1     : vWsize;
signal aluI2     : vWsize;
signal aluOUT    : vWsize;
signal ctrlALUmt : std_logic_vector(3 downto 0);

-- Data Memory
alias dmAddr : std_logic_vector(RAMSIZE-1 downto 0) is aluOUT(RAMSIZE-1 downto 0);
sinal dmOUT  : vWsize;

-- Constantes globais
signal cnstZERO : std_logic := '0';
signal cnstONE  : std_logic := '1';



begin

  -- COMPONENTES

  -- Registrador PC e PC+4
  regPC: REG port map(pcIN, clck, cnstZERO, cnstONE, pcOUT);
  regPCp4: REG port map(pcp4IN, clck, cnstZERO, cnstONE, pcp4OUT);

  -- Memória ROM de instruções
  romIM: ROM port map(imIN, imOUT);

  -- Gerador de imediatos
  GI: genImm32 port map(imOUT, imm32OUT);

  -- Banco de registradores
  regBANK: XREG port map(clk, ctrlRegWr, Irr1, Irr2, Iwrd, wregdataIN, rd1, rd2);

  -- ULA
  aluULA: ulaRV port map(ctrlALUmt, aluI1, aluI2, aluOUT, aluZERO);

  -- Controle ULA
  ctrlULA: ALUControl port map(ctrlALUOp, Ifunct3, Ifunct7, ctrlALUmt);

  -- Controle
  ctrlCPU: ControlUnit port map(Iopcode, ctrlBranch, ctrlJAL, ctrlJALr, ctrlLUI, ctrlAUIPC, ctrlMemRead, ctrlMemWr, ctrlMem2Reg, ctrlRegWr, ctrlALUSr, ctrlALUOp);

  -- Data Memory
  ramDM: RAM port map(clk, ctrlMemWr, cnstZERO, cnstZERO, dmAddr, rd2, dmOUT);



  -- PROCESSOS

  addPC4: process(pcIN)
  begin
    pcp4IN <= std_logic_vector(unsigned(pcIN) + 4);
  end process addPC4;

  addPCImm: process(imm32OUT, pcOUT)
  begin
    pcDISPL <= std_logic_vector(shift_left(unsigned(imm32OUT), 1) + unsigned(pcOUT));
  end process addPCImm;

  lgmuxPC: process(ctrlBranch, aluZERO)
  begin
    ctrlMpc <= ctrlBranch and aluZERO;
  end process lgmuxPC;

  muxPC: process(pcp4IN, pcDISPL, ctrlMpc)
  begin
    case ctrlMpc is
      when '0' => pcIN <= pcp4IN;
      when '1' => pcIN <= pcDISPL;
      when others => pcIN <= pcp4IN;
    end case;
  end process muxPC;

  muxRD2: process(rd2, imm32OUT, ctrlALUSr)
  begin
    case ctrlALUSr is
      when '0' => aluI2 <= rd2;
      when '1' => aluI2 <= imm32OUT;
      when others => aluI2 <= rd2;
    end case;
  end process muxRD2;

  muxMem2Reg: process(ctrlMem2Reg, dmOUT, aluOUT)
  begin
    case ctrlMem2Reg is
      when '0' => wregdataIN <= aluOUT;
      when '1' => wregdataIN <= dmOUT;
      when others => wregdataIN <= aluOUT;
    end case;
  end process muxMem2Reg;

end CPU;
