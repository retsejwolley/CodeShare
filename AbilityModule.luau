local KingCrimson = {}
KingCrimson.__index = KingCrimson

--[[
This is the start of the skill module of the ability: King Crimson

The ability i scripted comes from an anime Called Jojo's Bizarre Adventure where "stands" take place usually back to the user such as a shadow. 

I explained most of the functions and topics, I hope I have explained it well.

Please note that the first ability you spawn in the attached game is THIS ability.
]]--

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
--[[
Here i assigm services that i will use multiple times later in the code
]]--

-- Dependencies
local Modules = ReplicatedStorage:WaitForChild("Modules")
local DamageHandler = require(ServerScriptService:WaitForChild("DamageHandler"))
local BezierPunch = require(ServerStorage.BezierPunch)
local RagdollHandler = require(Modules:WaitForChild("RagdollHandler"))
local HitboxHandler = require(ServerScriptService:WaitForChild("HitboxHandler"))
local VFXHandler = require(Modules:WaitForChild("VFXHandler"))
local SFXHandler = require(Modules:WaitForChild("SFXHandler"))

local AbilityModels = ServerStorage:WaitForChild("AbilityModels")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local InfoFolder = ReplicatedStorage:WaitForChild("AbilityModules")
--[[
Here i call some other system modules and assign remote variables
]]--

-- Constants
local STAND_NAME = "KingCrimson"
local AbilityInfo = require(InfoFolder:WaitForChild(STAND_NAME))
local MOVES = AbilityInfo.GetMoves()
local ASSETS = AbilityInfo.GetAssets()

--[[
This variables are constant for this ability 
]]--

-- Constructor
function KingCrimson.new(player)
	local self = setmetatable({}, KingCrimson)

	self.Player = player
	self.Character = player.Character

	-- Instance specific state management prevents global variable conflicts
	self.State = {
		IsBarraging = false,
		BarrageAnim = nil,
		BarrageSound = nil,
		TimeEraseActive = false,
		AlreadyAttackPos = false,
		StayForwardTask = nil,
		OldTransparencyTable = nil
	}

	return self
end

--[[
Here is the most crucial part of my code. Metatables allow me to store unique variables separately for each player who uses this ability.
]]--

-- Helper Methods
function KingCrimson:GetStand()
	if not self.Character then return nil end
	return self.Character:FindFirstChild(self.Player.Name .. "_Stand")
end

function KingCrimson:CreateBulletTracer(startPos, endPos)
	local distance = (endPos - startPos).Magnitude
	local tracer = Instance.new("Part")

	tracer.Name = "BulletTracer"
	tracer.Anchored = true
	tracer.CanCollide = false
	tracer.CastShadow = false
	tracer.Material = Enum.Material.Neon
	tracer.Color = Color3.fromRGB(255, 255, 100)
	tracer.Size = Vector3.new(0.25, 0.25, distance)
	tracer.CFrame = CFrame.lookAt(startPos, endPos) * CFrame.new(0, 0, -distance / 2)
	tracer.Parent = workspace

	local fadeInfo = TweenInfo.new(0.25, Enum.EasingStyle.Linear, Enum.EasingDirection.In)
	TweenService:Create(tracer, fadeInfo, {Transparency = 1}):Play()
	Debris:AddItem(tracer, 0.25)
end

--[[
This is the bullet tracker function that creates a beam between final and starter points for a certain duration.
]]--


function KingCrimson:PlayAnim(targetModel, animId, speed)
	if not animId or not targetModel then return nil end

	local humanoid = targetModel:FindFirstChild("Humanoid")
	local animator = humanoid and humanoid:FindFirstChild("Animator") or Instance.new("Animator", humanoid)
	local animation = Instance.new("Animation")
	animation.AnimationId = animId

	local track = animator:LoadAnimation(animation)
	track:Play(0.1, 10, speed or 1)

	return track
end

--[[
This is the anim player function that loads targer animationId to the target character's animator and plays it with designated playback speed.
]]--


function KingCrimson:AttackPosition(forwardAmount, duration)
	local stand = self:GetStand()
	if not stand then return end

	local standHrp = stand:WaitForChild("HumanoidRootPart")
	local motor = standHrp:FindFirstChild("StandConnector")
	if not motor then return end

	-- Cancel the previous reset task if the player attacks consecutively
	if self.State.AlreadyAttackPos and self.State.StayForwardTask then
		task.cancel(self.State.StayForwardTask)
		self.State.StayForwardTask = nil
	end

	local attackGoal = {C0 = CFrame.new(0, 0, -forwardAmount)}
	local attackInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(motor, attackInfo, attackGoal):Play()
	self.State.AlreadyAttackPos = true

	self.State.StayForwardTask = task.delay(duration, function()
		if motor and motor.Parent then
			local resetGoal = {C0 = CFrame.new(2, 1, 2)}
			local resetInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			TweenService:Create(motor, resetInfo, resetGoal):Play()
			self.State.AlreadyAttackPos = false
		end
	end)

	task.wait(0.2)
