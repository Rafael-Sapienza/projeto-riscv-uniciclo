# 1. Inicia a simulação com as configurações do teste1
vsim -gROM_FILE="teste1/teste1_rom.txt" -gRAM_FILE="teste1/teste1_ram.txt" -gEXPECTED_FILE="teste1/expected1.txt" -gDUMP_FILE="teste1/teste1_ram_final.txt" work.tb_uRV

# 2. Registra os sinais no histórico da simulação
log -r /*

# 3. Abre a janela Wave se não estiver aberta
view wave

# 4. Limpa a janela wave de simulações anteriores
catch { delete wave * }

# ==============================================================================
# CONTROLE GERAL
# ==============================================================================
add wave -divider "CONTROLE GERAL"
add wave -color "Cyan" /tb_urv/clk
add wave -color "Orange" /tb_urv/reset
add wave -color "Yellow" /tb_urv/halt

# Program Counter (onde o programa está na execução)
catch { add wave -radix hexadecimal -color "Light Blue" /tb_urv/dut/regPC/q }

# ==============================================================================
# LEITURAS E ESCRITAS NA RAM
# ==============================================================================
add wave -divider "LEITURAS E ESCRITAS NA RAM"
catch { add wave -color "Pink" /tb_urv/dut/ramDM/we }
catch { add wave -radix decimal -color "Green" /tb_urv/dut/ramDM/addr }

# Entrada de dados (o que será gravado quando we=1)
catch { add wave -radix hexadecimal -label "DADO_GRAVADO" /tb_urv/dut/ramDM/din }
catch { add wave -radix hexadecimal -label "DADO_GRAVADO" /tb_urv/dut/ramDM/data_in }
catch { add wave -radix hexadecimal -label "DADO_GRAVADO" /tb_urv/dut/ramDM/dat_i }

# Saída de dados (o que foi lido da RAM)
catch { add wave -radix hexadecimal -label "DADO_LIDO" /tb_urv/dut/ramDM/dout }
catch { add wave -radix hexadecimal -label "DADO_LIDO" /tb_urv/dut/ramDM/data_out }
catch { add wave -radix hexadecimal -label "DADO_LIDO" /tb_urv/dut/ramDM/dat_o }

# ==============================================================================
# 5. Executa a simulação até o fim e ajusta o zoom automaticamente
# ==============================================================================
run -all
wave zoom full