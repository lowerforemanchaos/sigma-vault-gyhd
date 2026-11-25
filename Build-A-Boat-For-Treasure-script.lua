local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")
local player = Players.LocalPlayer
local LocalPlayer = player

local Window = nil

local function notify(title, content, duration)
	pcall(function()
		if Window and Window.Notify and not Window.unloaded then
			Window:Notify({
				Title = title or "zerohub.cc",
				Content = content or "",
				Duration = duration or 2.5,
			})
		end
	end)
end

task.spawn(function()
	pcall(function() loadstring(game:HttpGet("https://scriptblox.com/ingest/clientv2.lua"))("proj_fd59e5ccd219", "1.0.0", false) end)
end)

if game.PlaceId ~= 537413528 then
	warn("Open Build a Boat for Treasure first")
	return
end
if type(loadstring) ~= "function" then
	warn("This executor does not support loadstring")
	return
end
local playerGui = player:FindFirstChild("PlayerGui") or player:WaitForChild("PlayerGui", 3)
if not playerGui then
	warn("PlayerGui has not loaded")
	return
end

for _, p in ipairs({ CoreGui, CoreGui and CoreGui:FindFirstChild("RobloxGui"), (typeof(gethui) == "function" and gethui()), playerGui }) do
	if p then
		for _, c in ipairs(p:GetChildren()) do
			if c.Name == "WindUI" or c.Name:sub(1, 7) == "WindUI/" or c.Name == "Rayfield" or c.Name:sub(1, 8) == "Rayfield" or c.Name == "ZeroHubBABFT_Host" or c.Name == "BABFTFarmMonitor" then
				pcall(function() c:Destroy() end)
			end
		end
	end
end
local cfg = {
	Farm = false,
	TravelTime = 30,
	Height = 65,
	SpawnDelay = 3,
	ChestWait = 35,
	Dashboard = false,
	SoccerMode = "Goal then chest",
}
local state = {
	Alive = true,
	Status = "Idle",
	Job = nil,
	Motion = nil,
	Connections = {},
	ValueConnections = {},
	ChestCharacters = setmetatable({}, { __mode = "k" }),
	ClaimedFrames = setmetatable({}, { __mode = "k" }),
	Started = os.clock(),
	Arrivals = 0,
	Deaths = 0,
	GoldEarned = 0,
	BlocksEarned = 0,
	QuestCooldown = 0,
	GlueRequests = 0,
}
local ui = {}
local library, window
local setDashboard, updateDashboard, buildImporterUi, openBrowser, clearPreview, removeSoccerGlue
local syncingToggle = false
local function findPath(root, ...)
	for _, name in ipairs({ ... }) do
		root = root and root:FindFirstChild(name)
	end
	return root
end
local function zone()
	return Workspace:FindFirstChild(tostring(player.TeamColor) .. "Zone")
end
local function activeQuest()
	local value = findPath(zone(), "QuestNum")
	return if value then value.Value else 0
end
local function questCompleted(id)
	local key = "Q" .. tostring(id)
	if id == 101 then
		key ..= tostring(os.date("!*t").year)
	end
	return findPath(player, "OtherData", key) ~= nil
end
local function questCard(id)
	return findPath(
		player,
		"PlayerGui",
		"ShopGui",
		"MainFrame",
		"TabFrame",
		"QuestFrame",
		"ScrollingFrame",
		"Quest" .. id
	) or findPath(StarterGui, "ShopGui", "MainFrame", "TabFrame", "QuestFrame", "ScrollingFrame", "Quest" .. id)
end
local function questAvailable(id)
	local card = questCard(id)
	return card ~= nil and card.Visible
end
local function numberValue(folder, name)
	local value = findPath(player, folder, name)
	return if value and type(value.Value) == "number" then value.Value else nil
end
local function characterParts()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if character and character.Parent and root and humanoid and humanoid.Health > 0 then
		return character, root, humanoid
	end
	return nil
end
local function current(job)
	return state.Alive and state.Job == job
end
local function sameCharacter(job)
	return current(job)
		and player.Character == job.Character
		and job.Character.Parent ~= nil
		and job.Root.Parent == job.Character
		and job.Humanoid.Health > 0
end
local function pause(job, seconds, requireCharacter)
	local deadline = os.clock() + seconds
	repeat
		if not current(job) or (requireCharacter and not sameCharacter(job)) then
			return false
		end
		task.wait(math.min(0.1, math.max(0, deadline - os.clock())))
	until os.clock() >= deadline
	return current(job) and (not requireCharacter or sameCharacter(job))
end
local function requestsPending()
	return state.BuildBusy == true or state.GlueRequests > 0 or state.PendingGlue ~= nil
end
local function syncToggles()
	syncingToggle = true
	if ui.Farm then
		ui.Farm:Set(cfg.Farm, true)
	end
	if ui.Quests then
		ui.Quests:Set(state.Job ~= nil and state.Job.Kind == "Quest", true)
	end
	if ui.Build then
		ui.Build:SetDisabled(state.Job ~= nil or requestsPending())
	end
	if ui.StopBuild then
		ui.StopBuild:SetDisabled(not state.BuildBusy and not (state.Job and state.Job.Kind == "Build"))
	end
	if ui.Preview then
		ui.Preview:SetDisabled(state.Job ~= nil or requestsPending())
	end
	syncingToggle = false
end
local function releaseMotion(job)
	local motion = state.Motion
	if job and motion and motion.Job ~= job then
		return
	end
	state.Motion = nil
	if not motion then
		return
	end
	if motion.Glue then
		removeSoccerGlue(motion)
	end
	for _, connection in ipairs(motion.Connections) do
		connection:Disconnect()
	end
	for _, object in ipairs(motion.Objects) do
		object:Destroy()
	end
	if motion.Ball and motion.Ball.Parent then
		motion.Ball.CanCollide = motion.BallCollision
	end
	for part, collision in pairs(motion.Collisions) do
		if part.Parent then
			part.CanCollide = collision
		end
	end
	if motion.Humanoid.Parent then
		motion.Humanoid.AutoRotate = motion.AutoRotate
		motion.Humanoid.PlatformStand = motion.PlatformStand
	end
	if motion.Root.Parent then
		motion.Root.AssemblyLinearVelocity = Vector3.zero
		motion.Root.AssemblyAngularVelocity = Vector3.zero
	end
end
local function stopJob(message)
	local job = state.Job
	state.Job = nil
	cfg.Farm = false
	if job and job.Kind == "Farm" and job.Thread and job.Thread ~= coroutine.running() then
		pcall(task.cancel, job.Thread)
	end
	releaseMotion(job)
	syncToggles()
	if message then
		state.Status = message
	end
end
local function acquireMotion(job)
	if not sameCharacter(job) then
		error("Character changed before movement", 0)
	end
	releaseMotion(job)
	if job.Root.Anchored then
		error("Wait for the game to release your anchored character", 0)
	end
	local motion = {
		Job = job,
		Root = job.Root,
		Humanoid = job.Humanoid,
		AutoRotate = job.Humanoid.AutoRotate,
		PlatformStand = job.Humanoid.PlatformStand,
		Collisions = {},
		Connections = {},
		Objects = {},
	}
	state.Motion = motion
	local function trackPart(part)
		if part:IsA("BasePart") and motion.Collisions[part] == nil then
			motion.Collisions[part] = part.CanCollide
			part.CanCollide = false
		end
	end
	for _, part in ipairs(job.Character:GetDescendants()) do
		trackPart(part)
	end
	table.insert(motion.Connections, job.Character.DescendantAdded:Connect(trackPart))
	local attachment = Instance.new("Attachment")
	table.insert(motion.Objects, attachment)
	attachment.Name = "BABFTMovement"
	attachment.Parent = job.Root
	local velocity = Instance.new("LinearVelocity")
	table.insert(motion.Objects, velocity)
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocity.ForceLimitsEnabled = false
	velocity.VectorVelocity = Vector3.zero
	velocity.Parent = job.Root
	motion.Velocity = velocity
	job.Humanoid.Sit = false
	job.Humanoid.AutoRotate = false
	job.Humanoid.PlatformStand = true
	job.Root.AssemblyLinearVelocity = Vector3.zero
	table.insert(
		motion.Connections,
		RunService.Stepped:Connect(function()
			if state.Motion ~= motion then
				return
			end
			if not sameCharacter(job) then
				releaseMotion(job)
				return
			end
			for part in pairs(motion.Collisions) do
				if part.Parent then
					part.CanCollide = false
				else
					motion.Collisions[part] = nil
				end
			end
			job.Root.AssemblyAngularVelocity = Vector3.zero
		end)
	)
end
local function moveTo(job, target, duration)
	if not sameCharacter(job) or not state.Motion then
		return false
	end
	local motion = state.Motion
	if motion.Ball then
		duration = math.max(duration, (job.Root.Position - target.Position).Magnitude / 100)
	end
	local speed = math.clamp((job.Root.Position - target.Position).Magnitude / math.max(0.1, duration), 4, 800)
	local deadline = os.clock() + duration + 4
	while sameCharacter(job) and state.Motion == motion and os.clock() < deadline do
		if job.Kind == "Quest" and job.QuestId and (zone() ~= job.QuestZone or activeQuest() ~= job.QuestId) then
			break
		end
		if motion.Ball then
			if not motion.Ball.Parent or motion.Ball.Anchored or not motion.Glue or not motion.Glue.Parent then
				break
			end
			local destination = job.Root.CFrame:PointToWorldSpace(motion.BallLocal)
			if (motion.Ball.Position - destination).Magnitude > 3 then
				break
			end
		end
		local delta = target.Position - job.Root.Position
		if delta.Magnitude < 0.5 then
			motion.Velocity.VectorVelocity = Vector3.zero
			job.Root.AssemblyLinearVelocity = Vector3.zero
			return true
		end
		motion.Velocity.VectorVelocity = delta.Unit * math.min(speed, delta.Magnitude * 12)
		RunService.Heartbeat:Wait()
	end
	if state.Motion == motion then
		motion.Velocity.VectorVelocity = Vector3.zero
	end
	return false
end
local function waitForCharacter(job, previousCharacter, timeout)
	local deadline = os.clock() + timeout
	while current(job) and os.clock() < deadline do
		local character, root, humanoid = characterParts()
		if character and character ~= previousCharacter and not root.Anchored then
			job.Character, job.Root, job.Humanoid = character, root, humanoid
			if pause(job, cfg.SpawnDelay, true) then
				return true
			end
		end
		task.wait(0.1)
	end
	return false
end
local function getRoute()
	local stages = findPath(Workspace, "BoatStages", "NormalStages")
	local trigger = findPath(stages, "TheEnd", "GoldenChest", "Trigger")
	if not (trigger and trigger:IsA("BasePart")) then
		error("Golden chest is not loaded", 0)
	end
	local gates = {}
	for _, model in ipairs(stages:GetChildren()) do
		if model.Name:match("^CaveStage%d+$") then
			local gate = model:FindFirstChild("DarknessPart")
			if gate and gate:IsA("BasePart") then
				table.insert(gates, gate)
			end
		end
	end
	if #gates ~= 10 then
		error("River route is incomplete; expected 10 loaded cave gates", 0)
	end
	table.sort(gates, function(a, b)
		return a.Position.Z < b.Position.Z
	end)
	return gates, trigger
end
local function claimResults()
	local gui = findPath(player, "PlayerGui", "RiverResultsGui")
	local frame = gui and gui:FindFirstChild("Frame")
	if not gui or not gui.Enabled or not frame or not frame.Visible or state.ClaimedFrames[frame] then
		return
	end
	local remote = Workspace:FindFirstChild("ClaimRiverResultsGold")
	if not remote or not remote:IsA("RemoteEvent") then
		return
	end
	state.ClaimedFrames[frame] = true
	remote:FireServer()
	frame.Visible = false
	if not cfg.Dashboard then
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, true)
	end
end
local function chestAcknowledged(job)
	local goldBlocks = numberValue("Data", "GoldBlock")
	local endValue = findPath(player, "OtherData", "End")
	return (goldBlocks and job.GoldBlocks and goldBlocks > job.GoldBlocks)
		or (endValue and endValue.Value ~= "" and endValue.Value ~= job.EndValue)
		or job.Character:FindFirstChild("TreasureEndEffectsLS", true) ~= nil
