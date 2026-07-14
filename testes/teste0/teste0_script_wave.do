# 1. Inicia a simulação
vsim -gROM_FILE="teste0/teste0_rom.txt" -gRAM_FILE="teste0/teste0_ram.txt" -gEXPECTED_FILE="teste0/expected0.txt" -gDUMP_FILE="teste0/teste0_ram_final.txt" -gCHECK_TAIL_ZERO=true work.tb_uRV

# 2. Registra os sinais no histórico
log -r /*

# 3. Abre a janela Wave
view wave

# 4. Limpa a janela wave
catch { delete wave * }

# ==============================================================================
# CONTROLE GERAL (Como o programa está rodando)
# ==============================================================================
add wave -divider "CONTROLE GERAL"
add wave -color "Cyan" /tb_urv/clk
add wave -color "Orange" /tb_urv/reset
add wave -color "Yellow" /tb_urv/halt

# Mostra onde o programa está na execução (PC)
catch { add wave -radix hexadecimal -color "Light Blue" /tb_urv/dut/regPC/q }

# ==============================================================================
# ACESSOS À RAM (Apenas leituras e escritas ativas da CPU)
# ==============================================================================
add wave -divider "LEITURAS E ESCRITAS NA RAM"
catch { add wave -color "Pink" /tb_urv/dut/ramDM/we }
catch { add wave -radix decimal -color "Green" /tb_urv/dut/ramDM/addr }

# Tenta adicionar o dado de entrada (o que será ESCRITO se we=1) sob possíveis nomes:
catch { add wave -radix hexadecimal -label "DADO_GRAVADO" /tb_urv/dut/ramDM/din }
catch { add wave -radix hexadecimal -label "DADO_GRAVADO" /tb_urv/dut/ramDM/data_in }
catch { add wave -radix hexadecimal -label "DADO_GRAVADO" /tb_urv/dut/ramDM/dat_i }

# Tenta adicionar o dado de saída (o que foi LIDO da RAM) sob possíveis nomes:
catch { add wave -radix hexadecimal -label "DADO_LIDO" /tb_urv/dut/ramDM/dout }
catch { add wave -radix hexadecimal -label "DADO_LIDO" /tb_urv/dut/ramDM/data_out }
catch { add wave -radix hexadecimal -label "DADO_LIDO" /tb_urv/dut/ramDM/dat_o }

# ==============================================================================
# Executa a simulação e ajusta o zoom automaticamente
# ==============================================================================
run -all
wave zoom full