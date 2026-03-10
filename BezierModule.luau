--!strict

-- This module provides a framerate-independent, mathematically precise projectile pathing system.
-- It uses the polynomial expansion of cubic Bezier curves to calculate exact world space coordinates.
-- Instead of relying on positional differences for rotation, it calculates the true mathematical derivative 
-- of the curve to find the exact tangent vector at any given frame. The architecture is strictly typed 
-- to prevent runtime type mismatches and uses custom garbage collection to handle memory safely.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- Exporting the type configuration allows other scripts to require this module and receive full autocomplete 
-- and type checking for the constructor arguments. This enforces data integrity before the script even runs.
export type BezierConfig = {
	TargetPart: BasePart,
	FaceAttachment: Attachment,
	TargetPosition: Vector3,
	Duration: number,
	Style: string?,
	EasingStyle: Enum.EasingStyle?,
	EasingDirection: Enum.EasingDirection?,
	VisualizePath: boolean?
}

-- The primary object type defines every property and method attached to the instantiated table.
-- Defining internal methods (like _GetPositionAt) here ensures the strict typechecker tracks them properly.
export type BezierMover = {
	Config: BezierConfig,
	IsPlaying: boolean,
	IsPaused: boolean,
	_startPos: Vector3,
	_p1: Vector3,
	_p2: Vector3,
	_elapsedTime: number,
	_connection: RBXScriptConnection?,
	_completedEvent: BindableEvent,
	_waypointEvent: BindableEvent,
	Completed: RBXScriptSignal,
	WaypointReached: RBXScriptSignal,

	_GenerateControlPoints: (BezierMover) -> (),
	_GetPositionAt: (BezierMover, number) -> Vector3,
	_GetTangentAt: (BezierMover, number) -> Vector3,
	_DrawDebugPath: (BezierMover) -> (),

	Play: (BezierMover) -> (),
	Pause: (BezierMover) -> (),
	Resume: (BezierMover) -> (),
	Cancel: (BezierMover) -> (),
	Destroy: (BezierMover) -> ()
}

local BezierMover = {}
BezierMover.__index = BezierMover

-- Storing curve styles in a dictionary scales better than hardcoding strings throughout the logic.
-- If a new style is added, it only needs to be registered here and in the control point generator.
local CURVE_STYLES = {
	Standard = "Standard",
	ZigZag = "ZigZag",
	OverheadLoop = "OverheadLoop",
	Chaotic = "Chaotic",
	Boomerang = "Boomerang",
	GroundSkim = "GroundSkim",
	Orbit = "Orbit"
}

function BezierMover.new(config: BezierConfig): BezierMover
	-- Luau's strict mode blocks direct casting of newly attached metatables to exported type aliases.
	-- Casting the table to 'any' strips the internal metatable tracking.
	-- This bypasses the type error and allows the final return statement to enforce the BezierMover type.
	local self = setmetatable({}, BezierMover) :: any

	self.Config = config
	self.Config.Style = config.Style or CURVE_STYLES.Standard

	-- Using math.max prevents the user from accidentally passing a duration of 0.
	-- A duration of 0 causes a division by zero error when calculating the alpha during the RunService loop.
	self.Config.Duration = math.max(config.Duration, 0.01)
	self.Config.EasingStyle = config.EasingStyle or Enum.EasingStyle.Linear
	self.Config.EasingDirection = config.EasingDirection or Enum.EasingDirection.InOut

	self.IsPlaying = false
	self.IsPaused = false
	self._elapsedTime = 0

	-- Caching the starting position upon instantiation prevents the curve from breaking 
	-- if the TargetPart is accidentally bumped or moved by physics before Play() is called.
	self._startPos = config.TargetPart.Position

	self._completedEvent = Instance.new("BindableEvent")
	self._waypointEvent = Instance.new("BindableEvent")

	self.Completed = self._completedEvent.Event
	self.WaypointReached = self._waypointEvent.Event

	self:_GenerateControlPoints()

	if self.Config.VisualizePath then
		self:_DrawDebugPath()
	end

	return self :: BezierMover
end

