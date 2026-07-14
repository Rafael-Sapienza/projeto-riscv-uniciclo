-- Testbench da CPU (uRV)
--
-- Requer VHDL-2008 (no ModelSim: botão direito no arquivo -> Properties ->
-- aba VHDL -> marcar "Use VHDL 2008"), usado apenas pela instrução
-- `report ... severity ...;` "solta" (sem `assert false` na frente) e por
-- `std.env.stop`. NÃO usa mais "external names": a leitura do conteúdo
-- final da RAM é feita através de uma porta de depuração comum
-- (dump_addr/dump_word, ver RAM.vhd/CPU.vhd) -- external names se
-- mostraram frágeis quanto à ordem de elaboração em algumas versões do
-- ModelSim/Questa (o simulador tentava resolver o sinal interno da RAM
-- antes de o DUT estar totalmente elaborado, o que travava a simulação
-- em "Iteration limit reached" já em 0 ps, antes até do primeiro clock).
--
-- Fluxo:
--   1. instancia a CPU (uRV) apontando ROM_FILE/RAM_FILE para os arquivos
--      gerados pelo assembler.py (instruções + estado inicial da RAM);
--   2. roda o clock até a CPU sinalizar `halt='1'` (ecall Exit2, a7=93)
--      ou até MAX_STEPS ciclos, o que vier primeiro;
--   3. se EXPECTED_FILE não for vazio, compara a RAM final, linha a linha,
--      com esse arquivo (1 palavra hex de 32 bits por linha); quando o
--      arquivo esperado acaba antes do fim da RAM, os endereços restantes
--      precisam estar zerados;
--   4. se DUMP_FILE não for vazio, escreve a RAM final inteira nesse
--      arquivo (1 palavra hex de 32 bits por linha, mesmo formato de
--      ROM_FILE/RAM_FILE/EXPECTED_FILE) — evidência em texto do estado
--      final da memória, independente de já existir ou não EXPECTED_FILE.
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use std.textio.all;
use std.env.all;

entity tb_uRV is
  generic (
    ROM_FILE      : string  := "instrucoes_hex/i1.txt"; -- instruções (hex, 1 palavra/linha)
    RAM_FILE      : string  := "ram_input/ram1.txt";     -- estado inicial da RAM (hex, 1 palavra/linha)
    EXPECTED_FILE : string  := "";                       -- saída esperada da RAM ("" = pula a verificação)
    DUMP_FILE     : string  := "";                       -- arquivo de saída com a RAM final inteira ("" = não grava)
    MAX_STEPS     : integer := 2_000_000;                -- limite de ciclos caso o programa não dê ecall Exit2
    RAMSIZE       : integer := 13;                       -- deve bater com o generic RAMSIZE da uRV
    ROMSIZE       : integer := 11;                       -- deve bater com o generic ROMSIZE da uRV
    TRACE_CYCLES  : integer := 0;                        -- > 0: liga o trace de depuração da CPU (ver CPU.vhd)
    -- Programas SEM pilha de chamadas (ex.: teste1, bubble sort) não
    -- tocam em nenhum endereço além do que EXPECTED_FILE cobre, então
    -- todo o restante da RAM realmente deve estar zerado -- daí o
    -- default 'true'. Programas COM pilha (ex.: teste2, quicksort
    -- recursivo) usam e legitimamente deixam resíduo não-zerado em
    -- endereços de pilha ao final da execução (dar "pop" num quadro só
    -- move o sp de volta, não apaga o que estava lá); nesse caso, passe
    -- CHECK_TAIL_ZERO=false para não gerar falsos positivos.
    CHECK_TAIL_ZERO : boolean := true;
    CLK_PERIOD    : time    := 10 ns
  );
end entity tb_uRV;

architecture sim of tb_uRV is

  constant RAMDP_C : integer := 2**RAMSIZE;

  signal clk       : std_logic := '0';
  signal reset     : std_logic := '1'; -- liberado pelo processo "main" após o pulso inicial
  signal halt      : std_logic;
  signal exit_code : std_logic_vector(31 downto 0);
  signal dump_addr : std_logic_vector(RAMSIZE-1 downto 0) := (others => '0');
  signal dump_word : std_logic_vector(31 downto 0);

