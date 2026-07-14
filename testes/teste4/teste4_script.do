vsim -gROM_FILE="teste4/teste4_rom.txt" -gRAM_FILE="teste4/teste4_ram.txt" -gEXPECTED_FILE="teste4/expected4.txt" -gDUMP_FILE="teste4/teste4_ram_final.txt" -gCHECK_TAIL_ZERO=true work.tb_uRV
run -all