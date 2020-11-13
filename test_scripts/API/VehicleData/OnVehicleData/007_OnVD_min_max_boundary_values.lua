----------------------------------------------------------------------------------------------------
-- TBA
----------------------------------------------------------------------------------------------------
--[[ Required Shared libraries ]]-------------------------------------------------------------------
local common = require('test_scripts/API/VehicleData/common')

--[[ Local Constants ]]-----------------------------------------------------------------------------
local testTypes = {
  common.testType.VALID_RANDOM,
  common.testType.ONLY_MANDATORY_PARAMS,
  common.testType.LOWER_IN_BOUND,
  common.testType.UPPER_IN_BOUND,
  common.testType.LOWER_OUT_OF_BOUND,
  common.testType.UPPER_OUT_OF_BOUND,
  common.testType.ENUM_ITEMS,
}

--[[ Local Variables ]]-----------------------------------------------------------------------------
-- local param = "wiperStatus"--"clusterModeStatus"--"wiperStatus"--"headLampStatus"--"windowStatus"--"deviceStatus"

--[[ Local Functions ]]-----------------------------------------------------------------------------
local function processRPC(pParams, pTestType)
  local times = 1
  if pTestType == common.testType.LOWER_OUT_OF_BOUND or pTestType == common.testType.UPPER_OUT_OF_BOUND then
    times = 0
  end
  common.getHMIConnection():SendNotification(pParams.hmi.name, pParams.hmi.notification)
  common.getMobileSession():ExpectNotification(pParams.mobile.name, pParams.mobile.notification)
  :Times(times)
end

--[[ Scenario ]]------------------------------------------------------------------------------------
common.Title("Preconditions")
common.Step("Clean environment and update preloaded_pt file", common.preconditions)
common.Step("Start SDL, HMI, connect Mobile, start Session", common.start)
common.Step("Register App", common.registerApp)
common.Step("Activate App", common.activateApp)

common.Title("Test")
for param in common.spairs(common.getVDParams(true)) do
  common.Title("VD parameter: " .. param)
  common.Step("RPC " .. common.rpc.sub, common.processSubscriptionRPC, { common.rpc.sub, param })
  for _, testType in pairs(testTypes) do
    common.Title(common.getKeyByValue(common.testType, testType))
    for _, t in pairs(common.getTests(common.rpc.on, testType, param)) do
      common.Step(t.name, processRPC, { t.params, testType })
    end
  end
end

common.Title("Postconditions")
common.Step("Stop SDL", common.postconditions)
