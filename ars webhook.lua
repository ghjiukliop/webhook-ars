local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local hrp = character:WaitForChild("HumanoidRootPart")
local enemiesFolder = workspace:WaitForChild("__Main"):WaitForChild("__Enemies"):WaitForChild("Client")
local remote = ReplicatedStorage:WaitForChild("BridgeNet2"):WaitForChild("dataRemoteEvent")

local teleportEnabled = false
local killedNPCs = {}
local dungeonkill = {}
local selectedMobName = ""
local movementMethod = "Tween" -- Phương thức di chuyển mặc định
local farmingStyle = "Default" -- Phong cách farm mặc định

-- Tự động phát hiện HumanoidRootPart mới khi người chơi hồi sinh
player.CharacterAdded:Connect(function(newCharacter)
    character = newCharacter
    hrp = newCharacter:WaitForChild("HumanoidRootPart")
end)

local function anticheat()
    local player = game.Players.LocalPlayer
    if player and player.Character then
        local characterScripts = player.Character:FindFirstChild("CharacterScripts")
        
        if characterScripts then
            local flyingFixer = characterScripts:FindFirstChild("FlyingFixer")
            if flyingFixer then
                flyingFixer:Destroy()
            end

            local characterUpdater = characterScripts:FindFirstChild("CharacterUpdater")
            if characterUpdater then
                characterUpdater:Destroy()
            end
        end
    end
end

local function isEnemyDead(enemy)
    local healthBar = enemy:FindFirstChild("HealthBar")
    if healthBar and healthBar:FindFirstChild("Main") and healthBar.Main:FindFirstChild("Bar") then
        local amount = healthBar.Main.Bar:FindFirstChild("Amount")
        if amount and amount:IsA("TextLabel") and amount.ContentText == "0 HP" then
            return true
        end
    end
    return false
end

local function getNearestSelectedEnemy()
    local nearestEnemy = nil
    local shortestDistance = math.huge
    local playerPosition = hrp.Position

    for _, enemy in ipairs(enemiesFolder:GetChildren()) do
        if enemy:IsA("Model") and enemy:FindFirstChild("HumanoidRootPart") then
            local healthBar = enemy:FindFirstChild("HealthBar")
            if healthBar and healthBar:FindFirstChild("Main") and healthBar.Main:FindFirstChild("Title") then
                local title = healthBar.Main.Title
                if title and title:IsA("TextLabel") and title.ContentText == selectedMobName and not killedNPCs[enemy.Name] then
                    local enemyPosition = enemy.HumanoidRootPart.Position
                    local distance = (playerPosition - enemyPosition).Magnitude
                    if distance < shortestDistance then
                        shortestDistance = distance
                        nearestEnemy = enemy
                    end
                end
            end
        end
    end
    return nearestEnemy
end

local function getAnyEnemy()
    for _, enemy in ipairs(enemiesFolder:GetChildren()) do
        if enemy:IsA("Model") and enemy:FindFirstChild("HumanoidRootPart") and not dungeonkill[enemy.Name] then
            return enemy
        end
    end
    return nil
end

local function fireShowPetsRemote()
    local args = {
        [1] = {
            [1] = {
                ["Event"] = "ShowPets"
            },
            [2] = "\t"
        }
    }
    remote:FireServer(unpack(args))
end

local function getNearestEnemy()
    local nearestEnemy, shortestDistance = nil, math.huge
    local playerPosition = hrp.Position

    for _, enemy in ipairs(enemiesFolder:GetChildren()) do
        if enemy:IsA("Model") and enemy:FindFirstChild("HumanoidRootPart") and not killedNPCs[enemy.Name] then
            local distance = (playerPosition - enemy:GetPivot().Position).Magnitude
            if distance < shortestDistance then
                shortestDistance = distance
                nearestEnemy = enemy
            end
        end
    end
    return nearestEnemy
end

local function moveToTarget(target)
    if not target or not target:FindFirstChild("HumanoidRootPart") then return end
    local enemyHrp = target.HumanoidRootPart

    if movementMethod == "Teleport" then
        hrp.CFrame = enemyHrp.CFrame * CFrame.new(0, 0, 6)
    elseif movementMethod == "Tween" then
        local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Linear)
        local tween = TweenService:Create(hrp, tweenInfo, {CFrame = enemyHrp.CFrame * CFrame.new(0, 0, 6)})
        tween:Play()
    elseif movementMethod == "Walk" then
        hrp.Parent:MoveTo(enemyHrp.Position)
    end
end

local function teleportAndTrackDeath()
    while teleportEnabled do
        local target = getNearestEnemy()
        if target and target.Parent then
            anticheat()
            moveToTarget(target)
            task.wait(0.5)
            fireShowPetsRemote()
            remote:FireServer({
                {
                    ["PetPos"] = {},
                    ["AttackType"] = "All",
                    ["Event"] = "Attack",
                    ["Enemy"] = target.Name
                },
                "\7"
            })

            while teleportEnabled and target.Parent and not isEnemyDead(target) do
                task.wait(0.1)
            end

            killedNPCs[target.Name] = true
        end
        task.wait(0.2)
    end
end

local function teleportDungeon()
    while teleportEnabled do
        local target = getAnyEnemy()

        if target and target.Parent then
            anticheat()
            moveToTarget(target)
            task.wait(0.50)
            fireShowPetsRemote()
            remote:FireServer({
                {
                    ["PetPos"] = {},
                    ["AttackType"] = "All",
                    ["Event"] = "Attack",
                    ["Enemy"] = target.Name
                },
                "\7"
            })

            repeat task.wait() until not target.Parent or isEnemyDead(target)

            dungeonkill[target.Name] = true
        end
        task.wait()
    end
end

local function teleportToSelectedEnemy()
    while teleportEnabled do
        local target = getNearestSelectedEnemy()
        if target and target.Parent then
            anticheat()
            moveToTarget(target)
            task.wait(0.5)
            fireShowPetsRemote()

            remote:FireServer({
                {
                    ["PetPos"] = {},
                    ["AttackType"] = "All",
                    ["Event"] = "Attack",
                    ["Enemy"] = target.Name
                },
                "\7"
            })

            while teleportEnabled and target.Parent and not isEnemyDead(target) do
                task.wait(0.1)
            end

            killedNPCs[target.Name] = true
        end
        task.wait(0.20)
    end
end

local function attackEnemy()
    while damageEnabled do
        local targetEnemy = getNearestEnemy()
        if targetEnemy then
            local args = {
                [1] = {
                    [1] = {
                        ["Event"] = "PunchAttack",
                        ["Enemy"] = targetEnemy.Name
                    },
                    [2] = "\4"
                }
            }
            remote:FireServer(unpack(args))
        end
        task.wait(1)
    end
end

-- Farm Method Selection Dropdown
local Fluent
local SaveManager
local InterfaceManager

local success, err = pcall(function()
    Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
    SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
    InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()
end)

if not success then
    warn("Lỗi khi tải thư viện Fluent: " .. tostring(err))
    -- Thử tải từ URL dự phòng
    pcall(function()
        Fluent = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Fluent.lua"))()
        SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
        InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()
    end)
end

if not Fluent then
    error("Không thể tải thư viện Fluent. Vui lòng kiểm tra kết nối internet hoặc executor.")
    return
end

local Window = Fluent:CreateWindow({
    Title = "Kaihon Hub | Arise Crossover",
    SubTitle = "",
    TabWidth = 140,
    Size = UDim2.fromOffset(450, 350),
    Acrylic = false,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.LeftControl
})

