// Copyright EPFL contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include <stdio.h>
#include <stdlib.h>

#include "csr.h"
#include "hart.h"
#include "handler.h"
#include "core_v_mini_mcu.h"
#include "rv_plic.h"
#include "rv_plic_regs.h"
#include "dma.h"

#define COPY_SIZE 10

int8_t dma_intr_flag;

// Interrupt controller variables
dif_plic_params_t rv_plic_params;
dif_plic_t rv_plic;
dif_plic_result_t plic_res;
dif_plic_irq_id_t intr_num;

void handler_irq_external(void) {
    // Claim/clear interrupt
    plic_res = dif_plic_irq_claim(&rv_plic, 0, &intr_num);
    if (plic_res == kDifPlicOk && intr_num == DMA_INTR_DONE) {
        dma_intr_flag = 1;
    }
}

int main(int argc, char *argv[])
{
    printf("--- DMA EXAMPLE ---\n");

    printf("Init the PLIC...");
    rv_plic_params.base_addr = mmio_region_from_addr((uintptr_t)PLIC_START_ADDRESS);
    plic_res = dif_plic_init(rv_plic_params, &rv_plic);

    if (plic_res == kDifPlicOk) {
        printf("success\n");
    } else {
        printf("fail\n;");
    }

    printf("Set DMA interrupt priority to 1...");
    // Set dma priority to 1 (target threshold is by default 0) to trigger an interrupt to the target (the processor)
    plic_res = dif_plic_irq_set_priority(&rv_plic, DMA_INTR_DONE, 1);
    if (plic_res == kDifPlicOk) {
        printf("success\n");
    } else {
        printf("fail\n;");
    }

    printf("Enable DMA interrupt...");
    plic_res = dif_plic_irq_set_enabled(&rv_plic, DMA_INTR_DONE, 0, kDifPlicToggleEnabled);
    if (plic_res == kDifPlicOk) {
        printf("success\n");
    } else {
        printf("fail\n;");
    }

    // Enable interrupt on processor side
    // Enable global interrupt for machine-level interrupts
    CSR_SET_BITS(CSR_REG_MSTATUS, 0x8);
    // Set mie.MEIE bit to one to enable machine-level external interrupts
    const uint32_t mask = 1 << 11;//IRQ_EXT_ENABLE_OFFSET;
    CSR_SET_BITS(CSR_REG_MIE, mask);
    dma_intr_flag = 0;

    // Use the stack
    int32_t original_data[COPY_SIZE];
    int32_t copied_data[COPY_SIZE];
    // Or use the slow sram ip example for data
    // int32_t original_data = EXT_SLAVE_START_ADDRESS;
    // int32_t copied_data = EXT_SLAVE_START_ADDRESS+COPY_SIZE;

    volatile uint32_t *src_ptr = original_data;
    volatile uint32_t *dest_ptr = copied_data;

    // Put some data to initialize the memory addresses
    for(int i=0; i<COPY_SIZE; i++) {
        *src_ptr++ = i;
    }

    // dma peripheral structure to access the registers
    dma_t dma;
    dma.base_addr = mmio_region_from_addr((uintptr_t)DMA_START_ADDRESS);

    dma_set_read_ptr(&dma, (uint32_t) original_data);
    dma_set_write_ptr(&dma, (uint32_t) copied_data);
    printf("DMA launched...");
    // Give number of words to transfer
    dma_set_cnt_start(&dma, (uint32_t) COPY_SIZE);
    // Wait copy is done
    while(dma_intr_flag==0) {
        wait_for_interrupt();
    }
    printf("finished\n");

    printf("Complete interrupt...");
    plic_res = dif_plic_irq_complete(&rv_plic, 0, &intr_num);
    if (plic_res == kDifPlicOk && intr_num == DMA_INTR_DONE) {
        printf("success\n");
    } else {
        printf("fail\n;");
    }

    // Reinitialized the read pointer to the original address
    src_ptr = original_data;

    // Check for errors
    int32_t errors=0;
    for(int i=0; i<COPY_SIZE; i++) {
        if ((*src_ptr) != (*dest_ptr)) {
            printf("WARNING: %d != %d\n", *src_ptr, *dest_ptr);
            errors++;
        }
        src_ptr++;
	    dest_ptr++;
    }

    if (errors == 0) {
        printf("DMA TRANSFER SUCCESS\n");
    } else {
        printf("DMA TRANSFER FAILURE: %d errors out of %d words copied\n", errors, COPY_SIZE);
    }

    return EXIT_SUCCESS;
}
