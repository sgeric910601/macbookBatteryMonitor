#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tests
models=(Sources/macbookBatteryMonitor/Model/ChargeLimitLogic.swift Sources/macbookBatteryMonitor/Model/Update.swift Sources/macbookBatteryMonitor/Model/Peripheral.swift Sources/macbookBatteryMonitor/Model/ChargingPresentation.swift Sources/macbookBatteryMonitor/Model/ComponentPower.swift Sources/CPUPowerShared/CPUPowerStream.swift Sources/CPUPowerShared/CPUPowerModels.swift Sources/CPUPowerShared/CPUHelperProtocol.swift Sources/macbookBatteryMonitor/Model/ChargingPlan.swift Sources/macbookBatteryMonitor/Services/ChargingPlanController.swift Sources/macbookBatteryMonitor/Model/DailyBatteryRecap.swift Sources/macbookBatteryMonitor/Model/HistoryStore.swift Sources/macbookBatteryMonitor/Model/DesktopPetMessages.swift)
if [[ -f Sources/macbookBatteryMonitor/Model/PowerBreakdown.swift ]]; then
    models+=(Sources/macbookBatteryMonitor/Model/PowerBreakdown.swift)
fi
services=(Sources/macbookBatteryMonitor/Services/APFSCloneResolver.swift Sources/macbookBatteryMonitor/Services/ProcessGuard.swift Sources/macbookBatteryMonitor/Services/DiskCleanerService.swift Sources/macbookBatteryMonitor/Services/SystemMaintenanceService.swift)
swiftc Sources/macbookBatteryMonitor/Data/BatteryReader.swift Sources/macbookBatteryMonitor/Data/SMC.swift Sources/macbookBatteryMonitor/Data/ChargeLimit.swift Sources/macbookBatteryMonitor/Model/Estimator.swift "${models[@]}" "${services[@]}" Sources/macbookBatteryMonitor/UI/PowerFlowLayers.swift Sources/macbookBatteryMonitor/Monitors/MonitorModels.swift Tests/macbookBatteryMonitorTests/*.swift Tests/main.swift -o build/tests/power-tests
build/tests/power-tests