local Tabs = {
    Discord = Window:AddTab({ Title = "INFO", Icon = ""}),
    Main = Window:AddTab({ Title = "Main", Icon = "" }),
    tp = Window:AddTab({ Title = "Teleports", Icon = "" }),
    mount = Window:AddTab({ Title = "Mount Location/farm", Icon = "" }),
    dungeon = Window:AddTab({ Title = "Dungeon ", Icon = "" }),
    pets = Window:AddTab({ Title = "Pets ", Icon = "" }),
    Player = Window:AddTab({ Title = "Player", Icon = "" }),
    misc = Window:AddTab({ Title = "misc", Icon = "" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" })
}

Tabs.Main:AddInput("MobNameInput", {
    Title = "Enter Mob Name",
    Default = "",
    Placeholder = "Type Here",
    Callback = function(text)
        selectedMobName = text
        killedNPCs = {} -- Đặt lại danh sách NPC đã tiêu diệt khi thay đổi mob
        print("Selected Mob:", selectedMobName) -- Gỡ lỗi
    end
})

Tabs.Main:AddToggle("FarmSelectedMob", {
    Title = "Farm Selected Mob",
    Default = false,
    Flag = "FarmSelectedMob", -- Thêm Flag để lưu cấu hình
    Callback = function(state)
        teleportEnabled = state
        damageEnabled = state -- Đảm bảo tính năng tấn công mobs được kích hoạt
        killedNPCs = {} -- Đặt lại danh sách NPC đã tiêu diệt khi bắt đầu farm
        if state then
            task.spawn(teleportToSelectedEnemy)
        end
    end
})

Tabs.Main:AddToggle("TeleportMobs", {
    Title = "Auto farm (nearest NPCs)",
    Default = false,
    Flag = "AutoFarmNearestNPCs", -- Thêm Flag để lưu cấu hình
    Callback = function(state)
        teleportEnabled = state
        if state then
            task.spawn(teleportAndTrackDeath)
        end
    end
})

local Dropdown = Tabs.Main:AddDropdown("MovementMethod", {
    Title = "Farming Method",
    Values = {"Tween", "Teleport"},
    Multi = false,
    Default = 1, -- Mặc định là "Tween"
    Flag = "FarmingMethod", -- Thêm Flag để lưu cấu hình
    Callback = function(option)
        movementMethod = option
    end
})

Tabs.Main:AddToggle("DamageMobs", {
    Title = "Damage Mobs ENABLE THIS",
    Default = false,
    Flag = "DamageMobs", -- Thêm Flag để lưu cấu hình
    Callback = function(state)
        damageEnabled = state
        if state then
            task.spawn(attackEnemy)
        end
    end
})



Tabs.dungeon:AddToggle("TeleportMobs", { 
    Title = "Auto farm Dungeon", 
    Default = false, 
    Flag = "AutoFarmDungeon", -- Thêm Flag để lưu cấu hình
    Callback = function(state) 
        teleportEnabled = state 
        if state then 
            task.spawn(teleportDungeon) 
        end 
    end 
})

Tabs.Main:AddToggle("GamepassShadowFarm", {
    Title = "Gamepass Shadow farm",
    Default = false,
    Callback = function(state)
        local attackatri = game:GetService("Players").LocalPlayer.Settings
        local atri = attackatri:GetAttribute("AutoAttack")
        
        if state then
            -- Bật tính năng
            if atri == false then
                attackatri:SetAttribute("AutoAttack", true)
            end
            print("Shadow farm đã bật")
        else
            -- Tắt tính năng
            attackatri:SetAttribute("AutoAttack", false)
            print("Shadow farm đã tắt")
        end
    end
})

local function SetSpawnAndReset(spawnName)
    local args = {
        [1] = {
            [1] = {
                ["Event"] = "ChangeSpawn",
                ["Spawn"] = spawnName
            },
            [2] = "\n"
        }
    }

    local remote = game:GetService("ReplicatedStorage"):WaitForChild("BridgeNet2"):WaitForChild("dataRemoteEvent")
    remote:FireServer(unpack(args))

    -- Đợi một chút trước khi hồi sinh (tùy chọn, để đảm bảo điểm hồi sinh được thiết lập)
    task.wait(0.5)

    -- Hồi sinh nhân vật
    local player = game.Players.LocalPlayer
if player.Character and player.Character.Parent then
    local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.Health = 0 -- Tạo ra cái chết tự nhiên mà không xóa nhân vật đột ngột
    end
end

end

Tabs.tp:AddButton({
    Title = "Brum Island",
    Description = "Set spawn & reset",
    Callback = function()
        SetSpawnAndReset("OPWorld") -- Thay đổi thành tên điểm hồi sinh đúng
    end
})

Tabs.tp:AddButton({
    Title = "Grass Village",
    Description = "Set spawn & reset",
    Callback = function()
        SetSpawnAndReset("NarutoWorld")
    end
})

Tabs.tp:AddButton({
    Title = "Solo City",
    Description = "Set spawn & reset",
    Callback = function()
        SetSpawnAndReset("SoloWorld")
    end
})

Tabs.tp:AddButton({
    Title = "Faceheal Town",
    Description = "Set spawn & reset",
    Callback = function()
        SetSpawnAndReset("BleachWorld")
    end
})

Tabs.tp:AddButton({
    Title = "Lucky island",
    Description = "Set spawn & reset",
    Callback = function()
        SetSpawnAndReset("BCWorld")
    end
})

local TweenService = game:GetService("TweenService")





-- Lấy Player và HumanoidRootPart
local TweenService = game:GetService("TweenService")
local player = game.Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local hrp = character:WaitForChild("HumanoidRootPart")

-- Cập nhật HRP khi nhân vật hồi sinh
player.CharacterAdded:Connect(function(newCharacter)
    character = newCharacter
    hrp = character:WaitForChild("HumanoidRootPart") -- Lấy HRP mới sau khi hồi sinh
end)

-- Hàm di chuyển (Luôn sử dụng HRP mới nhất)
local function teleportWithTween(targetCFrame)
    if hrp then
        local tweenInfo = TweenInfo.new(
            2, -- Thời gian (giây)
            Enum.EasingStyle.Sine,
            Enum.EasingDirection.Out,
            0, -- Không lặp lại
            false, -- Không đảo ngược
            0 -- Không độ trễ
        )

        local tweenGoal = {CFrame = targetCFrame}
        local tween = TweenService:Create(hrp, tweenInfo, tweenGoal)
        tween:Play()
    end
end


-- Locations List
local locations = {
    {Name = "Location 1", CFrame = CFrame.new(-6161.25781, 140.639832, 5512.9668, -0.41691944, -8.07482721e-08, 0.908943415, -2.94452178e-07, 1, -4.62235228e-08, -0.908943415, -2.86911842e-07, -0.41691944)},
    {Name = "Location 2", CFrame = CFrame.new(-5868.44141, 132.70488, 362.519379, 0.836233854, -7.47273816e-08, -0.548372984, 2.59595481e-07, 1, 2.59595481e-07, 0.548372984, -3.59437678e-07, 0.836233854)},
    {Name = "Location 3", CFrame = CFrame.new(-5430.81006, 107.441559, -5502.25244, 0.8239398, -3.60997859e-07, -0.566677332, 2.59595453e-07, 1, -2.59595396e-07, 0.566677332, 6.67841249e-08, 0.8239398)},
    {Name = "Location 4", CFrame = CFrame.new(-702.243225, 133.344467, -3538.11646, 0.978662074, 0.000114096198, -0.205476329, -0.000112703143, 1, 1.84834444e-05, 0.205476329, 5.06878177e-06, 0.978662074)},
    {Name = "Location 5", CFrame = CFrame.new(450.001709, 117.564827, 3435.4292, -0.999887109, -1.20863996e-12, 0.0150266131, -1.12492459e-12, 1, 5.57959278e-12, -0.0150266131, 5.56205906e-12, -0.999887109)},
    {Name = "Location 6", CFrame = CFrame.new(3230.96826, 135.41008, 36.1600113, -0.534268856, -4.75206689e-05, 0.845314622, -7.48304665e-05, 1, 8.92103617e-06, -0.845314622, -5.84890549e-05, -0.534268856)},
    {Name = "Location 7", CFrame = CFrame.new(4325.36523, 118.995422, -4819.78857, -0.257801384, 3.98855832e-07, -0.966197908, -5.63039578e-07, 1, 5.63040146e-07, 0.966197908, 6.89160231e-07, -0.257801384)}
    
    
}

-- Add buttons for each location
for _, loc in ipairs(locations) do
    Tabs.mount:AddButton({
        Title = loc.Name,
        Callback = function()
            teleportWithTween(loc.CFrame)
        end
    })
end


local autoDestroy = false
local autoArise = false

-- Function to Fire DestroyPrompt


local enemiesFolder = workspace:WaitForChild("__Main"):WaitForChild("__Enemies"):WaitForChild("Client")


local function fireDestroy()
    while autoDestroy do
        task.wait(0.3)  -- Delay to prevent overloading

        for _, enemy in ipairs(enemiesFolder:GetChildren()) do
            if enemy:IsA("Model") then
                local rootPart = enemy:FindFirstChild("HumanoidRootPart")
                local DestroyPrompt = rootPart and rootPart:FindFirstChild("DestroyPrompt")

                if DestroyPrompt then
                    DestroyPrompt:SetAttribute("MaxActivationDistance", 100000)
                    fireproximityprompt(DestroyPrompt)
                end
            end
        end
    end
end



-- Function to Fire ArisePrompt

local enemiesFolder = workspace:WaitForChild("__Main"):WaitForChild("__Enemies"):WaitForChild("Client")


local function fireArise()
    while autoArise do
        task.wait(0.3)  -- Delay to prevent overloading

        for _, enemy in ipairs(enemiesFolder:GetChildren()) do
            if enemy:IsA("Model") then
                local rootPart = enemy:FindFirstChild("HumanoidRootPart")
                local arisePrompt = rootPart and rootPart:FindFirstChild("ArisePrompt")

                if arisePrompt then
                    arisePrompt:SetAttribute("MaxActivationDistance", 100000)
                    fireproximityprompt(arisePrompt)
                end
            end
        end
    end
end





-- Auto Destroy Toggle
Tabs.Main:AddToggle("AutoDestroy", {
    Title = "Auto Destroy",
    Default = false,
    Flag = "MainAutoDestroy", -- Thêm Flag để lưu cấu hình
    Callback = function(state)
        autoDestroy = state
        if state then
            task.spawn(fireDestroy)
        end
    end
})

-- Auto Arise Toggle
Tabs.Main:AddToggle("AutoArise", {
    Title = "Auto Arise",
    Default = false,
    Flag = "MainAutoArise", -- Thêm Flag để lưu cấu hình
    Callback = function(state)
        autoArise = state
        if state then
            task.spawn(fireArise)
        end
    end
})

Tabs.dungeon:AddToggle("AutoDestroy", {
    Title = "Auto Destroy",
    Default = false,
    Flag = "DungeonAutoDestroy", -- Thêm Flag để lưu cấu hình
    Callback = function(state)
        autoDestroy = state
        if state then
            task.spawn(fireDestroy)
        end
    end
})

-- Auto Arise Toggle
Tabs.dungeon:AddToggle("AutoArise", {
    Title = "Auto Arise",
    Default = false,
    Flag = "DungeonAutoArise", -- Thêm Flag để lưu cấu hình
    Callback = function(state)
        autoArise = state
        if state then
            task.spawn(fireArise)
        end
    end
})


local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local hrp = character:WaitForChild("HumanoidRootPart")

local dungeonFolder = workspace:WaitForChild("__Main"):WaitForChild("__Dungeon")

-- Variable to control teleporting
local teleportingEnabled = false

-- Function to create a dungeon
local function createDungeon()
    print("[DEBUG] Đang cố gắng tạo dungeon...")
    local args = {
        [1] = {
            [1] = {
                ["Event"] = "DungeonAction",
                ["Action"] = "Create"
            },
            [2] = "\n" 
        }
    }
    ReplicatedStorage:WaitForChild("BridgeNet2"):WaitForChild("dataRemoteEvent"):FireServer(unpack(args))
    print("[DEBUG] Đã kích hoạt sự kiện tạo Dungeon!")
end

-- Function to start the dungeon
local function startDungeon()
    local dungeonInstance = dungeonFolder:FindFirstChild("Dungeon")
    if dungeonInstance then
        local dungeonID = dungeonInstance:GetAttribute("ID")
        if dungeonID then
            print("[DEBUG] Bắt đầu dungeon với ID:", dungeonID)
            local args = {
                [1] = {
                    [1] = {
                        ["Dungeon"] = dungeonID,
                        ["Event"] = "DungeonAction",
                        ["Action"] = "Start"
                    },
                    [2] = "\n"
                }
            }
            ReplicatedStorage:WaitForChild("BridgeNet2"):WaitForChild("dataRemoteEvent"):FireServer(unpack(args))
            print("[DEBUG] Đã kích hoạt sự kiện bắt đầu Dungeon!")
        else
            print("[LỖI] Không tìm thấy ID của Dungeon!")
        end
    else
        print("[LỖI] Không tìm thấy instance của Dungeon!")
    end
end

-- Function to teleport directly to an object and bypass anti-cheat
local function teleportToObject(object)
    if object and object:IsA("Part") then
        print("[DEBUG] Đang dịch chuyển đến:", object.Name)

        -- Vượt qua anti-cheat
        local f = player.Character and player.Character:FindFirstChild("CharacterScripts") and player.Character.CharacterScripts:FindFirstChild("FlyingFixer")
        if f then f:Destroy() else print("blablabla bleble") end

        local cha = player.Character and player.Character:FindFirstChild("CharacterScripts") and player.Character.CharacterScripts:FindFirstChild("CharacterUpdater")
        if cha then cha:Destroy() print("discord") else print("Cid") end

        -- Dịch chuyển trực tiếp
        hrp.CFrame = object.CFrame
        print("[DEBUG] Đã hoàn thành dịch chuyển đến:", object.Name)

        task.wait(2) -- Độ trễ nhỏ sau khi dịch chuyển
        createDungeon() -- Kích hoạt remote tạo dungeon

        task.wait(1) -- Độ trễ ngắn trước khi bắt đầu dungeon
        startDungeon() -- Kích hoạt remote bắt đầu dungeon
    else
        print("[LỖI] Mục tiêu dịch chuyển không hợp lệ!")
    end
end

-- Function to continuously teleport to objects when enabled
local function teleportLoop()
    while teleportingEnabled do
        print("[DEBUG] Đang tìm kiếm các đối tượng dungeon...")
        local foundObject = false
        for _, object in ipairs(dungeonFolder:GetChildren()) do
            if object:IsA("Part") then
                foundObject = true
                teleportToObject(object)
                task.wait(1) -- Ngăn thực thi quá mức
            end
        end
        if not foundObject then
            print("[CẢNH BÁO] Không tìm thấy đối tượng dungeon hợp lệ!")
        end
        task.wait(0.5) -- Độ trễ trước khi kiểm tra lại
    end
end



-- Add the toggle button to start/stop teleporting
Tabs.dungeon:AddToggle("TeleportToDungeon", {
    Title = "Teleport to Dungeon",
    Default = false,
    Callback = function(state)
        teleportingEnabled = state
        print("[DEBUG] Đã bật/tắt dịch chuyển:", state)
        if state then
            task.spawn(teleportLoop) -- Bắt đầu vòng lặp dịch chuyển khi bật
        end
    end
})


local AutoDetectToggle = Tabs.dungeon:AddToggle("AutoDetectDungeon", {Title = "Auto Detect Dungeon (KEEP THIS ON)", Default = true})

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local villageSpawns = {
    ["Grass Village"] = "NarutoWorld",
    ["BRUM ISLAND"] = "OPWorld",
    ["Leveling City"] = "SoloWorld",
    ["FACEHEAL TOWN"] = "BleachWorld",
    ["Lucky"] = "BCWorld"
}

local function SetSpawnAndReset(spawnName)
    local args = {
        [1] = {
            [1] = {
                ["Event"] = "ChangeSpawn",
                ["Spawn"] = spawnName
            },
            [2] = "\n"
        }
    }

    local remote = ReplicatedStorage:WaitForChild("BridgeNet2"):WaitForChild("dataRemoteEvent")
    remote:FireServer(unpack(args))

    -- Đợi một chút trước khi hồi sinh (tùy chọn, để đảm bảo điểm hồi sinh được thiết lập)
    task.wait(0.5)

    -- Hồi sinh nhân vật
    if player.Character then
        player.Character:BreakJoints() -- Buộc nhân vật phải hồi sinh
    end
end

local function detectDungeon()
    player.PlayerGui.Warn.ChildAdded:Connect(function(dungeon)
        if dungeon:IsA("Frame") and AutoDetectToggle.Value then
            print("Đã phát hiện Dungeon!")
            for _, child in ipairs(dungeon:GetChildren()) do
                if child:IsA("TextLabel") then
                    for village, spawnName in pairs(villageSpawns) do
                        if string.find(string.lower(child.Text), string.lower(village)) then
                            teleportEnabled = false
                            print("Đã phát hiện làng:", village)
                            SetSpawnAndReset(spawnName)
                            return
                        end
                    end
                end
            end
        end
    end)
end

-- Đảm bảo hàm hoạt động
AutoDetectToggle:OnChanged(function(value)
    if value then
        detectDungeon()
    end
end)

detectDungeon()

local function resetAutoFarm()
    -- Đặt lại tất cả trạng thái và hàm
    killedNPCs = {} -- Đặt lại số lượng NPC đã tiêu diệt

    print("AutoFarm đã được đặt lại!") -- In thông báo xác nhận

    -- Khởi động lại tất cả các hàm nếu cần
end

task.spawn(function()
    while true do
        task.wait(120) -- Đợi 120 giây
        resetAutoFarm() -- Gọi hàm đặt lại
    end
end)

local rankMapping = { "E", "D", "C", "B", "A", "S", "SS" }

-- Dropdown để chọn các cấp độ để bán
local SellDropdown = Tabs.pets:AddDropdown("ChooseRankToSell", {
    Title = "Choose Rank to Sell",
    Values = rankMapping,
    Multi = true,
    Default = {}
})

-- Dropdown để chọn pet cần giữ lại
local KeepPetsDropdown = Tabs.pets:AddDropdown("ChoosePetsToKeep", {
    Title = "Pets to Not Delete",
    Values = {},
    Multi = true,
    Default = {}
})

-- Nút để làm mới dropdown "Keep Pets"
Tabs.pets:AddButton({
    Title = "Refresh Keep Pets List",
    Callback = function()
        updateKeepPetsDropdown()
    end
})

-- Hàm để lấy pet theo cấp độ đã chọn
local function getPetsByRank(selectedRanks, keepPets)
    local player = game:GetService("Players").LocalPlayer
    local petsFolder = player.leaderstats.Inventory:FindFirstChild("Pets")
    if not petsFolder then return {} end

    local petsByRank = {}  -- Lưu trữ pet theo cấp độ
    local petsToSell = {}  -- Các pet sẽ được bán
    local keepOnePet = {}  -- Đảm bảo chỉ giữ 1 pet mỗi loại đã chọn

    for _, pet in ipairs(petsFolder:GetChildren()) do
        local rankValue = pet:GetAttribute("Rank")
        local petName = pet.Name

        if rankValue and rankMapping[rankValue] and selectedRanks[rankMapping[rankValue]] then
            petsByRank[rankMapping[rankValue]] = petsByRank[rankMapping[rankValue]] or {}
            table.insert(petsByRank[rankMapping[rankValue]], petName)
        end
    end

    -- Xử lý từng cấp độ
    for rank, petList in pairs(petsByRank) do
        table.sort(petList) -- Sắp xếp pet để đảm bảo tính nhất quán

        local keptOne = false
        for _, pet in ipairs(petList) do
            if keepPets[pet] then
                if not keepOnePet[pet] then
                    keepOnePet[pet] = true -- Chỉ giữ 1 bản sao của pet này
                    keptOne = true
                else
                    table.insert(petsToSell, pet) -- Bán các bản sao thừa
                end
            elseif not keptOne then
                keptOne = true -- Đảm bảo ít nhất 1 pet mỗi cấp độ được giữ lại
            else
                table.insert(petsToSell, pet) -- Bán các pet còn lại
            end
        end
    end

    return petsToSell
end

-- Hàm để bán pet
local function sellPets()
    local selectedRanks = SellDropdown.Value
    local keepPets = KeepPetsDropdown.Value
    local pets = getPetsByRank(selectedRanks, keepPets)

    if #pets > 0 then
        local args = {
            [1] = {
                [1] = {
                    ["Event"] = "SellPet",
                    ["Pets"] = pets
                },
                [2] = "\t"
            }
        }
        game:GetService("ReplicatedStorage"):WaitForChild("BridgeNet2"):WaitForChild("dataRemoteEvent"):FireServer(unpack(args))
    end
end

-- Hàm để cập nhật dropdown "Keep Pets"
function updateKeepPetsDropdown()
    local player = game:GetService("Players").LocalPlayer
    local petsFolder = player.leaderstats.Inventory:FindFirstChild("Pets")
    if not petsFolder then return end

    local petNames = {} -- Mảng cho dropdown

    for _, pet in ipairs(petsFolder:GetChildren()) do
        if not table.find(petNames, pet.Name) then
            table.insert(petNames, pet.Name) -- Thêm tên pet chỉ một lần
        end
    end

    KeepPetsDropdown:SetValues(petNames) -- Cập nhật dropdown với tên pet
end

-- Bắt đầu vòng lặp bán
local function startSellingLoop()
    while true do
        sellPets()
        wait(1) -- Ngăn spam
    end
end

-- Chạy vòng lặp trong một luồng riêng biệt
spawn(startSellingLoop)

-- Khởi tạo dropdown pet khi bắt đầu
updateKeepPetsDropdown()

-- Làm mới danh sách pet khi dropdown thay đổi
SellDropdown:OnChanged(updateKeepPetsDropdown)
KeepPetsDropdown:OnChanged(updateKeepPetsDropdown)

local VirtualUser = game:GetService("VirtualUser")
local LocalPlayer = game:GetService("Players").LocalPlayer

local antiAfkConnection

local AntiAfkToggle = Tabs.Player:AddToggle("AntiAfk", {
    Title = "Anti AFK",
    Default = false,
    Callback = function(enabled)
        if enabled then
            print("Đã bật Anti AFK")
            -- Đảm bảo không tạo nhiều kết nối
            if not antiAfkConnection then
                antiAfkConnection = LocalPlayer.Idled:Connect(function()
                    VirtualUser:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
                    task.wait(1) -- Thời gian chờ có thể điều chỉnh
                    VirtualUser:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
                end)
            end
        else
            print("Đã tắt Anti AFK")
            -- Ngắt kết nối sự kiện khi tắt
            if antiAfkConnection then
                antiAfkConnection:Disconnect()
                antiAfkConnection = nil -- Đặt lại biến kết nối
            end
        end
    end
})



local function getUniqueWeaponNames()
    local weapons = {}
    local seenNames = {} -- Để theo dõi tên duy nhất

    local playerWeapons = game:GetService("Players").LocalPlayer.leaderstats.Inventory.Weapons:GetChildren()
    print("Đang lấy danh sách vũ khí...") -- GỠ LỖI

    for _, weapon in ipairs(playerWeapons) do
        local weaponName = weapon:GetAttribute("Name") -- Lấy thuộc tính "Name"
        if weaponName then
            print("Đã tìm thấy vũ khí:", weaponName) -- GỠ LỖI
            if not seenNames[weaponName] then
                table.insert(weapons, weaponName)
                seenNames[weaponName] = true -- Đánh dấu tên đã thấy
            end
        end
    end
    return weapons
end

-- Tạo dropdown với tên vũ khí **duy nhất**
local weaponNames = getUniqueWeaponNames()
local WeaponDropdown = Tabs.misc:AddDropdown("WeaponDropdown", {
    Title = "Select Weapon to Upgrade",
    Description = "Choose a weapon to upgrade",
    Values = weaponNames,
    Multi = false, -- Chọn một
    Default = ""
})

-- Dropdown để chọn cấp độ nâng cấp (2-6)
local LevelDropdown = Tabs.misc:AddDropdown("LevelDropdown", {
    Title = "Select Upgrade Level",
    Description = "Choose the level for upgrade",
    Values = {"2", "3", "4", "5", "6", "7"},
    Multi = false,
    Default = "2"
})

-- Bật/tắt tự động nâng cấp vũ khí
 local AutoUpgradeToggle = Tabs.misc:AddToggle("AutoUpgradeToggle", { Title = "Auto Upgrade Weapon", Default = false })

local function AutoUpgradeWeapon()
    while AutoUpgradeToggle.Value do
        local selectedWeapon = WeaponDropdown.Value
        local selectedLevel = tonumber(LevelDropdown.Value) or 2

        if selectedWeapon and selectedWeapon ~= "" then
            local args = {
                [1] = {
                    [1] = {
                        ["Type"] = selectedWeapon,
                        ["BuyType"] = "Gems",
                        ["Weapons"] = {},
                        ["Event"] = "UpgradeWeapon",
                        ["Level"] = selectedLevel
                    },
                    [2] = "\n"
                }
            }

            game:GetService("ReplicatedStorage"):WaitForChild("BridgeNet2"):WaitForChild("dataRemoteEvent"):FireServer(unpack(args))
            task.wait(0.1) -- Điều chỉnh độ trễ nếu cần
        else
            Fluent:Notify({
                Title = "Error",
                Content = "Vui lòng chọn vũ khí trước khi nâng cấp.",
                Duration = 5
            })
            print("LỖI: Không có vũ khí nào được chọn!") -- GỠ LỖI
            break
        end
    end
end

AutoUpgradeToggle:OnChanged(function(Value)
    if Value then
        task.spawn(AutoUpgradeWeapon) -- Bắt đầu nâng cấp trong một luồng riêng biệt
    end
end)

 local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local AppearFolder = workspace:FindFirstChild("__Extra") and workspace.__Extra:FindFirstChild("__Appear")

local locations = {
    {Name = "Location 1", CFrame = CFrame.new(-6161.25781, 140.639832, 5512.9668)},
    {Name = "Location 2", CFrame = CFrame.new(-5868.44141, 132.70488, 362.519379)},
    {Name = "Location 3", CFrame = CFrame.new(-5430.81006, 107.441559, -5502.25244)},
    {Name = "Location 4", CFrame = CFrame.new(-702.243225, 133.344467, -3538.11646)},
    {Name = "Location 5", CFrame = CFrame.new(450.001709, 117.564827, 3435.4292)},
    {Name = "Location 6", CFrame = CFrame.new(3230.96826, 135.41008, 36.1600113)},
    {Name = "Location 7", CFrame = CFrame.new(4325.36523, 118.995422, -4819.78857)}
}

local PlaceID = game.PlaceId
local AllIDs = {}
local foundAnything = ""
local actualHour = os.date("!*t").hour
local File = pcall(function()
    AllIDs = game:GetService('HttpService'):JSONDecode(readfile("NotSameServers.json"))
end)

if not File then
    table.insert(AllIDs, actualHour)
    writefile("NotSameServers.json", game:GetService('HttpService'):JSONEncode(AllIDs))
end

function TPReturner()
    local Site
    if foundAnything == "" then
        Site = game.HttpService:JSONDecode(game:HttpGet('https://games.roblox.com/v1/games/' .. PlaceID .. '/servers/Public?sortOrder=Asc&limit=100'))
    else
        Site = game.HttpService:JSONDecode(game:HttpGet('https://games.roblox.com/v1/games/' .. PlaceID .. '/servers/Public?sortOrder=Asc&limit=100&cursor=' .. foundAnything))
    end
    local ID = ""
    if Site.nextPageCursor and Site.nextPageCursor ~= "null" and Site.nextPageCursor ~= nil then
        foundAnything = Site.nextPageCursor
    end
    local num = 0
    for _, v in pairs(Site.data) do
        local Possible = true
        ID = tostring(v.id)
        if tonumber(v.maxPlayers) > tonumber(v.playing) then
            for _, Existing in pairs(AllIDs) do
                if num ~= 0 then
                    if ID == tostring(Existing) then
                        Possible = false
                    end
                else
                    if tonumber(actualHour) ~= tonumber(Existing) then
                        local delFile = pcall(function()
                            delfile("NotSameServers.json")
                            AllIDs = {}
                            table.insert(AllIDs, actualHour)
                        end)
                    end
                end
                num = num + 1
            end
            if Possible then
                table.insert(AllIDs, ID)
                wait()
                pcall(function()
                    writefile("NotSameServers.json", game:GetService('HttpService'):JSONEncode(AllIDs))
                    wait()
                    game:GetService("TeleportService"):TeleportToPlaceInstance(PlaceID, ID, Players.LocalPlayer)
                end)
                wait(4)
                break -- Thoát vòng lặp sau khi tìm thấy máy chủ phù hợp để dịch chuyển đến
            end
        end
    end
end

local function hasSpawned()
    return AppearFolder and #AppearFolder:GetChildren() > 0
end

local function tweenTeleport(targetCFrame)
    if not Character or not Character:FindFirstChild("HumanoidRootPart") then return end
    local HRP = Character.HumanoidRootPart
    local Tween = TweenService:Create(HRP, TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {CFrame = targetCFrame})
    Tween:Play()
    Tween.Completed:Wait()
end
local function fireProximityPrompts()
    if not AppearFolder then return end
    for _, mount in ipairs(AppearFolder:GetChildren()) do
        for _, descendant in ipairs(mount:GetDescendants()) do
            if descendant:IsA("ProximityPrompt") then
                fireproximityprompt(descendant)
            end
        end
    end
end

local DelayToggle = false

local function checkMountsAndTeleport()
    local inventoryMounts = {}
    for _, mount in ipairs(LocalPlayer.leaderstats.Inventory.Mounts:GetChildren()) do
        table.insert(inventoryMounts, mount.Name:sub(1, 4))
    end

    for _, mount in ipairs(AppearFolder:GetChildren()) do
        local mountId = mount.Name:sub(1, 4)
        for _, invMount in ipairs(inventoryMounts) do
            if mountId == invMount then
                Fluent:Notify({
                    Title = "Mount Detected!",
                    Content = "Tìm thấy mount trùng khớp! Đang chuyển máy chủ...",
                    Duration = 5
                })
                TPReturner()
                return
            end
        end
    end
  for _, mount in ipairs(AppearFolder:GetChildren()) do
        local targetPosition = mount:GetPivot()
        tweenTeleport(targetPosition)

        if DelayToggle then
            task.wait(15)  -- Đợi 15 giây CHỈ KHI bật toggle
        end

        fireProximityPrompts()
    end
end

local function teleportSequence()
    for _, loc in ipairs(locations) do
        tweenTeleport(loc.CFrame)
        task.wait(3)

        if hasSpawned() then
            checkMountsAndTeleport()
            Fluent:Notify({
                Title = "Mount Collected!",
                Content = "Đang chuyển máy chủ...",
                Duration = 5
            })
            TPReturner()
            return
        end
    end
    TPReturner()
end




local TeleportToggle = Tabs.mount:AddToggle("AutoTeleport", {Title = "Auto Find Mount (serverHop)", Default = false })

TeleportToggle:OnChanged(function(enabled)
    if enabled then
        teleportSequence()
    end
end)

local DelayToggleOption = Tabs.mount:AddToggle("DelayBeforeFire", {Title = "Wait 15s ENABLE THIS IF U GET KICKED", Default = false })

DelayToggleOption:OnChanged(function(enabled)
    DelayToggle = enabled
end)



local function getUniquePetNames()
    local pets = {}
    local seenNames = {} -- To track unique names

    local playerPets = game:GetService("Players").LocalPlayer.leaderstats.Inventory.Pets:GetChildren()
    print("Fetching pets...") -- DEBUG

    for _, pet in ipairs(playerPets) do
        local petName = pet:GetAttribute("Name") -- Get "Name" attribute
        if petName then
            print("Found Pet:", petName) -- DEBUG
            if not seenNames[petName] then
                table.insert(pets, petName)
                seenNames[petName] = true -- Mark name as seen
            end
        end
    end
    return pets
end

-- Populate dropdown with **unique** pet names







local autoEquipEnabled = false

local function EquipBestPets()
    local player = game:GetService("Players").LocalPlayer
    local petsFolder = player.leaderstats.Inventory.Pets
    local maxEquip = player.leaderstats.Values:GetAttribute("MaxEquipPets") or 1
    local bestPets = {}

    local petsList = {}
    for _, pet in ipairs(petsFolder:GetChildren()) do
        local rank = pet:GetAttribute("Rank")
        if rank and typeof(rank) == "number" then
            table.insert(petsList, {name = pet.Name, rank = rank})
        end
    end

    table.sort(petsList, function(a, b) return a.rank > b.rank end)

    local equipCount = 0
    for _, petData in ipairs(petsList) do
        if equipCount < maxEquip then
            table.insert(bestPets, petData.name)
            equipCount = equipCount + 1
        else
            break
        end
    end

    if #bestPets > 0 then
        game:GetService("ReplicatedStorage"):WaitForChild("BridgeNet2"):WaitForChild("dataRemoteEvent"):FireServer({
            {["Event"] = "EquipBest", ["Pets"] = bestPets},
            "\n"
        })
    end
end


local Toggle = Tabs.pets:AddToggle("AutoEquip", { Title = "Auto Equip Best Pets", Default = false })

Toggle:OnChanged(function(state)
    autoEquipEnabled = state
    if state then
        Fluent:Notify({ Title = "Auto Equip", Content = "Enabled. Equipping every 2 minutes.", Duration = 5 })
        task.spawn(function()
            while autoEquipEnabled do
                EquipBestPets()
                wait(120)
            end
        end)
    else
        Fluent:Notify({ Title = "Auto Equip", Content = "Disabled.", Duration = 5 })
    end
end)

Tabs.Player:AddButton({
    Title = "Boost FPS",
    Description = "Lowers graphics",
    Callback = function()
        local Optimizer = {Enabled = false}

        local function DisableEffects()
            for _, v in pairs(game:GetDescendants()) do
                if v:IsA("ParticleEmitter") or v:IsA("Smoke") or v:IsA("Fire") or v:IsA("Sparkles") then
                    v.Enabled = not Optimizer.Enabled
                end
                if v:IsA("PostEffect") or v:IsA("BloomEffect") or v:IsA("BlurEffect") or v:IsA("SunRaysEffect") then
                    v.Enabled = not Optimizer.Enabled
                end
            end
        end

        local function MaximizePerformance()
            local lighting = game:GetService("Lighting")
            if Optimizer.Enabled then
                lighting.GlobalShadows = false
                lighting.FogEnd = 9e9
                lighting.Brightness = 2
                settings().Rendering.QualityLevel = 1
                settings().Physics.PhysicsEnvironmentalThrottle = 1
                settings().Rendering.MeshPartDetailLevel = Enum.MeshPartDetailLevel.Level01
                settings().Physics.AllowSleep = true
                settings().Physics.ForceCSGv2 = false
                settings().Physics.DisableCSGv2 = true
                settings().Rendering.EagerBulkExecution = true

                game:GetService("StarterGui"):SetCore("TopbarEnabled", false)

                settings().Network.IncomingReplicationLag = 0
                settings().Rendering.MaxPartCount = 100000
            else
                lighting.GlobalShadows = true
                lighting.FogEnd = 100000
                lighting.Brightness = 3
                settings().Rendering.QualityLevel = 7
                settings().Physics.PhysicsEnvironmentalThrottle = 0
                settings().Rendering.MeshPartDetailLevel = Enum.MeshPartDetailLevel.Level04
                settings().Physics.AllowSleep = false
                settings().Physics.ForceCSGv2 = true
                settings().Physics.DisableCSGv2 = false
                settings().Rendering.EagerBulkExecution = false

                game:GetService("StarterGui"):SetCore("TopbarEnabled", true)

                settings().Network.IncomingReplicationLag = 1
                settings().Rendering.MaxPartCount = 500000
            end
        end

        local function OptimizeInstances()
            for _, v in pairs(game:GetDescendants()) do
                if v:IsA("BasePart") then
                    v.CastShadow = not Optimizer.Enabled
                    v.Reflectance = Optimizer.Enabled and 0 or v.Reflectance
                    v.Material = Optimizer.Enabled and Enum.Material.SmoothPlastic or v.Material
                end
                if v:IsA("Decal") or v:IsA("Texture") then
                    v.Transparency = Optimizer.Enabled and 1 or 0
                end
                if v:IsA("MeshPart") then
                    v.RenderFidelity = Optimizer.Enabled and Enum.RenderFidelity.Performance or Enum.RenderFidelity.Precise
                end
            end

            game:GetService("Debris"):SetAutoCleanupEnabled(true)
        end

        local function CleanMemory()
            if Optimizer.Enabled then
                game:GetService("Debris"):AddItem(Instance.new("Model"), 0)
                settings().Physics.ThrottleAdjustTime = 2
                game:GetService("RunService"):Set3dRenderingEnabled(false)
            else
                game:GetService("RunService"):Set3dRenderingEnabled(true)
            end
        end

        local function ToggleOptimizer()
            Optimizer.Enabled = not Optimizer.Enabled
            DisableEffects()
            MaximizePerformance()
            OptimizeInstances()
            CleanMemory()
            print("FPS Booster: " .. (Optimizer.Enabled and "ON" or "OFF"))
        end

        game:GetService("UserInputService").InputBegan:Connect(function(input)
            if input.KeyCode == Enum.KeyCode.RightControl then
                ToggleOptimizer()
            end
        end)

        ToggleOptimizer()

        game:GetService("RunService").Heartbeat:Connect(function()
            if Optimizer.Enabled then
                CleanMemory()
            end
        end)
    end
})



local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local hrp = character:WaitForChild("HumanoidRootPart")

local targetCFrame = CFrame.new(
    3648.76318, 223.552261, 2637.36719, 
    0.846323907, 7.72367986e-18, -0.532668591, 
    -1.10462046e-17, 1, -3.05065368e-18, 
    0.532668591, 8.46580728e-18, 0.846323907
)

local function tweenToPivot()
    hrp.CFrame = targetCFrame
end


local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local speedValue = 16 -- Tốc độ di chuyển mặc định
local jumpValue = 50  -- Lực nhảy mặc định
local speedEnabled = false
local jumpEnabled = false

local function updateCharacter()
    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
        local humanoid = LocalPlayer.Character.Humanoid
        humanoid.WalkSpeed = speedEnabled and speedValue or 16
        humanoid.JumpPower = jumpEnabled and jumpValue or 50
    end
end

-- Nhập tốc độ
local SpeedInput = Tabs.Player:AddInput("SpeedInput", {
    Title = "Speed",
    Default = tostring(speedValue),
    Placeholder = "Enter speed",
    Numeric = true,
    Finished = true, 
    Callback = function(Value)
        speedValue = tonumber(Value) or 16
        updateCharacter() -- Cập nhật nhân vật ngay lập tức khi tốc độ thay đổi
    end
})

-- Nhập lực nhảy
local JumpInput = Tabs.Player:AddInput("JumpInput", {
    Title = "Jump Power",
    Default = tostring(jumpValue),
    Placeholder = "Enter jump power",
    Numeric = true,
    Finished = true, 
    Callback = function(Value)
        jumpValue = tonumber(Value) or 50
        updateCharacter() -- Cập nhật nhân vật ngay lập tức khi lực nhảy thay đổi
    end
})

-- Bật/tắt tốc độ
local SpeedToggle = Tabs.Player:AddToggle("SpeedToggle", {
    Title = "Enable Speed",
    Default = false
})

SpeedToggle:OnChanged(function(Value)
    speedEnabled = Value
    updateCharacter() -- Cập nhật nhân vật ngay lập tức khi toggle thay đổi
end)

-- Bật/tắt lực nhảy
local JumpToggle = Tabs.Player:AddToggle("JumpToggle", {
    Title = "Enable Jump Power",
    Default = false
})

JumpToggle:OnChanged(function(Value)
    jumpEnabled = Value
    updateCharacter() -- Cập nhật nhân vật ngay lập tức khi toggle thay đổi
end)

-- Cập nhật nhân vật khi hồi sinh
LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1) -- Đợi nhân vật tải xong
    updateCharacter()
end)

