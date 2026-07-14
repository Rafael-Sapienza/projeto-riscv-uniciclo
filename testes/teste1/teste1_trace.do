vsim -gROM_FILE="teste1/teste1_rom.txt" -gRAM_FILE="teste1/teste1_ram.txt" -gEXPECTED_FILE="teste1/expected1.txt" -gDUMP_FILE="teste1/teste1_ram_final.txt" -gTRACE_CYCLES=1000 work.tb_uRV
run -all