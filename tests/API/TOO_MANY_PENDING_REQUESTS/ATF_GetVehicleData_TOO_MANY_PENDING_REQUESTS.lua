Test = require('connecttest')
require('cardinalities')
local events = require('events')
local mobile_session = require('mobile_session')
local mobile  = require('mobile_connection')
local tcp = require('tcp_connection')
local file_connection  = require('file_connection')

local commonSteps = require('user_modules/shared_testcases/commonSteps')

local TooManyPenReqCount = 0

function DelayedExp()
  local event = events.Event()
  event.matches = function(self, e) return self == e end
  EXPECT_EVENT(event, "Delayed event")
  RUN_AFTER(function()
              RAISE_EVENT(event, event)
            end, 5000)
end

---------------------------------------------------------------------------------------------
-------------------------------------------Preconditions-------------------------------------
---------------------------------------------------------------------------------------------
	--Begin Precondition.1
	--Description: Activation App by sending SDL.ActivateApp	
		commonSteps:ActivationApp()
	--End Precondition.1
	
---------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------
----------------------------------------IV TEST BLOCK-----------------------------------------
---------------------------------------Result codes check--------------------------------------
----------------------------------------------------------------------------------------------

--Begin Test suit ResultCodeCheck
--Description:TC check TOO_MANY_PENDING_REQUESTS resultCode

	--Requirement id in JAMA: SDLAQ-CRS-611

    --Verification criteria: The system has more than M (M defined in smartDeviceLink.ini) requests  at a timethat haven't been responded yet.

	function Test:GetVehicleData_TooManyPendingRequests()
		for i = 1, 20 do
			--mobile side: GetVehicleData request  
			self.mobileSession:SendRPC("GetVehicleData",
														{
															speed = true
														})
		end
		
		EXPECT_RESPONSE("GetVehicleData")
			:ValidIf(function(exp,data)
				if 
					data.payload.resultCode == "TOO_MANY_PENDING_REQUESTS" then
			    		TooManyPenReqCount = TooManyPenReqCount+1
			    		print(" \27[32m GetVehicleData response came with resultCode TOO_MANY_PENDING_REQUESTS \27[0m")
						return true
				elseif 
				   	exp.occurences == 20 and TooManyPenReqCount == 0 then 
				  		print(" \27[36m Response GetVehicleData with resultCode TOO_MANY_PENDING_REQUESTS did not came \27[0m")
			  			return false
				elseif 
			  		data.payload.resultCode == "GENERIC_ERROR" then
			    		print(" \27[32m GetVehicleData response came with resultCode GENERIC_ERROR \27[0m")
			    		return true				
				elseif 
			  		data.payload.resultCode == "REJECTED" then
			    		print(" \27[32m GetVehicleData response came with resultCode REJECTED \27[0m")
			    		return true
				else
			    	print(" \27[36m GetVehicleData response came with resultCode "..tostring(data.payload.resultCode .. "\27[0m" ))
			    	return false
				end
			end)
			:Times(20)
			:Timeout(15000)

		--expect absence of OnAppInterfaceUnregistered
		EXPECT_NOTIFICATION("OnAppInterfaceUnregistered")
		:Times(0)

		--expect absence of BasicCommunication.OnAppUnregistered
		EXPECT_HMICALL("BasicCommunication.OnAppUnregistered")
		:Times(0)

		DelayedExp()
	end
--End Test suit ResultCodeCheck