end

--[[
Attack position makes the ability take place front of the user before attacking. 

This functions tweens ability rig position to the front of the player by "forwardAmount" (studs) throughout the "duration" (number)

The reason why I use motor6d instead of classic welds is because motor6d makes the rig animations works correctly instead of just freezing it. Along side this motor6d provides more flexible movement&tweening
]]--


--[[
Helper methods are usually part of multiple abilities,that's why I created simple functions of these codes in order to avoid using them repeatedly 
]]--


-- Core Abilities
function KingCrimson:Summon()
	local existingStand = self:GetStand()

	-- Handle despawn logic if the stand already exists
	if existingStand then
		local hrp = existingStand:FindFirstChild("HumanoidRootPart")
		local motor = hrp and hrp:FindFirstChild("StandConnector")

		if motor then
			TweenService:Create(motor, TweenInfo.new(0.3, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {C0 = CFrame.new(0,0,0)}):Play()

			for _, v in pairs(existingStand:GetDescendants()) do	
				if v:IsA("BasePart") then
					TweenService:Create(v, TweenInfo.new(0.3, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {Transparency = 1}):Play()
				end
			end
		end

		task.delay(0.3, function() 
			if existingStand then existingStand:Destroy() end 
		end)
		return
	end

	-- Handle spawn logic
	if not self.Character then return end
	local hrp = self.Character:WaitForChild("HumanoidRootPart")
	local standModel = AbilityModels:FindFirstChild(STAND_NAME)

	if not standModel then return end

	local standClone = standModel:Clone()
	standClone.Name = self.Player.Name .. "_Stand"
	standClone.Parent = self.Character

	local standHrp = standClone:WaitForChild("HumanoidRootPart")
	for _, v in pairs(standClone:GetDescendants()) do 
		if v:IsA("BasePart") then 
			v.CanCollide = false 
			v.Massless = true 
		end 
	end

	local motor = Instance.new("Motor6D")
	motor.Name = "StandConnector"
	motor.Part0 = hrp
	motor.Part1 = standHrp
	motor.Parent = standHrp
	motor.C0 = CFrame.new(0,0,0)

	SFXHandler.PlaySound(standHrp, ASSETS.Sounds.Summon)
	VFXHandler.PlayVFX(standClone, "#4_Summon", "HumanoidRootPart", 2)

	TweenService:Create(motor, TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {C0 = CFrame.new(2,1,2)}):Play()

	if standClone.Parent then 
		self:PlayAnim(standClone, ASSETS.Animations.Idle) 
	end
end

--[[

 In this Summon ability whenever player triggers the designated key it gets fired, checks for the ability model, clones and tweens it to the correct place.
]]--



function KingCrimson:BarrageStart()
	local stand = self:GetStand()
	if not stand or self.State.IsBarraging then return end

	local data = MOVES.Barrage
	self.Player:SetAttribute("IsHolding_Barrage", true)
	self.State.IsBarraging = true

	self.State.BarrageSound = SFXHandler.PlaySound(stand.HumanoidRootPart, ASSETS.Sounds.Barrage[1], false, 0, ASSETS.Sounds.Barrage[2])
	self.State.BarrageAnim = self:PlayAnim(stand, ASSETS.Animations.Barrage)

	BezierPunch.Start(stand, data.HitDuration)
	self:AttackPosition(data.SelfForward, data.SelfDuration)
	HitboxHandler.Run(self.Player, stand, data)
end

function KingCrimson:BarrageStop()
	if not self.State.IsBarraging then return end

	self.Player:SetAttribute("IsHolding_Barrage", nil)
	self.State.IsBarraging = false

	if self.State.BarrageAnim then self.State.BarrageAnim:Stop(0.2) end
	if self.State.BarrageSound then 
		self.State.BarrageSound:Stop()
		self.State.BarrageSound:Destroy() 
	end

	local stand = self:GetStand()
	if stand then
		BezierPunch.Stop(stand)
		local motor = stand.HumanoidRootPart:FindFirstChild("StandConnector")
		if motor then
			TweenService:Create(motor, TweenInfo.new(0.4, Enum.EasingStyle.Quad), {C0 = CFrame.new(2, 1, 2)}):Play()
		end
	end
end


--[[
Barrage is an iconic skill for this type of abilities, basically spawns multiple hitboxes along side a bezier curve module that creates extra arms in order to feel like character punches really fast.

how this function works is since this ability is holdable it's divided into two scripts.

starter script creates the hitbox, arms, animation and sound while stop function disables all relevant self. variables

This action makes the client side of the module check if attack still ongoing or not.
]]--


function KingCrimson:Heavy()
	local stand = self:GetStand()
	if not stand then return end

	local data = MOVES.Heavy
	SFXHandler.PlaySound(stand.HumanoidRootPart, ASSETS.Sounds.Heavy)

	self:PlayAnim(stand, ASSETS.Animations.Heavy, 2.25)
	self:AttackPosition(data.SelfForward, data.SelfDuration)

	task.delay(0.35, function()
		HitboxHandler.Run(self.Player, stand, data)
	end)
end

--[[
This is the heavy punch ability plays an animation and sound right before punching through the enemy
]]--


function KingCrimson:Punch()
	local stand = self:GetStand()
	if not stand then return end

	local data = MOVES.Punch
	self:PlayAnim(stand, ASSETS.Animations.M1, 2)
	self:AttackPosition(data.SelfForward, data.SelfDuration)

	HitboxHandler.Run(self.Player, stand, data)
end

--[[
This is the similar version of heavy punch ability with a lower damage on its "data"

how data works is there is basically an information table located in client version of this module that includes various variables which will be checked by the hitbox handler server module
]]--


function KingCrimson:Chop()
	local stand = self:GetStand()
	if not stand then return end

	local data = table.clone(MOVES.Chop)
	local speed = 1

	-- Apply buffs if Time Erase is currently active
	if self.State.TimeEraseActive then
		speed = 2
		data.DPSTotal = 50
		data.Ragdoll = true
		BezierPunch.Start(stand, 0.75)
	end

	SFXHandler.PlaySound(stand.HumanoidRootPart, ASSETS.Sounds.Chop)
	self:PlayAnim(stand, ASSETS.Animations.Chop, speed)
	self:AttackPosition(data.SelfForward, data.SelfDuration)

	task.delay(0.3 / speed, function()
		HitboxHandler.Run(self.Player, stand, data)
	end)
end

--[[
A similar version of previous two skills but connects with the DamagePerSecond system in it's data in order to create bleeding effect on enemy.
]]--


-- Time Erase And Counter

--[[
Both of the skills below explained end of the code
]]--


function KingCrimson:ReverseErase()
	if not self.State.TimeEraseActive then return end

	Remotes.ScreenAction:FireClient(self.Player, "TimeErase")

	if self.Character then
		local hum = self.Character:FindFirstChildOfClass("Humanoid")
		if hum then hum.WalkSpeed = 16 end

		local hrp = self.Character:FindFirstChild("HumanoidRootPart")
		if hrp then SFXHandler.PlaySound(hrp, ASSETS.Sounds.TimeEraseStop) end

		self.Character:SetAttribute("Safe", nil)
		self.Character:SetAttribute("TimeErase", nil)

		-- Restore visibility dynamically to prevent memory leaks
		if self.State.OldTransparencyTable then
			for _, info in pairs(self.State.OldTransparencyTable) do
				if info.Part then info.Part.Transparency = info.OldTrans end
			end
		end

		self.State.OldTransparencyTable = nil
	end

	task.wait(1)
	self.State.TimeEraseActive = false
end

function KingCrimson:TimeEraseStart()
	local stand = self:GetStand()
	if not self.Character or not stand then return end

	local hum = self.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = 0
		hum.JumpPower = 0
	end

	local data = MOVES.TimeErase
	self.Character:SetAttribute("Safe", true)
	self.Character:SetAttribute("TimeErase", true)
	self.State.TimeEraseActive = true

	local anim = self:PlayAnim(stand, ASSETS.Animations.TimeEraseStand)
	self:PlayAnim(self.Character, ASSETS.Animations.TimeErasePlayer)
	self:AttackPosition(data.SelfForward, data.SelfDuration)	

	SFXHandler.PlaySound(stand.HumanoidRootPart, ASSETS.Sounds.TimeErase, false, 0, 1.5)

	anim.KeyframeReached:Once(function(name)
		if name ~= "Erase" then return end

		if hum then
			hum.WalkSpeed = 32
			hum.JumpPower = 50
		end

		self.State.OldTransparencyTable = {}

		-- Map current elements to store their original transparency state
		for _, part in pairs(self.Character:GetDescendants()) do
			if (part:IsA("BasePart") and part.Name ~= "HumanoidRootPart") or part:IsA("Decal") or part:IsA("Texture") then
				table.insert(self.State.OldTransparencyTable, {
					Part = part,
					OldTrans = part.Transparency
				})
				part.Transparency = 1
			end
		end

		-- Dispatch UI event to client
		Remotes.ScreenAction:FireClient(self.Player, "TimeErase", {
			Duration = data.Duration, 
			Weight = 2.5,
			State = true, 
			List = self.State.OldTransparencyTable
		})

		task.delay(data.Duration, function()
			self:ReverseErase()
		end)
	end)
end

function KingCrimson:TimeEraseStop()
	self:ReverseErase()
end

function KingCrimson:Epitaph()
	if not self.Character then return end
	local root = self.Character:FindFirstChild("HumanoidRootPart")
	local hum = self.Character:FindFirstChildOfClass("Humanoid")

	local moveData = MOVES.Epitaph
	local duration = moveData.Duration or 2

	self.Character:SetAttribute("StandName", "KingCrimson")
	self.Character:SetAttribute("Countering", "Epitaph")

	if root and ASSETS.Sounds.Epitaph then
		SFXHandler.PlaySound(root, ASSETS.Sounds.Epitaph, false, 0, 2)
	end

	if hum then
		hum.WalkSpeed = 0
		hum.JumpPower = 0
	end

	local shadow = Instance.new("Highlight")
	shadow.Name = "CounterShadow"
	shadow.Parent = self.Character
	shadow.FillColor = Color3.new(0, 0, 0)
	shadow.OutlineTransparency = 1
	shadow.FillTransparency = 1
	shadow.DepthMode = Enum.HighlightDepthMode.Occluded

	local tweenInfo = TweenInfo.new(duration / 2, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out, 0, true)
	TweenService:Create(shadow, tweenInfo, {FillTransparency = 0.1}):Play()

	task.delay(duration, function()
		if self.Character:GetAttribute("Countering") == "Epitaph" then
			self.Character:SetAttribute("Countering", nil)

			if shadow then
				local endTween = TweenService:Create(shadow, TweenInfo.new(0.5), {FillTransparency = 1})
				endTween:Play()
				endTween.Completed:Wait()
				shadow:Destroy()
			end

			if hum then
				hum.WalkSpeed = 16
				hum.JumpPower = 50
			end
		end
	end)
end
--This is a counter ability which reqired by another server script. That is the reason why i didn't use metatable 
function KingCrimson.EpitaphApply(victimChar, attackerChar)
	local victimRoot = victimChar:FindFirstChild("HumanoidRootPart")
	local attackerRoot = attackerChar:FindFirstChild("HumanoidRootPart")

	-- Clear counter state
	victimChar:SetAttribute("Countering", nil)
	local shadow = victimChar:FindFirstChild("CounterShadow")
	if shadow then shadow:Destroy() end

	if victimRoot and attackerRoot then
		SFXHandler.PlaySound(victimRoot, ASSETS.Sounds.TimeSkip, false, 0, 1)

		-- Position behind the attacker
		local behindCFrame = attackerRoot.CFrame * CFrame.new(0, 0, 5)
		victimRoot.CFrame = CFrame.lookAt(behindCFrame.Position, attackerRoot.Position)

		task.delay(0.3, function() 
			if not victimChar.Parent or not attackerChar.Parent then return end

			local hum = victimChar:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.AutoRotate = false
				hum.WalkSpeed = 0 
				hum.JumpPower = 0
			end

			local victimPlayer = Players:GetPlayerFromCharacter(victimChar)
			if victimPlayer then
				HitboxHandler.Run(victimPlayer, victimChar, MOVES.Epitaph)
			end

			task.delay(0.5, function() 
				if hum then
					hum.AutoRotate = true
					hum.WalkSpeed = 16
					hum.JumpPower = 50
				end
			end)
		end)
	end
end



--[[
The counter: Epitaph

This is the counter ability, when player triggers the designated keycode "Start" function makes player go idle for a few seconds.

in this period of time player recieves an attribute that can be detected by Hitbox handler.


whenever hitbox handler detects any counter attributes it immediately checks for the server module of the target ability name which is this module for our example.

the counter.Stop is runned by HITBOX HANDLER, not player itself. Which gives a reason why I didn't use self. metetable here 

what counter does is plays :Chop right after teleporting back of the enemy.
]]--

--[[
Time erase


Time erase is the most complicated system in this script that it has it's own client script.


When the skill is triggered, the player becomes invisible from the server.

But the client makes the player visible again immediately which creates a cool looking visual where player can see themselves while others can't see them.

this skill is gets stopped automatically by the client module if it was active for a certain seconds or if player makes any move. 

the :Resume function turns player back to the visible 

the client side of the code includes environmental changes where you can see in the game such as world gets crashed & skybox changes
]]--


--[[
Thanks for reading my ability script I hope I explained myself well.
]]--

return KingCrimson
