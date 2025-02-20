// Copyright EPFL contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include <stdio.h>
#include <stdlib.h>
#include "csr.h"
#include "hart.h"
#include "handler.h"
#include "core_v_mini_mcu.h"
#include "rv_timer.h"
#include "power_manager.h"
#include "soc_ctrl.h"

static rv_timer_t timer;
static const uint64_t kTickFreqHz = 1000 * 1000; // 1 MHz

static power_manager_t power_manager;

int main(int argc, char *argv[])
{

    //Get current Frequency
    soc_ctrl_t soc_ctrl;
    soc_ctrl.base_addr = mmio_region_from_addr((uintptr_t)SOC_CTRL_START_ADDRESS);
    uint32_t freq_hz = soc_ctrl_get_frequency(&soc_ctrl);

    // Setup rv_timer
    mmio_region_t timer_reg = mmio_region_from_addr(RV_TIMER_START_ADDRESS);
    rv_timer_init(timer_reg, (rv_timer_config_t){.hart_count = 1, .comparator_count = 1}, &timer);
    rv_timer_tick_params_t tick_params;
    rv_timer_approximate_tick_params(freq_hz, kTickFreqHz, &tick_params);
    rv_timer_set_tick_params(&timer, 0, tick_params);
    rv_timer_irq_enable(&timer, 0, 0, kRvTimerEnabled);
    rv_timer_arm(&timer, 0, 0, 1024);
    rv_timer_counter_set_enabled(&timer, 0, kRvTimerEnabled);

    // Setup power_manager
    mmio_region_t power_manager_reg = mmio_region_from_addr(POWER_MANAGER_START_ADDRESS);
    power_manager.base_addr = power_manager_reg;


    power_manager_cpu_counters_t power_manager_cpu_counters;
    // the reset_on must be greater thatn powergate_on (i.e. first turn on, then you deassert the reset)
    // the reset_off must be greater thatn powergate_off (i.e. first turn off, then you reset)

    // reset_off, reset_on, powergate_off, powergate_on
    if (power_gate_cpu_counters_init(&power_manager_cpu_counters, 40, 40, 30, 30) != kPowerManagerOk)
    {
        printf("Error: power manager fail. Check the reset and powergate counters value\n");
        return EXIT_FAILURE;
    }

    // Power gate the core and wait for rv_timer interrupt
    if (power_gate_core(&power_manager, kTimer, &power_manager_cpu_counters) != kPowerManagerOk)
    {
        printf("Error: power manager fail.\n");
        return EXIT_FAILURE;
    }

    /* write something to stdout */
    printf("Success.\n");
    return EXIT_SUCCESS;
}