function BezierMover._GenerateControlPoints(self: BezierMover)
	local p0 = self._startPos
	local p3 = self.Config.TargetPosition
	local distance = (p3 - p0).Magnitude

	local midPoint = p0:Lerp(p3, 0.5)
	local upVector = Vector3.new(0, 1, 0)
	local forwardVector = (p3 - p0).Unit

	-- The cross product calculates a vector perfectly perpendicular to both the forward and up vectors.
	-- This generates a localized right-side vector, ensuring horizontal offsets apply correctly 
	-- regardless of where the target is located in the world space.
	local rightVector = forwardVector:Cross(upVector).Unit
	if rightVector.Magnitude == 0 then
		rightVector = Vector3.new(1, 0, 0)
	end

	local style = self.Config.Style

	-- Modifying the control points (P1 and P2) dictates the physical bending of the curve.
	-- For example, pulling P1 backwards and upwards creates an initial arc, 
	-- while pushing P2 downwards forces a dive effect.
	if style == CURVE_STYLES.Standard then
		self._p1 = p0:Lerp(midPoint, 0.5) + Vector3.new(0, distance * 0.2, 0)
		self._p2 = midPoint:Lerp(p3, 0.5) + Vector3.new(0, distance * 0.2, 0)

	elseif style == CURVE_STYLES.ZigZag then
		self._p1 = p0:Lerp(midPoint, 0.5) + (rightVector * (distance * 0.4))
		self._p2 = midPoint:Lerp(p3, 0.5) - (rightVector * (distance * 0.4))

	elseif style == CURVE_STYLES.OverheadLoop then
		self._p1 = p0 + (forwardVector * (distance * 0.1)) + Vector3.new(0, distance * 0.9, 0)
		self._p2 = p3 + (forwardVector * -(distance * 0.2)) + Vector3.new(0, distance * 0.6, 0)

	elseif style == CURVE_STYLES.Chaotic then
		-- A localized Random object is created instead of using math.random.
		-- math.random shares a global seed, which causes repeating patterns if called by multiple scripts simultaneously.
		local rng = Random.new()
		self._p1 = p0 + Vector3.new(rng:NextNumber(-distance, distance), rng:NextNumber(0, distance), rng:NextNumber(-distance, distance))
		self._p2 = p3 + Vector3.new(rng:NextNumber(-distance, distance), rng:NextNumber(0, distance), rng:NextNumber(-distance, distance))

	elseif style == CURVE_STYLES.Boomerang then
		self._p1 = p3 + (forwardVector * distance) + (rightVector * (distance * 0.5))
		self._p2 = p3 - (forwardVector * (distance * 0.2)) + (rightVector * (distance * 0.5))

	elseif style == CURVE_STYLES.GroundSkim then
		self._p1 = p0 - Vector3.new(0, distance * 0.4, 0)
		self._p2 = p3 - Vector3.new(0, distance * 0.4, 0)

	elseif style == CURVE_STYLES.Orbit then
		self._p1 = p0 + (rightVector * distance) + Vector3.new(0, distance * 0.5, 0)
		self._p2 = p3 - (rightVector * distance) - Vector3.new(0, distance * 0.5, 0)
	else
		self._p1 = p0:Lerp(p3, 0.33)
		self._p2 = p0:Lerp(p3, 0.66)
	end
end

function BezierMover._GetPositionAt(self: BezierMover, t: number): Vector3
	local u = 1 - t
	local uu = u * u
	local uuu = uu * u
	local tt = t * t
	local ttt = tt * t

	-- This implements the mathematical formula for a cubic Bezier.
	-- Evaluating the polynomial directly at progress 't' prevents the need for recursive Lerping, 
	-- which heavily reduces processor overhead.
	local term1 = uuu * self._startPos
	local term2 = 3 * uu * t * self._p1
	local term3 = 3 * u * tt * self._p2
	local term4 = ttt * self.Config.TargetPosition

	return term1 + term2 + term3 + term4
end

function BezierMover._GetTangentAt(self: BezierMover, t: number): Vector3
	local u = 1 - t
	local tt = t * t
	local uu = u * u

	local p0 = self._startPos
	local p1 = self._p1
	local p2 = self._p2
	local p3 = self.Config.TargetPosition

	-- This calculates the derivative of the cubic function to find the tangent vector.
	-- Extracting the mathematical slope directly is highly accurate compared to checking the position 
	-- slightly ahead of the current frame, completely eliminating rotation jitter at high speeds.
	local term1 = 3 * uu * (p1 - p0)
	local term2 = 6 * u * t * (p2 - p1)
	local term3 = 3 * tt * (p3 - p2)

	local tangent = term1 + term2 + term3

	if tangent.Magnitude > 0 then
		return tangent.Unit
	else
		return Vector3.new(0, 0, -1) 
	end
end

