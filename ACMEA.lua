--========================================================================================================================
--||Aerial_Combat_Missile_Evade_Ability v1.02 (A.C.M.E.A.) by Wei-Chun													||
--||This is the Lua code for Lua control in FtD (From the Depths)                                                       ||
--||This Lua has following major features                                                                               ||
--||1. Can control airplane to evade incoming missiles by perform two different maneuvers                               ||
--||2. Can recover from high altitude (such as space)                                                                   ||
--||3. Can guide Lua missiles without change target during missile flying period                                        ||
--||4. Can predict better missile launching timing determined by the time before hit instead of determined by range only||
--||                                                                                                                    ||
--||Written by Wei-Chun                                                                                                 ||
--========================================================================================================================
--=====================================Don't change the value in this section=============================================
--Predefined control parameters in FtD
--local Water = 0
--local Land = 1
local Air = 2
--local YawLeft = 0
--local YawRight = 1
local RollLeft = 2
local RollRight = 3
local NoseUp = 4
local NoseDown = 5
--local Increase = 6
--local Decrease = 7
local MainPropulsion = 8
local inGameTickPerSecond = 40	--40 in game ticks for 1 second in real time. Do not change this!
--========================================================================================================================

--Self mainframe index used for missile warning
local mainframeIndex = 0

--Self mainframe index used for aquire target info
local targetMainframeIndex = 0

--Aerial AI parameters
--local AngleDeviationBeforeTurnStarted = 0
--local AngleDeviationBeforeWeRollToTurn = 15
--local MostExtremeRollBasedTurnAngle = 87
--local CruisingAltitude = 750
--local MinimumAltitude = 750
--local DistanceBeginAtkRun = 2000
--local DistanceAbortAtkRun = 1000
--local AtkRunElapsedTime = 18
--Dediblade continuous speed parameters
local dedibladeContinuousFullSpeed = 30

--Parameters for evasive maneuvers
local missileRangeinSecond = 1.5 --In N seconds missile will collide Self so will try to evade
local selfVelocityRelateToSelfMissileVelocity = 1.5	--selfVelocityRelateToSelfMissileVelocity = (SelfSpeed + MissileInitialSpeed) / SelfSpeed
local defaultEvadingTick = 100

--Parameter for recover from maneuver
local recoverPitchAngle = 30	--Nose down degree
local recoverAltitude = 1100
local recoverRollTollerance = 15
local recoverPitchTollerance = 10

--Parameter for Weapon control
local missilePredictThrustTime = 10	--Proximity time in seconds
local missilePredictImpactTime = 4
local missileWeaponSlot = 1
--local flareWeaponSlot = 2
local indexOfSubConstructWithMissile = 19	--Fixed index of the subconstruct with missile weapon
local indexOfMissileControllers = {0, 1, 2}	--Fixed index of the missile controllers
local missileLaunchDistance = 1800

--targeting parameters
local highestValueTarget = 0 --Priority is selected by Target priority card
local targetMaxElevation = 40
local targetMaxAzimuth = 40
local defaultTargetChangeTick = inGameTickPerSecond * missilePredictThrustTime	--Translate second to tick
local fastTargetStandard = 200	--If target speed higher than this value will ignore the firing range limit

--=====================================Don't change the value in this section=============================================
--Global variables for previous state
prevSelfAIMode = nil
prevTargetId = nil
mainTargetIndex = highestValueTarget
targetChangeTick = defaultTargetChangeTick
IsTicking = false	--Use to determine if missile is still flying. Will not chagne to new target if is ticking. Will end when reach defaultTargetChangeTick
evadingTick = defaultEvadingTick
--========================================================================================================================

--//////////////Basic calculation functions//////////////
function RelativeVelocity(vel1, vel2)
	return vel1 - vel2
end

function Speed(vel)
	return math.sqrt(vel[1]^2 + vel[2]^2 + vel[3]^2)
end

function Distance(pos1,pos2)
	return Speed(pos1 - pos2)
end

function Normalize(vector)
    return vector/Speed(vector)
end

function GetBearings(I, targetLocation, currentSelfPosition)
	local heading = Normalize(targetLocation - currentSelfPosition)
    local angle = (math.atan2(heading[1], heading[3]) * 57.296) % 360
    if(angle == 360 or angle == -360) then 
		angle = 0
	end
    local steer = ((I:GetConstructYaw() - angle + 180) % 360) - 180
    return steer
end

function Predict(P1,V1,P2,V2)
   local D = Distance(P1,P2)
   local S = Speed(V2-V1)
   local Time =  D/S
   if(Time>0 and Time < 200) then
      P2 = P2 + V2 * Time
   end
   return P2
