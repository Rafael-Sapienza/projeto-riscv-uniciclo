vsim -gROM_FILE="teste2/teste2_rom.txt" -gRAM_FILE="teste2/teste2_ram.txt" -gEXPECTED_FILE="teste2/expected2.txt" -gDUMP_FILE="teste2/teste2_ram_final.txt" -gTRACE_CYCLES=300 work.tb_uRV
run -all