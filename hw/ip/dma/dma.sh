# Copyright EPFL contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

echo "Generating RTL"
../../vendor/pulp_platform_register_interface/vendor/lowrisc_opentitan/util/regtool.py -r -t rtl data/dma.hjson
echo "Generating SW"
../../vendor/pulp_platform_register_interface/vendor/lowrisc_opentitan/util/regtool.py --cdefines -o dma_regs.h data/dma.hjson
