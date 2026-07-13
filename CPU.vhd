-- Processador Uniciclo
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use std.textio.all;

entity uRV is
  generic (
    WSIZE : integer := 32;
    ROMSIZE : integer := 11;
    RAMSIZE : integer := 13;
    ROMDP : integer := (2**ROMSIZE);
    RADRR : natural := 5;
    ROM_FILE : string := "data.txt"; -- arquivo de instruções (hex, 1 palavra/linha)
    RAM_FILE : string := "";         -- arquivo de dados iniciais da RAM (vazio = RAM zerada)
    TRACE_CYCLES : integer := 0      -- > 0: imprime pc/instr/registradores nos N primeiros ciclos (debug)
  );
  port (
    clk       : in  std_logic;
    -- reset assíncrono do PC (ativo em '1'). Sem isso, o registrador do PC
    -- nunca recebe um valor definido: seu próprio "d" (pcIN) depende de
    -- pcp4OUT, que depende de pcOUT -- um laço que, partindo de 'U'
    -- (indefinido), nunca converge sozinho para um valor real. O
    -- testbench deve pulsar reset='1' por pelo menos 1 ciclo no início da
    -- simulação antes de liberar o clock.
    reset     : in  std_logic := '1';
    halt      : out std_logic := '0'; -- '1' quando o programa chamou ecall Exit2 (a7=93)
    exit_code : out std_logic_vector(WSIZE-1 downto 0) := (others => '0'); -- valor de a0 no Exit2
    -- porta de depuração (somente leitura, combinacional): permite ao
    -- testbench ler qualquer palavra da RAM final sem precisar de
    -- "external names" -- ver RAM.vhd (porta tb_addr/tb_word)
    dump_addr : in  std_logic_vector(RAMSIZE-1 downto 0) := (others => '0');
    dump_word : out std_logic_vector(WSIZE-1 downto 0)
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
end component REG;

-- Memória ROM (IM)
component ROM is
  generic (
    WSIZE     : integer := 32;
    ASIZE     : integer := 11;
    ROMDP     : integer := (2**ASIZE);
    INIT_FILE : string  := "data.txt"
  );
  port (
    addr : in std_logic_vector(ASIZE-1 downto 0); -- 10:0
    outw : out std_logic_vector(WSIZE-1 downto 0)
  );
end component ROM;

-- Memória RAM (DM)
component RAM is
  generic (
    BSIZE     : integer := 8;
    WSIZE     : integer := 4*BSIZE;
    ASIZE     : integer := 13;
    RAMDP     : integer := (2**ASIZE);
    INIT_FILE : string  := ""
  );
  port (
    clk      : in std_logic;
    we       : in std_logic;
    byte_en  : in std_logic;
    sgn_en   : in std_logic;
    addr     : in std_logic_vector(ASIZE-1 downto 0); -- 12:0
    datain   : in std_logic_vector(WSIZE-1 downto 0);
    dataout  : out std_logic_vector(WSIZE-1 downto 0);
    dbg_addr : in std_logic_vector(ASIZE-1 downto 0) := (others => '0');
    dbg_byte : out std_logic_vector(BSIZE-1 downto 0);
    tb_addr  : in std_logic_vector(ASIZE-1 downto 0) := (others => '0');
    tb_word  : out std_logic_vector(WSIZE-1 downto 0)
  );
end component RAM;

-- Banco de registradores
component XREGS is
  port (
    clk, wren    : in std_logic;
    reset        : in std_logic := '1';
    rs1, rs2, rd : in std_logic_vector(RADRR-1 downto 0);
    data         : in std_logic_vector(WSIZE-1 downto 0);
    ro1, ro2     : out std_logic_vector(WSIZE-1 downto 0);
    ro_a0, ro_a7 : out std_logic_vector(WSIZE-1 downto 0);
    dbg_rnum     : in  std_logic_vector(RADRR-1 downto 0) := (others => '0');
    dbg_rval     : out std_logic_vector(WSIZE-1 downto 0)
  );
end component XREGS;

-- Gerador de Imediatos
component genImm32 is
  port (
    instr : in std_logic_vector(31 downto 0);
    imm32 : out signed(31 downto 0)
  );
end component genImm32;

-- ULA
component ulaRV is
  port (
    opcode : in std_logic_vector(3 downto 0);
    A, B   : in std_logic_vector(WSIZE-1 downto 0);
    Z      : out std_logic_vector(WSIZE-1 downto 0);
    cond   : out std_logic
  );
end component ulaRV;

-- Controle
component ControlUnit is
  Port (
    opcode      : in  STD_LOGIC_VECTOR(6 downto 0);
    Branch      : out STD_LOGIC;
    JumpAndLink : out STD_LOGIC;
    IsJalr      : out STD_LOGIC;
    IsLUI       : out STD_LOGIC;
    IsAuipc     : out STD_LOGIC;
    Ecall       : out STD_LOGIC;
    MemRead     : out STD_LOGIC;
    MemWrite    : out STD_LOGIC;
    MemToReg    : out STD_LOGIC;
    RegWrite    : out STD_LOGIC;
    ALUSrc      : out STD_LOGIC;
    ALUOp       : out STD_LOGIC_VECTOR(1 downto 0)
  );
end component ControlUnit;

-- ULA Controle
component ALUControl is
    Port (
        ALUOp      : in  STD_LOGIC_VECTOR(1 downto 0);
        funct3     : in  STD_LOGIC_VECTOR(2 downto 0);
        funct7     : in  STD_LOGIC_VECTOR(6 downto 0);
        ALUControl : out STD_LOGIC_VECTOR(3 downto 0)
    );
end component ALUControl;



-- type vWsize is std_logic_vector(WSIZE-1 downto 0);


-- SINAIS

signal pcIN, pcOUT     : std_logic_vector(WSIZE-1 downto 0) := (others => '0'); -- PC in/out
signal pcDISPL         : std_logic_vector(WSIZE-1 downto 0) := (others => '0'); -- PC displacement (pc+imm)
signal pcTARGET        : std_logic_vector(WSIZE-1 downto 0) := (others => '0');
-- PC+4 (combinacional, direto de pcOUT -- ver addPC4). NÃO é registrado:
-- é usado tanto para o "próximo PC" (fall-through) quanto para o endereço
-- de retorno de JAL/JALR, e em ambos os casos precisa refletir o PC
-- ATUAL (pcOUT) no MESMO ciclo. Um registrador separado aqui (como havia
-- antes) criava um laço combinacional pcIN -> pcp4IN -> pcIN sem nenhum
-- elemento de memória quebrando o ciclo, travando a simulação em "iteration
-- limit reached" logo em 0 ps, antes do primeiro clock.
signal pcp4OUT         : std_logic_vector(WSIZE-1 downto 0) := (others => '0');

alias imIN is pcOUT(12 downto 2); -- Instruction Memory in
signal imOUT : std_logic_vector(WSIZE-1 downto 0) := (others => '0'); -- Instruction Memory out

-- Separando a instrução
alias Iopcode : std_logic_vector(6 downto 0) is imOUT(6 downto 0);
alias Irr1    : std_logic_vector(4 downto 0) is imOUT(19 downto 15);
alias Irr2    : std_logic_vector(4 downto 0) is imOUT(24 downto 20);
alias Iwrd    : std_logic_vector(4 downto 0) is imOUT(11 downto 7);
alias Ifunct3 : std_logic_vector(2 downto 0) is imOUT(14 downto 12);
alias Ifunct7 : std_logic_vector(6 downto 0) is imOUT(31 downto 25);

signal wregdataIN : std_logic_vector(WSIZE-1 downto 0) := (others => '0'); -- Write Data XREG
signal rd1, rd2   : std_logic_vector(WSIZE-1 downto 0) := (others => '0'); -- Read registers XREG
signal a0OUT, a7OUT : std_logic_vector(WSIZE-1 downto 0) := (others => '0'); -- a0/a7 (ver ecall)

signal imm32OUT : signed(WSIZE-1 downto 0) := (others => '0'); -- Immediate OUT

-- Sinais de controle
signal ctrlBranch  : std_logic := '0';
signal ctrlJAL     : std_logic := '0';
signal ctrlJALr    : std_logic := '0';
signal ctrlLUI     : std_logic := '0';
signal ctrlAUIPC   : std_logic := '0';
signal ctrlEcall   : std_logic := '0';
signal ctrlMemRead : std_logic := '0';
signal ctrlMemWr   : std_logic := '0';
signal ctrlMem2Reg : std_logic := '0';
signal ctrlRegWr   : std_logic := '0';
signal ctrlALUOp   : std_logic_vector(1 downto 0) := (others => '0');
signal ctrlALUSr   : std_logic := '0';
signal ctrlMpc     : std_logic := '0'; -- PC Mux control
signal ctrlExit    : std_logic := '0'; -- '1' quando o programa chamou ecall Exit2 (a7=93)

-- ULA
signal aluZERO   : std_logic;
signal aluI1     : std_logic_vector(WSIZE-1 downto 0);
signal aluI2     : std_logic_vector(WSIZE-1 downto 0);
signal aluOUT    : std_logic_vector(WSIZE-1 downto 0);
signal ctrlALUmt : std_logic_vector(3 downto 0);

-- Data Memory
alias dmAddr : std_logic_vector(RAMSIZE-1 downto 0) is aluOUT(RAMSIZE-1 downto 0);
signal dmOUT : std_logic_vector(WSIZE-1 downto 0);
signal dbgAddr : std_logic_vector(RAMSIZE-1 downto 0) := (others => '0'); -- endereço de depuração (ecall PrintString)
signal dbgByte : std_logic_vector(7 downto 0);

-- Depuração (temporária): leitura de qualquer registrador por número, só
-- para o trace controlado por TRACE_CYCLES
signal dbgRnum : std_logic_vector(RADRR-1 downto 0) := (others => '0');
signal dbgRval : std_logic_vector(WSIZE-1 downto 0);

-- Constantes globais
signal cnstZERO : std_logic := '0';
signal cnstONE  : std_logic := '1';

-- Códigos de chamada de sistema (ecall), lidos de a7 (x17) — compatíveis
-- com os syscalls equivalentes do RARS
constant SYSCALL_PRINT_INT    : std_logic_vector(WSIZE-1 downto 0) := x"00000001";
constant SYSCALL_PRINT_STRING : std_logic_vector(WSIZE-1 downto 0) := x"00000004";
constant SYSCALL_EXIT2        : std_logic_vector(WSIZE-1 downto 0) := x"0000005D"; -- 93



begin

  -- COMPONENTES

  -- Registrador PC (PC+4 agora é combinacional, ver addPC4/pcp4OUT).
  -- clr = reset (não mais cnstZERO): é o único jeito de o PC começar
  -- definido em vez de indeterminado (ver comentário no port de reset).
  regPC: REG port map(pcIN, clk, reset, cnstONE, pcOUT);

  -- Memória ROM de instruções
  romIM: ROM
    generic map(WSIZE => WSIZE, ASIZE => ROMSIZE, INIT_FILE => ROM_FILE)
    port map(imIN, imOUT);

  -- Gerador de imediatos
  GI: genImm32 port map(imOUT, imm32OUT);

  -- Banco de registradores
  regBANK: XREGS port map(clk, ctrlRegWr, reset, Irr1, Irr2, Iwrd, wregdataIN, rd1, rd2, a0OUT, a7OUT, dbgRnum, dbgRval);

  -- ULA
  aluULA: ulaRV port map(ctrlALUmt, aluI1, aluI2, aluOUT, aluZERO);

  -- Controle ULA
  ctrlULA: ALUControl port map(ctrlALUOp, Ifunct3, Ifunct7, ctrlALUmt);

  -- Controle
  ctrlCPU: ControlUnit port map(Iopcode, ctrlBranch, ctrlJAL, ctrlJALr, ctrlLUI, ctrlAUIPC, ctrlEcall, ctrlMemRead, ctrlMemWr, ctrlMem2Reg, ctrlRegWr, ctrlALUSr, ctrlALUOp);

  -- Data Memory
  ramDM: RAM
    generic map(WSIZE => WSIZE, ASIZE => RAMSIZE, INIT_FILE => RAM_FILE)
    port map(clk, ctrlMemWr, cnstZERO, cnstZERO, dmAddr, rd2, dmOUT, dbgAddr, dbgByte, dump_addr, dump_word);



  -- PROCESSOS

  muxALUI1: process(rd1, pcOUT, ctrlLUI, ctrlAUIPC)
  begin
    if ctrlLUI = '1' then
      aluI1 <= (others => '0');
    elsif ctrlAUIPC = '1' then
      aluI1 <= pcOUT;
    else
      aluI1 <= rd1;
    end if;
  end process muxALUI1;

  addPC4: process(pcOUT)
  begin
    pcp4OUT <= std_logic_vector(unsigned(pcOUT) + 4);
  end process addPC4;

  addPCImm: process(imm32OUT, pcOUT)
  begin
    pcDISPL <= std_logic_vector(shift_left(imm32OUT, 1) + signed(pcOUT));
  end process addPCImm;

  muxJALR: process(pcDISPL, aluOUT, ctrlJALr)
  -- No jalr, o valor em rd1 pode não ser múltiplo de 4, o que geraria problemas de acesso a memória
  -- Forçamos o endereço a ser múltiplo de 4
  constant mask_align : std_logic_vector(WSIZE-1 downto 0) := (31 downto 2 => '1', others => '0');
  begin
    case ctrlJALr is
      when '0'    => pcTARGET <= pcDISPL;
      when '1'    => pcTARGET <= aluOUT and mask_align;
      when others => pcTARGET <= pcDISPL;
    end case;
  end process muxJALR;

  -- BEQ (funct3=000) e BNE (funct3=001) usam o MESMO ALUControl (SUB, ver
  -- ALUControl.vhdl) e portanto o mesmo aluZERO ("A=B?"); o bit0 de
  -- Ifunct3 é exatamente o que diferencia BEQ de BNE, então usamos ele
  -- para inverter a condição de desvio quando for BNE (desvia se A/=B).
  lgmuxPC: process(ctrlBranch, aluZERO, ctrlJAL, Ifunct3)
  begin
    if ctrlBranch = '1' then
      ctrlMpc <= aluZERO xor Ifunct3(0);
    else
      ctrlMpc <= ctrlJAL;
    end if;
  end process lgmuxPC;

  -- Detecta o ecall de saída (Exit2, a7=93). O restante do datapath
  -- continua decodificando a MESMA instrução ecall enquanto o PC estiver
  -- congelado (ver muxPC), o que é seguro: ecall nunca escreve em
  -- registrador nem em memória (RegWrite/MemWrite ficam em '0' por
  -- default no ControlUnit para o opcode SYSTEM).
  lgExit: process(ctrlEcall, a7OUT)
  begin
    if ctrlEcall = '1' and a7OUT = SYSCALL_EXIT2 then
      ctrlExit <= '1';
    else
      ctrlExit <= '0';
    end if;
  end process lgExit;

  muxPC: process(pcp4OUT, pcTARGET, ctrlMpc, ctrlExit, pcOUT)
  begin
    if ctrlExit = '1' then
      pcIN <= pcOUT; -- congela o PC: programa encerrado
    else
      case ctrlMpc is
        when '0'    => pcIN <= pcp4OUT;
        when '1'    => pcIN <= pcTARGET;
        when others => pcIN <= pcp4OUT;
      end case;
    end if;
  end process muxPC;

  muxRD2: process(rd2, imm32OUT, ctrlALUSr)
  begin
    case ctrlALUSr is
      when '0' => aluI2 <= rd2;
      when '1' => aluI2 <= std_logic_vector(imm32OUT);
      when others => aluI2 <= rd2;
    end case;
  end process muxRD2;

  muxWriteReg: process(ctrlMem2Reg, ctrlJAL, ctrlJALr, dmOUT, aluOUT, pcp4OUT)
  begin
    if (ctrlJAL = '1' or ctrlJALr = '1') then
      wregdataIN <= pcp4OUT;
    elsif ctrlMem2Reg = '1' then
      wregdataIN <= dmOUT;
    else
      wregdataIN <= aluOUT;
    end if;
  end process muxWriteReg;

  -- Sinalização de fim de programa para o testbench
  halt      <= ctrlExit;
  exit_code <= a0OUT;

  -- ecall PrintInt (a7=1) e PrintString (a7=4): efeitos colaterais de
  -- console (somente em simulação), sem impacto no estado do processador.
  -- Compatíveis com os syscalls equivalentes do RARS.
  ecallPrint: process
    variable l           : line;
    variable strAddr     : unsigned(RAMSIZE-1 downto 0);
    variable char_count  : integer;
    constant MAX_STR_LEN : integer := 4096;
  begin
    wait until rising_edge(clk);
    if ctrlEcall = '1' then
      if a7OUT = SYSCALL_PRINT_INT then
        write(l, integer'image(to_integer(signed(a0OUT))));
        writeline(output, l);
      elsif a7OUT = SYSCALL_PRINT_STRING then
        strAddr := unsigned(a0OUT(RAMSIZE-1 downto 0));
        char_count := 0;
        dbgAddr <= std_logic_vector(strAddr);
        wait for 1 ns;
        while dbgByte /= x"00" and char_count < MAX_STR_LEN loop
          write(l, character'val(to_integer(unsigned(dbgByte))));
          strAddr := strAddr + 1;
          dbgAddr <= std_logic_vector(strAddr);
          wait for 1 ns;
          char_count := char_count + 1;
        end loop;
        writeline(output, l);
      end if;
    end if;
  end process ecallPrint;

  -- Trace de depuração TEMPORÁRIO (TRACE_CYCLES=0 desativa, é o padrão):
  -- imprime pc/instrução/alguns registradores a cada ciclo, para comparar
  -- contra um emulador de referência e localizar divergências de execução.
  tracePr: process
    variable l : line;
    variable n : integer := 0;

    procedure read_reg(rnum : in integer; v : out std_logic_vector(WSIZE-1 downto 0)) is
    begin
      dbgRnum <= std_logic_vector(to_unsigned(rnum, RADRR));
      wait for 1 ns;
      v := dbgRval;
    end procedure read_reg;

    variable v_s0, v_s1, v_s2, v_t2, v_t3, v_t4, v_t6 : std_logic_vector(WSIZE-1 downto 0);
  begin
    wait until rising_edge(clk);
    if TRACE_CYCLES > 0 and n < TRACE_CYCLES then
      read_reg(8,  v_s0); -- s0
      read_reg(9,  v_s1); -- s1
      read_reg(18, v_s2); -- s2
      read_reg(7,  v_t2); -- t2
      read_reg(28, v_t3); -- t3
      read_reg(29, v_t4); -- t4
      read_reg(31, v_t6); -- t6

      write(l, string'("step="));
      write(l, n);
      write(l, string'(" pc="));
      hwrite(l, pcOUT);
      write(l, string'(" instr="));
      hwrite(l, imOUT);
      write(l, string'(" s0="));
      write(l, to_integer(signed(v_s0)));
      write(l, string'(" s1="));
      write(l, to_integer(signed(v_s1)));
      write(l, string'(" s2="));
      hwrite(l, v_s2);
      write(l, string'(" t2="));
      write(l, to_integer(signed(v_t2)));
      write(l, string'(" t3="));
      write(l, to_integer(signed(v_t3)));
      write(l, string'(" t4="));
      write(l, to_integer(signed(v_t4)));
      write(l, string'(" t6="));
      write(l, to_integer(unsigned(v_t6)));
      writeline(output, l);

      n := n + 1;
    end if;
  end process tracePr;

end CPU;
