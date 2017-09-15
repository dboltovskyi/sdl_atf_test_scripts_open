---------------------------------------------------------------------------------------------------
-- SendLocation common module
---------------------------------------------------------------------------------------------------
--[[ General configuration parameters ]]
config.deviceMAC = "12ca17b49af2289436f303e0166030a21e525d266e209267433801a8fd4071a0"
config.defaultProtocolVersion = 2

--[[ Required Shared libraries ]]
local mobile_session = require("mobile_session")
local json = require("modules/json")

local commonFunctions = require("user_modules/shared_testcases/commonFunctions")
local commonSteps = require("user_modules/shared_testcases/commonSteps")
local commonTestCases = require("user_modules/shared_testcases/commonTestCases")
local commonPreconditions = require('user_modules/shared_testcases/commonPreconditions')

--[[ Local Variables ]]
local ptu_table = {}
local hmiAppIds = {}

local commonSendLocation = {}

commonSendLocation.timeout = 2000
commonSendLocation.minTimeout = 500
commonSendLocation.DEFAULT = "Default"

local function allowSDL(self)
  self.hmiConnection:SendNotification("SDL.OnAllowSDLFunctionality",
    { allowed = true, source = "GUI", device = { id = config.deviceMAC, name = "127.0.0.1" } })
end

local function checkIfPTSIsSentAsBinary(bin_data)
  if not (bin_data ~= nil and string.len(bin_data) > 0) then
    commonFunctions:userPrint(31, "PTS was not sent to Mobile in payload of OnSystemRequest")
  end
end

function commonSendLocation.getSendLocationConfig()
  return {
    keep_context = false,
    steal_focus = false,
    priority = "NONE",
    default_hmi = "NONE",
    groups = { "Base-4", "SendLocation" }
  }
end

local function getPTUFromPTS(tbl)
  tbl.policy_table.consumer_friendly_messages.messages = nil
  tbl.policy_table.device_data = nil
  tbl.policy_table.module_meta = nil
  tbl.policy_table.usage_and_error_counts = nil
  tbl.policy_table.functional_groupings["DataConsent-2"].rpcs = json.null
  tbl.policy_table.module_config.preloaded_pt = nil
  tbl.policy_table.module_config.preloaded_date = nil
end

local function jsonFileToTable(pFileName)
  local f = io.open(pFileName, "r")
  local content = f:read("*all")
  f:close()
  return json.decode(content)
end

local function ptu(self, id, pUpdateFunction)
  local function getAppsCount()
    local count = 0
    for _ in pairs(hmiAppIds) do
      count = count + 1
    end
    return count
  end

  local policy_file_name = "PolicyTableUpdate"
  local policy_file_path = commonFunctions:read_parameter_from_smart_device_link_ini("SystemFilesPath")
  local pts_file_name = commonFunctions:read_parameter_from_smart_device_link_ini("PathToSnapshot")
  local ptu_file_name = os.tmpname()
  local requestId = self.hmiConnection:SendRequest("SDL.GetURLS", { service = 7 })
  EXPECT_HMIRESPONSE(requestId)
  :Do(function()
      self.hmiConnection:SendNotification("BasicCommunication.OnSystemRequest", { requestType = "PROPRIETARY", fileName = pts_file_name })
      getPTUFromPTS(ptu_table)
      local function updatePTU(tbl)
        tbl.policy_table.functional_groupings.SendLocation.rpcs.SendLocation.parameters = {}
        tbl.policy_table.functional_groupings.SendLocation.rpcs.SendLocation.parameters[1] = "longitudeDegrees"
        tbl.policy_table.functional_groupings.SendLocation.rpcs.SendLocation.parameters[2] = "latitudeDegrees"
        tbl.policy_table.app_policies[commonSendLocation.getMobileAppId(id)] = commonSendLocation.getSendLocationConfig()
      end
      updatePTU(ptu_table)
      if pUpdateFunction then
        pUpdateFunction(ptu_table)
      end
      local function tableToJsonFile(tbl, file_name)
        local f = io.open(file_name, "w")
        f:write(json.encode(tbl))
        f:close()
      end
      tableToJsonFile(ptu_table, ptu_file_name)

      local event = events.Event()
      event.matches = function(self, e) return self == e end
      EXPECT_EVENT(event, "PTU event")
      :Timeout(11000)

      for id = 1, getAppsCount() do
        local mobileSession = commonSendLocation.getMobileSession(id, self)
        mobileSession:ExpectNotification("OnSystemRequest", { requestType = "PROPRIETARY" })
        :Do(function(_, d2)
            -- print("App ".. id .. " was used for PTU")
            RAISE_EVENT(event, event, "PTU event")
            checkIfPTSIsSentAsBinary(d2.binaryData)
            local corIdSystemRequest = mobileSession:SendRPC("SystemRequest", { requestType = "PROPRIETARY", fileName = policy_file_name }, ptu_file_name)
            EXPECT_HMICALL("BasicCommunication.SystemRequest")
            :Do(function(_, d3)
                self.hmiConnection:SendResponse(d3.id, "BasicCommunication.SystemRequest", "SUCCESS", { })
                self.hmiConnection:SendNotification("SDL.OnReceivedPolicyUpdate", { policyfile = policy_file_path .. "/" .. policy_file_name })
              end)
            mobileSession:ExpectResponse(corIdSystemRequest, { success = true, resultCode = "SUCCESS" })
          end)
        :Times(AtMost(1))
      end
    end)
  os.remove(ptu_file_name)