-- Cập nhật ban đầu
updateCharacter()

local player = game.Players.LocalPlayer

local function tweenCharacter(targetCFrame)
    if player and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
        local hrp = player.Character.HumanoidRootPart
        local tweenService = game:GetService("TweenService")
        local tweenInfo = TweenInfo.new(3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        local tween = tweenService:Create(hrp, tweenInfo, {CFrame = targetCFrame})
        tween:Play()
    end
end

-- Thêm nút
Tabs.tp:AddButton({
    Title = "Tween to Dedu island",
    Description = "Smoothly moves your character",
    Callback = function()
        tweenCharacter(CFrame.new(3859.06299, 60.1228409, 3081.9458, -0.987112403, 6.46206388e-07, -0.160028473, 5.63319077e-07, 1, 5.63319418e-07, 0.160028473, 4.65912507e-07, -0.987112403)) -- Thay đổi vị trí theo nhu cầu
    end
})



local NoClipToggle = Tabs.Player:AddToggle("NoClipToggle", {
    Title = "Enable NoClip",
    Default = false
})

-- Hàm NoClip
local noclipEnabled = false
NoClipToggle:OnChanged(function(Value)
    noclipEnabled = Value
    if noclipEnabled then
        task.spawn(function()
            while noclipEnabled do
                for _, part in ipairs(game.Players.LocalPlayer.Character:GetDescendants()) do
                    if part:IsA("BasePart") then
                        part.CanCollide = false
                    end
                end
                task.wait()
            end
        end)
    else
        for _, part in ipairs(game.Players.LocalPlayer.Character:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = true
            end
        end
    end
end)



Tabs.Player:AddButton({
    Title = "Server Hop",
    Description = "Switches to a different server",
    Callback = function()
        local PlaceID = game.PlaceId
        local AllIDs = {}
        local foundAnything = ""
        local actualHour = os.date("!*t").hour
        local File = pcall(function()
            AllIDs = game:GetService('HttpService'):JSONDecode(readfile("NotSameServers.json"))
        end)
        if not File then
            table.insert(AllIDs, actualHour)
            writefile("NotSameServers.json", game:GetService('HttpService'):JSONEncode(AllIDs))
        end
        local function TPReturner()
            local Site
            if foundAnything == "" then
                Site = game.HttpService:JSONDecode(game:HttpGet('https://games.roblox.com/v1/games/' .. PlaceID .. '/servers/Public?sortOrder=Asc&limit=100'))
            else
                Site = game.HttpService:JSONDecode(game:HttpGet('https://games.roblox.com/v1/games/' .. PlaceID .. '/servers/Public?sortOrder=Asc&limit=100&cursor=' .. foundAnything))
            end
            for _, v in pairs(Site.data) do
                if tonumber(v.maxPlayers) > tonumber(v.playing) then
                    local ID = tostring(v.id)
                    local isNewServer = true
                    for _, existing in pairs(AllIDs) do
                        if ID == tostring(existing) then
                            isNewServer = false
                            break
                        end
                    end
                    if isNewServer then
                        table.insert(AllIDs, ID)
                        writefile("NotSameServers.json", game:GetService('HttpService'):JSONEncode(AllIDs))
                        game:GetService("TeleportService"):TeleportToPlaceInstance(PlaceID, ID, game.Players.LocalPlayer)
                        return
                    end
                end
            end
        end
        TPReturner()
    end
})



    

        
Tabs.dungeon:AddToggle("AutoBuyDungeonTicket", {
    Title = "Auto Buy Dungeon Ticket",
    Default = false,
    Callback = function(state)
        buyTicketEnabled = state
        print("[DEBUG] Auto Buy Dungeon Ticket toggled:", state)
        
        if state then
            task.spawn(function()
                while buyTicketEnabled do
                    local args = {
                        [1] = {
                            [1] = {
                                ["Type"] = "Gems",
                                ["Event"] = "DungeonAction",
                                ["Action"] = "BuyTicket"
                            },
                            [2] = "\n"
                        }
                    }

                    game:GetService("ReplicatedStorage"):WaitForChild("BridgeNet2"):WaitForChild("dataRemoteEvent"):FireServer(unpack(args))
                    task.wait(5) -- Đợi 5 giây trước khi gửi lại
                end
            end)
        end
    end
})



    local localPlayer = game:GetService("Players").LocalPlayer
local playerCharacter = localPlayer.Character or localPlayer.CharacterAdded:Wait()
local playerHRP = playerCharacter:WaitForChild("HumanoidRootPart")
local enemyContainer = workspace:WaitForChild("__Main"):WaitForChild("__Enemies"):WaitForChild("Client")
local networkEvent = game:GetService("ReplicatedStorage"):WaitForChild("BridgeNet2"):WaitForChild("dataRemoteEvent")

local autoFarmActive = false
local defeatedEnemies = {}

local function isTargetDefeated(target)
    local healthUI = target:FindFirstChild("HealthBar")
    if healthUI and healthUI:FindFirstChild("Main") and healthUI.Main:FindFirstChild("Bar") then
        local healthText = healthUI.Main.Bar:FindFirstChild("Amount")
        if healthText and healthText:IsA("TextLabel") and healthText.ContentText == "0 HP" then
            return true
        end
    end
    return false
end

local function findClosestTarget()
    local closestJJ2, closestJJ3, closestJJ4 = nil, nil, nil
    local distJJ2, distJJ3, distJJ4 = math.huge, math.huge, math.huge
    local playerPos = localPlayer.Character and localPlayer.Character:GetPivot().Position

    if not playerPos then return nil end

    for _, enemy in ipairs(enemyContainer:GetChildren()) do
        if enemy:IsA("Model") and enemy:FindFirstChild("HumanoidRootPart") then
            local enemyType = enemy:GetAttribute("ID")
            
            -- Đảm bảo script bỏ qua các kẻ địch đã chết
            if not defeatedEnemies[enemy.Name] then
                local distance = (playerPos - enemy:GetPivot().Position).Magnitude
                
                if enemyType == "JJ2" and distance < distJJ2 then
                    distJJ2 = distance
                    closestJJ2 = enemy
                elseif enemyType == "JJ3" and distance < distJJ3 then
                    distJJ3 = distance
                    closestJJ3 = enemy
                elseif enemyType == "JJ4" and distance < distJJ4 then
                    distJJ4 = distance
                    closestJJ4 = enemy
                end
            end
        end
    end

    -- Ưu tiên: JJ2 > JJ3 > JJ4
    return closestJJ2 or closestJJ3 or closestJJ4
end

local function triggerPetVisibility()
    local arguments = {
        [1] = {
            [1] = {
                ["Event"] = "ShowPets"
            },
            [2] = "\t"
        }
    }
    game:GetService("ReplicatedStorage"):WaitForChild("BridgeNet2"):WaitForChild("dataRemoteEvent"):FireServer(unpack(arguments))
end

local function startAutoFarm()
    while autoFarmActive do
        local targetEnemy = findClosestTarget()
        
        while autoFarmActive and targetEnemy do
            if not targetEnemy.Parent then break end

            local targetHRP = targetEnemy:FindFirstChild("HumanoidRootPart")
            local playerHRP = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")

            if targetHRP and playerHRP then
                -- Move to target enemy
                playerHRP.CFrame = targetHRP.CFrame * CFrame.new(0, 0, 6)

                task.wait(0.5)
                triggerPetVisibility()

                networkEvent:FireServer({
                    {
                        ["PetPos"] = {},
                        ["AttackType"] = "All",
                        ["Event"] = "Attack",
                        ["Enemy"] = targetEnemy.Name
                    },
                    "\7"
                })

                -- Wait until enemy is defeated or a higher-priority one appears
                while autoFarmActive and targetEnemy.Parent do
                    if isTargetDefeated(targetEnemy) then
                        defeatedEnemies[targetEnemy.Name] = true -- Mark it as dead immediately
                        break
                    end
                    
                    task.wait(0.1)
                    
                    -- Switch if a higher-priority target appears
                    local newTarget = findClosestTarget()
                    if newTarget and newTarget:GetAttribute("ID") == "JJ2" and newTarget ~= targetEnemy then
                        break
                    elseif newTarget and newTarget:GetAttribute("ID") == "JJ3" and targetEnemy:GetAttribute("ID") == "JJ4" then
                        break
                    end
                end
            end

            targetEnemy = findClosestTarget() -- Move to next enemy
        end

        task.wait(0.20)
    end
end

Tabs.Main:AddToggle("AutoFarmToggle", {
    Title = "auto Jeju farm",
    Default = false,
    Callback = function(state)
        autoFarmActive = state
        if state then
            task.spawn(startAutoFarm)
        end
    end
})


local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
local Inventory = LocalPlayer:FindFirstChild("leaderstats") and LocalPlayer.leaderstats:FindFirstChild("Inventory")





local SelectedLevel = 1
local SellingEnabled = false

-- Dropdown để chọn cấp độ vũ khí (đã chuyển sang tab Misc)
local Dropdown = Tabs.misc:AddDropdown("WeaponLevel", {
    Title = "Select Weapon Level",
    Values = {"1", "2", "4", "5", "6", "7"},
    Multi = false,
    Default = "1",
})

Dropdown:OnChanged(function(Value)
    SelectedLevel = tonumber(Value)
end)

-- Bật/tắt tự động bán (đã chuyển sang tab Misc)
local Toggle = Tabs.misc:AddToggle("AutoSell", { Title = "Auto-Sell Weapons", Default = false })

Toggle:OnChanged(function(Value)
    SellingEnabled = Value
end)

-- Hàm để bán vũ khí dựa trên cấp độ đã chọn
local function SellWeapons()
    if not Inventory or not SellingEnabled then return end
    
    for _, weapon in ipairs(Inventory.Weapons:GetChildren()) do
        local level = weapon:GetAttribute("Level")
        if level == SelectedLevel then
            local args = {
                [1] = {
                    [1] = {
                        ["Action"] = "Sell",
                        ["Event"] = "WeaponAction",
                        ["Name"] = weapon.Name
                    },
                    [2] = "\n"
                }
            }
            ReplicatedStorage:WaitForChild("BridgeNet2"):WaitForChild("dataRemoteEvent"):FireServer(unpack(args))
            
        end
    end
end

-- Vòng lặp liên tục kiểm tra vũ khí để bán
task.spawn(function()
    while task.wait(0.5) do
        if SellingEnabled then
            SellWeapons()
        end
    end
end)


local AutoEnterDungeon = Tabs.dungeon:AddToggle("AutoEnterDungeon", { Title = "Auto Enter Guild Dungeon", Default = false })

local function EnterDungeon()
    while AutoEnterDungeon.Value do
        local args = {
            [1] = {
                [1] = {
                    ["Event"] = "DungeonAction",
                    ["Action"] = "TestEnter"
                },
                [2] = "\n"
            }
        }

        game:GetService("ReplicatedStorage"):WaitForChild("BridgeNet2"):WaitForChild("dataRemoteEvent"):FireServer(unpack(args))
        task.wait(0.5) -- Điều chỉnh độ trễ nếu cần
    end
end

AutoEnterDungeon:OnChanged(function(Value)
    if Value then
        task.spawn(EnterDungeon) -- Start loop when enabled
    end
end)

Tabs.Discord:AddParagraph({
    Title = "🎉 Chào mừng đến với Etherbyte Hub Premium!",
    Content = "Mở khóa trải nghiệm tốt nhất với các tính năng cao cấp của chúng tôi!\n\n" ..
              "✅ **Vượt qua Anti-Cheat nâng cao** – Luôn an toàn và không bị phát hiện.\n" ..
              "⚡ **Thực thi nhanh hơn & Tối ưu hóa** – Tận hưởng gameplay mượt mà hơn.\n" ..
              "🔄 **Cập nhật độc quyền** – Tiếp cận sớm các tính năng mới.\n" ..
              "🎁 **Hỗ trợ & Cộng đồng cao cấp** – Kết nối với các người dùng ưu tú khác.\n\n" ..
              "Nâng cấp ngay và nâng cao trải nghiệm chơi game của bạn!"
})

Tabs.Discord:AddButton({
    Title = "Copy Discord Link",
    Description = "Copies the Discord invite link to clipboard",
    Callback = function()
        setclipboard("https://discord.gg/W77Vj2HNBA")
        Fluent:Notify({
            Title = "Đã sao chép!",
            Content = "Đường dẫn Discord đã được sao chép vào clipboard.",
            Duration = 3
        })
    end
})


SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)

-- Thay đổi cách lưu cấu hình để sử dụng tên người chơi
local playerName = game:GetService("Players").LocalPlayer.Name
InterfaceManager:SetFolder("KaihonScriptHub")
SaveManager:SetFolder("KaihonScriptHub/AriseCrossover/" .. playerName)

-- Xóa đoạn xây dựng phần cấu hình trong Settings tab
-- InterfaceManager:BuildInterfaceSection(Tabs.Settings)
-- SaveManager:BuildConfigSection(Tabs.Settings)

-- Thêm thông tin vào tab Settings
Tabs.Settings:AddParagraph({
    Title = "Cấu hình tự động",
    Content = "Cấu hình của bạn đang được tự động lưu theo tên nhân vật: " .. playerName
})

Tabs.Settings:AddParagraph({
    Title = "Phím tắt",
    Content = "Nhấn LeftControl để ẩn/hiện giao diện"
})

-- Thêm nút xóa cấu hình hiện tại
Tabs.Settings:AddButton({
    Title = "Xóa cấu hình hiện tại",
    Description = "Đặt lại tất cả cài đặt về mặc định",
    Callback = function()
        SaveManager:Delete("AutoSave_" .. playerName)
        Fluent:Notify({
            Title = "Đã xóa cấu hình",
            Content = "Tất cả cài đặt đã được đặt lại về mặc định",
            Duration = 3
        })
    end
})

Window:SelectTab(1)

Fluent:Notify({
    Title = "Kaihon Hub",
    Content = "Script đã tải xong! Cấu hình tự động lưu theo tên người chơi: " .. playerName,
    Duration = 3
})

-- Thay đổi cách tải cấu hình
local function AutoSaveConfig()
    local configName = "AutoSave_" .. playerName
    
    -- Tự động lưu cấu hình hiện tại
    task.spawn(function()
        while task.wait(10) do -- Lưu mỗi 10 giây
            pcall(function()
                SaveManager:Save(configName)
            end)
        end
    end)
    
    -- Tải cấu hình đã lưu nếu có
    pcall(function()
        SaveManager:Load(configName)
    end)
end

-- Thực thi tự động lưu/tải cấu hình
AutoSaveConfig()

-- Thêm hỗ trợ Mobile UI
repeat task.wait(0.25) until game:IsLoaded()
getgenv().Image = "rbxassetid://13099788281" -- ID tài nguyên hình ảnh đã sửa
getgenv().ToggleUI = "LeftControl" -- Phím để bật/tắt giao diện

-- Tạo giao diện mobile cho người dùng điện thoại
task.spawn(function()
    local success, errorMsg = pcall(function()
        if not getgenv().LoadedMobileUI == true then 
            getgenv().LoadedMobileUI = true
            local OpenUI = Instance.new("ScreenGui")
            local ImageButton = Instance.new("ImageButton")
            local UICorner = Instance.new("UICorner")
            
            -- Kiểm tra thiết bị
            if syn and syn.protect_gui then
                syn.protect_gui(OpenUI)
                OpenUI.Parent = game:GetService("CoreGui")
            elseif gethui then
                OpenUI.Parent = gethui()
            else
                OpenUI.Parent = game:GetService("CoreGui")
            end
            
            OpenUI.Name = "OpenUI"
            OpenUI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
            
            ImageButton.Parent = OpenUI
            ImageButton.BackgroundColor3 = Color3.fromRGB(105,105,105)
            ImageButton.BackgroundTransparency = 0.8
            ImageButton.Position = UDim2.new(0.9,0,0.1,0)
            ImageButton.Size = UDim2.new(0,50,0,50)
            ImageButton.Image = getgenv().Image
            ImageButton.Draggable = true
            ImageButton.Transparency = 0.2
            
            UICorner.CornerRadius = UDim.new(0,200)
            UICorner.Parent = ImageButton
            
            ImageButton.MouseButton1Click:Connect(function()
                game:GetService("VirtualInputManager"):SendKeyEvent(true,getgenv().ToggleUI,false,game)
            end)
        end
    end)
    
    if not success then
        warn("Lỗi khi tạo nút Mobile UI: " .. tostring(errorMsg))
    end
end) -- Thêm từ khóa end thiếu ở đây

-- Kiểm tra script đã tải thành công
local scriptSuccess, scriptError = pcall(function()
    Fluent:Notify({
        Title = "Script đã khởi động thành công",
        Content = "Kaihon Hub | Arise Crossover đang hoạt động",
        Duration = 5
    })
end)

if not scriptSuccess then
    warn("Lỗi khi khởi động script: " .. tostring(scriptError))
    -- Thử cách khác để thông báo người dùng
    if game:GetService("Players").LocalPlayer and game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui") then
        local screenGui = Instance.new("ScreenGui")
        screenGui.Parent = game:GetService("Players").LocalPlayer.PlayerGui
        
        local textLabel = Instance.new("TextLabel")
        textLabel.Size = UDim2.new(0.3, 0, 0.1, 0)
        textLabel.Position = UDim2.new(0.35, 0, 0.45, 0)
        textLabel.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
        textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        textLabel.Text = "Kaihon Hub đã khởi động nhưng gặp lỗi. Hãy thử lại."
        textLabel.Parent = screenGui
        
        local uiCorner = Instance.new("UICorner")
        uiCorner.CornerRadius = UDim.new(0, 8)
        uiCorner.Parent = textLabel
        
        game:GetService("Debris"):AddItem(screenGui, 5)
    end
end