end
--//////////////Basic calculation functions//////////////
function MainThrustAndDedibladeThrottleControl(I, mainThrustThrottle)
	I:RequestControl(Air, MainPropulsion, mainThrustThrottle)	--Add Mainpropulsion here to full thrust when controlled by LUA
	for DedibladeCount = 0,I:GetDedibladeCount() - 1 do
		I:SetDedibladeSpeedFactor(DedibladeCount, dedibladeContinuousFullSpeed * mainThrustThrottle)
	end
end

function ChangeMainThrustandDedibladeThrottlebyAIMode(I)
	if(I:IsDocked()) then	--If docked, cut off all thrust
		MainThrustAndDedibladeThrottleControl(I, DedibladeContinuousNoSpeed, 0)
	else
		local currentSelfAIMode = I.AIMode
		if(currentSelfAIMode ~= PrevSelfAIMode) then	--Only adjust the throttle when AI mode is changed
		--Throttle Main thrust to full power in following AI mode
			if(currentSelfAIMode == "combat" 
				or currentSelfAIMode == "follow" 
				or currentSelfAIMode == "patrol" 
				or currentSelfAIMode == "fleetmove") then
				MainThrustAndDedibladeThrottleControl(I, 1)
			else
				MainThrustAndDedibladeThrottleControl(I, 0)
			end
		end
	end
end

function FireMissiles(I)
	local indexOfWeapon = nil
	--Since we can get fixed index of subconstruct so we use following code to reduce calculation complexity
	for k, indexOfWeapon in pairs(indexOfMissileControllers) do
		local weaponInfoOnSub = I:GetWeaponInfoOnSubConstruct(indexOfSubConstructWithMissile, indexOfWeapon)
		I:AimWeaponInDirectionOnSubConstruct(indexOfSubConstructWithMissile, indexOfWeapon, weaponInfoOnSub.CurrentDirection[1], weaponInfoOnSub.CurrentDirection[2], weaponInfoOnSub.CurrentDirection[3], missileWeaponSlot)
		--Try to fire missiles and start ticking if it is fired.
		local missileFired = I:FireWeaponOnSubConstruct(indexOfSubConstructWithMissile, indexOfWeapon, missileWeaponSlot)
		if(missileFired and targetChangeTick == defaultTargetChangeTick) then
			IsTicking = true
		end
	end
end

function LuaMissileGuidence(I, currentSelfPosition, currentSelfVelocityVector)
	local numberOfTargets = I:GetNumberOfTargets(mainframeIndex)
	if(numberOfTargets > 0) then
		local targetInfo
		if(not IsTicking) then	--If is not ticking means no missile is flying
			mainTargetIndex = highestValueTarget
		end
		targetInfo = I:GetTargetInfo(targetMainframeIndex, mainTargetIndex)
		if(prevTargetId ~= targetInfo.Id and IsTicking and targetInfo.Valid) then	--If previous target is still tracked by previously fired missiles
			for t = 1, numberOfTargets do	--Trace back all targets until find the previous target
				targetInfo = I:GetTargetInfo(targetMainframeIndex, t)
				if(targetInfo.Id == prevTargetId and targetInfo.Valid) then
					mainTargetIndex = targetInfo.Priority
					break
				end
			end
		else	--If previous target not found(might be dead). Switch to highest value target
			targetInfo = I:GetTargetInfo(targetMainframeIndex, mainTargetIndex)
		end
		--I:LogToHud("ID: "..targetInfo.Id.." mainTargetIndex: "..mainTargetIndex.." Priority:"..targetInfo.Priority.."Tick: "..targetChangeTick)
		if(targetInfo.Valid) then
			prevTargetId = targetInfo.Id
			local transceiverIndex = 0
			local missileIndex = 0
			local targetPositionInfo = I:GetTargetPositionInfo(targetMainframeIndex, mainTargetIndex)
			local targetDistance = targetPositionInfo.Range
			for transceiverIndex = 0,I:GetLuaTransceiverCount() do
				for missileIndex = 0,I:GetLuaControlledMissileCount(transceiverIndex) -1 do
					local luaMissileInfo = I:GetLuaControlledMissileInfo(transceiverIndex, missileIndex)
					local target = Predict(luaMissileInfo.Position ,luaMissileInfo.Velocity ,targetInfo.AimPointPosition ,targetInfo.Velocity)
					I:SetLuaControlledMissileAimPoint(transceiverIndex ,missileIndex ,target[1] ,target[2] ,target[3])
				end
			end
			local targetPositionInfo = I:GetTargetPositionInfo(targetMainframeIndex, mainTargetIndex)
			--If target relative velocity is high enough to impact Self
			if(targetDistance / (Speed(RelativeVelocity(targetInfo.Velocity, currentSelfVelocityVector * selfVelocityRelateToSelfMissileVelocity))) < missilePredictImpactTime
				and targetPositionInfo.Azimuth < targetMaxAzimuth 
				and targetPositionInfo.Azimuth > targetMaxAzimuth * -1
				and targetPositionInfo.Elevation < targetMaxElevation
				and targetPositionInfo.Elevation > targetMaxElevation * -1) then
				
				local targetSpeed = Speed(targetInfo.Velocity)
				if(targetSpeed >= fastTargetStandard) then	--If target is too fast, ignore missile firing range limit
					FireMissiles(I)
				elseif(targetSpeed < fastTargetStandard and targetDistance < missileLaunchDistance) then	--If target is slow, add missile firing range limit to increase accuracy
					FireMissiles(I)
				end
			end
		end
	end