end

function commonSendLocation.preconditions()
  commonFunctions:SDLForceStop()
  commonSteps:DeletePolicyTable()
  commonSteps:DeleteLogsFiles()
end

--[[Module functions]]

function commonSendLocation.activateApp(pAppId, self)
  self, pAppId = commonSendLocation.getSelfAndParams(pAppId, self)
  if not pAppId then pAppId = 1 end
  local pHMIAppId = hmiAppIds[config["application" .. pAppId].registerAppInterfaceParams.appID]
  local mobSession = commonSendLocation.getMobileSession(pAppId, self)
  local requestId = self.hmiConnection:SendRequest("SDL.ActivateApp", { appID = pHMIAppId })
  EXPECT_HMIRESPONSE(requestId)
  mobSession:ExpectNotification("OnHMIStatus", { hmiLevel = "FULL", audioStreamingState = "AUDIBLE", systemContext = "MAIN" })
  commonTestCases:DelayedExp(commonSendLocation.minTimeout)
end

function commonSendLocation.backupHMICapabilities()
  local hmiCapabilitiesFile = commonFunctions:read_parameter_from_smart_device_link_ini("HMICapabilities")
  commonPreconditions:BackupFile(hmiCapabilitiesFile)
end

function commonSendLocation.getDeviceMAC()
  return config.deviceMAC
end

function commonSendLocation.getSelfAndParams(...)
  local out = { }
  local selfIdx = nil
  for i,v in pairs({...}) do
    if type(v) == "table" and v.isTest then
      table.insert(out, v)
      selfIdx = i
      break
    end
  end
  local idx = 2
  for i = 1, table.maxn({...}) do
    if i ~= selfIdx then
      out[idx] = ({...})[i]
      idx = idx + 1
    end
  end
  return table.unpack(out, 1, table.maxn(out))
end

function commonSendLocation.getHMIAppId(pAppId)
  if not pAppId then pAppId = 1 end
  return hmiAppIds[config["application" .. pAppId].registerAppInterfaceParams.appID]
end

function commonSendLocation.getMobileSession(pAppId, self)
  self, pAppId = commonSendLocation.getSelfAndParams(pUpdateFunction, self)
  if not pAppId then pAppId = 1 end
  return self["mobileSession" .. pAppId]
end

function commonSendLocation.getMobileAppId(pAppId)
  if not pAppId then pAppId = 1 end
  return config["application" .. pAppId].registerAppInterfaceParams.appID
end

function commonSendLocation.getPathToSDL()
  return config.pathToSDL
end

function commonSendLocation.postconditions()
  StopSDL()
end

