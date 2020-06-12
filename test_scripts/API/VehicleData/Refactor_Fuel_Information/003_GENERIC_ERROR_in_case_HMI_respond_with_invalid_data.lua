---------------------------------------------------------------------------------------------------
-- Proposal:https://github.com/smartdevicelink/sdl_evolution/blob/master/proposals/0256-Refactor-Fuel-Information-Related-Vehicle-Data.md
-- Description: SDL sends respond GENERIC_ERROR to app in case HMI sends the response with invalid `FuelRange` structure
-- In case:
-- 1) App sends GetVehicleData(FuelRange:true) request
-- 2) SDL transfers this request to HMI
-- 3) HMI sends the invalid `FuelRange` structure in GetVehicleData response
-- SDL does:
-- 1) respond GENERIC_ERROR to mobile application
---------------------------------------------------------------------------------------------------
--[[ Required Shared libraries ]]
local common = require('test_scripts/API/VehicleData/Refactor_Fuel_Information/common')

--[[ Local Variables ]]
local invalidTypeValue = true

--[[ Local Functions ]]
local function processGetVDunsuccess(pData)
  local cid = common.getMobileSession():SendRPC("GetVehicleData", { fuelRange = true })
  common.getHMIConnection():ExpectRequest("VehicleInfo.GetVehicleData", { fuelRange = true })
  :Do(function(_, data)
    common.getHMIConnection():SendResponse(data.id, data.method, "SUCCESS",
    { fuelRange = pData })
  end)
  common.getMobileSession():ExpectResponse(cid, { success = false, resultCode = "GENERIC_ERROR" })
end

local function setData(pParameterName, pValue)
  local vehicleData = common.cloneTable(common.allVehicleData)
  vehicleData[pParameterName] = pValue
  return vehicleData
end

--[[ Scenario ]]
common.Title("Preconditions")
common.Step("Clean environment", common.preconditions)
common.Step("Start SDL, HMI, connect Mobile, start Session", common.start)
common.Step("Register App", common.registerApp)
common.Step("PTU", common.policyTableUpdate, { common.pTUpdateFunc })
common.Step("Activate App", common.activateApp)

common.Title("Test")
for parameterName in pairs(common.allVehicleData) do
  common.Step("HMI sends response with invalid type for " .. parameterName, processGetVDunsuccess,
    { { [parameterName] = invalidTypeValue } })
  for _, value in pairs (common.allVehicleDataOutOfBoundaryValues[parameterName]) do
    common.Step("HMI sends response with invalid data " .. parameterName .. "=" .. value,
      processGetVDunsuccess, { { setData(parameterName, value) } })
  end
end

common.Title("Postconditions")
common.Step("Stop SDL", common.postconditions)