end

function MissileEvadeDetermine(I, currentSelfPosition, currentSelfVelocityVector)
	local numberOfWarnings = I:GetNumberOfWarnings(mainframeIndex)
	if(numberOfWarnings > 0) then	--If any incoming missile exists
		for incomingMissileIndex = 0, numberOfWarnings do
			local incomingMissileInfo = I:GetMissileWarning(mainframeIndex, incomingMissileIndex)	--Get the missile information
			if(incomingMissileInfo.Valid) then	--If the missile info is fetched
				--If missile is in N second range
				if((incomingMissileInfo.Range / Speed(incomingMissileInfo.Velocity - currentSelfVelocityVector)) < missileRangeinSecond	
					-- and missile is closing to Self (Current missile range is larger than predicted next tick missile range)
					and incomingMissileInfo.Range > Distance(currentSelfPosition + (currentSelfVelocityVector / inGameTickPerSecond), incomingMissileInfo.Position + (incomingMissileInfo.Velocity / inGameTickPerSecond))) then	
						--I:LogToHud("Speed: "..Speed(incomingMissileInfo.Velocity - currentSelfVelocityVector).." Range: "..incomingMissileInfo.Range)
						return true
				end
			end
		end
	end
	return false
end

function EvasiveManeuver(I, currentSelfPosition)
	I:TellAiThatWeAreTakingControl()
	I:RequestControl(Air,NoseUp,1)
	if(evadingTick < 80 and currentSelfPosition[2] > 300 and currentSelfPosition[2] < 1300) then
		I:RequestControl(Air,RollRight,0.5)
	end
	evadingTick = evadingTick - 1
end

function RecoverfromHighAltitude(I)
	local currentSelfPitch = I:GetConstructPitch()
	local currentSelfRoll = I:GetConstructRoll()
	I:TellAiThatWeAreTakingControl()
	--Pitch control
	if(currentSelfPitch < recoverPitchAngle - recoverPitchTollerance) then
		I:RequestControl(Air,NoseDown,1)
	elseif(currentSelfPitch > recoverPitchAngle + recoverPitchTollerance) then
		I:RequestControl(Air,NoseUp,1)
	end
	--Roll control
	if(currentSelfRoll < 180 and currentSelfRoll > recoverRollTollerance) then
		I:RequestControl(Air,RollRight,1)
	elseif(currentSelfRoll > 180 and currentSelfRoll < (360 - recoverRollTollerance)) then
		I:RequestControl(Air,RollLeft,1)
	end
end

function Update(I)
	local currentSelfVelocityVector = I:GetVelocityVector()
	local currentSelfPosition = I:GetConstructCenterOfMass()
	local IsNeedEvade = MissileEvadeDetermine(I, currentSelfPosition, currentSelfVelocityVector)	--Determine if need to evade missiles
	ChangeMainThrustandDedibladeThrottlebyAIMode(I)	--Change MainThrust and DedibladeThrottle determined by AI mode	
	if(IsNeedEvade) then	
		EvasiveManeuver(I, currentSelfPosition)	--Start evasive maneuver
	elseif(currentSelfPosition[2] > recoverAltitude) then	--If fly too high
		RecoverfromHighAltitude(I)	--Recover from high altitude
	end
	if(not IsNeedEvade) then
		evadingTick = defaultEvadingTick
	end
	--I:LogToHud("evadingTick: "..evadingTick)
	--I:LogToHud("currentSelfPitch: "..currentSelfPitch.."  currentSelfRoll: "..currentSelfRoll.." currentSelfPosition[2]: "..currentSelfPosition[2])
	LuaMissileGuidence(I, currentSelfPosition, currentSelfVelocityVector)	--Missile Guidence
		if(targetChangeTick <= 0) then
		IsTicking = false
		targetChangeTick = defaultTargetChangeTick
	end
	if(IsTicking) then
		targetChangeTick = targetChangeTick - 1
	end
	PrevSelfAIMode = currentSelfAIMode	--Update last frame of AI Mode
end