--========================================================================================================================
--||Helicopter_Artifficial_Intellengence v0.01 (H.A.I.) by Wei-Chun														||
--||This is the Lua code for Lua control in FtD (From the Depths)                                                       ||
--||This Lua has following major features                                                                               ||
--||1. Can fly helicopter better than default Aerial AI 	                             								||                                                                                                                   ||
--||Written by Wei-Chun                                                                                                 ||
--========================================================================================================================
--=====================================Don't change the value in this section=============================================
--Predefined control parameters in FtD
--local Water = 0
--local Land = 1
local Air = 2
--local YawLeft = 0
--local YawRight = 1
--local RollLeft = 2
--local RollRight = 3
local NoseUp = 4
local NoseDown = 5
--local Increase = 6
--local Decrease = 7
--local MainPropulsion = 8
--local inGameTickPerSecond = 40	--40 in game ticks for 1 second in real time. Do not change this!
--========================================================================================================================

--Self mainframe index used for missile warning
local mainframeIndex = 0

--Self mainframe index used for aquire target info
local targetMainframeIndex = 0

--Aerial AI parameters
--local AngleDeviationBeforeTurnStarted = 0
local CruisingAltitude = 300
local MinimumAltitude = 230
--local DistanceBeginAtkRun = 2000
--local DistanceAbortAtkRun = 1000
--local AtkRunElapsedTime = 18
--Dediblade continuous speed parameters
local dedibladeContinuousFullSpeed = 30
local landingSpeed = 2
local altitudeOffsetTollerence = 30