function commonSendLocation.registerApplicationWithPTU(pAppId, pUpdateFunction, self)
  self, pAppId, pUpdateFunction = commonSendLocation.getSelfAndParams(pAppId, pUpdateFunction, self)
  if not pAppId then pAppId = 1 end
  self["mobileSession" .. pAppId] = mobile_session.MobileSession(self, self.mobileConnection)
  self["mobileSession" .. pAppId]:StartService(7)
  :Do(function()
      local corId = self["mobileSession" .. pAppId]:SendRPC("RegisterAppInterface", config["application" .. pAppId].registerAppInterfaceParams)
      EXPECT_HMINOTIFICATION("BasicCommunication.OnAppRegistered", { application = { appName = config["application" .. pAppId].registerAppInterfaceParams.appName } })
      :Do(function(_, d1)
          hmiAppIds[config["application" .. pAppId].registerAppInterfaceParams.appID] = d1.params.application.appID
          EXPECT_HMINOTIFICATION("SDL.OnStatusUpdate", { status = "UPDATE_NEEDED" }, { status = "UPDATING" }, { status = "UP_TO_DATE" })
          :Times(3)
          EXPECT_HMICALL("BasicCommunication.PolicyUpdate")
          :Do(function(_, d2)
              self.hmiConnection:SendResponse(d2.id, d2.method, "SUCCESS", { })
              ptu_table = jsonFileToTable(d2.params.file)
              ptu(self, pAppId, pUpdateFunction)
            end)
        end)
      self["mobileSession" .. pAppId]:ExpectResponse(corId, { success = true, resultCode = "SUCCESS" })
      :Do(function()
          self["mobileSession" .. pAppId]:ExpectNotification("OnHMIStatus", { hmiLevel = "NONE", audioStreamingState = "NOT_AUDIBLE", systemContext = "MAIN" })
          :Times(AtLeast(1)) -- issue with SDL --> notification is sent twice
          self["mobileSession" .. pAppId]:ExpectNotification("OnPermissionsChange")
        end)
    end)
end

function commonSendLocation.rai_n(id, self)
  self, id = commonSendLocation.getSelfAndParams(id, self)
  if not id then id = 1 end
  self["mobileSession" .. id] = mobile_session.MobileSession(self, self.mobileConnection)
  self["mobileSession" .. id]:StartService(7)
  :Do(function()
      local corId = self["mobileSession" .. id]:SendRPC("RegisterAppInterface", config["application" .. id].registerAppInterfaceParams)
      EXPECT_HMINOTIFICATION("BasicCommunication.OnAppRegistered", { application = { appName = config["application" .. id].registerAppInterfaceParams.appName } })
      :Do(function(_, d1)
          hmiAppIds[config["application" .. id].registerAppInterfaceParams.appID] = d1.params.application.appID
        end)
      self["mobileSession" .. id]:ExpectResponse(corId, { success = true, resultCode = "SUCCESS" })
      :Do(function()
          self["mobileSession" .. id]:ExpectNotification("OnHMIStatus", { hmiLevel = "NONE", audioStreamingState = "NOT_AUDIBLE", systemContext = "MAIN" })
          :Times(AtLeast(1)) -- issue with SDL --> notification is sent twice
          self["mobileSession" .. id]:ExpectNotification("OnPermissionsChange")
        end)
    end)
end

function commonSendLocation.restoreHMICapabilities()
  local hmiCapabilitiesFile = commonFunctions:read_parameter_from_smart_device_link_ini("HMICapabilities")
  commonPreconditions:RestoreFile(hmiCapabilitiesFile)
end

function commonSendLocation.start(pHMIParams, self)
  self, pHMIParams = commonSendLocation.getSelfAndParams(pHMIParams, self)
  self:runSDL()
  commonFunctions:waitForSDLStart(self)
  :Do(function()
      self:initHMI(self)
      :Do(function()
          commonFunctions:userPrint(35, "HMI initialized")
          self:initHMI_onReady(pHMIParams)
          :Do(function()
              commonFunctions:userPrint(35, "HMI is ready")
              self:connectMobile()
              :Do(function()
                  commonFunctions:userPrint(35, "Mobile connected")
                  allowSDL(self)
                end)
            end)
        end)
    end)
end

function commonSendLocation.unregisterApp(pAppId, self)
  local mobSession = commonSendLocation.getMobileSession(pAppId, self)
  local hmiAppId = commonSendLocation.getHMIAppId(pAppId)
  local cid = mobSession:SendRPC("UnregisterAppInterface",{})
  EXPECT_HMINOTIFICATION("BasicCommunication.OnAppUnregistered", { appID = hmiAppId, unexpectedDisconnect = false })
  mobSession:ExpectResponse(cid, { success = true, resultCode = "SUCCESS"})
end

return commonSendLocation