function BezierMover._DrawDebugPath(self: BezierMover)
	local segments = 30
	local folder = Instance.new("Folder")
	folder.Name = "BezierDebug_" .. self.Config.TargetPart.Name
	folder.Parent = workspace

	for i = 0, segments do
		local t = i / segments
		local pos = self:_GetPositionAt(t)
		local tangent = self:_GetTangentAt(t)

		-- To accurately align debug markers to the curve, a full rotational matrix is required.
		-- By crossing the tangent with the global up vector, the true localized right vector is extracted.
		-- Crossing the right vector back against the tangent generates the true localized up vector.
		local up = Vector3.new(0, 1, 0)
		local right = tangent:Cross(up).Unit
		local realUp = right:Cross(tangent).Unit

		local marker = Instance.new("Part")
		marker.Size = Vector3.new(0.1, 0.1, 0.5)
		marker.Anchored = true
		marker.CanCollide = false
		marker.Material = Enum.Material.Neon
		marker.Color = Color3.new(1, 0, 0)

		-- Constructing a CFrame via fromMatrix applies the localized vectors directly, 
		-- pointing the debug parts identically to how the moving object will travel.
		marker.CFrame = CFrame.fromMatrix(pos, right, realUp, -tangent)
		marker.Parent = folder
	end

	game:GetService("Debris"):AddItem(folder, self.Config.Duration + 2)
end

function BezierMover.Play(self: BezierMover)
	if self.IsPlaying then return end

	self.IsPlaying = true
	self.IsPaused = false

	-- Heartbeat fires right before the physics step on every frame.
	-- Tying the calculation to Heartbeat prevents position stuttering caused by server latency.
	self._connection = RunService.Heartbeat:Connect(function(deltaTime)
		if self.IsPaused then return end

		-- Accumulating deltaTime calculates the exact time passed regardless of frame drops.
		self._elapsedTime += deltaTime
		local rawAlpha = math.clamp(self._elapsedTime / self.Config.Duration, 0, 1)

		-- TweenService:GetValue translates the linear time progress (rawAlpha) into an eased progression.
		-- This modifies the velocity along the path without altering the coordinate geometry of the path itself.
		local t = TweenService:GetValue(rawAlpha, self.Config.EasingStyle :: Enum.EasingStyle, self.Config.EasingDirection :: Enum.EasingDirection)

		local currentPos = self:_GetPositionAt(t)
		local tangentVector = self:_GetTangentAt(t)

		local baseCFrame = CFrame.lookAt(currentPos, currentPos + tangentVector)

		-- Inverting the Attachment's rotational matrix returns its opposite offset values.
		-- Multiplying the base CFrame by this inverse counters the default front-facing orientation,
		-- forcing the specified Attachment face to look forward along the curve.
		local attachmentOffset = self.Config.FaceAttachment.CFrame.Rotation:Inverse()
		self.Config.TargetPart.CFrame = baseCFrame * attachmentOffset

		-- The waypoint event fires precisely halfway through the animation progression.
		-- Subtracting the frame's progression step prevents the event from firing repeatedly if the alpha lingers near 0.5.
		if rawAlpha >= 0.5 and rawAlpha - (deltaTime / self.Config.Duration) < 0.5 then
			self._waypointEvent:Fire(0.5)
		end

		if rawAlpha >= 1 then
			self.Config.TargetPart.Position = self.Config.TargetPosition 
			self:Cancel()
			self._completedEvent:Fire()
		end
	end)
end

function BezierMover.Pause(self: BezierMover)
	self.IsPaused = true
end

function BezierMover.Resume(self: BezierMover)
	if self.IsPlaying and self.IsPaused then
		self.IsPaused = false
	end
end

function BezierMover.Cancel(self: BezierMover)
	self.IsPlaying = false
	if self._connection then
		-- Disconnecting the RunService connection immediately halts the physics loop.
		-- If this is neglected, abandoned loops will stack and degrade server performance permanently.
		self._connection:Disconnect()
		self._connection = nil
	end
end

function BezierMover.Destroy(self: BezierMover)
	self:Cancel()
	self._completedEvent:Destroy()
	self._waypointEvent:Destroy()

	-- table.clear purges all references inside the metatable object.
	-- This completely drops the data from memory, allowing the Luau garbage collector to reclaim it.
	table.clear(self)
end

return BezierMover

-- Integrating Custom Events and rigorous GC (Garbage Collection) logic solidifies this script's durability in production environments.
-- Firing custom BindableEvents connects isolated modules cleanly without tangling the codebase, 
-- and clearing the internal tables during destruction strictly addresses the memory constraints required for continuous, heavy ability usage.