local minTargetRange = 400
local maxTargetRangeOffsetTollerence = 100
local maxTargetRange = 1600
-- Pitch/roll/yaw
--local maxPitchMagnitude       = 30      -- Pitch with a bigger absolute value will be clamped to match this
--local maxRoll                 = 0       -- Roll with a bigger absolute value will be clamped to match this
--maxYawDifferential      = 1       -- Values over 0 enable differential trust for yawing(an example: 0.5 means that a left-of-the-CoM, backwards facing jet's output will be increased by up to 50% when turning right, decreased by 50% when turning left)
--maxPitchDifferential    = 0       -- Values over 0 enable differential trust for pitching
--pitchMovementAssist     = 0       -- Max angle to pitch at to help forward/backwards movement
--rollMovementAssist      = 0       -- Max angle to roll at to help left/right movement

local helicopterRotorMaxAngle = 12
local maxRotorAngleModifier = 0.7 --lower = higher effect
local pitchSpinBlockId = 9
local rollSpinBlockId = 6
local pilotSpinBlockId = 35
local mainRotorId = 0
local rearRotorId = 1
local targetAziforEvade = 0.2

--=====================================Don't change the value in this section=============================================
--Global variables for previous state
prevSelfAIMode = nil
--prevTargetId = nil
--mainTargetIndex = highestValueTarget
--targetChangeTick = defaultTargetChangeTick
--IsTicking = false	--Use to determine if missile is still flying. Will not chagne to new target if is ticking. Will end when reach defaultTargetChangeTick
--evadingTick = defaultEvadingTick
mainRotorPower = 1
targetAltitude = CruisingAltitude
IsMainRotorPitchInvert = mainRotorPower
IsMainRotorRollInvert = -mainRotorPower
--========================================================================================================================

-- Tune PIDs here
--							P,						D,			I,			OutMax,		OutMin,		IMax,		IMin
local pitchPIDData={		0.10,					0.0001,		0.0001,		1,			-1,			1,			-1}
local rollPIDData={			0.03,					0.0001,		0.0001,		1,			-1,			1,			-1}
local yawPIDData={			0.01,					0.0,		0.0,		1,			-1,			1,			-1}
local altitudePIDData={		0.06,					0.0,		0.0,		1,			-1,			1000,		0}
local distancePIDData={		0.6,					0.0,		0.0,		0,			-30,		2000,		0}

function Speed(vel)
	return math.sqrt(vel[1]^2 + vel[2]^2 + vel[3]^2)
end

function Distance(pos1,pos2)
	return Speed(pos1 - pos2)
end

function Predict(P1,V1,P2,V2)
	local D = Distance(P1,P2)
	local S = Speed(V2-V1)
	local Time =  D/S
	if(S > 500) then
		V2 = V2 * 1.1
	end
	P2 = P2 + V2 * Time
	return P2
end

function SetAltitude(I, currentAltitude, targetAltitude)
	altitudeInput,altitudePID       = GetPIDOutput(targetAltitude, currentAltitude, altitudePID)
	return altitudeInput
end

function SetDistance(I, currentTargetRange, targetDistance)
	distanceInput,distancePID       = GetPIDOutput(targetDistance, currentTargetRange, distancePID)
	return distanceInput
end

function SetPitch(I, currentSelfPitch, targetPitch)
	local pitchModifier = 1
	pitchInput,pitchPID       = GetPIDOutput(targetPitch, currentSelfPitch, pitchPID)
	I:LogToHud("currentSelfPitch: "..currentSelfPitch.."pitchInput1:"..pitchInput)
--	if(mainRotorPower < maxRotorAngleModifier and mainRotorPower >= 0) then
--		pitchModifier = maxRotorAngleModifier
--	elseif(mainRotorPower > -maxRotorAngleModifier and mainRotorPower < 0) then
--		pitchModifier = -maxRotorAngleModifier
--	else
--		pitchModifier = mainRotorPower
--	end
	if(mainRotorPower >= 0) then
		pitchModifier = 1
	else
		pitchModifier = -1
	end
	if(pitchInput > 0) then
		I:SetSpinBlockRotationAngle(pitchSpinBlockId, helicopterRotorMaxAngle * pitchInput * pitchModifier)
	elseif(pitchInput < 0) then
		I:SetSpinBlockRotationAngle(pitchSpinBlockId, 360 - helicopterRotorMaxAngle * -pitchInput * pitchModifier)
	end
	return pitchInput
end

function SetRoll(I, currentSelfRoll, targetRoll)
	if(currentSelfRoll > 180) then
		currentSelfRoll = currentSelfRoll - 360
	end
	local rollModifier = 1
	rollInput,rollPID         = GetPIDOutput(targetRoll,  currentSelfRoll,  rollPID)
	I:LogToHud("currentSelfRoll: "..currentSelfRoll.."rollInput:"..rollInput)
--	if(mainRotorPower < maxRotorAngleModifier and mainRotorPower >= 0) then
--		rollModifier = maxRotorAngleModifier
--	elseif(mainRotorPower > -maxRotorAngleModifier and mainRotorPower < 0) then
--		rollModifier = -maxRotorAngleModifier
--	else
--		rollModifier = mainRotorPower
--	end
	if(mainRotorPower >= 0) then
		rollModifier = 1
	else
		rollModifier = -1
	end
	if(rollInput > 0) then
		I:SetSpinBlockRotationAngle(rollSpinBlockId, 360 - helicopterRotorMaxAngle * rollInput * -rollModifier)
	elseif(rollInput < 0) then
		I:SetSpinBlockRotationAngle(rollSpinBlockId, helicopterRotorMaxAngle * -rollInput * -rollModifier)
	end
	return rollInput
end

function SetYaw(I, currentSelfYaw, targetAzi)
	yawInput,yawPID = GetPIDOutput(0, targetAzi, yawPID)
	I:LogToHud("currentSelfYaw: "..currentSelfYaw.."yawInput:"..rollInput.." targetAzi:"..targetAzi)
	I:SetDedibladeInstaSpin(rearRotorId, yawInput)
	return yawInput
end

function SetMainRotorPower(I, currentValue, targetValue, controlPID)
	controlInput,controlPID = GetPIDOutput(targetValue, currentValue, controlPID)
	mainRotorPower = controlInput
	I:SetDedibladeInstaSpin(mainRotorId, mainRotorPower)
	return controlInput
end

function InitPID(pidData)
	PID = {}
	PID.Kp            = pidData[1]
	PID.Kd            = pidData[2]
	PID.Ki            = pidData[3]
	PID.OutMax        = pidData[4]
	PID.OutMin        = pidData[5]
	PID.IMax          = pidData[6]
	PID.IMin          = pidData[7]
	PID.integral      = 0
	PID.previousError = 0
	
	return PID
end

function InitPIDs()
	pitchPID    = InitPID(pitchPIDData)
	rollPID     = InitPID(rollPIDData)
	yawPID      = InitPID(yawPIDData)
	altitudePID = InitPID(altitudePIDData)
	distancePID = InitPID(distancePIDData)
end

function GetPIDOutput(SetPoint, ProcessVariable, PID)
	local error = SetPoint - ProcessVariable
	local timeDelta = 0.025
	local derivative
	local output
	
	PID.integral = PID.integral + (error*timeDelta) * PID.Ki
	if (PID.integral > PID.IMax) then PID.integral = PID.IMax end
	if (PID.integral < PID.IMin) then PID.integral = PID.IMin end
	
	derivative = (error - PID.previousError)/timeDelta
	
	output = PID.Kp*error + PID.Kd*derivative + PID.integral
	if (output > PID.OutMax) then output = PID.OutMax end
	if (output < PID.OutMin) then output = PID.OutMin end
	
	PID.previousError = error
	return output,PID
end

function InitDedibladeManager(I)
	for dedibladeIndex = 0, I:GetDedibladeCount()-1 do
		--local dedibladeInfo = I:GetDedibladeInfo(dedibladeIndex)
		--I:Log("dedibladeIndex: "..dedibladeIndex)
		--I:Log(dedibladeInfo.LocalForwards[1]..", "..dedibladeInfo.LocalForwards[2]..", "..dedibladeInfo.LocalForwards[3])
		--if(dedibladeInfo.LocalForwards[1] ~= 0) then
		if(I:IsDedibladeOnHull(dedibladeIndex)) then
			rearRotorId = dedibladeIndex
		else
			mainRotorId = dedibladeIndex
		end
	end
end

function HeliControl(I, targetPitch, targetRoll, targetYaw, targetPowerReference, currentSelfPitch, currentSelfRoll, currentSelfYaw, currentPowerReference, rotorPowerPID)
	local pitchForce = SetPitch(I, currentSelfPitch, targetPitch)
	SetMainRotorPower(I, currentPowerReference, targetPowerReference, rotorPowerPID)
	SetRoll(I, currentSelfRoll, targetRoll)
	SetYaw(I, currentSelfYaw, targetYaw)
	if(targetPitch > 0) then
		I:RequestControl(Air,NoseUp, 1)	--Tailplane control
	elseif(targetPitch < 0) then
		I:RequestControl(Air,NoseDown, 1)	--Tailplane control
	end
end

function Update(I)
	local currentSelfAIMode = I.AIMode
	local currentSelfPitch = I:GetConstructPitch()
	local currentSelfRoll = I:GetConstructRoll()
	local currentSelfYaw = I:GetConstructYaw()
	local currentSelfPosition = I:GetConstructCenterOfMass()
	local currentSelfVelocityVector = I:GetVelocityVector()
	local targetInfo = I:GetTargetInfo(targetMainframeIndex, 0)
	local targetPitch = 0
	local targetRoll = 0
	local targetYaw = 0
	local mainRotorDrive = 0
		
	InitPIDs()
	InitDedibladeManager(I)
	I:TellAiThatWeAreTakingControl()
	if(I:IsDocked()) then	--If docked, do nothing

	elseif(currentSelfAIMode == "off") then	--If off, start landing sequence
		if(landingSpeed > 0) then
			landingSpeed = landingSpeed * -1
		end
		mainRotorDrive = 0
		I:SetSpinBlockRotationAngle(pilotSpinBlockId, 90)
		I:SetDedibladeInstaSpin(mainRotorId, 0.7)
		local tailPlaneControl = SetPitch(I, currentSelfPitch, targetPitch)
		SetRoll(I, currentSelfRoll, targetRoll)
		SetYaw(I, currentSelfYaw, targetYaw)
		if(tailPlaneControl < 0) then
			I:RequestControl(Air,NoseUp, -tailPlaneControl)	--Tailplane control
		elseif(tailPlaneControl > 0) then
			I:RequestControl(Air,NoseDown, tailPlaneControl)	--Tailplane control
	end
	else
		if(targetInfo.Valid) then
			local transceiverIndex
			local missileIndex
			for transceiverIndex = 0,I:GetLuaTransceiverCount() do
				for missileIndex = 0,I:GetLuaControlledMissileCount(transceiverIndex) -1 do
					local luaMissileInfo = I:GetLuaControlledMissileInfo(transceiverIndex, missileIndex)
					local target = Predict(luaMissileInfo.Position ,luaMissileInfo.Velocity ,targetInfo.AimPointPosition ,targetInfo.Velocity)
					I:SetLuaControlledMissileAimPoint(transceiverIndex ,missileIndex ,target[1] ,target[2] ,target[3])
				end
			end
			mainRotorDrive = 10
			local targetPositionInfo = I:GetTargetPositionInfo(targetMainframeIndex, 0)
			targetYaw = targetPositionInfo.Azimuth
			if(targetPositionInfo.Range < maxTargetRange + maxTargetRangeOffsetTollerence) then
				targetPitch = (1 - targetPositionInfo.Range/maxTargetRange) * -40
				targetAltitude = CruisingAltitude
--UpDown Jitter evade method
--				if(currentSelfPosition[2] > CruisingAltitude - altitudeOffsetTollerence) then
--					targetAltitude = MinimumAltitude
--				end
--			
--				if(currentSelfPosition[2] < MinimumAltitude + altitudeOffsetTollerence) then
--					targetAltitude = CruisingAltitude
--				end
--ZigZag evade method
--				if(targetPositionInfo.Azimuth > targetAziforEvade) then 
--					targetRoll = 115
--				end
--			
--				if(targetPositionInfo.Azimuth < -targetAziforEvade) then
--					targetRoll = -115
--				end
--				targetAltitude = 600
			else
				targetAltitude = CruisingAltitude
				targetPitch = 90 - 90 * ((SetAltitude(I, currentSelfPosition[2], targetAltitude) + 1) / 2)
				targetAltitude = 1000
				currentSelfPosition[2] = 0
			end
		end
		I:SetSpinBlockRotationAngle(pilotSpinBlockId, 0)
		HeliControl(I, targetPitch, targetRoll, targetYaw, targetAltitude, currentSelfPitch, currentSelfRoll, currentSelfYaw, currentSelfPosition[2], altitudePID)
	end
	I:SetDedibladePowerDrive(mainRotorId, mainRotorDrive)
end