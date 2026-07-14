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
    tb_word  : out std_logic_vector(WSIZE-1 downto 0);
    trc_addr : in std_logic_vector(ASIZE-1 downto 0) := (others => '0');
    trc_word : out std_logic_vector(WSIZE-1 downto 0)
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

-- Depuração (temporária): leitura de 1 palavra da RAM por endereço, uso
-- exclusivo do trace de execução (tracePr, controlado por TRACE_CYCLES)
signal trcAddr : std_logic_vector(RAMSIZE-1 downto 0) := (others => '0');
signal trcWord : std_logic_vector(WSIZE-1 downto 0);

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
    port map(clk, ctrlMemWr, cnstZERO, cnstZERO, dmAddr, rd2, dmOUT, dbgAddr, dbgByte, dump_addr, dump_word, trcAddr, trcWord);



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

  -- BEQ usa SUB (ver ALUControl.vhdl) e desvia quando aluZERO ("A-B=0",
  -- ou seja A=B). Todos os outros branches (BNE, BLT, BGE, BLTU, BGEU)
  -- desviam quando aluZERO='0':
  --   - BNE tambem usa SUB -- aluZERO=0 significa A/=B, exatamente a
  --     condicao de desvio.
  --   - BLT/BGE/BLTU/BGEU usam os comparadores da ULA (uSLT/uSGE/uSLTU/
  --     uSGEU), que ja produzem a32=1 (condicao satisfeita) ou a32=0
  --     diretamente -- e aluZERO="a32=0", entao aluZERO=0 <=> a32=1 <=>
  --     branch tomado, sem precisar de nenhum tratamento especial por
  --     instrucao.
  lgmuxPC: process(ctrlBranch, aluZERO, ctrlJAL, Ifunct3)
  begin
    if ctrlBranch = '1' then
      if Ifunct3 = "000" then
        ctrlMpc <= aluZERO;       -- BEQ
      else
        ctrlMpc <= not aluZERO;   -- BNE, BLT, BGE, BLTU, BGEU
      end if;
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

    -- lê 1 palavra da RAM (endereço em bytes) através da porta de
    -- depuração trcAddr/trcWord -- uso exclusivo deste trace
    procedure read_mem(byte_addr : in integer; w : out std_logic_vector(WSIZE-1 downto 0)) is
    begin
      trcAddr <= std_logic_vector(to_unsigned(byte_addr, RAMSIZE));
      wait for 1 ns;
      w := trcWord;
    end procedure read_mem;

    -- ra/sp/a0/a1/s0-s3: registradores relevantes para depurar chamadas
    -- de função (call/ret via auipc+jalr), usados por testes recursivos
    -- como o quicksort (ver testes/teste2)
    variable v_ra, v_sp, v_a0, v_a1, v_s0, v_s1, v_s2, v_s3 : std_logic_vector(WSIZE-1 downto 0);
    -- conteúdo da RAM nos endereços 4068 (slot de s1) e 4076 (slot de ra)
    -- do quadro de pilha de "partition", para depurar diretamente se a
    -- gravação (sw) ou a leitura de volta (lw) é que está incorreta
    variable v_mem4068, v_mem4076 : std_logic_vector(WSIZE-1 downto 0);
  begin
    wait until rising_edge(clk);
    if TRACE_CYCLES > 0 and n < TRACE_CYCLES then
      read_reg(1,  v_ra); -- ra (x1)
      read_reg(2,  v_sp); -- sp (x2)
      read_reg(10, v_a0); -- a0 (x10)
      read_reg(11, v_a1); -- a1 (x11)
      read_reg(8,  v_s0); -- s0 (x8)
      read_reg(9,  v_s1); -- s1 (x9)
      read_reg(18, v_s2); -- s2 (x18)
      read_reg(19, v_s3); -- s3 (x19)
      read_mem(4068, v_mem4068);
      read_mem(4076, v_mem4076);

      write(l, string'("step="));
      write(l, n);
      write(l, string'(" pc="));
      hwrite(l, pcOUT);
      write(l, string'(" instr="));
      hwrite(l, imOUT);
      write(l, string'(" ra="));
      hwrite(l, v_ra);
      write(l, string'(" sp="));
      write(l, to_integer(unsigned(v_sp)));
      write(l, string'(" a0="));
      write(l, to_integer(signed(v_a0)));
      write(l, string'(" a1="));
      write(l, to_integer(signed(v_a1)));
      write(l, string'(" s0="));
      write(l, to_integer(signed(v_s0)));
      write(l, string'(" s1="));
      write(l, to_integer(signed(v_s1)));
      write(l, string'(" s2="));
      write(l, to_integer(signed(v_s2)));
      write(l, string'(" s3="));
      write(l, to_integer(signed(v_s3)));
      write(l, string'(" we="));
      if ctrlMemWr = '1' then
        write(l, string'("1"));
      else
        write(l, string'("0"));
      end if;
      write(l, string'(" dmAddr="));
      write(l, to_integer(unsigned(dmAddr)));
      write(l, string'(" rd2="));
      hwrite(l, rd2);
      write(l, string'(" mem4068="));
      hwrite(l, v_mem4068);
      write(l, string'(" mem4076="));
      hwrite(l, v_mem4076);
      writeline(output, l);

      n := n + 1;
    end if;
  end process tracePr;

end CPU;