begin

  dut: entity work.uRV(CPU)
    generic map(
      ROMSIZE      => ROMSIZE,
      RAMSIZE      => RAMSIZE,
      ROM_FILE     => ROM_FILE,
      RAM_FILE     => RAM_FILE,
      TRACE_CYCLES => TRACE_CYCLES
    )
    port map(
      clk       => clk,
      reset     => reset,
      halt      => halt,
      exit_code => exit_code,
      dump_addr => dump_addr,
      dump_word => dump_word
    );

  clk_gen: process
  begin
    clk <= '0';
    wait for CLK_PERIOD/2;
    clk <= '1';
    wait for CLK_PERIOD/2;
  end process clk_gen;

  main: process
    variable step_count : integer := 0;

    variable exp_status : file_open_status;
    file     exp_file    : text;
    variable exp_line    : line;
    variable exp_word    : std_logic_vector(31 downto 0);
    variable got_word    : std_logic_vector(31 downto 0);
    variable addr        : integer;
    variable exp_lines   : integer := 0;
    variable errors      : integer := 0;

    variable dmp_status : file_open_status;
    file     dmp_file    : text;
    variable dmp_line    : line;

    variable msg_line     : line;
    variable did_compare  : boolean := false;

    -- lê 1 palavra de 32 bits da RAM final através da porta de depuração
    -- (dump_addr/dump_word), esperando 1 ns para o valor combinacional se
    -- propagar através do DUT antes de amostrar dump_word
    procedure read_ram_word(byte_addr : in integer; w : out std_logic_vector(31 downto 0)) is
    begin
      dump_addr <= std_logic_vector(to_unsigned(byte_addr, RAMSIZE));
      wait for 1 ns;
      w := dump_word;
    end procedure read_ram_word;
  begin
    -- pulso de reset: sem isso, o registrador do PC nunca sai do estado
    -- indefinido ('U') -- ver comentário no port "reset" de CPU.vhd.
    reset <= '1';
    wait for CLK_PERIOD;
    reset <= '0';

    -- roda a CPU até o ecall de saída (halt='1') ou MAX_STEPS ciclos
    wait until rising_edge(clk);
    while halt /= '1' and step_count < MAX_STEPS loop
      wait until rising_edge(clk);
      step_count := step_count + 1;
    end loop;

    if halt = '1' then
      report "programa encerrado via ecall Exit2 (a7=93) apos " &
             integer'image(step_count) & " ciclo(s); codigo de saida = " &
             integer'image(to_integer(signed(exit_code))) severity note;
    else
      report "limite de MAX_STEPS (" & integer'image(MAX_STEPS) &
             ") atingido sem ecall Exit2 (a7=93) -- comparando a RAM no " &
             "estado em que estiver" severity warning;
    end if;

    -- compara a RAM final com o arquivo de saida esperada, linha a linha
    if EXPECTED_FILE'length > 0 then
      file_open(exp_status, exp_file, EXPECTED_FILE, read_mode);
      if exp_status /= open_ok then
        report "nao foi possivel abrir o arquivo de saida esperada: " &
               EXPECTED_FILE severity failure;
        errors := errors + 1;
      else
        addr := 0;
        while not endfile(exp_file) loop
          readline(exp_file, exp_line);
          hread(exp_line, exp_word);
          read_ram_word(addr, got_word);
          if got_word /= exp_word then
            report "divergencia no endereco " & integer'image(addr) &
                   ": esperado=" & to_hstring(unsigned(exp_word)) &
                   " obtido=" & to_hstring(unsigned(got_word)) severity error;
            errors := errors + 1;
          end if;
          addr := addr + 4;
          exp_lines := exp_lines + 1;
        end loop;
        file_close(exp_file);

        -- o restante da RAM (alem do que o arquivo esperado cobre) precisa
        -- estar zerado -- só faz sentido para programas que não usam
        -- pilha de chamadas (ver CHECK_TAIL_ZERO acima)
        if CHECK_TAIL_ZERO then
          while addr <= RAMDP_C - 4 loop
            read_ram_word(addr, got_word);
            if got_word /= x"00000000" then
              report "endereco " & integer'image(addr) &
                     " deveria estar zerado, mas contem " &
                     to_hstring(unsigned(got_word)) severity error;
              errors := errors + 1;
            end if;
            addr := addr + 4;
          end loop;
        end if;

        did_compare := true;
      end if;
    end if;

    -- grava a RAM final inteira em texto (1 palavra hex/linha), para
    -- inspeção manual ou para anexar como evidência da execução
    if DUMP_FILE'length > 0 then
      file_open(dmp_status, dmp_file, DUMP_FILE, write_mode);
      if dmp_status /= open_ok then
        report "nao foi possivel criar o arquivo de dump da RAM: " &
               DUMP_FILE severity error;
        errors := errors + 1;
      else
        addr := 0;
        while addr <= RAMDP_C - 4 loop
          read_ram_word(addr, got_word);
          hwrite(dmp_line, got_word);
          writeline(dmp_file, dmp_line);
          addr := addr + 4;
        end loop;
        file_close(dmp_file);
        report "RAM final (" & integer'image(RAMDP_C/4) & " palavra(s)) escrita em " &
               DUMP_FILE severity note;
      end if;
    end if;

    -- veredito final: impresso por último de propósito (depois do dump),
    -- para ficar fácil de achar no fim do transcript
    if did_compare then
      if errors = 0 then
        if CHECK_TAIL_ZERO then
          write(msg_line, string'("Sucesso!!! :) RAM final confere com ") & EXPECTED_FILE &
                " (" & integer'image(exp_lines) &
                " palavra(s) verificada(s), restante zerado).");
        else
          write(msg_line, string'("Sucesso!!! :) RAM final confere com ") & EXPECTED_FILE &
                " (" & integer'image(exp_lines) & " palavra(s) verificada(s); " &
                "verificacao de zeros no restante da RAM desativada -- " &
                "CHECK_TAIL_ZERO=false).");
        end if;
        writeline(output, msg_line);
      else
        write(msg_line, string'("Falha! ") & integer'image(errors) &
              " divergencia(s) entre a RAM final e a saida esperada.");
        writeline(output, msg_line);
      end if;
    end if;

    std.env.stop(errors);
    wait;
  end process main;

end architecture sim;