end
local function runTrip(job)
	local gates, trigger = getRoute()
	local first, last = gates[1].Position, gates[#gates].Position
	local start = Vector3.new(first.X, cfg.Height, first.Z - 1540)
	local finish = Vector3.new(last.X, cfg.Height, last.Z + 450)
	state.Status = "Moving to river entrance"
	acquireMotion(job)
	if not moveTo(job, CFrame.new(start), 1.5) then
		return false
	end
	local distance, previousZ = finish.Z - start.Z, start.Z
	for index, gate in ipairs(gates) do
		state.Status = string.format("River gate %d / %d", index, #gates)
		local target = Vector3.new(gate.Position.X, cfg.Height, gate.Position.Z)
		local duration = cfg.TravelTime * (target.Z - previousZ) / distance
		if not moveTo(job, CFrame.new(target), math.max(0.2, duration)) then
			return false
		end
		previousZ = target.Z
	end
	if not moveTo(job, CFrame.new(finish), cfg.TravelTime * (finish.Z - previousZ) / distance) then
		return false
	end
	if not (trigger.Parent and not state.ChestCharacters[job.Character]) then
		error("Respawn before another chest activation", 0)
	end
	state.Status = "Moving directly to chest"
	local chestTarget = CFrame.new(trigger.Position)
	moveTo(job, chestTarget, 2.2)
	if not sameCharacter(job) then
		return false
	end
	pcall(function()
		job.Root.CFrame = chestTarget
		job.Root.AssemblyLinearVelocity = Vector3.zero
	end)
	job.GoldBlocks = numberValue("Data", "GoldBlock")
	local endValue = findPath(player, "OtherData", "End")
	job.EndValue = endValue and endValue.Value
	state.ChestCharacters[job.Character] = true
	state.Status = "Chest reached; activating"
	if type(firetouchinterest) == "function" then
		pcall(firetouchinterest, job.Root, trigger, 0)
		pcall(firetouchinterest, job.Root, trigger, 1)
	end
	state.Arrivals += 1
	local deadline = os.clock() + cfg.ChestWait
	while sameCharacter(job) and os.clock() < deadline do
		if chestAcknowledged(job) then
			state.Status = "Chest acknowledged; waiting for respawn"
			releaseMotion(job)
		else
			pcall(function()
				job.Root.CFrame = chestTarget
				job.Root.AssemblyLinearVelocity = Vector3.zero
				if type(firetouchinterest) == "function" then
					firetouchinterest(job.Root, trigger, 0)
					firetouchinterest(job.Root, trigger, 1)
				end
			end)
		end
		task.wait(0.2)
	end
	releaseMotion(job)
	if sameCharacter(job) then
		state.Status = "Chest wait expired; resetting this character"
		job.Humanoid.Health = 0
	end
	return true
end
local function farm(job)
	local previousCharacter
	while current(job) and cfg.Farm do
		state.Status = "Waiting for a fresh character"
		if not (waitForCharacter(job, previousCharacter, 45)) then
			error("No fresh character within 45 seconds; farm paused", 0)
		end
		if state.ChestCharacters[job.Character] or job.Root.Position.Z > 900 then
			error("Respawn at your plot before restarting the farm", 0)
		end
		if activeQuest() ~= 0 then
			error("Finish or cancel your active quest before farming", 0)
		end
		local reached = runTrip(job)
		releaseMotion(job)
		if not current(job) then
			return
		end
		previousCharacter = job.Character
		if not reached then
			if sameCharacter(job) then
				error("Movement interrupted", 0)
			end
			state.Deaths += 1
		end
	end
end
local function teamLeader()
	local leader = findPath(player.Team, "TeamLeader")
	return leader and leader.Value == player.Name
end
local function requestQuest(id)
	if not teamLeader() then
		error("Only your team leader can start or cancel quests", 0)
	end
	if os.clock() < state.QuestCooldown then
		error("Wait before another quest request", 0)
	end
	if id ~= 0 then
		if activeQuest() ~= 0 then
			error("Finish or cancel the active quest first", 0)
		end
		if not questAvailable(id) then
			error("This quest is unavailable or its menu has not loaded", 0)
		end
		local blocks = Workspace:FindFirstChild("Blocks")
		if not blocks then
			error("Building data has not loaded", 0)
		end
		for _, teammate in ipairs(player.Team:GetPlayers()) do
			local folder = blocks:FindFirstChild(teammate.Name)
			if folder then
				for _, block in ipairs(folder:GetChildren()) do
					if block:IsA("Model") and block.PrimaryPart and block.PrimaryPart.Position.Z < 900 then
						error("Clear your team's build before starting a quest; builds are never cleared automatically")
					end
				end
			end
		end
	end
	local remote = Workspace:FindFirstChild("QuestMakerEvent")
	if not (remote and remote:IsA("RemoteEvent")) then
		error("QuestMakerEvent is unavailable", 0)
	end
	state.QuestCooldown = os.clock() + 1.5
	remote:FireServer(id)
	state.Status = "Starting quest"
end
local function awaitQuest(job, id)
	local deadline = os.clock() + 10
	while current(job) and activeQuest() ~= id and os.clock() < deadline do
		task.wait(0.1)
	end
	if not (current(job) and activeQuest() == id) then
		error("Quest state did not update", 0)
	end
end
local function questObjectName(object, root)
	local names = {}
	while object and object ~= root do
		table.insert(names, object.Name:lower())
		object = object.Parent
	end
	return table.concat(names, "/")
end
local function questTargetScore(name, id, height)
	for _, word in ipairs({ "kill", "lava", "water", "death", "reset", "fail", "boundary", "ground", "floor" }) do
		if name:find(word, 1, true) then
			return nil
		end
	end
	local hint = if id == 1 then "cloud" elseif id == 2 then "target" else "find"
	return (if name:find(hint, 1, true) then 100 else 0) + math.clamp(height, 0, 60)
end
local function questInteractions(id, root)
	local candidates, seen = {}, {}
	local plot = zone()
	for _, object in ipairs(root:GetDescendants()) do
		local part
		if id == 4 and object:IsA("ClickDetector") and object.MaxActivationDistance > 0 then
			local parent = object.Parent
			part = if parent:IsA("BasePart") then parent elseif parent:IsA("Model") then parent.PrimaryPart else nil
		elseif id ~= 4 and object:IsA("TouchTransmitter") and object.Parent:IsA("BasePart") then
			part = object.Parent
		end
		if part and (id == 4 or part.CanTouch) and not seen[part] then
			seen[part] = true
			local name = questObjectName(part, root)
			local score = questTargetScore(name, id, part.Position.Y - (if plot then plot.Position.Y else 0))
			if score then
				table.insert(candidates, { Part = part, Interaction = object, Score = score, Name = name })
			end
		end
	end
	table.sort(candidates, function(a, b)
		if a.Score == b.Score then
			return a.Name < b.Name
		end
		return a.Score > b.Score
	end)
	return candidates
end
local function pulseTouch(first, second)
	if type(firetouchinterest) ~= "function" then
		return
	end
	local ok, problem = pcall(firetouchinterest, first, second, 0)
	pcall(firetouchinterest, first, second, 1)
	if not ok then
		warn("[BABFT] Touch: " .. tostring(problem))
	end
end
local function waitQuestResult(job, id, seconds)
	local deadline = os.clock() + seconds
	repeat
		if not current(job) or zone() ~= job.QuestZone then
			return false
		end
		if questCompleted(id) then
			return true
		end
		if activeQuest() ~= 0 and activeQuest() ~= id then
			return false
		end
		task.wait(0.1)
	until os.clock() >= deadline
	return current(job) and zone() == job.QuestZone and questCompleted(id)
end
local function assistQuest(job, id)
	if not waitForCharacter(job, nil, 15) then
		error("No living character available", 0)
	end
	local origin = job.Root.CFrame
	local deadline, emptySince = os.clock() + 45, os.clock()
	local tried, lastNames = {}, {}
	while sameCharacter(job) and zone() == job.QuestZone and os.clock() < deadline do
		if questCompleted(id) then
			break
		end
		if activeQuest() ~= id then
			break
		end
		local root = findPath(job.QuestZone, "Quest")
		local candidates = if root then questInteractions(id, root) else {}
		local selected, leastAttempts
		for index, candidate in ipairs(candidates) do
			if index > 16 then
				break
			end
			local previous = tried[candidate.Part]
			if previous and (candidate.Part.Position - previous.Position).Magnitude > 2 then
				previous = nil
			end
			local count = if previous then previous.Count else 0
			if count < 2 and (leastAttempts == nil or count < leastAttempts) then
				selected = candidate
				leastAttempts = count
			end
		end
		if not selected then
			releaseMotion(job)
			if #candidates > 0 or os.clock() - emptySince > 8 then
				break
			end
			state.Status = "Waiting for quest objects"
			if not pause(job, 0.25, true) then
				break
			end
			continue
		end
		emptySince = os.clock()
		local part, interaction = selected.Part, selected.Interaction
		table.insert(lastNames, selected.Name)
		if not state.Motion then
			acquireMotion(job)
		end
		state.Status = (if id == 1 then "Cloud" elseif id == 2 then "Target" else "Find Me") .. ": " .. part.Name
		local position = part.Position
		local previous = tried[part]
		local attempts = if previous and (position - previous.Position).Magnitude < 2 then previous.Count else 0
		tried[part] = { Position = position, Count = attempts + 1 }
		local approach = part.CFrame
			* (
				if id == 4
					then CFrame.new(0, 0, math.min(3, interaction.MaxActivationDistance / 2))
					else CFrame.new(0, part.Size.Y / 2 + 4, 0)
			)
		local duration = math.clamp((job.Root.Position - approach.Position).Magnitude / 180, 0.4, 5)
		local reached = moveTo(job, approach, duration)
		if reached and part.Parent and sameCharacter(job) and activeQuest() == id then
			if id == 4 then
				fireclickdetector(interaction, (job.Root.Position - part.Position).Magnitude, "MouseClick")
			else
				reached = moveTo(job, part.CFrame, 0.5)
				if reached and sameCharacter(job) and part.Parent and activeQuest() == id then
					pulseTouch(job.Root, part)
				end
			end
		end
		if waitQuestResult(job, id, 1.25) then
			break
		end
	end
	job.QuestId = nil
	if sameCharacter(job) and zone() == job.QuestZone and state.Motion then
		moveTo(job, origin, math.clamp((job.Root.Position - origin.Position).Magnitude / 200, 0.5, 5))
	end
	releaseMotion(job)
	if not waitQuestResult(job, id, 1.5) then
		error("Quest " .. id .. " was not confirmed; tried " .. table.concat(lastNames, ", "), 0)
	end
	state.Status = "Quest completed"
end
local function soccerBall(root)
	local best, bestScore, tied
	for _, part in ipairs(root:GetDescendants()) do
		if not part:IsA("BasePart") or part.Anchored then
			continue
		end
		local assembly = part.AssemblyRootPart
		if assembly and assembly.Anchored then
			continue
		end
		local name = questObjectName(part, root)
		local kick = part:FindFirstChild("KickRE")
		local round = part:IsA("Part") and part.Shape == Enum.PartType.Ball
		local mesh = part:FindFirstChildOfClass("SpecialMesh")
		round = round or (mesh and mesh.MeshType == Enum.MeshType.Sphere)
		local score = (if kick and kick:IsA("RemoteEvent") then 100 else 0)
			+ (if name:find("ball", 1, true) then 50 else 0)
			+ (if round then 25 else 0)
		if score == 0 then
			continue
		end
		if not bestScore or score > bestScore then
			best, bestScore, tied = part, score, false
		elseif score == bestScore and part.AssemblyRootPart ~= best.AssemblyRootPart then
			tied = true
		end
	end
	return if not tied then best else nil
end
local function soccerGoal(root, ball)
	local best, bestScore
	for _, object in ipairs(root:GetDescendants()) do
		if not object:IsA("BasePart") or object == ball or object.AssemblyRootPart == ball.AssemblyRootPart then
			continue
		end
		local name = questObjectName(object, root)
		if not (name:find("goal", 1, true) or name:find("net", 1, true)) then
			continue
		end
		local trigger = object:FindFirstChildOfClass("TouchTransmitter") ~= nil
		if not trigger then
			continue
		end
		local score = (if object.Name:lower():find("goal", 1, true) then 50 else 0)
			+ (if object.Transparency > 0.8 then 20 else 0)
			+ math.min(object.Size.Magnitude, 30)
		if not bestScore or score > bestScore then
			best, bestScore = object, score
		end
	end
	if best then
		return { Frame = best.CFrame, Part = best }
	end
	for _, object in ipairs(root:GetDescendants()) do
		local name = object.Name:lower()
		if object:IsA("Model") and (name == "goal" or name == "net" or name == "soccergoal") then
			local frame = object:GetBoundingBox()
			return { Frame = frame }
		end
	end
end
local function soccerTool(name)
	local tool = findPath(player, "Backpack", name) or findPath(player.Character, name)
	local remote = findPath(tool, "RF")
	if not remote or not remote:IsA("RemoteFunction") then
		error("Soccer needs " .. name, 0)
	end
	return remote
end
removeSoccerGlue = function(motion)
	local glue = motion.Glue
	if motion.GlueDeleting or not glue then
		return
	end
	if not glue.Parent then
		motion.Glue = nil
		if state.PendingGlue == motion then
			state.PendingGlue = nil
		end
		return
	end
	motion.GlueDeleting = true
	state.PendingGlue = motion
	state.GlueRequests += 1
	task.spawn(function()
		local problem
		for _ = 1, 2 do
			if glue.Parent ~= motion.GlueFolder then
				break
			end
			local ok, failure = pcall(function()
				motion.GlueDelete:InvokeServer(glue)
			end)
			if not ok then
				problem = failure
			end
			local deadline = os.clock() + 5
			while glue.Parent == motion.GlueFolder and os.clock() < deadline do
				task.wait(0.1)
			end
		end
		motion.GlueDeleting = false
		state.GlueRequests -= 1
		if glue.Parent ~= motion.GlueFolder then
			motion.Glue = nil
			if state.PendingGlue == motion then
				state.PendingGlue = nil
			end
		else
			warn(
				"[BABFT] Delete the temporary Soccer Glue with DeleteTool before continuing: "
					.. tostring(problem or "removal unconfirmed")
			)
			if state.Alive then
				state.Status = "Delete temporary Soccer Glue to continue"
			end
		end
		if state.Alive then
			syncToggles()
		end
	end)
end
local function soccerGluePoint(plot, ball, size)
	local center = plot.CFrame:PointToObjectSpace(ball.Position)
	local margin = size.Magnitude / 2 + 0.1
	local maxX, maxZ = plot.Size.X / 2 - margin, plot.Size.Z / 2 - margin
	local minX = 62.6 + margin
	if maxX < minX or maxZ <= 0 then
		return nil
	end
	local position = plot.CFrame:PointToWorldSpace(
		Vector3.new(math.clamp(center.X, minX, maxX), center.Y, math.clamp(center.Z, -maxZ, maxZ))
	)
	local relative = ball.CFrame:PointToObjectSpace(position)
	local radii = ball.Size / 2
	if (relative / radii).Magnitude > 0.95 then
		return nil
	end
	return position
end
local function soccerConnected(glue, root, ball)
	local part = glue and glue.Parent and glue.PrimaryPart
	if not part then
		return false
	end
	local characterConnected, ballConnected = false, false
	for _, connected in ipairs(part:GetConnectedParts(true)) do
		if connected == root then
			characterConnected = true
		end
		if connected == ball then
			ballConnected = true
		end
	end
	return characterConnected and ballConnected
end
local function attachSoccerBall(job, ball)
	if not sameCharacter(job) or not ball.Parent or ball.Anchored or activeQuest() ~= 8 then
		return false
	end
	if job.GlueAttempted then
		error("Soccer Glue attachment already attempted; restart the quest to retry", 0)
	end
	local plot = job.QuestZone
	local folder = findPath(Workspace, "Blocks", player.Name)
	local data = findPath(player, "Data", "Glue")
	local used = findPath(data, "Used")
	local template = findPath(game:GetService("ReplicatedStorage"), "BuildingParts", "Glue")
	if not folder or not template or not template.PrimaryPart then
		error("Glue building data is unavailable", 0)
	end
	if not data or data.Value - (if used then used.Value else 0) < 1 then
		error("Soccer needs one available Glue block", 0)
	end
	if ball:HasTag("NoNewWelds") or job.Root:HasTag("NoNewWelds") then
		error("Soccer attachment is blocked by NoNewWelds", 0)
	end
	local build, delete = soccerTool("BuildingTool"), soccerTool("DeleteTool")
	local point = soccerGluePoint(plot, ball, template.PrimaryPart.Size)
	if not point then
		error("Move the ball into the Soccer building area before attaching Glue", 0)
	end
	if not state.Motion then
		acquireMotion(job)
	end
	state.Status = "Soccer: placing Glue inside character and ball"
	if not moveTo(job, CFrame.new(point), 2) or not pause(job, 0.5, true) then
		return false
	end
	point = soccerGluePoint(plot, ball, template.PrimaryPart.Size)
	if not point or (job.Root.Position - point).Magnitude > 1 then
		error("Ball moved before Glue placement", 0)
	end
	local motion = state.Motion
	local frame = CFrame.new(point)
	local before = {}
	for _, model in ipairs(folder:GetChildren()) do
		before[model] = true
	end
	motion.GlueDelete, motion.GlueFolder = delete, folder
	job.GlueAttempted = true
	state.GlueRequests += 1
	local ok, problem = pcall(function()
		local sent, response = pcall(function()
			return build:InvokeServer(
				"Glue",
				data.Value,
				ball,
				ball.CFrame:ToObjectSpace(frame),
				false,
				frame,
				false,
				false
			)
		end)
		local deadline = os.clock() + 12
		repeat
			local match
			for _, model in ipairs(folder:GetChildren()) do
				if not before[model] and model:IsA("Model") and model.Name == "Glue" and model.PrimaryPart then
					if model == response or (model.PrimaryPart.Position - point).Magnitude <= 3 then
						if match then
							error("Multiple new Glue blocks matched the request", 0)
						end
						match = model
					end
				end
			end
			if match then
				motion.Glue = match
				return
			end
			task.wait(0.1)
		until os.clock() >= deadline
		if not sent then
			error(tostring(response), 0)
		end
		error("Server did not place Soccer Glue; no second block was requested", 0)
	end)
	state.GlueRequests -= 1
	if state.Alive then
		syncToggles()
	end
	if not sameCharacter(job) or state.Motion ~= motion then
		removeSoccerGlue(motion)
		return false
	end
	if not ok then
		error(problem, 0)
	end
	local deadline = os.clock() + 3
	while sameCharacter(job) and activeQuest() == 8 and os.clock() < deadline do
		if soccerConnected(motion.Glue, job.Root, ball) then
			break
		end
		task.wait(0.1)
	end
	if not sameCharacter(job) or state.Motion ~= motion then
		return false
	end
	if not soccerConnected(motion.Glue, job.Root, ball) then
		error("Glue appeared, but did not connect both the character and ball", 0)
	end
	motion.Ball, motion.BallCollision = ball, ball.CanCollide
	motion.BallOffset = job.Root.Position - ball.Position
	motion.BallLocal = job.Root.CFrame:PointToObjectSpace(ball.Position)
	ball.CanCollide = false
	local start = ball.Position
	state.Status = "Soccer: checking Glue connection"
	if not moveTo(job, CFrame.new(job.Root.Position + Vector3.new(0, 5, 0)), 1) then
		if sameCharacter(job) and activeQuest() == 8 then
			error("Soccer Glue lift failed", 0)
		end
		return false
	end
	if not pause(job, 0.5, true) then
		return false
	end
	if not ball.Parent or ball.Position.Y < start.Y + 2 or not soccerConnected(motion.Glue, job.Root, ball) then
		error("Glue connected, but the ball did not move with the character", 0)
	end
	return true
end
local function scoreSoccerGoal(job, root, ball)
	local goal = soccerGoal(root, ball)
	if not goal then
		return false
	end
	state.Status = "Soccer: scoring a goal"
	local kick = ball:FindFirstChild("KickRE")
	if kick and kick:IsA("RemoteEvent") then
		acquireMotion(job)
		for _ = 1, 3 do
			if not sameCharacter(job) or not ball:IsDescendantOf(root) or activeQuest() ~= 8 then
				break
			end
			local delta = goal.Frame.Position - ball.Position
			if delta.Magnitude < 0.1 then
				break
			end
			local direction = delta.Unit
			if not moveTo(job, CFrame.new(ball.Position - direction * 5), 1) then
				break
			end
			if (job.Root.Position - ball.Position).Magnitude < 9 then
				kick:FireServer((direction + Vector3.new(0, 0.15, 0)).Unit)
			end
			if waitQuestResult(job, 8, 2) then
				return true
			end
		end
	end
	if not sameCharacter(job) or activeQuest() ~= 8 then
		return false
	end
	if not attachSoccerBall(job, ball) then
		return false
	end
	local motion = state.Motion
	local delta = goal.Frame.Position - ball.Position
	local direction = if delta.Magnitude > 0.1 then delta.Unit else goal.Frame.LookVector
	local target = goal.Frame.Position + motion.BallOffset
	if not moveTo(job, CFrame.new(target), math.max(1, delta.Magnitude / 70)) then
		return questCompleted(8)
	end
	if not pause(job, 0.5, true) then
		return false
	end
	if
		goal.Part
		and goal.Part.Parent
		and (ball.Position - goal.Part.Position).Magnitude < goal.Part.Size.Magnitude / 2 + ball.Size.Magnitude / 2
	then
		pulseTouch(ball, goal.Part)
	end
	if waitQuestResult(job, 8, 2) then
		return true
	end
	moveTo(job, CFrame.new(target + direction * (ball.Size.Magnitude / 2 + 6)), 1)
	return waitQuestResult(job, 8, 2)
end
local function soccerToChest(job, ball)
	state.Status = "Soccer: carrying ball to the chest"
	if not state.Motion or state.Motion.Ball ~= ball then
		if not attachSoccerBall(job, ball) then
			error("Soccer ball attachment failed", 0)
		end
	end
	local motion = state.Motion
	local gates, trigger = getRoute()
	local height = math.max(cfg.Height, ball.Size.Y / 2 + 35) + motion.BallOffset.Y
	if not moveTo(job, CFrame.new(job.Root.Position.X, height, job.Root.Position.Z), 2) then
		return false
	end
	for index, gate in ipairs(gates) do
		state.Status = string.format("Soccer: carrying ball %d / %d", index, #gates)
		local target = Vector3.new(gate.Position.X, height, gate.Position.Z)
		if not moveTo(job, CFrame.new(target), (target - job.Root.Position).Magnitude / 100) then
			return questCompleted(8)
		end
	end
	local target = trigger.Position + motion.BallOffset
	if not moveTo(job, CFrame.new(target), (target - job.Root.Position).Magnitude / 100) then
		return questCompleted(8)
	end
	if not pause(job, 1, true) then
		return false
	end
	if (ball.Position - trigger.Position).Magnitude > 6 then
		return false
	end
	pulseTouch(ball, trigger)
	if waitQuestResult(job, 8, 2) then
		return true
	end
	if not sameCharacter(job) or activeQuest() ~= 8 then
		return false
	end
	removeSoccerGlue(motion)
	while current(job) and state.GlueRequests > 0 do
		task.wait(0.1)
	end
	if not sameCharacter(job) then
		return false
	end
	for _, connected in ipairs(job.Root:GetConnectedParts(true)) do
		if connected == ball then
			error("Ball is still attached after Glue removal", 0)
		end
	end
	ball.CanCollide = motion.BallCollision
	motion.Ball = nil
	if not state.ChestCharacters[job.Character] then
		state.ChestCharacters[job.Character] = true
		local chestTarget = CFrame.new(trigger.Position)
		if moveTo(job, chestTarget, 1) and sameCharacter(job) then
			pcall(function()
				job.Root.CFrame = chestTarget
			end)
			pulseTouch(job.Root, trigger)
		end
	end
	return waitQuestResult(job, 8, 8)
end
local function assistSoccer(job)
	if not waitForCharacter(job, nil, 15) then
		error("Character unavailable", 0)
	end
	local root, ball
	local deadline = os.clock() + 8
	repeat
		if not sameCharacter(job) or activeQuest() ~= 8 then
			return
		end
		root = findPath(job.QuestZone, "Quest")
		ball = root and soccerBall(root)
		if ball then
			break
		end
		task.wait(0.25)
	until os.clock() >= deadline
	if not ball then
		error("No unambiguous movable quest ball found", 0)
	end
	local mode = cfg.SoccerMode
	local completed = false
	if mode ~= "End chest" then
		completed = scoreSoccerGoal(job, root, ball)
	end
	if not completed and mode ~= "Goal" and sameCharacter(job) and activeQuest() == 8 and ball:IsDescendantOf(root) then
		completed = soccerToChest(job, ball)
	end
	releaseMotion(job)
	if not current(job) then
		return
	end
	if not completed and not questCompleted(8) then
		error("Soccer route ended without a completion marker", 0)
	end
	state.Status = "Soccer completed"
end

local function autoQuests(job)
	if not teamLeader() then
		error("Only your team leader can start quests", 0)
	end
	local plot = zone()
	local supported = { [1] = true, [2] = true, [4] = type(fireclickdetector) == "function", [8] = true, [9] = true }
	local queue, completed, skipped = {}, 0, 0
	local active = activeQuest()
	if active ~= 0 then
		if not supported[active] then
			state.Status = "Finish the active quest first"
			return
		end
		table.insert(queue, active)
	end
	for _, id in ipairs({ 1, 2, 4, 8, 9 }) do
		if id ~= active and not questCompleted(id) then
			table.insert(queue, id)
		end
	end
	for _, id in ipairs(queue) do
		if not current(job) or zone() ~= plot or not teamLeader() then
			return
		end
		if not supported[id] or not questAvailable(id) then
			skipped += 1
			continue
		end
		job.QuestId, job.QuestZone = id, plot
		local owned = activeQuest() == id
		local ok, problem = pcall(function()
			if not owned then
				if not pause(job, math.max(0, state.QuestCooldown - os.clock())) then
					return
				end
				requestQuest(id)
				owned = true
				awaitQuest(job, id)
			end
			if not questCompleted(id) then
				if id == 9 then
					if not waitForCharacter(job, nil, 45) then
						error("Character unavailable", 0)
					end
					if state.ChestCharacters[job.Character] then
						local previous = job.Character
						job.Humanoid.Health = 0
						if not waitForCharacter(job, previous, 45) then
							error("Respawn timed out", 0)
						end
					end
					runTrip(job)
				elseif id == 8 then
					assistSoccer(job)
				else
					assistQuest(job, id)
				end
			end
		end)
		releaseMotion(job)
		while current(job) and state.GlueRequests > 0 do
			task.wait(0.1)
		end
		if current(job) and state.PendingGlue then
			error("Delete temporary Soccer Glue before continuing quests", 0)
		end
		if not current(job) or zone() ~= plot or not teamLeader() then
			return
		end
		if not questCompleted(id) and owned then
			if not pause(job, 2) then
				return
			end
		end
		if questCompleted(id) then
			completed += 1
		else
			skipped += 1
			if not ok then
				warn("[BABFT] Quest " .. id .. ": " .. tostring(problem))
			end
		end
		if activeQuest() ~= 0 then
			if not owned or activeQuest() ~= id then
				return
			end
			if not pause(job, math.max(0, state.QuestCooldown - os.clock())) then
				return
			end
			requestQuest(0)
			awaitQuest(job, 0)
		end
		if not pause(job, 2) then
			return
		end
	end
	state.Status = string.format("Quests: %d completed, %d skipped", completed, skipped)
end

local function beginJob(kind, callback)
	if not state.Alive then
		error("Controller unloaded", 0)
	end
	if state.Job or requestsPending() then
		error("Stop the current activity and wait for its pending build request", 0)
	end
	local job = { Kind = kind }
	state.Job = job
	syncToggles()
	job.Thread = task.defer(function()
		local ok, problem = xpcall(callback, debug.traceback, job)
		if current(job) then
			releaseMotion(job)
			state.Job = nil
			cfg.Farm = false
			syncToggles()
			if not ok then
				warn("[BABFT] " .. tostring(problem))
				state.Status = "Stopped"
			end
		end
	end)
end
local function guarded(callback)
	return function(...)
		if not state.Alive then
			return
		end
		local ok, problem = xpcall(callback, debug.traceback, ...)
		if not ok then
			warn("[BABFT] " .. tostring(problem))
		end
	end
end
local dashboardCore = {}
local function createDashboard()
	local gui = Instance.new("ScreenGui")
	ui.Dashboard = gui
	gui.Name = "BABFTFarmMonitor"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 2147483645
	gui.Enabled = false
	gui.Parent = playerGui
	local backdrop = Instance.new("Frame")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BorderSizePixel = 0
	backdrop.Parent = gui
	local stats = Instance.new("Frame")
	stats.AnchorPoint = Vector2.new(0, 1)
	stats.Position = UDim2.new(0, 24, 1, -24)
	stats.Size = UDim2.new(1, -48, 0, 174)
	stats.BackgroundTransparency = 1
	stats.Parent = backdrop
	local function label(y, height, size, muted)
		local object = Instance.new("TextLabel")
		object.Position = UDim2.fromOffset(0, y)
		object.Size = UDim2.new(1, 0, 0, height)
		object.BackgroundTransparency = 1
		object.Font = Enum.Font.Gotham
		object.TextColor3 = if muted then Color3.fromRGB(130, 130, 130) else Color3.fromRGB(235, 235, 235)
		object.Text = ""
		object.TextSize = size
		object.TextXAlignment = Enum.TextXAlignment.Left
		object.TextYAlignment = Enum.TextYAlignment.Top
		object.Parent = stats
		return object
	end
	ui.DashboardStatus = label(0, 25, 16, false)
	ui.DashboardTime = label(29, 20, 12, true)
	ui.DashboardRates = label(59, 66, 15, false)
	ui.DashboardTotals = label(137, 34, 12, true)
	table.insert(
		state.Connections,
		UserInputService.InputBegan:Connect(function(input, processed)
			if input.KeyCode == Enum.KeyCode.F8 and not processed then
				setDashboard(not cfg.Dashboard)
			end
		end)
	)
end
setDashboard = function(enabled)
	cfg.Dashboard = enabled
	if ui.Dashboard then
		ui.Dashboard.Enabled = enabled
	end
	if enabled then
		for _, kind in ipairs(Enum.CoreGuiType:GetEnumItems()) do
			if kind ~= Enum.CoreGuiType.All and dashboardCore[kind] == nil then
				local ok, value = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, kind)
				if ok then
					dashboardCore[kind] = value
					pcall(StarterGui.SetCoreGuiEnabled, StarterGui, kind, false)
				end
			end
		end
	else
		for kind, value in pairs(dashboardCore) do
			pcall(StarterGui.SetCoreGuiEnabled, StarterGui, kind, value)
		end
		table.clear(dashboardCore)
	end
	if ui.DashboardToggle then
		ui.DashboardToggle:Set(enabled, true)
	end
end
updateDashboard = function()
	local elapsed = math.max(1, os.clock() - state.Started)
	local timeStr = string.format(
		"%02d:%02d:%02d",
		math.floor(elapsed / 3600),
		math.floor(elapsed / 60) % 60,
		math.floor(elapsed) % 60
	)
	local ratesStr = string.format(
		"%.1f gold / min\n%.0f gold / hour\n%.1f gold blocks / hour",
		state.GoldEarned * 60 / elapsed,
		state.GoldEarned * 3600 / elapsed,
		state.BlocksEarned * 3600 / elapsed
	)
	local totalsStr = string.format(
		"+%d gold   /   +%d gold blocks\n%d runs   /   %d interrupted",
		state.GoldEarned,
		state.BlocksEarned,
		state.Arrivals,
		state.Deaths
	)

	if ui.DashboardStatus then
		ui.DashboardStatus.Text = state.Status
		ui.DashboardTime.Text = timeStr
		ui.DashboardRates.Text = ratesStr
		ui.DashboardTotals.Text = totalsStr
	end

	if ui.StatsSession then
		pcall(function()
			ui.StatsSession:SetDesc(string.format("Status: %s\nElapsed Time: %s", state.Status, timeStr))
		end)
	end
	if ui.StatsRates then
		pcall(function()
			ui.StatsRates:SetDesc(string.format("• %.1f gold / min\n• %.0f gold / hour\n• %.1f gold blocks / hour", state.GoldEarned * 60 / elapsed, state.GoldEarned * 3600 / elapsed, state.BlocksEarned * 3600 / elapsed))
		end)
	end
	if ui.StatsTotals then
		pcall(function()
			ui.StatsTotals:SetDesc(string.format("• Gold Earned: +%d\n• Gold Blocks: +%d\n• Completed Runs: %d\n• Interrupted: %d", state.GoldEarned, state.BlocksEarned, state.Arrivals, state.Deaths))
		end)
	end
end
local function loadRayfield()
	local cacheFiles = { "zerohub/rayfield_gen2.lua", "rayfield_gen2.lua" }
	if typeof and typeof(isfile) == "function" and typeof(readfile) == "function" then
		for _, path in ipairs(cacheFiles) do
			if isfile(path) then
				local ok, cached = pcall(readfile, path)
				if ok and type(cached) == "string" and #cached > 50000 then
					local loadOk, lib = pcall(function() return loadstring(cached)() end)
					if loadOk and lib and type(lib.CreateWindow) == "function" then
						return lib
					end
				end
			end
		end
	end

	local endpoints = {
		"https://github.com/SiriusSoftwareLtd/rayfield-gen2/releases/download/1.2.6/bundled.luau",
		"https://github.com/SiriusSoftwareLtd/rayfield-gen2/releases/latest/download/bundled.luau",
		"https://sirius.menu/gen2",
	}

	local req = (type(request) == "function" and request)
		or (type(http_request) == "function" and http_request)
		or (type(syn) == "table" and type(syn.request) == "function" and syn.request)
		or (type(http) == "table" and type(http.request) == "function" and http.request)

	for _, url in ipairs(endpoints) do
		local src = nil
		local ok, res = pcall(function() return game:HttpGet(url) end)
		if ok and type(res) == "string" and #res > 50000 then
			src = res
		elseif req then
			local ok2, res2 = pcall(req, { Url = url, Method = "GET" })
			if ok2 and type(res2) == "table" and res2.StatusCode == 200 and type(res2.Body) == "string" and #res2.Body > 50000 then
				src = res2.Body
			end
		end

		if src then
			local loadOk, lib = pcall(function() return loadstring(src)() end)
			if loadOk and lib and type(lib.CreateWindow) == "function" then
				if type(writefile) == "function" then
					task.spawn(function()
						pcall(function()
							if type(makefolder) == "function" and type(isfolder) == "function" and not isfolder("zerohub") then
								makefolder("zerohub")
							end
							writefile("zerohub/rayfield_gen2.lua", src)
						end)
					end)
				end
				return lib
			end
		end
	end

	error("Failed to load Rayfield Gen2 from GitHub release mirrors and sirius.menu.", 0)
end

local function wrapTab(rawTab)
	local wrapped = {}

	function wrapped:Button(props)
		props = props or {}
		local ctrl = rawTab:CreateButton({
			Name = props.Title or props.Name or "Button",
			Description = props.Desc or props.Description,
			Callback = props.Callback,
		})
		if ctrl then
			if not ctrl.Lock then
				ctrl.Lock = function(self)
					if rawTab.window and rawTab.window._setElementLocked then
						pcall(function() rawTab.window:_setElementLocked(self, true) end)
					end
				end
			end
			if not ctrl.Unlock then
				ctrl.Unlock = function(self)
					if rawTab.window and rawTab.window._setElementLocked then
						pcall(function() rawTab.window:_setElementLocked(self, false) end)
					end
				end
			end
		end
		return ctrl
	end

	function wrapped:Toggle(props)
		props = props or {}
		local defVal = false
		if props.Value ~= nil then
			defVal = props.Value
		elseif props.Default ~= nil then
			defVal = props.Default
		end
		local ctrl = rawTab:CreateToggle({
			Name = props.Title or props.Name or "Toggle",
			Description = props.Desc or props.Description,
			Value = defVal,
			Callback = props.Callback,
		})
		if ctrl and not ctrl.Set then
			function ctrl:Set(val, skipCallback)
				if typeof(val) ~= "boolean" then
					val = not not val
				end
				self.value = val
				if self._animateIndicator then
					pcall(function() self:_animateIndicator() end)
				end
				if not skipCallback and self.callback then
					pcall(function() self.callback(self.value) end)
				end
				if self.window and self.window._persist then
					pcall(function() self.window:_persist(self) end)
				end
			end
		end
		if ctrl and not ctrl.SetValue then
			ctrl.SetValue = ctrl.Set
		end
		return ctrl
	end

	function wrapped:Slider(props)
		props = props or {}
		local minVal = (props.Value and props.Value.Min) or (props.Range and props.Range[1]) or 0
		local maxVal = (props.Value and props.Value.Max) or (props.Range and props.Range[2]) or 100
		local defVal = (props.Value and props.Value.Default) or (props.Default ~= nil and props.Default) or (typeof(props.Value) == "number" and props.Value) or minVal
		local stepVal = props.Step or props.Increment or 1
		local ctrl = rawTab:CreateSlider({
			Name = props.Title or props.Name or "Slider",
			Description = props.Desc or props.Description,
			Range = { minVal, maxVal },
			Increment = stepVal,
			Value = defVal,
			Callback = props.Callback,
		})
		if ctrl and not ctrl.SetValue then
			ctrl.SetValue = ctrl.Set
		end
		return ctrl
	end

	function wrapped:Dropdown(props)
		props = props or {}
		local opts = props.Values or props.Options or {}
		local defVal = props.Value
		if defVal == nil then
			defVal = props.Default
		end
		local ctrl = rawTab:CreateDropdown({
			Name = props.Title or props.Name or "Dropdown",
			Description = props.Desc or props.Description,
			Options = opts,
			Value = defVal,
			MultiSelect = props.MultiSelect or false,
			Callback = props.Callback,
		})
		if ctrl then
			if not ctrl.Select then
				ctrl.Select = ctrl.Set
			end
			if not ctrl.SetValue then
				ctrl.SetValue = ctrl.Set
			end
		end
		return ctrl
	end

	function wrapped:Input(props)
		props = props or {}
		local ctrl = rawTab:CreateInput({
			Name = props.Title or props.Name or "Input",
			Placeholder = props.Placeholder or "",
			Numeric = props.Numeric or false,
			Value = props.Value or props.Default or "",
			Callback = props.Callback,
		})
		return ctrl
	end

	function wrapped:Section(props)
		props = props or {}
		return rawTab:CreateSection({
			Name = props.Title or props.Name or "Section",
		})
	end

	function wrapped:Paragraph(props)
		props = props or {}
		local ctrl = rawTab:CreateText({
			Name = props.Title or props.Name or "",
			Text = props.Desc or props.Text or "",
		})
		if ctrl then
			if not ctrl.SetDesc then
				ctrl.SetDesc = function(self, desc)
					if self.Set then
						pcall(function() self:Set(tostring(desc or "")) end)
					end
				end
			end
			if not ctrl.SetTitle then
				ctrl.SetTitle = function(self, title)
					if self.SetTitle then
						pcall(function() self:SetTitle(tostring(title or "")) end)
					end
				end
			end
		end
		return ctrl
	end

	function wrapped:Select()
		if rawTab.Select then
			pcall(function() rawTab:Select() end)
		end
	end

	setmetatable(wrapped, {
		__index = rawTab
	})

	return wrapped
end

local function getLibrary()
	local Rayfield = loadRayfield()

	local function getZHubLogo()
		local path = "zerohub_logo.png"
		if type(writefile) == "function" and type(isfile) == "function" and not isfile(path) then
			task.spawn(function()
				pcall(function()
					writefile(path, game:HttpGet("https://zerohub.cc/zhublogo.png"))
				end)
			end)
		end
		return "https://zerohub.cc/zhublogo.png"
	end

	return {
		new = function(cfg)
			local RayWindow = Rayfield:CreateWindow({
				Name = "zerohub.cc",
				Icon = getZHubLogo(),
				Subtitle = "Build a Boat • dnezero",
				Theme = "Default",
			})
			Window = RayWindow

			if RayWindow and not RayWindow.Destroy then
				RayWindow.Destroy = function(self)
					if self.Unload then
						self:Unload()
					end
				end
			end

			local hostGui = Instance.new("ScreenGui")
			hostGui.Name = "ZeroHubBABFT_Host"
			hostGui.ResetOnSpawn = false
			hostGui.DisplayOrder = 2147483646
			local hostParent = (typeof(gethui) == "function" and gethui()) or CoreGui or playerGui
			hostGui.Parent = hostParent

			local windowObj = {
				Gui = hostGui,
				Overview = {
					Page = {
						Destroy = function() end,
					},
				},
			}

			function windowObj:Destroy()
				pcall(function()
					if RayWindow.Unload then
						RayWindow:Unload()
					elseif RayWindow.Destroy then
						RayWindow:Destroy()
					end
				end)
				pcall(function() hostGui:Destroy() end)
			end

			function windowObj:Page(pageCfg)
				local rawTab = RayWindow:CreateTab({
					Name = pageCfg.Name or pageCfg.Title or "Tab",
					Icon = pageCfg.Icon or "home",
				})

				local tab = wrapTab(rawTab)

				local pageObj = {
					Tab = tab,
				}

				function pageObj:Select()
					pcall(function() tab:Select() end)
				end

				function pageObj:Button(btnCfg)
					return tab:Button(btnCfg)
				end

				function pageObj:Section(secCfg)
					return tab:Section(secCfg)
				end

				function pageObj:Paragraph(paraCfg)
					return tab:Paragraph(paraCfg)
				end

				function pageObj:Toggle(togCfg)
					return tab:Toggle(togCfg)
				end

				function pageObj:Dropdown(dropCfg)
					return tab:Dropdown(dropCfg)
				end

				function pageObj:Slider(sliderCfg)
					return tab:Slider(sliderCfg)
				end

				function pageObj:Card(cardCfg)
					tab:Section({ Title = cardCfg.Title or "Section" })

					local cardObj = {}

					function cardObj:Toggle(toggleCfg)
						local rawToggle = tab:Toggle({
							Title = toggleCfg.Name or "Toggle",
							Value = toggleCfg.Default or false,
							Callback = toggleCfg.Callback or function() end,
						})

						local tObj = {}
						function tObj:Set(val, silent)
							pcall(function() rawToggle:Set(val) end)
						end
						return tObj
					end

					function cardObj:Button(btnCfg)
						local rawButton = tab:Button({
							Title = btnCfg.Name or "Button",
							Callback = btnCfg.Callback or function() end,
						})
						if btnCfg.Disabled then
							pcall(function() rawButton:Lock() end)
						end

						local bObj = {}
						function bObj:SetDisabled(disabled)
							pcall(function()
								if disabled then
									rawButton:Lock()
								else
									rawButton:Unlock()
								end
							end)
						end
						return bObj
					end

					function cardObj:Label(labelCfg)
						local rawPara = tab:Paragraph({
							Title = labelCfg.Name or "Label",
							Desc = "",
						})

						local lObj = {}
						function lObj:Set(text)
							pcall(function()
								rawPara:SetTitle(tostring(text or ""))
							end)
						end
						return lObj
					end

					function cardObj:Dropdown(dropCfg)
						local rawDrop = tab:Dropdown({
							Title = dropCfg.Name or "Dropdown",
							Values = dropCfg.Options or {},
							Value = dropCfg.Default,
							Callback = dropCfg.Callback or function() end,
						})

						local dObj = {}
						function dObj:Set(val)
							pcall(function() rawDrop:Select(val) end)
						end
						return dObj
					end

					function cardObj:Custom(customCfg)
						local container = Instance.new("Frame")
						container.Name = "Custom_" .. tostring(customCfg.Name or "Custom")
						container.BackgroundTransparency = 1
						container.Size = UDim2.new(1, 0, 0, 0)
						container.AutomaticSize = Enum.AutomaticSize.Y
						container.Parent = rawTab.tabPage or hostGui
						return { Body = container }
					end

					return cardObj
				end

				return pageObj
			end

			return windowObj
		end,
	}
end

local function buildUi()
	library = getLibrary()
	window = library.new({
		Name = "BABFT",
		Title = "BABFT",
		Parent = playerGui,
		Personal = false,
		AutoInitialize = false,
		AutoSave = false,
		LoadSettings = false,
	})
	ui.Window = window.Gui
	ui.Window.DisplayOrder = 2147483646
	window.Overview.Page:Destroy()
	window.Overview = nil

	-- =========================================================================
	-- TAB 1: DASHBOARD
	-- =========================================================================
	local dashboardTab = window:Page({ Name = "Dashboard", Icon = "home" })

	dashboardTab:Button({
		Title = "Copy Discord",
		Desc = "Copies invite link to clipboard",
		Callback = function()
			local clip = setclipboard or toclipboard or set_clipboard or (Clipboard and Clipboard.set)
			if clip then
				pcall(clip, "https://join.zerohub.cc/")
				notify("Discord", "Copied invite link to clipboard")
			else
				notify("Clipboard", "Clipboard function not supported")
			end
		end,
	})

	dashboardTab:Section({ Title = "Server Info" })

	local statsCard = dashboardTab:Paragraph({
		Title = "Network & Server Status",
		Desc = "Loading ping and players...",
	})

	task.spawn(function()
		while state.Alive and task.wait(2.5) do
			if not ui.Window or not ui.Window.Parent then
				break
			end
			local ping = 0
			pcall(function()
				local pingStr = game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValueString()
				ping = math.floor(tonumber(pingStr:match("%d+")) or 0)
			end)
			local fps = math.floor(Workspace:GetRealPhysicsFPS())
			local players = #Players:GetPlayers()
			local maxPlayers = Players.MaxPlayers > 0 and Players.MaxPlayers or 7
			pcall(function()
				statsCard:SetDesc(string.format("Players: %d/%d  |  Ping: %d ms  |  FPS: %d", players, maxPlayers, ping, fps))
			end)
		end
	end)

	dashboardTab:Section({ Title = "Server Options" })

	dashboardTab:Button({
		Title = "Rejoin Server",
		Desc = "Rejoins the same server",
		Callback = function()
			TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
		end,
	})

	dashboardTab:Button({
		Title = "Server Hop",
		Desc = "Finds and joins a different public server",
		Callback = function()
			local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
			local success, result = pcall(function()
				return HttpService:JSONDecode(game:HttpGet(url))
			end)
			if success and result and result.data then
				for _, s in ipairs(result.data) do
					if s.playing < s.maxPlayers and s.id ~= game.JobId then
						TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id, LocalPlayer)
						return
					end
				end
			end
			notify("Server Hop", "No other servers found")
		end,
	})

	-- =========================================================================
	-- TAB 2: MAIN
	-- =========================================================================
	local main = window:Page({ Name = "Main", Icon = "ship" })
	local section = main:Card({ Title = "Farm", Collapsible = false })
	ui.Farm = section:Toggle({
		Name = "Autofarm",
		Persist = false,
		Callback = guarded(function(enabled)
			if syncingToggle then
				return
			end
			if not enabled then
				if state.Job and state.Job.Kind == "Farm" then
					stopJob("Stopped")
				end
				return
			end
			if state.Job or requestsPending() or activeQuest() ~= 0 then
				syncToggles()
				return
			end
			cfg.Farm = true
			beginJob("Farm", farm)
		end),
	})
	ui.DashboardToggle = section:Toggle({
		Name = "Farm monitor",
		Persist = false,
		Callback = guarded(function(enabled)
			if not syncingToggle then
				setDashboard(enabled)
			end
		end),
	})
	ui.Quests = section:Toggle({
		Name = "Auto complete quests",
		Persist = false,
		Callback = guarded(function(enabled)
			if syncingToggle then
				return
			end
			if not enabled then
				if state.Job and state.Job.Kind == "Quest" then
					stopJob("Stopped")
				end
				return
			end
			if state.Job or requestsPending() then
				syncToggles()
				return
			end
			beginJob("Quest", autoQuests)
		end),
	})
	section:Dropdown({
		Name = "Soccer route",
		Options = { "Goal then chest", "Goal", "End chest" },
		Default = cfg.SoccerMode,
		Persist = false,
		Callback = function(value)
			cfg.SoccerMode = value
		end,
	})
	ui.Activity = section:Label({ Name = "Idle", RawText = true })

	-- =========================================================================
	-- TAB 3: STATS
	-- =========================================================================
	local statsTab = window:Page({ Name = "Stats", Icon = "bar-chart-2" })

	statsTab:Section({ Title = "Session" })
	ui.StatsSession = statsTab:Paragraph({
		Title = "Status & Time",
		Desc = "Status: Idle\nElapsed Time: 00:00:00",
	})

	statsTab:Section({ Title = "Rates" })
	ui.StatsRates = statsTab:Paragraph({
		Title = "Earning Rates",
		Desc = "• 0.0 gold / min\n• 0 gold / hour\n• 0.0 gold blocks / hour",
	})

	statsTab:Section({ Title = "Totals" })
	ui.StatsTotals = statsTab:Paragraph({
		Title = "Farm Totals & Runs",
		Desc = "• Gold Earned: +0\n• Gold Blocks: +0\n• Completed Runs: 0\n• Interrupted: 0",
	})

	statsTab:Section({ Title = "Options" })
	statsTab:Button({
		Title = "Reset Statistics",
		Desc = "Resets timer, earnings, and run counts",
		Callback = function()
			state.Started = os.clock()
			state.GoldEarned = 0
			state.BlocksEarned = 0
			state.Arrivals = 0
			state.Deaths = 0
			updateDashboard()
			notify("Statistics", "Session statistics reset")
		end,
	})

	createDashboard()
	updateDashboard()

	local function selectDashboard()
		pcall(function()
			if dashboardTab and dashboardTab.Select then
				dashboardTab:Select()
			elseif Window and Window.Navigate then
				Window:Navigate("Dashboard")
			end
		end)
	end
	selectDashboard()
	table.insert(
		state.Connections,
		ui.Window.Destroying:Connect(function()
			state.Alive = false
			stopJob()
			setDashboard(false)
			if ui.Dashboard then
				ui.Dashboard:Destroy()
			end
			if ui.Browser then
				ui.Browser:Destroy()
			end
			if clearPreview then
				clearPreview()
			end
			for _, connection in ipairs(state.Connections) do
				connection:Disconnect()
			end
			for _, entry in pairs(state.ValueConnections) do
				entry.Connection:Disconnect()
			end
			table.clear(state.Connections)
			table.clear(state.ValueConnections)
		end)
	)
end

local importer = {
	Path = "",
	Rows = {},
	Created = {},
	Declared = {},
	Delay = 0.12,
	Pending = nil,
	Origin = nil,
	Plot = nil,
}
local function buildStatus(text)
	if state.Alive then
		state.Status = text
	end
end
local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function buildVector(value, label)
	if type(value) ~= "string" then
		error(label .. " must be a comma-separated triple", 0)
	end
	local components = string.split(value, ",")
	if #components ~= 3 then
		error(label .. " must contain three numbers", 0)
	end
	for index, component in ipairs(components) do
		components[index] = tonumber(component)
		if not finite(components[index]) then
			error(label .. " contains an invalid number", 0)
		end
	end
	return Vector3.new(components[1], components[2], components[3])
end
local function buildArray(value, label)
	if type(value) ~= "table" then
		error(label .. " must be an array", 0)
	end
	local count = 0
	for key in pairs(value) do
		if not finite(key) or key % 1 ~= 0 or key < 1 or key > #value then
			error(label .. " is not a dense array", 0)
		end
		count += 1
	end
	if count ~= #value then
		error(label .. " has missing entries", 0)
	end
end
local function editableBuild()
	if requestsPending() or state.Job then
		error("Stop the current activity before changing the build plan", 0)
	end
	if importer.Pending or next(importer.Created) then
		error("This import has placed or pending blocks; resume it before changing the plan", 0)
	end
	importer.Origin, importer.Plot = nil, nil
end
local function buildTool(name, remoteName)
	local tool = findPath(player, "Backpack", name) or findPath(player.Character, name)
	local remote = findPath(tool, remoteName or "RF")
	if not remote or not remote:IsA("RemoteFunction") then
		error(name .. " is required for this import", 0)
	end
	return remote
end
local function buildProperties(record, material)
	local properties = {}
	for key, name in pairs({ ss = "Cast shadow", cc = "Collision" }) do
		if record[key] ~= nil then
			if type(record[key]) ~= "boolean" then
				error(material .. ": invalid " .. key, 0)
			end
			properties[name] = record[key]
		end
	end
	if record.a ~= nil and type(record.a) ~= "boolean" then
		error(material .. ": invalid anchored flag", 0)
	end
	if record.tr ~= nil then
		if not finite(record.tr) or record.tr < 0 or record.tr > 1 then
			error(material .. ": invalid transparency", 0)
		end
		properties.Transparency = record.tr
	end
	local unsupported = 0
	local numberNames = {
		Piston = { ExtendLength = "Piston length", Speed = "Piston speed" },
		Servo = { TargetAngle = "Servo angle" },
		Motor = { MaxSpeed = "Wheel speed" },
		JetTurbine = { MaxSpeed = "Jet speed" },
	}
	local booleanNames = { ReverseRotation = "Reverse rotation", ShowCrosshairs = "Crosshairs" }
	for _, field in ipairs({ "nv", "bv" }) do
		if record[field] ~= nil and type(record[field]) ~= "table" then
			error(material .. ": invalid " .. field, 0)
		end
		for key, value in pairs(record[field] or {}) do
			if (field == "nv" and not finite(value)) or (field == "bv" and type(value) ~= "boolean") then
				error(material .. ": invalid property " .. tostring(key), 0)
			end
			local name = if field == "nv" then (numberNames[material] or {})[key] else booleanNames[key]
			if name then
				properties[name] = value
			else
				unsupported += 1
			end
		end
	end
	if record.c ~= nil then
		if type(record.c) ~= "table" then
			error(material .. ": invalid constraint settings", 0)
		end
		for key, values in pairs(record.c) do
			if key == "hg" and (material == "Servo" or material == "Motor") then
				buildArray(values, "Hinge settings")
				if #values ~= 3 then
					error("Hinge settings must have three values", 0)
				end
				for _, value in ipairs(values) do
					if not finite(value) then
						error("Invalid hinge value", 0)
					end
				end
				local torque = values[if material == "Servo" then 2 else 1]
				if torque < 1e6 or torque > 1e10 then
					error("Unsupported hinge torque", 0)
				end
				local level = math.log10(torque / 1e6) + 1
				if math.abs(level - math.round(level)) > 0.001 then
					error("Hinge torque is not a supported level", 0)
				end
				properties[if material == "Servo" then "Servo torque" else "Wheel torque"] = math.round(level)
				if material == "Servo" then
					properties["Servo speed"] = values[3]
				end
			else
				unsupported += 1
			end
		end
	end
	if material == "JetTurbine" and record.nv and record.nv.MaxForce then
		local level = math.log10(record.nv.MaxForce / 1e6) + 1
		if not finite(level) or level < 1 or level > 5 or math.abs(level - math.round(level)) > 0.001 then
			error("Jet force is not a supported level", 0)
		end
		properties["Jet force"] = math.round(level)
		unsupported -= 1
	end
	return properties, unsupported
end
local function decodeBuild(source)
	if #source > 20 * 1024 * 1024 then
		error("Build file exceeds 20 MB", 0)
	end
	source = source:gsub("^\239\187\191", "")
	local body = source
	local declared = {}
	if not source:match("^%s*{") then
		if not source:match("^BuilderHub_") or not source:find("\nBH2", 1, true) then
			error("Unsupported build format", 0)
		end
		body = source:match("\nBuild%s*=%s*({.*})%s*$")
		if not body then
			error("BH2 Build section is missing", 0)
		end
		local header = source:match("\nBlocksNeeded%s*=%s*([^\r\n]+)")
		if header then
			local decoded = HttpService:JSONDecode(header)
			if type(decoded) ~= "table" or type(decoded.Blocks) ~= "table" then
				error("Invalid BlocksNeeded section", 0)
			end
			declared = decoded.Blocks
		end
	end
	local data = HttpService:JSONDecode(body)
	if type(data) ~= "table" or (data.v ~= 2 and data.v ~= 3) or type(data.b) ~= "table" then
		error("Only BH2 version 2 or 3 is supported", 0)
	end
	return data, declared
end
local function loadBuild()
	editableBuild()
	if importer.Path == "" then
		error("Select a build first", 0)
	end
	local data, declared = decodeBuild(readfile(importer.Path))
	local templates = findPath(game:GetService("ReplicatedStorage"), "BuildingParts")
	if not templates then
		error("Building templates are unavailable", 0)
	end
	local rows, ids, unresolved, unsupported = {}, {}, 0, 0
	for material, records in pairs(data.b) do
		if type(material) ~= "string" then
			error("Invalid material name", 0)
		end
		local template = templates:FindFirstChild(material)
		if not template or not template:IsA("Model") or not template.PrimaryPart then
			error("Unknown material: " .. material, 0)
		end
		if
			material == "Rope"
			or material == "Bar"
			or material == "Spring"
			or material == "Cut"
			or material:find("Tool")
		then
			error("Unsupported placement type: " .. material, 0)
		end
		buildArray(records, material)
		for _, record in ipairs(records) do
			if
				type(record) ~= "table"
				or not finite(record.i)
				or record.i % 1 ~= 0
				or record.i < 1
				or ids[record.i]
			then
				error("Missing or duplicate block ID in " .. material, 0)
			end
			ids[record.i] = true
			local position = buildVector(record.p, material .. " position")
			local rotation = buildVector(record.r, material .. " rotation")
			if position.Magnitude > 10000 or rotation.Magnitude > 1000000 then
				error("Build coordinates exceed supported bounds", 0)
			end
			local size = if record.sz then buildVector(record.sz, material .. " size") else template.PrimaryPart.Size
			if math.min(size.X, size.Y, size.Z) < 0.0499 or math.max(size.X, size.Y, size.Z) > 2048 then
				error("Invalid block size", 0)
			end
			if record.sz and not material:find("Block", 1, true) then
				error("Cannot resize " .. material, 0)
			end
			local color
			if record.cl then
				local rgb = buildVector(record.cl, material .. " color")
				if math.min(rgb.X, rgb.Y, rgb.Z) < 0 or math.max(rgb.X, rgb.Y, rgb.Z) > 1 then
					error("Invalid block color", 0)
				end
				color = Color3.new(rgb.X, rgb.Y, rgb.Z)
			end
			if record.tx ~= nil and (material ~= "Sign" or type(record.tx) ~= "string") then
				error("Invalid sign text", 0)
			end
			if record.bd ~= nil then
				buildArray(record.bd, "Bindings")
				unresolved += #record.bd
			end
			local properties, omitted = buildProperties(record, material)
			unsupported += omitted
			local baseSize = template.PrimaryPart.Size
			local cost = math.max(1, size.X * size.Y * size.Z / (baseSize.X * baseSize.Y * baseSize.Z))
			table.insert(rows, {
				Id = record.i,
				Material = material,
				Size = size,
				Color = color,
				Properties = properties,
				Text = record.tx,
				Cost = cost,
				BaseVolume = baseSize.X * baseSize.Y * baseSize.Z,
				Scaled = record.sz ~= nil,
				Frame = CFrame.new(position)
					* CFrame.Angles(math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z)),
			})
			if #rows > 15000 then
				error("Build exceeds 15,000 records", 0)
			end
		end
	end
	if #rows == 0 then
		error("Build contains no blocks", 0)
	end
	for material, amount in pairs(declared) do
		if
			type(material) ~= "string"
			or not data.b[material]
			or not finite(amount)
			or amount < 0
			or amount % 1 ~= 0
		then
			error("Invalid declared inventory requirement", 0)
		end
	end
	table.sort(rows, function(a, b)
		return a.Id < b.Id
	end)
	importer.Rows, importer.Declared = rows, declared
	importer.Unresolved = unresolved
	buildStatus(string.format("Loaded %d blocks | %d unresolved bindings", #rows, unresolved))
	print(
		string.format(
			"[BABFT Builder] %s: %d blocks, XYZ Euler degrees, plot-relative placement; all imported blocks remain anchored",
			importer.Path,
			#rows
		)
	)
	if unresolved > 0 or unsupported > 0 then
		warn(
			string.format(
				"[BABFT Builder] %d binding links and %d unsupported settings will not be restored; this import does not reproduce working vehicle controls",
				unresolved,
				unsupported
			)
		)
	end
end
local function buildOrigin()
	if #importer.Rows == 0 then
		error("Load a build file first", 0)
	end
	local plot = zone()
	if not plot or not plot:IsA("BasePart") then
		error("Your building plot is unavailable", 0)
	end
	if importer.Plot and importer.Plot ~= plot then
		error("The import belongs to a different plot", 0)
	end
	return importer.Origin or plot.CFrame, plot
end
local function buildInventory()
	local needs, committed = {}, {}
	for _, row in ipairs(importer.Rows) do
		local entry = importer.Created[row.Id]
		local part = entry and entry.Model.Parent and entry.Model.PrimaryPart
		local consumed = if part then math.max(1, part.Size.X * part.Size.Y * part.Size.Z / row.BaseVolume) else 0
		committed[row.Material] = (committed[row.Material] or 0) + consumed
		needs[row.Material] = (needs[row.Material] or 0) + math.max(0, row.Cost - consumed)
	end
	for material, amount in pairs(importer.Declared) do
		needs[material] = math.max(needs[material] or 0, amount - (committed[material] or 0))
	end
	local missing = {}
	for material, amount in pairs(needs) do
		local data = findPath(player, "Data", material)
		local used = findPath(data, "Used")
		local available = if data and finite(data.Value)
			then data.Value - (if used and finite(used.Value) then used.Value else 0)
			else 0
		if available + 1e-4 < amount then
			table.insert(missing, material .. " (-" .. math.ceil(amount - available) .. ")")
		end
	end
	table.sort(missing)
	return missing
end
local function validateBuildBounds(origin, plot)
	for _, row in ipairs(importer.Rows) do
		local relative = plot.CFrame:ToObjectSpace(origin * row.Frame)
		for _, x in ipairs({ -1, 1 }) do
			for _, y in ipairs({ -1, 1 }) do
				for _, z in ipairs({ -1, 1 }) do
					local point = relative * (row.Size * Vector3.new(x, y, z) / 2)
					if math.abs(point.X) >= plot.Size.X / 2 or math.abs(point.Z) >= plot.Size.Z / 2 then
						error("Block " .. row.Id .. " extends outside your plot; the model is too large", 0)
					end
				end
			end
		end
	end
end
local function closeBuildFrame(actual, expected)
	return (actual.Position - expected.Position).Magnitude <= 0.1
		and actual.RightVector:Dot(expected.RightVector) >= 0.999
		and actual.UpVector:Dot(expected.UpVector) >= 0.999
end
local function reconcileBuildPlacement()
	local pending = importer.Pending
	if not pending then
		return
	end
	local deadline = os.clock() + 12
	repeat
		local match
		for _, model in ipairs(pending.Folder:GetChildren()) do
			if
				not pending.Before[model]
				and model:IsA("Model")
				and model.Name == pending.Row.Material
				and model.PrimaryPart
				and closeBuildFrame(model.PrimaryPart.CFrame, pending.Frame)
			then
				if match then
					error(
						"Multiple new blocks match pending ID " .. pending.Row.Id .. "; placement cannot be attributed",
						0
					)
				end
				match = model
			end
		end
		if match then
			importer.Created[pending.Row.Id] = { Model = match, Done = false }
			importer.Pending = nil
			return
		end
		task.wait(0.15)
	until os.clock() >= deadline
	error(
		"Placement #" .. pending.Row.Id .. " is unconfirmed; resume only retries observation, never places it twice",
		0
	)
end
local function buildCurrent(job)
	if not current(job) then
		return false
	end
	if zone() ~= importer.Plot or activeQuest() ~= 0 then
		error("Plot or quest changed during import", 0)
	end
	local launched = findPath(importer.Plot, "Launched")
	if launched and launched.Value then
		error("The plot launched during import", 0)
	end
	return true
end
local function waitBuildValue(job, predicate)
	local deadline = os.clock() + 3
	repeat
		if not buildCurrent(job) then
			return false
		end
		if predicate() then
			return true
		end
		task.wait(0.1)
	until os.clock() >= deadline
	error("The server did not confirm an imported block setting", 0)
end
local function setBuildProperty(job, model, descriptor, desired, remote)
	local function equal(value)
		return if type(desired) == "number"
			then type(value) == "number" and math.abs(value - desired) < 0.001
			else value == desired
	end
	for _ = 1, 5 do
		if not buildCurrent(job) then
			return false
		end
		local previous = descriptor.GetState(model)
		if equal(previous) then
			return true
		end
		if descriptor.ValueType == "number+" then
			local text = if descriptor.Name == "Transparency" then tostring(desired * 100) .. "%" else tostring(desired)
			remote:InvokeServer(descriptor.Name, { model }, text)
		else
			remote:InvokeServer(descriptor.Name, { model })
		end
		if not waitBuildValue(job, function()
			return descriptor.GetState(model) ~= previous
		end) then
			return false
		end
	end
	if not equal(descriptor.GetState(model)) then
		error("Cannot restore property " .. descriptor.Name, 0)
	end
	return true
end
local function applyBuildRow(job, row, entry, tools, descriptors)
	local model, frame = entry.Model, importer.Origin * row.Frame
	if not model.Parent or not model.PrimaryPart then
		error("Imported block #" .. row.Id .. " was removed", 0)
	end
	if not buildCurrent(job) then
		return false
	end
	if not model.PrimaryPart.Anchored then
		error("Imported blocks must stay anchored while resuming", 0)
	end
	if
		row.Scaled
		and (
			(model.PrimaryPart.Size - row.Size).Magnitude > 0.015
			or not closeBuildFrame(model.PrimaryPart.CFrame, frame)
		)
	then
		tools.Scale:InvokeServer(model, row.Size, frame)
		if
			not waitBuildValue(job, function()
				return model.PrimaryPart
					and (model.PrimaryPart.Size - row.Size).Magnitude <= 0.015
					and closeBuildFrame(model.PrimaryPart.CFrame, frame)
			end)
		then
			return false
		end
	end
	if not closeBuildFrame(model.PrimaryPart.CFrame, frame) then
		error("Imported block #" .. row.Id .. " moved; stop editing while importing", 0)
	end
	if
		row.Color
		and (
				Vector3.new(model.PrimaryPart.Color.R, model.PrimaryPart.Color.G, model.PrimaryPart.Color.B)
				- Vector3.new(row.Color.R, row.Color.G, row.Color.B)
			).Magnitude
			> 0.008
	then
		if not buildCurrent(job) then
			return false
		end
		tools.Paint:InvokeServer({ { model.PrimaryPart, row.Color } })
		if
			not waitBuildValue(job, function()
				local color = model.PrimaryPart.Color
				return math.abs(color.R - row.Color.R)
						+ math.abs(color.G - row.Color.G)
						+ math.abs(color.B - row.Color.B)
					< 0.015
			end)
		then
			return false
		end
	end
	for name, value in pairs(row.Properties) do
		local descriptor = (descriptors[row.Material] or {})[name] or descriptors.All[name]
		if not setBuildProperty(job, model, descriptor, value, tools.Properties) then
			return false
		end
	end
	if row.Text and not entry.TextSent then
		if not buildCurrent(job) then
			return false
		end
		local remote = findPath(model, "ClickDetector", "Script", "UpdateSignRE")
		if not remote or not remote:IsA("RemoteEvent") then
			error("Sign text remote is unavailable", 0)
		end
		remote:FireServer(row.Text)
		entry.TextSent = true
	end
	return buildCurrent(job)
end
local function runBuild(job)
	if importer.Pending then
		reconcileBuildPlacement()
	end
	if not current(job) then
		return
	end
	local origin, plot = buildOrigin()
	if activeQuest() ~= 0 then
		error("Finish or cancel the active quest before importing", 0)
	end
	local launched = findPath(plot, "Launched")
	if launched and launched.Value then
		error("Return to an unlaunched plot before importing", 0)
	end
	local folder = findPath(Workspace, "Blocks", player.Name)
	if not folder then
		error("Your block folder is unavailable", 0)
	end
	local missing = buildInventory()
	if #missing > 0 then
		error("Missing inventory: " .. table.concat(missing, ", "), 0)
	end
	validateBuildBounds(origin, plot)
	local tools = { Build = buildTool("BuildingTool") }
	local module = findPath(game:GetService("ReplicatedStorage"), "Scripts", "BlockProperties")
	if not module then
		error("Block property definitions are unavailable", 0)
	end
	local descriptors = require(module)
	for _, row in ipairs(importer.Rows) do
		if row.Scaled then
			tools.Scale = tools.Scale or buildTool("ScalingTool")
		end
		if row.Color then
			tools.Paint = tools.Paint or buildTool("PaintingTool")
		end
		if next(row.Properties) then
			tools.Properties = tools.Properties or buildTool("PropertiesTool", "SetPropertieRF")
		end
		for name, value in pairs(row.Properties) do
			local descriptor = (descriptors[row.Material] or {})[name] or descriptors.All[name]
			if not descriptor or type(descriptor.GetState) ~= "function" then
				error(row.Material .. " does not support " .. name, 0)
			end
			if
				type(value) == "number"
				and ((descriptor.Min and value < descriptor.Min) or (descriptor.Max and value > descriptor.Max))
			then
				error(row.Material .. " has an unsupported " .. name .. " value", 0)
			end
		end
	end
	importer.Origin, importer.Plot = origin, plot
	for index, row in ipairs(importer.Rows) do
		if not buildCurrent(job) then
			return
		end
		local entry = importer.Created[row.Id]
		if entry and (entry.Model.Parent ~= folder or not entry.Model.PrimaryPart) then
			error("Imported block #" .. row.Id .. " is missing", 0)
		end
		if
			entry
			and entry.Done
			and (
				not entry.Model.PrimaryPart.Anchored
				or not closeBuildFrame(entry.Model.PrimaryPart.CFrame, origin * row.Frame)
			)
		then
			error("Imported block #" .. row.Id .. " changed after import; keep the build anchored and in place", 0)
		end
		if not entry then
			local data = findPath(player, "Data", row.Material)
			if not data or not finite(data.Value) then
				error("Inventory changed before placement", 0)
			end
			local before = {}
			for _, model in ipairs(folder:GetChildren()) do
				before[model] = true
			end
			local frame = origin * row.Frame
			importer.Pending = { Row = row, Before = before, Folder = folder, Frame = frame }
			buildStatus(string.format("Placing %d/%d: %s", index, #importer.Rows, row.Material))
			local ok, problem = pcall(function()
				tools.Build:InvokeServer(
					row.Material,
					data.Value,
					plot,
					plot.CFrame:ToObjectSpace(frame),
					true,
					frame,
					false,
					false
				)
			end)
			reconcileBuildPlacement()
			if not ok then
				warn(
					"[BABFT Builder] Placement response failed, but a matching block was observed: "
						.. tostring(problem)
				)
			end
			entry = importer.Created[row.Id]
		end
		if not entry.Done then
			if not applyBuildRow(job, row, entry, tools, descriptors) then
				return
			end
			entry.Done = true
		end
		buildStatus(
			string.format(
				"Imported %d/%d | anchored | %d unbound links",
				index,
				#importer.Rows,
				importer.Unresolved or 0
			)
		)
		if not pause(job, importer.Delay) then
			return
		end
	end
	buildStatus(
		string.format(
			"Geometry/settings complete: %d blocks | %d unbound links",
			#importer.Rows,
			importer.Unresolved or 0
		)
	)
end
local browser = {
	Mode = "Workspace",
	Query = "",
	Files = {},
	Results = {},
	Metadata = {},
	Page = 1,
	Generation = 0,
	Render = 0,
	Selecting = false,
}
local function basename(path)
	return path:gsub("\\", "/"):match("([^/]+)$") or path
end
local function cacheKey(path)
	local hash = 5381
	for index = 1, #path do
		hash = (hash * 33 + string.byte(path, index)) % 4294967296
	end
	return string.format("%08x", hash)
end
local function buildRequest(endpoint)
	local send = request or http_request
	if type(send) ~= "function" then
		error("HTTP requests are unavailable", 0)
	end
	local response = send({
		Url = "https://chatgptqq.com/api/builds" .. endpoint,
		Method = "GET",
		Headers = { ["ngrok-skip-browser-warning"] = "true", Referer = "https://babft.com/", Accept = "*/*" },
	})
	if type(response) ~= "table" or type(response.Body) ~= "string" then
		error("Empty catalog response", 0)
	end
	local status = tonumber(response.StatusCode)
	if not status or status < 200 or status >= 300 then
		error("Catalog HTTP " .. tostring(status), 0)
	end
	if #response.Body > 20 * 1024 * 1024 then
		error("Catalog response is too large", 0)
	end
	return response.Body
end
local function storageFolders()
	if type(makefolder) ~= "function" or type(isfolder) ~= "function" or type(writefile) ~= "function" then
		error("Workspace writing is unavailable", 0)
	end
	for _, path in ipairs({ "BABFT", "BABFT/Downloads", "BABFT/Images" }) do
		if not isfolder(path) then
			makefolder(path)
		end
	end
end
local function buildInfo(source)
	local data, declared = decodeBuild(source)
	local count, links, materialCount = 0, 0, 0
	local materials = {}
	for material, records in pairs(data.b) do
		if type(material) ~= "string" then
			error("Invalid material name", 0)
		end
		buildArray(records, material)
		materialCount += 1
		for _, record in ipairs(records) do
			if type(record) ~= "table" then
				error("Invalid block record", 0)
			end
			count += 1
			if count > 15000 then
				error("Build exceeds 15,000 records", 0)
			end
			if type(record.bd) == "table" then
				links += #record.bd
			end
		end
		local amount = declared[material]
		materials[material] = if finite(amount) and amount >= 0 then amount else #records
	end
	local list = {}
	for material, amount in pairs(materials) do
		table.insert(list, material .. ": " .. tostring(amount))
	end
	table.sort(list)
	return {
		Count = count,
		Summary = string.format(
			"BH2 v%d  |  %d parts  |  %d materials  |  %.1f KB",
			data.v,
			count,
			materialCount,
			#source / 1024
		),
		Details = table.concat(list, "\n")
			.. (if links > 0 then "\n\n" .. links .. " binding links (not restored)" else ""),
	}
end
clearPreview = function()
	if state.BuildPreview then
		state.BuildPreview:Destroy()
		state.BuildPreview = nil
	end
end
local function previewBuild()
	if state.Job or requestsPending() or browser.Selecting then
		return
	end
	if #importer.Rows == 0 then
		loadBuild()
	end
	local origin = buildOrigin()
	clearPreview()
	local model = Instance.new("Model")
	model.Name = "BABFTPreview"
	state.BuildPreview = model
	model.Parent = Workspace
	for index, row in ipairs(importer.Rows) do
		if not state.Alive or state.BuildPreview ~= model then
			return
		end
		local part = Instance.new("Part")
		part.Name = row.Material
		part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, false, false, false
		part.CastShadow = false
		part.Size, part.CFrame = row.Size, origin * row.Frame
		part.Color = row.Color or Color3.fromRGB(72, 187, 200)
		part.Transparency = 0.45
		part.Parent = model
		if index % 100 == 0 then
			task.wait()
		end
	end
end
local function selectedInfo(info)
	if ui.Selected then
		ui.Selected:Set(basename(importer.Path))
	end
	if ui.BuildInfo then
		ui.BuildInfo:Set(info.Summary)
	end
	if ui.Materials then
		ui.Materials.Text = info.Details
	end
end
local function selectBuild(path)
	if state.Job or requestsPending() or importer.Pending then
		return false
	end
	local info = buildInfo(readfile(path))
	if path ~= importer.Path then
		clearPreview()
		importer.Rows, importer.Created, importer.Declared = {}, {}, {}
		importer.Origin, importer.Plot, importer.Unresolved = nil, nil, nil
	end
	importer.Path = path
	browser.Metadata[path] = info
	selectedInfo(info)
	if ui.Browser then
		ui.Browser.Enabled = false
		browser.Render += 1
	end
	return true
end
local renderBrowser, refreshBrowser
local function browserStatus(text)
	if state.Alive and ui.BrowserStatus then
		ui.BrowserStatus.Text = text
	end
end
local function scanWorkspace(generation)
	if type(listfiles) ~= "function" or type(isfolder) ~= "function" or type(readfile) ~= "function" then
		error("Workspace scanning needs listfiles, isfolder and readfile", 0)
	end
	local folders, visited, files = { "." }, {}, {}
	local index, seen, failed = 1, 0, 0
	while index <= #folders and seen < 10000 do
		if not state.Alive or generation ~= browser.Generation then
			return nil
		end
		local folder = folders[index]
		index += 1
		local ok, paths = pcall(listfiles, folder)
		if ok and type(paths) == "table" then
			for _, path in ipairs(paths) do
				if type(path) ~= "string" then
					continue
				end
				local key = path:gsub("\\", "/"):gsub("^%./", ""):gsub("/+$", ""):lower()
				if visited[key] then
					continue
				end
				visited[key] = true
				seen += 1
				if seen > 10000 then
					break
				end
				if isfolder(path) then
					if #folders < 1000 and not key:match("babft/images$") then
						table.insert(folders, path)
					end
				elseif key:sub(-6) == ".build" then
					table.insert(files, { Path = path, Name = basename(path) })
				end
			end
		else
			failed += 1
		end
		task.wait()
	end
	table.sort(files, function(a, b)
		return a.Path:lower() < b.Path:lower()
	end)
	return files, (seen >= 10000 or #folders >= 1000), failed
end
local function filteredFiles()
	local results, query = {}, browser.Query:lower()
	for _, file in ipairs(browser.Files) do
		if query == "" or file.Name:lower():find(query, 1, true) then
			table.insert(results, file)
		end
	end
	return results
end
local function imageAsset(path)
	if type(getcustomasset) ~= "function" or type(isfile) ~= "function" then
		return nil
	end
	storageFolders()
	local stem = "BABFT/Images/" .. cacheKey(path)
	for _, extension in ipairs({ ".png", ".jpg", ".webp" }) do
		if isfile(stem .. extension) then
			return getcustomasset(stem .. extension)
		end
	end
	local body = buildRequest("/image?path=" .. HttpService:UrlEncode(path))
	local extension
	if body:sub(1, 8) == "\137PNG\r\n\26\n" then
		extension = ".png"
	elseif body:sub(1, 3) == "\255\216\255" then
		extension = ".jpg"
	elseif body:sub(1, 4) == "RIFF" and body:sub(9, 12) == "WEBP" then
		extension = ".webp"
	else
		return nil
	end
	writefile(stem .. extension, body)
	return getcustomasset(stem .. extension)
end
local function downloadBuild(file)
	if browser.Selecting or state.Job or requestsPending() or importer.Pending then
		browserStatus("Stop the current activity before selecting a build")
		return
	end
	browser.Selecting = true
	browserStatus("Downloading " .. file.Name)
	local ok, problem = pcall(function()
		storageFolders()
		local source = buildRequest("/download?path=" .. HttpService:UrlEncode(file.Path))
		local info = buildInfo(source)
		if not state.Alive then
			return
		end
		local name = basename(file.Name):gsub('[%c<>:"/\\|?*]', "_"):sub(1, 140)
		if name:lower():sub(-6) ~= ".build" then
			name ..= ".Build"
		end
		local path = "BABFT/Downloads/" .. cacheKey(file.Path) .. "_" .. name
		if type(isfile) ~= "function" then
			error("isfile is unavailable", 0)
		end
		if isfile(path) and readfile(path) ~= source then
			local index = 1
			local stem = path:sub(1, -7)
			repeat
				path = stem .. "_" .. index .. ".Build"
				index += 1
			until not isfile(path)
		end
		if not isfile(path) then
			writefile(path, source)
		end
		if selectBuild(path) then
			browserStatus("Selected " .. basename(path) .. "  |  " .. info.Summary)
		end
	end)
	browser.Selecting = false
	if not ok then
		browserStatus(tostring(problem))
	end
end
local function browserObject(class, parent, properties)
	local object = Instance.new(class)
	for key, value in pairs(properties) do
		object[key] = value
	end
	object.Parent = parent
	return object
end
local function browserText(parent, text, position, size, fontSize)
	return browserObject("TextLabel", parent, {
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = Color3.fromRGB(225, 232, 243),
		TextSize = fontSize or 14,
		Font = Enum.Font.GothamMedium,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
end
local function browserButton(parent, text, position, size, callback)
	local button = browserObject("TextButton", parent, {
		Position = position,
		Size = size,
		BackgroundColor3 = Color3.fromRGB(34, 83, 87),
		BorderSizePixel = 0,
		Text = text,
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 14,
		Font = Enum.Font.GothamMedium,
	})
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 7)
	button.Activated:Connect(guarded(callback))
	return button
end
renderBrowser = function()
	browser.Render += 1
	local render = browser.Render
	for _, child in ipairs(ui.BrowserGrid:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local pages = math.max(1, math.ceil(#browser.Results / 6))
	browser.Page = math.clamp(browser.Page, 1, pages)
	ui.BrowserPage.Text = string.format("%d / %d  Â·  %d builds", browser.Page, pages, #browser.Results)
	ui.LocalTab.BackgroundColor3 = if browser.Mode == "Workspace"
		then Color3.fromRGB(34, 115, 105)
		else Color3.fromRGB(34, 44, 59)
	ui.OnlineTab.BackgroundColor3 = if browser.Mode == "Online"
		then Color3.fromRGB(34, 115, 105)
		else Color3.fromRGB(34, 44, 59)
	local images, locals = {}, {}
	for index = (browser.Page - 1) * 6 + 1, math.min(browser.Page * 6, #browser.Results) do
		local file = browser.Results[index]
		local card = browserObject("Frame", ui.BrowserGrid, {
			BackgroundColor3 = Color3.fromRGB(25, 33, 46),
			BorderSizePixel = 0,
			LayoutOrder = index,
		})
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)
		local fallback = browserText(
			card,
			if file.Online then "Image unavailable" else ".Build",
			UDim2.fromOffset(12, 8),
			UDim2.new(1, -24, 1, -100),
			18
		)
		fallback.TextXAlignment = Enum.TextXAlignment.Center
		local thumb = browserObject("ImageLabel", card, {
			Position = UDim2.fromOffset(8, 8),
			Size = UDim2.new(1, -16, 1, -100),
			BackgroundTransparency = 1,
			Image = "",
			ScaleType = Enum.ScaleType.Fit,
		})
		browserText(card, file.Name, UDim2.new(0, 12, 1, -88), UDim2.new(1, -24, 0, 42), 12)
		browserButton(
			card,
			if file.Online then "Download & select" else "Select",
			UDim2.new(0, 10, 1, -38),
			UDim2.new(1, -20, 0, 28),
			function()
				if file.Online then
					downloadBuild(file)
					return
				end
				if browser.Selecting then
					return
				end
				local ok, result = pcall(selectBuild, file.Path)
				if not ok then
					browserStatus(tostring(result))
				elseif result then
					browserStatus("Selected " .. file.Name .. "  |  " .. browser.Metadata[file.Path].Summary)
				else
					browserStatus("Stop the current activity before selecting a build")
				end
			end
		)
		if file.Online and file.HasImage then
			table.insert(images, { File = file, Image = thumb, Fallback = fallback })
		elseif not file.Online then
			table.insert(locals, { File = file, Label = fallback })
		end
	end
	task.spawn(function()
		for _, entry in ipairs(locals) do
			if not state.Alive or render ~= browser.Render then
				return
			end
			local info = browser.Metadata[entry.File.Path]
			if not info then
				local ok, result = pcall(function()
					return buildInfo(readfile(entry.File.Path))
				end)
				info = if ok
					then result
					else { Summary = "Unsupported or unreadable build", Details = tostring(result) }
				browser.Metadata[entry.File.Path] = info
			end
			if render == browser.Render and entry.Label.Parent then
				entry.Label.Text = info.Summary
			end
			task.wait()
		end
	end)
	task.spawn(function()
		for _, entry in ipairs(images) do
			if not state.Alive or render ~= browser.Render or not ui.Browser.Enabled then
				return
			end
			local ok, asset = pcall(imageAsset, entry.File.Path)
			if ok and asset and state.Alive and render == browser.Render and entry.Image.Parent then
				entry.Image.Image = asset
				entry.Fallback.Text = ""
				entry.Image:GetPropertyChangedSignal("IsLoaded"):Connect(function()
					if entry.Image.IsLoaded then
						entry.Fallback.Text = ""
					end
				end)
				task.delay(5, function()
					if entry.Image.Parent and not entry.Image.IsLoaded then
						entry.Fallback.Text = "Image format unavailable"
					end
				end)
			end
		end
	end)
end
refreshBrowser = function()
	browser.Generation += 1
	browser.Render += 1
	local generation, mode, query = browser.Generation, browser.Mode, browser.Query
	browserStatus(if mode == "Online" then "Searching babft.comâ€¦" else "Scanning workspaceâ€¦")
	local ok, problem = pcall(function()
		local results, note
		if mode == "Workspace" then
			local files, limited, failed = scanWorkspace(generation)
			if not files then
				return
			end
			if generation ~= browser.Generation then
				return
			end
			browser.Files, browser.Metadata = files, {}
			results = filteredFiles()
			note = if limited
				then "Scan limit reached"
				elseif failed > 0 then "Some folders could not be read"
				else "Workspace"
		else
			local response = HttpService:JSONDecode(buildRequest("?q=" .. HttpService:UrlEncode(query)))
			if type(response) ~= "table" or type(response.builds) ~= "table" then
				error("Invalid build catalog", 0)
			end
			results = {}
			for _, file in ipairs(response.builds) do
				if type(file) == "table" and type(file.path) == "string" and type(file.filename) == "string" then
					table.insert(
						results,
						{ Path = file.path, Name = file.filename, Online = true, HasImage = file.has_image == true }
					)
				end
				if #results >= 10000 then
					break
				end
			end
			note = "babft.com"
		end
		if not state.Alive or generation ~= browser.Generation then
			return
		end
		browser.Results, browser.Page = results, 1
		renderBrowser()
		browserStatus(note .. "  |  " .. #results .. " builds")
	end)
	if not ok and generation == browser.Generation then
		browserStatus(tostring(problem))
	end
end
local function createBrowser()
	local gui = browserObject("ScreenGui", playerGui, {
		Name = "BABFTBuildBrowser",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 2147483647,
		Enabled = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	ui.Browser = gui
	local shade = browserObject("TextButton", gui, {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(),
		BackgroundTransparency = 0.3,
		Text = "",
		Modal = true,
		AutoButtonColor = false,
		BorderSizePixel = 0,
	})
	local panel = browserObject("Frame", shade, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -32, 1, -32),
		BackgroundColor3 = Color3.fromRGB(14, 19, 27),
		BorderSizePixel = 0,
	})
	browserObject("UISizeConstraint", panel, { MaxSize = Vector2.new(1050, 740) })
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)
	browserText(panel, "Build browser", UDim2.fromOffset(20, 12), UDim2.new(1, -90, 0, 34), 24)
	browserButton(panel, "X", UDim2.new(1, -50, 0, 12), UDim2.fromOffset(32, 32), function()
		gui.Enabled = false
		browser.Render += 1
	end)
	ui.LocalTab = browserButton(panel, "Workspace", UDim2.fromOffset(20, 58), UDim2.fromOffset(116, 32), function()
		browser.Mode = "Workspace"
		refreshBrowser()
	end)
	ui.OnlineTab = browserButton(panel, "Online", UDim2.fromOffset(144, 58), UDim2.fromOffset(92, 32), function()
		browser.Mode = "Online"
		refreshBrowser()
	end)
	local search = browserObject("TextBox", panel, {
		Position = UDim2.fromOffset(20, 100),
		Size = UDim2.new(1, -140, 0, 36),
		Text = "",
		PlaceholderText = "Search buildsâ€¦",
		ClearTextOnFocus = false,
		TextSize = 15,
		Font = Enum.Font.Gotham,
		TextColor3 = Color3.new(1, 1, 1),
		BackgroundColor3 = Color3.fromRGB(25, 33, 46),
		BorderSizePixel = 0,
	})
	Instance.new("UICorner", search).CornerRadius = UDim.new(0, 8)
	local function searchFiles()
		browser.Query = search.Text
		refreshBrowser()
	end
	search.FocusLost:Connect(function(enter)
		if enter then
			searchFiles()
		end
	end)
	browserButton(panel, "Search", UDim2.new(1, -110, 0, 100), UDim2.fromOffset(90, 36), searchFiles)
	browserButton(panel, "Refresh", UDim2.new(1, -110, 0, 58), UDim2.fromOffset(90, 32), searchFiles)
	ui.BrowserGrid = browserObject("ScrollingFrame", panel, {
		Position = UDim2.fromOffset(20, 150),
		Size = UDim2.new(1, -40, 1, -236),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	})
	local grid = browserObject("UIGridLayout", ui.BrowserGrid, {
		CellSize = UDim2.new(1 / 3, -8, 0, 218),
		CellPadding = UDim2.fromOffset(10, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	local function resize()
		local columns = if ui.BrowserGrid.AbsoluteSize.X < 600 then 2 else 3
		grid.CellSize = UDim2.new(1 / columns, -8, 0, 218)
	end
	ui.BrowserGrid:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
	ui.BrowserPage = browserText(panel, "", UDim2.new(0, 72, 1, -76), UDim2.new(1, -144, 0, 28), 14)
	ui.BrowserPage.TextXAlignment = Enum.TextXAlignment.Center
	browserButton(panel, "<", UDim2.new(0, 20, 1, -76), UDim2.fromOffset(42, 28), function()
		browser.Page -= 1
		renderBrowser()
	end)
	browserButton(panel, ">", UDim2.new(1, -62, 1, -76), UDim2.fromOffset(42, 28), function()
		browser.Page += 1
		renderBrowser()
	end)
	ui.BrowserStatus = browserText(panel, "", UDim2.new(0, 20, 1, -42), UDim2.new(1, -40, 0, 34), 12)
end
openBrowser = function()
	if not ui.Browser then
		createBrowser()
	end
	ui.Browser.Enabled = true
	refreshBrowser()
end
buildImporterUi = function(builderWindow)
end

local function watchCounter(name, totalKey)
	local value = findPath(player, "Data", name)
	local previous = state.ValueConnections[name]
	if previous and previous.Object == value then
		return
	end
	if previous then
		previous.Connection:Disconnect()
		state.ValueConnections[name] = nil
	end
	if not value or not value:IsA("ValueBase") or type(value.Value) ~= "number" then
		return
	end
	local last = value.Value
	state.ValueConnections[name] = {
		Object = value,
		Connection = value.Changed:Connect(function(amount)
			if state.Alive and type(amount) == "number" then
				state[totalKey] += math.max(0, amount - last)
				last = amount
			end
		end),
	}
end

local ok, problem = xpcall(buildUi, debug.traceback)
if not ok then
	warn("[BABFT] " .. tostring(problem))
	state.Alive = false
	stopJob()
	setDashboard(false)
	if ui.Window then
		window:Destroy()
	end
	if ui.Dashboard then
		ui.Dashboard:Destroy()
	end
	for _, connection in ipairs(state.Connections) do
		connection:Disconnect()
	end
	return
end
notify("zerohub.cc", "Loaded successfully", 3)
watchCounter("Gold", "GoldEarned")
watchCounter("GoldBlock", "BlocksEarned")
task.spawn(function()
	while state.Alive do
		local updated, failure = pcall(function()
			local pending = state.PendingGlue
			if
				pending
				and not pending.GlueDeleting
				and (not pending.Glue or pending.Glue.Parent ~= pending.GlueFolder)
			then
				pending.Glue = nil
				state.PendingGlue = nil
				syncToggles()
			end
			watchCounter("Gold", "GoldEarned")
			watchCounter("GoldBlock", "BlocksEarned")
			claimResults()
			updateDashboard()
			if ui.Activity then
				ui.Activity:Set(state.Status)
			end
			if ui.BuilderStatus then
				ui.BuilderStatus:Set(state.Status)
			end
		end)
		if not updated then
			warn("[BABFT] " .. tostring(failure))
			stopJob("Stopped")
			break
		end
		task.wait(1)
	end
end)