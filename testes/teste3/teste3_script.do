vsim -gROM_FILE="teste3/teste3_rom.txt" -gRAM_FILE="teste3/teste3_ram.txt" -gEXPECTED_FILE="teste3/expected3.txt" -gDUMP_FILE="teste3/teste3_ram_final.txt" -gCHECK_TAIL_ZERO=true work.tb_uRV
run -all