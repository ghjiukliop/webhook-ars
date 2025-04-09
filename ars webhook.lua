-- Arise Crossover - Discord Webhook cho AFKRewards
local allowedPlaceId = 87039211657390 -- PlaceId mà script được phép chạy
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Player = Players.LocalPlayer

-- Sử dụng tên người chơi để tạo file cấu hình riêng cho từng tài khoản
local playerName = Player.Name:gsub("[^%w_]", "_") -- Loại bỏ ký tự đặc biệt
local CONFIG_FILE = "AriseWebhook_" .. playerName .. ".json"

-- Biến kiểm soát trạng thái script
local scriptRunning = true

-- Đọc cấu hình từ file (nếu có)
local function loadConfig()
    local success, result = pcall(function()
        if readfile and isfile and isfile(CONFIG_FILE) then
            return HttpService:JSONDecode(readfile(CONFIG_FILE))
        end
        return nil
    end)
    
    if success and result then
        print("Đã tải cấu hình từ file cho tài khoản " .. playerName)
        return result
    else
        print("Không tìm thấy file cấu hình cho tài khoản " .. playerName)
        return nil
    end
end

-- Lưu cấu hình xuống file
local function saveConfig(config)
    local success, err = pcall(function()
        if writefile then
            writefile(CONFIG_FILE, HttpService:JSONEncode(config))
            return true
        end
        return false
    end)
    
    if success then
        print("Đã lưu cấu hình vào file " .. CONFIG_FILE)
        return true
    else
        warn("Lỗi khi lưu cấu hình: " .. tostring(err))
        return false
    end
end

-- Tắt hoàn toàn script (định nghĩa hàm này trước khi được gọi)
local function shutdownScript()
    print("Đang tắt script Arise Webhook...")
    scriptRunning = false
    
    -- Lưu cấu hình trước khi tắt
    saveConfig(CONFIG)
    
    -- Hủy bỏ tất cả các kết nối sự kiện (nếu có)
    for _, connection in pairs(connections or {}) do
        if typeof(connection) == "RBXScriptConnection" and connection.Connected then
            connection:Disconnect()
        end
    end
    
    -- Xóa UI
    if webhookUI and webhookUI.Parent then
        webhookUI:Destroy()
    end
    
    print("Script Arise Webhook đã tắt hoàn toàn")
end

-- Cấu hình Webhook Discord của bạn
local WEBHOOK_URL = "YOUR_URL" -- Giá trị mặc định

-- Tải cấu hình từ file (nếu có)
local savedConfig = loadConfig()
if savedConfig and savedConfig.WEBHOOK_URL then
    WEBHOOK_URL = savedConfig.WEBHOOK_URL
    print("Đã tải URL webhook từ cấu hình: " .. WEBHOOK_URL:sub(1, 30) .. "...")
end

-- Tùy chọn định cấu hình
local CONFIG = {
    WEBHOOK_URL = WEBHOOK_URL,
    WEBHOOK_COOLDOWN = 3,
    SHOW_UI = true,
    UI_POSITION = UDim2.new(0.7, 0, 0.05, 0),
    ACCOUNT_NAME = playerName -- Lưu tên tài khoản vào cấu hình
}

-- Lưu cấu hình hiện tại
saveConfig(CONFIG)

-- Lưu trữ phần thưởng đã nhận để tránh gửi trùng lặp
local receivedRewards = {}

-- Theo dõi tổng phần thưởng
local totalRewards = {}

-- Lưu trữ số lượng item đã kiểm tra từ RECEIVED
local playerItems = {}

-- Cooldown giữa các lần gửi webhook (giây)
local WEBHOOK_COOLDOWN = CONFIG.WEBHOOK_COOLDOWN
local lastWebhookTime = 0

-- Đang xử lý một phần thưởng (tránh xử lý đồng thời)
local isProcessingReward = false

-- UI chính
local webhookUI = nil

-- Lưu danh sách các kết nối sự kiện để có thể ngắt kết nối khi tắt script
local connections = {}

-- Tạo khai báo trước các hàm để tránh lỗi gọi nil
local findRewardsUI
local findReceivedFrame
local findNewRewardNotification
local checkNewRewards
local checkReceivedRewards
local checkNewRewardNotification
local readActualItemQuantities
local sendTestWebhook

-- Mẫu regex để trích xuất số lượng trong ngoặc
local function extractQuantity(text)
    -- Tìm số lượng trong ngoặc, ví dụ: GEMS(10)
    local quantity = text:match("%((%d+)%)")
    if quantity then
        return tonumber(quantity)
    end
    return nil
end

-- Tạo một ID duy nhất cho phần thưởng mà không dùng timestamp
local function createUniqueRewardId(rewardText)
    -- Loại bỏ khoảng trắng và chuyển về chữ thường để so sánh nhất quán
    local id = rewardText:gsub("%s+", ""):lower()
    
    -- Loại bỏ tiền tố "RECEIVED:" nếu có
    id = id:gsub("received:", "")
    
    -- Loại bỏ tiền tố "YOU GOT A NEW REWARD!" nếu có
    id = id:gsub("yougotanewreward!", "")
    
    return id
end

-- Kiểm tra xem một phần thưởng có phải là CASH không
local function isCashReward(rewardText)
    return rewardText:upper():find("CASH") ~= nil
end

-- Phân tích chuỗi phần thưởng để lấy số lượng và loại
local function parseReward(rewardText)
    -- Loại bỏ các tiền tố không cần thiết
    rewardText = rewardText:gsub("RECEIVED:%s*", "")
    rewardText = rewardText:gsub("YOU GOT A NEW REWARD!%s*", "")
    
    -- Tìm số lượng và loại phần thưởng từ text
    local amount, itemType = rewardText:match("(%d+)%s+([%w%s]+)")
    
    if amount and itemType then
        amount = tonumber(amount)
        itemType = itemType:gsub("^%s+", ""):gsub("%s+$", "") -- Xóa khoảng trắng thừa
        
        -- Kiểm tra xem có số lượng trong ngoặc không
        local quantityInBrackets = itemType:match("%((%d+)%)$")
        if quantityInBrackets then
            -- Loại bỏ phần số lượng trong ngoặc khỏi tên item
            itemType = itemType:gsub("%(%d+%)$", ""):gsub("%s+$", "")
        end
        
        return amount, itemType
    else
        return nil, rewardText
    end
end

-- Tìm UI phần thưởng
findRewardsUI = function()
    -- Tìm trong PlayerGui
    for _, gui in pairs(Player.PlayerGui:GetChildren()) do
        if gui:IsA("ScreenGui") then
            -- Tìm frame chứa các phần thưởng
            local rewardsFrame = gui:FindFirstChild("REWARDS", true) 
            if rewardsFrame then
                return rewardsFrame.Parent
            end
            
            -- Tìm theo tên khác nếu không tìm thấy
            for _, obj in pairs(gui:GetDescendants()) do
                if obj:IsA("TextLabel") and (obj.Text == "REWARDS" or obj.Text:find("REWARD")) then
                    return obj.Parent
                end
            end
        end
    end
    return nil
end

-- Theo dõi phần thưởng "RECEIVED"
findReceivedFrame = function()
    -- Thêm thông báo debug
    print("Đang tìm kiếm UI RECEIVED...")
    
    for _, gui in pairs(Player.PlayerGui:GetChildren()) do
        if gui:IsA("ScreenGui") then
            -- Phương pháp 1: Tìm trực tiếp label RECEIVED
            for _, obj in pairs(gui:GetDescendants()) do
                if obj:IsA("TextLabel") and obj.Text == "RECEIVED" then
                    print("Đã tìm thấy label RECEIVED qua TextLabel")
                    return obj.Parent
                end
            end
            
            -- Phương pháp 2: Tìm ImageLabel hoặc Frame có tên là RECEIVED
            local receivedFrame = gui:FindFirstChild("RECEIVED", true)
            if receivedFrame then
                print("Đã tìm thấy RECEIVED qua FindFirstChild")
                return receivedFrame.Parent
            end
            
            -- Phương pháp 3: Tìm các Frame chứa phần thưởng 
            for _, frame in pairs(gui:GetDescendants()) do
                if (frame:IsA("Frame") or frame:IsA("ScrollingFrame")) and
                   (frame.Name:upper():find("RECEIVED") or 
                    (frame.Name:upper():find("REWARD") and not frame.Name:upper():find("REWARDS"))) then
                    print("Đã tìm thấy RECEIVED qua tên Frame: " .. frame.Name)
                    return frame
                end
            end
            
            -- Phương pháp 4: Tìm các phần thưởng đặc trưng trong RECEIVED
            for _, frame in pairs(gui:GetDescendants()) do
                if frame:IsA("Frame") or frame:IsA("ImageLabel") then
                    -- Đếm số lượng item trong frame
                    local itemCount = 0
                    local hasPercentage = false
                    
                    for _, child in pairs(frame:GetDescendants()) do
                        if child:IsA("TextLabel") then
                            -- Kiểm tra phần trăm (dấu hiệu của item)
                            if child.Text:match("^%d+%.?%d*%%$") then
                                hasPercentage = true
                            end
                            
                            -- Kiểm tra "POWDER", "GEMS", "TICKETS" (dấu hiệu của item)
                            if child.Text:find("POWDER") or child.Text:find("GEMS") or child.Text:find("TICKETS") then
                                itemCount = itemCount + 1
                            end
                        end
                    end
                    
                    -- Nếu frame chứa nhiều loại item và có phần trăm, có thể là RECEIVED
                    if itemCount >= 2 and hasPercentage and not frame.Name:upper():find("REWARDS") then
                        print("Đã tìm thấy RECEIVED qua việc phân tích nội dung: " .. frame.Name)
                        return frame
                    end
                end
            end
        end
    end
    
    print("KHÔNG thể tìm thấy UI RECEIVED, tiếp tục tìm với cách khác...")
    
    -- Phương pháp cuối: Tìm một frame bất kỳ chứa TextLabel "POWDER", không thuộc REWARDS
    for _, gui in pairs(Player.PlayerGui:GetChildren()) do
        if gui:IsA("ScreenGui") then
            for _, frame in pairs(gui:GetDescendants()) do
                if (frame:IsA("Frame") or frame:IsA("ImageLabel")) and not frame.Name:upper():find("REWARDS") then
                    for _, child in pairs(frame:GetDescendants()) do
                        if child:IsA("TextLabel") and 
                           (child.Text:find("POWDER") or child.Text:find("GEMS")) and
                           not frame:FindFirstChild("REWARDS", true) then
                            local parentName = frame.Parent and frame.Parent.Name or "unknown"
                            print("Tìm thấy frame có thể là RECEIVED: " .. frame.Name .. " (Parent: " .. parentName .. ")")
                            return frame
                        end
                    end
                end
            end
        end
    end
    
    return nil
end

-- Tìm frame thông báo phần thưởng mới "YOU GOT A NEW REWARD!"
findNewRewardNotification = function()
    for _, gui in pairs(Player.PlayerGui:GetChildren()) do
        if gui:IsA("ScreenGui") then
            for _, obj in pairs(gui:GetDescendants()) do
                if obj:IsA("TextLabel") and obj.Text:find("YOU GOT A NEW REWARD") then
                    return obj.Parent
                end
            end
        end
    end
    return nil
end

-- Đọc số lượng item thực tế từ UI RECEIVED
readActualItemQuantities = function()
    local receivedUI = findReceivedFrame()
    if not receivedUI then 
        print("Không tìm thấy UI RECEIVED để đọc số lượng")
        return 
    end
    
    print("Đang đọc phần thưởng từ RECEIVED UI: " .. receivedUI:GetFullName())
    
    -- Reset playerItems để cập nhật lại
    playerItems = {}
    local foundAnyItem = false
    
    -- Debug: In ra tất cả con của receivedUI
    print("Các phần tử con của RECEIVED UI:")
    for i, child in pairs(receivedUI:GetChildren()) do
        print("  " .. i .. ": " .. child.Name .. " [" .. child.ClassName .. "]")
    end
    
    for _, itemFrame in pairs(receivedUI:GetChildren()) do
        if itemFrame:IsA("Frame") or itemFrame:IsA("ImageLabel") then
            local itemType = ""
            local baseQuantity = 0
            local multiplier = 1
            
            -- Debug: In thông tin từng frame
            print("Đang phân tích frame: " .. itemFrame.Name)
            
            -- Tìm tên item và số lượng
            for _, child in pairs(itemFrame:GetDescendants()) do
                if child:IsA("TextLabel") then
                    local text = child.Text
                    print("  TextLabel: '" .. text .. "'")
                    
                    -- Tìm loại item (GEMS, POWDER, TICKETS, v.v.)
                    local foundItemType = text:match("(%w+)%s*%(%d+%)") or text:match("(%w+)%s*$")
                    if foundItemType then
                        itemType = foundItemType
                        print("    Phát hiện loại item: " .. itemType)
                    end
                    
                    -- Tìm số lượng trong ngoặc - ví dụ: GEMS(1)
                    local foundQuantity = extractQuantity(text)
                    if foundQuantity then
                        multiplier = foundQuantity
                        print("    Phát hiện số lượng từ ngoặc (multiplier): " .. multiplier)
                    end
                    
                    -- Tìm số lượng đứng trước tên item - ví dụ: 500 GEMS
                    local amountPrefix = text:match("^(%d+)%s+%w+")
                    if amountPrefix then
                        baseQuantity = tonumber(amountPrefix)
                        print("    Phát hiện số lượng cơ bản: " .. baseQuantity)
                    end
                end
            end
            
            -- Tính toán số lượng thực tế bằng cách nhân số lượng cơ bản với hệ số từ ngoặc
            local finalQuantity = baseQuantity * multiplier
            print("    Số lượng cuối cùng: " .. baseQuantity .. " x " .. multiplier .. " = " .. finalQuantity)
            
            -- Chỉ lưu các phần thưởng không phải CASH
            if itemType ~= "" and finalQuantity > 0 and not isCashReward(itemType) then
                playerItems[itemType] = (playerItems[itemType] or 0) + finalQuantity
                print("Đã đọc item: " .. finalQuantity .. " " .. itemType .. " (từ " .. baseQuantity .. " x " .. multiplier .. ")")
                foundAnyItem = true
            elseif itemType ~= "" and finalQuantity > 0 then
                print("Bỏ qua item CASH: " .. finalQuantity .. " " .. itemType)
            end
        end
    end
    
    -- Cố gắng đọc theo cách khác nếu không tìm thấy item nào
    if not foundAnyItem then
        print("Không tìm thấy item nào bằng phương pháp thông thường, thử phương pháp thay thế...")
        
        -- Tìm tất cả TextLabel trong receivedUI có chứa GEMS, POWDER, TICKETS
        for _, child in pairs(receivedUI:GetDescendants()) do
            if child:IsA("TextLabel") then
                local text = child.Text
                
                -- Tìm item có pattern X ITEM_TYPE(Y)
                local baseAmount, itemType, multiplier = text:match("(%d+)%s+([%w%s]+)%((%d+)%)")
                if baseAmount and itemType and multiplier then
                    baseAmount = tonumber(baseAmount)
                    multiplier = tonumber(multiplier)
                    local finalAmount = baseAmount * multiplier
                    
                    if not isCashReward(itemType) then
                        playerItems[itemType] = (playerItems[itemType] or 0) + finalAmount
                        print("Phương pháp thay thế - Đã đọc item: " .. finalAmount .. " " .. itemType .. " (từ " .. baseAmount .. " x " .. multiplier .. ")")
                        foundAnyItem = true
                    end
                end
            end
        end
    end
    
    -- Hiển thị tất cả các item đã đọc được
    print("----- Danh sách item hiện có (không bao gồm CASH) -----")
    if next(playerItems) ~= nil then
        for itemType, amount in pairs(playerItems) do
            print(itemType .. ": " .. amount)
        end
    else
        print("Không đọc được bất kỳ item nào từ UI RECEIVED!")
    end
    print("------------------------------------------------------")
    
    return playerItems
end

-- Cập nhật tổng phần thưởng
local function updateTotalRewards(rewardText)
    local amount, itemType = parseReward(rewardText)
    
    if amount and itemType then
        -- Bỏ qua CASH
        if isCashReward(itemType) then
            print("Bỏ qua cập nhật CASH: " .. amount .. " " .. itemType)
            return
        end
        
        if not totalRewards[itemType] then
            totalRewards[itemType] = amount
        else
            totalRewards[itemType] = totalRewards[itemType] + amount
        end
        print("Đã cập nhật tổng phần thưởng: " .. amount .. " " .. itemType)
    end
end

-- Tạo chuỗi tổng hợp tất cả phần thưởng
local function getTotalRewardsText()
    local result = "Tổng phần thưởng:\n"
    
    -- Đọc số lượng item thực tế từ UI
    readActualItemQuantities()
    
    -- Ưu tiên hiển thị số liệu từ playerItems nếu có
    if next(playerItems) ~= nil then
        for itemType, amount in pairs(playerItems) do
            -- Loại bỏ CASH (thêm biện pháp bảo vệ)
            if not isCashReward(itemType) then
                result = result .. "- " .. amount .. " " .. itemType .. "\n"
            end
        end
    else
        -- Sử dụng totalRewards nếu không đọc được từ UI
        for itemType, amount in pairs(totalRewards) do
            -- Loại bỏ CASH (thêm biện pháp bảo vệ)
            if not isCashReward(itemType) then
                result = result .. "- " .. amount .. " " .. itemType .. "\n"
            end
        end
    end
    
    return result
end

-- Tạo chuỗi hiển thị các phần thưởng vừa nhận
local function getLatestRewardsText(newRewardInfo)
    -- Loại bỏ các tiền tố không cần thiết
    local cleanRewardInfo = newRewardInfo:gsub("RECEIVED:%s*", "")
    cleanRewardInfo = cleanRewardInfo:gsub("YOU GOT A NEW REWARD!%s*", "")
    
    local amount, itemType = parseReward(cleanRewardInfo)
    local result = "Phần thưởng mới:\n- " .. cleanRewardInfo .. "\n\n"
    
    -- Chỉ hiển thị tổng nếu không phải CASH
    if amount and itemType and playerItems[itemType] and not isCashReward(itemType) then
        result = result .. "Tổng " .. itemType .. ": " .. playerItems[itemType] .. " (+" .. amount .. ")\n"
    end
    
    return result
end

-- Kiểm tra xem có thể gửi webhook không (cooldown)
local function canSendWebhook()
    local currentTime = tick()
    if currentTime - lastWebhookTime < WEBHOOK_COOLDOWN then
        return false
    end
    return true
end

-- Gửi webhook thử nghiệm để kiểm tra kết nối
sendTestWebhook = function(customMessage)
    -- Nếu đang xử lý phần thưởng khác, không gửi webhook thử nghiệm
    if isProcessingReward then
        print("Đang xử lý phần thưởng khác, không thể gửi webhook thử nghiệm")
        return false
    end
    
    -- Đánh dấu đang xử lý
    isProcessingReward = true
    
    local message = customMessage or "Đây là webhook thử nghiệm từ Arise Crossover Rewards Tracker"
    
    local data = {
        content = nil,
        embeds = {
            {
                title = "🔍 Arise Crossover - Webhook Thử Nghiệm",
                description = message,
                color = 5814783, -- Màu tím
                fields = {
                    {
                        name = "Thời gian",
                        value = os.date("%d/%m/%Y %H:%M:%S"),
                        inline = true
                    },
                    {
                        name = "Người chơi",
                        value = Player.Name,
                        inline = true
                    }
                },
                footer = {
                    text = "Arise Crossover Rewards Tracker - Kiểm tra webhook"
                }
            }
        }
    }
    
    -- Chuyển đổi dữ liệu thành chuỗi JSON
    local jsonData = HttpService:JSONEncode(data)
    
    print("Đang gửi webhook thử nghiệm...")
    
    -- Sử dụng HTTP request từ executor
    local success, err = pcall(function()
        -- Synapse X
        if syn and syn.request then
            syn.request({
                Url = CONFIG.WEBHOOK_URL,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json"
                },
                Body = jsonData
            })
            print("Đã gửi webhook thử nghiệm qua syn.request")
        -- KRNL, Script-Ware và nhiều executor khác
        elseif request then
            request({
                Url = CONFIG.WEBHOOK_URL,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json"
                },
                Body = jsonData
            })
            print("Đã gửi webhook thử nghiệm qua request")
        -- Các Executor khác
        elseif http and http.request then
            http.request({
                Url = CONFIG.WEBHOOK_URL,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json"
                },
                Body = jsonData
            })
            print("Đã gửi webhook thử nghiệm qua http.request")
        -- JJSploit và một số executor khác
        elseif httppost then
            httppost(CONFIG.WEBHOOK_URL, jsonData)
            print("Đã gửi webhook thử nghiệm qua httppost")
        else
            error("Không tìm thấy HTTP API nào được hỗ trợ bởi executor hiện tại")
        end
    end)
    
    -- Kết thúc xử lý
    wait(0.5)
    isProcessingReward = false
    
    if success then
        print("Đã gửi webhook thử nghiệm thành công")
        return true
    else
        warn("Lỗi gửi webhook thử nghiệm: " .. tostring(err))
        return false
    end
end

-- Tạo UI cấu hình Webhook
local function createWebhookUI()
    if webhookUI then
        webhookUI:Destroy()
    end
    
    -- Tạo UI
    webhookUI = Instance.new("ScreenGui")
    webhookUI.Name = "AriseWebhookUI"
    webhookUI.ResetOnSpawn = false
    webhookUI.Parent = Player.PlayerGui
    
    -- Frame chính
    local mainFrame = Instance.new("Frame")
    mainFrame.Size = UDim2.new(0, 300, 0, 200)
    mainFrame.Position = CONFIG.UI_POSITION
    mainFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    mainFrame.BorderSizePixel = 0
    mainFrame.Active = true
    mainFrame.Draggable = true
    mainFrame.Parent = webhookUI
    
    -- Tạo hiệu ứng góc bo tròn
    local UICorner = Instance.new("UICorner")
    UICorner.CornerRadius = UDim.new(0, 10)
    UICorner.Parent = mainFrame
    
    -- Tiêu đề
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, 0, 0, 30)
    titleLabel.Position = UDim2.new(0, 0, 0, 0)
    titleLabel.BackgroundColor3 = Color3.fromRGB(60, 60, 180)
    titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.Text = "Arise Webhook - " .. playerName  -- Hiển thị tên người chơi trong tiêu đề
    titleLabel.TextSize = 16
    titleLabel.BorderSizePixel = 0
    titleLabel.Parent = mainFrame
    
    -- Bo tròn cho tiêu đề
    local titleCorner = Instance.new("UICorner")
    titleCorner.CornerRadius = UDim.new(0, 10)
    titleCorner.Parent = titleLabel
    
    -- Nhãn URL
    local urlLabel = Instance.new("TextLabel")
    urlLabel.Size = UDim2.new(0.3, 0, 0, 25)
    urlLabel.Position = UDim2.new(0.05, 0, 0.2, 0)
    urlLabel.BackgroundTransparency = 1
    urlLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    urlLabel.Font = Enum.Font.Gotham
    urlLabel.Text = "URL:"
    urlLabel.TextSize = 14
    urlLabel.TextXAlignment = Enum.TextXAlignment.Left
    urlLabel.Parent = mainFrame
    
    -- Khung nhập URL
    local urlInput = Instance.new("TextBox")
    urlInput.Size = UDim2.new(0.9, 0, 0, 25)
    urlInput.Position = UDim2.new(0.05, 0, 0.3, 0)
    urlInput.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    urlInput.TextColor3 = Color3.fromRGB(255, 255, 255)
    urlInput.Font = Enum.Font.Gotham
    urlInput.PlaceholderText = "Nhập URL webhook Discord..."
    urlInput.Text = CONFIG.WEBHOOK_URL ~= "YOUR_URL" and CONFIG.WEBHOOK_URL or ""
    urlInput.TextSize = 14
    urlInput.BorderSizePixel = 0
    urlInput.ClearTextOnFocus = false
    urlInput.Parent = mainFrame
    
    -- Bo tròn cho khung nhập
    local inputCorner = Instance.new("UICorner")
    inputCorner.CornerRadius = UDim.new(0, 5)
    inputCorner.Parent = urlInput
    
    -- Nút Lưu
    local saveButton = Instance.new("TextButton")
    saveButton.Size = UDim2.new(0.4, 0, 0, 30)
    saveButton.Position = UDim2.new(0.05, 0, 0.5, 0)
    saveButton.BackgroundColor3 = Color3.fromRGB(76, 175, 80)
    saveButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    saveButton.Font = Enum.Font.GothamBold
    saveButton.Text = "Lưu URL"
    saveButton.TextSize = 14
    saveButton.BorderSizePixel = 0
    saveButton.Parent = mainFrame
    
    -- Bo tròn cho nút lưu
    local saveCorner = Instance.new("UICorner")
    saveCorner.CornerRadius = UDim.new(0, 5)
    saveCorner.Parent = saveButton
    
    -- Nút Kiểm Tra
    local testButton = Instance.new("TextButton")
    testButton.Size = UDim2.new(0.4, 0, 0, 30)
    testButton.Position = UDim2.new(0.55, 0, 0.5, 0)
    testButton.BackgroundColor3 = Color3.fromRGB(33, 150, 243)
    testButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    testButton.Font = Enum.Font.GothamBold
    testButton.Text = "Kiểm Tra"
    testButton.TextSize = 14
    testButton.BorderSizePixel = 0
    testButton.Parent = mainFrame
    
    -- Bo tròn cho nút kiểm tra
    local testCorner = Instance.new("UICorner")
    testCorner.CornerRadius = UDim.new(0, 5)
    testCorner.Parent = testButton
    
    -- Trạng thái
    local statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(0.9, 0, 0, 25)
    statusLabel.Position = UDim2.new(0.05, 0, 0.7, 0)
    statusLabel.BackgroundTransparency = 1
    statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.Text = "Trạng thái: Chưa kiểm tra"
    statusLabel.TextSize = 14
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.Parent = mainFrame
    
    -- Nút Đóng
    local closeButton = Instance.new("TextButton")
    closeButton.Size = UDim2.new(0, 25, 0, 25)
    closeButton.Position = UDim2.new(1, -30, 0, 3)
    closeButton.BackgroundColor3 = Color3.fromRGB(255, 75, 75)
    closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeButton.Font = Enum.Font.GothamBold
    closeButton.Text = "X"
    closeButton.TextSize = 14
    closeButton.BorderSizePixel = 0
    closeButton.Parent = mainFrame
    
    -- Bo tròn cho nút đóng
    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = UDim.new(0, 5)
    closeCorner.Parent = closeButton
    
    -- Xử lý sự kiện nút Lưu
    saveButton.MouseButton1Click:Connect(function()
        local newUrl = urlInput.Text
        if newUrl ~= "" and newUrl ~= CONFIG.WEBHOOK_URL then
            CONFIG.WEBHOOK_URL = newUrl
            WEBHOOK_URL = newUrl  -- Cập nhật biến toàn cục
            
            -- Lưu vào file cấu hình
            if saveConfig(CONFIG) then
                statusLabel.Text = "Trạng thái: Đã lưu URL mới cho " .. playerName
            else
                statusLabel.Text = "Trạng thái: Đã lưu URL mới (không lưu được file)"
            end
            
            statusLabel.TextColor3 = Color3.fromRGB(76, 175, 80)
        else
            statusLabel.Text = "Trạng thái: URL không thay đổi"
            statusLabel.TextColor3 = Color3.fromRGB(255, 235, 59)
        end
    end)
    
    -- Xử lý sự kiện nút Kiểm Tra
    testButton.MouseButton1Click:Connect(function()
        statusLabel.Text = "Trạng thái: Đang kiểm tra..."
        statusLabel.TextColor3 = Color3.fromRGB(33, 150, 243)
        
        -- Thử gửi webhook kiểm tra
        local success = sendTestWebhook("Kiểm tra kết nối từ Arise Crossover Rewards Tracker")
        
        if success then
            statusLabel.Text = "Trạng thái: Kiểm tra thành công!"
            statusLabel.TextColor3 = Color3.fromRGB(76, 175, 80)
        else
            statusLabel.Text = "Trạng thái: Kiểm tra thất bại!"
            statusLabel.TextColor3 = Color3.fromRGB(255, 75, 75)
        end
    end)
    
    -- Xử lý sự kiện nút Đóng
    closeButton.MouseButton1Click:Connect(function()
        -- Thay đổi: Không chỉ ẩn UI mà còn tắt hoàn toàn script
        local confirmShutdown = Instance.new("Frame")
        confirmShutdown.Size = UDim2.new(0, 250, 0, 100)
        confirmShutdown.Position = UDim2.new(0.5, -125, 0.5, -50)
        confirmShutdown.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
        confirmShutdown.BorderSizePixel = 0
        confirmShutdown.ZIndex = 10
        confirmShutdown.Parent = webhookUI
        
        -- Bo tròn cho khung xác nhận
        local confirmCorner = Instance.new("UICorner")
        confirmCorner.CornerRadius = UDim.new(0, 10)
        confirmCorner.Parent = confirmShutdown
        
        -- Tiêu đề xác nhận
        local confirmTitle = Instance.new("TextLabel")
        confirmTitle.Size = UDim2.new(1, 0, 0, 30)
        confirmTitle.Position = UDim2.new(0, 0, 0, 0)
        confirmTitle.BackgroundColor3 = Color3.fromRGB(255, 75, 75)
        confirmTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
        confirmTitle.Font = Enum.Font.GothamBold
        confirmTitle.Text = "Xác nhận đóng script"
        confirmTitle.TextSize = 14
        confirmTitle.BorderSizePixel = 0
        confirmTitle.ZIndex = 10
        confirmTitle.Parent = confirmShutdown
        
        -- Bo tròn cho tiêu đề
        local titleConfirmCorner = Instance.new("UICorner")
        titleConfirmCorner.CornerRadius = UDim.new(0, 10)
        titleConfirmCorner.Parent = confirmTitle
        
        -- Nội dung xác nhận
        local confirmText = Instance.new("TextLabel")
        confirmText.Size = UDim2.new(1, 0, 0, 40)
        confirmText.Position = UDim2.new(0, 0, 0, 30)
        confirmText.BackgroundTransparency = 1
        confirmText.TextColor3 = Color3.fromRGB(255, 255, 255)
        confirmText.Font = Enum.Font.Gotham
        confirmText.Text = "Bạn có muốn tắt hoàn toàn script không?"
        confirmText.TextSize = 12
        confirmText.ZIndex = 10
        confirmText.Parent = confirmShutdown
        
        -- Nút Hủy
        local cancelButton = Instance.new("TextButton")
        cancelButton.Size = UDim2.new(0.4, 0, 0, 25)
        cancelButton.Position = UDim2.new(0.08, 0, 0.7, 0)
        cancelButton.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
        cancelButton.TextColor3 = Color3.fromRGB(255, 255, 255)
        cancelButton.Font = Enum.Font.GothamBold
        cancelButton.Text = "Chỉ Ẩn UI"
        cancelButton.TextSize = 12
        cancelButton.BorderSizePixel = 0
        cancelButton.ZIndex = 10
        cancelButton.Parent = confirmShutdown
        
        -- Bo tròn cho nút hủy
        local cancelCorner = Instance.new("UICorner")
        cancelCorner.CornerRadius = UDim.new(0, 5)
        cancelCorner.Parent = cancelButton
        
        -- Nút Xác Nhận
        local confirmButton = Instance.new("TextButton")
        confirmButton.Size = UDim2.new(0.4, 0, 0, 25)
        confirmButton.Position = UDim2.new(0.52, 0, 0.7, 0)
        confirmButton.BackgroundColor3 = Color3.fromRGB(255, 75, 75)
        confirmButton.TextColor3 = Color3.fromRGB(255, 255, 255)
        confirmButton.Font = Enum.Font.GothamBold
        confirmButton.Text = "Tắt Script"
        confirmButton.TextSize = 12
        confirmButton.BorderSizePixel = 0
        confirmButton.ZIndex = 10
        confirmButton.Parent = confirmShutdown
        
        -- Bo tròn cho nút xác nhận
        local confirmButtonCorner = Instance.new("UICorner")
        confirmButtonCorner.CornerRadius = UDim.new(0, 5)
        confirmButtonCorner.Parent = confirmButton
        
        -- Xử lý sự kiện nút Hủy
        cancelButton.MouseButton1Click:Connect(function()
            confirmShutdown:Destroy()
            mainFrame.Visible = false  -- Chỉ ẩn UI
        end)
        
        -- Xử lý sự kiện nút Xác Nhận
        confirmButton.MouseButton1Click:Connect(function()
            confirmShutdown:Destroy()
            shutdownScript()  -- Tắt hoàn toàn script
        end)
    end)
    
    -- Tạo nút mở UI
    local openButton = Instance.new("TextButton")
    openButton.Size = UDim2.new(0, 150, 0, 30)  -- Làm rộng nút để hiển thị tên người chơi
    openButton.Position = UDim2.new(0, 10, 0, 10)
    openButton.BackgroundColor3 = Color3.fromRGB(60, 60, 180)
    openButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    openButton.Font = Enum.Font.GothamBold
    openButton.Text = "Webhook - " .. playerName:sub(1, 10)  -- Thêm tên người chơi (giới hạn 10 ký tự)
    openButton.TextSize = 12
    openButton.BorderSizePixel = 0
    openButton.Parent = webhookUI
    
    -- Bo tròn cho nút mở
    local openCorner = Instance.new("UICorner")
    openCorner.CornerRadius = UDim.new(0, 5)
    openCorner.Parent = openButton
    
    -- Xử lý sự kiện nút Mở
    openButton.MouseButton1Click:Connect(function()
        mainFrame.Visible = not mainFrame.Visible
    end)
    
    -- Mặc định ẩn frame chính nếu không hiển thị UI
    mainFrame.Visible = CONFIG.SHOW_UI
    
    return webhookUI
end

-- Gửi thông tin đến Discord webhook (sử dụng HTTP request từ executor)
local function sendWebhook(rewardInfo, rewardObject, isNewReward)
    -- Loại bỏ các tiền tố không cần thiết
    local cleanRewardInfo = rewardInfo:gsub("RECEIVED:%s*", "")
    cleanRewardInfo = cleanRewardInfo:gsub("YOU GOT A NEW REWARD!%s*", "")
    
    -- Bỏ qua nếu phần thưởng là CASH
    if isCashReward(cleanRewardInfo) then
        print("Bỏ qua gửi webhook cho CASH: " .. cleanRewardInfo)
        return
    end
    
    -- Kiểm tra xem có đang xử lý phần thưởng khác không
    if isProcessingReward then
        print("Đang xử lý phần thưởng khác, bỏ qua...")
        return
    end
    
    -- Kiểm tra cooldown
    if not canSendWebhook() then
        print("Cooldown webhook còn " .. math.floor(WEBHOOK_COOLDOWN - (tick() - lastWebhookTime)) .. " giây, bỏ qua...")
        return
    end
    
    -- Tạo ID duy nhất và kiểm tra trùng lặp
    local rewardId = createUniqueRewardId(cleanRewardInfo)
    if receivedRewards[rewardId] then
        print("Phần thưởng này đã được gửi trước đó: " .. cleanRewardInfo)
        return
    end
    
    -- Đánh dấu đang xử lý
    isProcessingReward = true
    lastWebhookTime = tick()
    
    -- Đánh dấu đã nhận
    receivedRewards[rewardId] = true
    
    -- Đọc số lượng item thực tế trước khi gửi webhook
    readActualItemQuantities()
    
    local title = "🎁 Arise Crossover - AFKRewards"
    local description = "Phần thưởng mới đã nhận được!"
    
    -- Cập nhật tổng phần thưởng
    updateTotalRewards(cleanRewardInfo)
    
    local data = {
        content = nil,
        embeds = {
            {
                title = title,
                description = description,
                color = 7419530, -- Màu xanh biển
                fields = {
                    {
                        name = "Thông tin phần thưởng",
                        value = getLatestRewardsText(cleanRewardInfo),
                        inline = false
                    },
                    {
                        name = "Thời gian",
                        value = os.date("%d/%m/%Y %H:%M:%S"),
                        inline = true
                    },
                    {
                        name = "Người chơi",
                        value = Player.Name,
                        inline = true
                    },
                    {
                        name = "Tổng hợp phần thưởng",
                        value = getTotalRewardsText(),
                        inline = false
                    }
                },
                footer = {
                    text = "Arise Crossover Rewards Tracker"
                }
            }
        }
    }
    
    -- Chuyển đổi dữ liệu thành chuỗi JSON
    local jsonData = HttpService:JSONEncode(data)
    
    -- Cập nhật URL từ cấu hình
    local currentWebhookUrl = CONFIG.WEBHOOK_URL
    
    -- Sử dụng HTTP request từ executor thay vì HttpService
    local success, err = pcall(function()
        -- Synapse X
        if syn and syn.request then
            syn.request({
                Url = currentWebhookUrl,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json"
                },
                Body = jsonData
            })
        -- KRNL, Script-Ware và nhiều executor khác
        elseif request then
            request({
                Url = currentWebhookUrl,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json"
                },
                Body = jsonData
            })
        -- Các Executor khác
        elseif http and http.request then
            http.request({
                Url = currentWebhookUrl,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json"
                },
                Body = jsonData
            })
        -- JJSploit và một số executor khác
        elseif httppost then
            httppost(currentWebhookUrl, jsonData)
        else
            error("Không tìm thấy HTTP API nào được hỗ trợ bởi executor hiện tại")
        end
    end)
    
    if success then
        print("Đã gửi phần thưởng thành công: " .. cleanRewardInfo)
    else
        warn("Lỗi gửi webhook: " .. tostring(err))
    end
    
    -- Kết thúc xử lý
    wait(0.5) -- Chờ một chút để tránh xử lý quá nhanh
    isProcessingReward = false
end

-- Set này dùng để theo dõi đã gửi webhook của phần thưởng
local sentRewards = {}

-- Kiểm tra phần thưởng mới từ thông báo "YOU GOT A NEW REWARD!"
checkNewRewardNotification = function(notificationContainer)
    if not notificationContainer then return end
    
    -- Tìm các thông tin phần thưởng trong thông báo
    local rewardText = ""
    
    for _, child in pairs(notificationContainer:GetDescendants()) do
        if child:IsA("TextLabel") and not child.Text:find("YOU GOT") then
            rewardText = rewardText .. child.Text .. " "
        end
    end
    
    -- Nếu tìm thấy thông tin phần thưởng
    if rewardText ~= "" then
        -- Tạo ID để kiểm tra
        local rewardId = createUniqueRewardId(rewardText)
        
        -- Nếu chưa gửi phần thưởng này
        if not sentRewards[rewardId] then
            sentRewards[rewardId] = true
            
            -- Đọc số lượng item hiện tại trước
            readActualItemQuantities()
            -- Gửi webhook với thông tin phần thưởng mới
            sendWebhook(rewardText, notificationContainer, true)
            return true
        end
    end
    
    return false
end

-- Kiểm tra phần thưởng mới
checkNewRewards = function(rewardsContainer)
    if not rewardsContainer then return end
    
    for _, rewardObject in pairs(rewardsContainer:GetChildren()) do
        if rewardObject:IsA("Frame") or rewardObject:IsA("ImageLabel") then
            -- Tìm các text label trong phần thưởng
            local rewardText = ""
            
            for _, child in pairs(rewardObject:GetDescendants()) do
                if child:IsA("TextLabel") then
                    rewardText = rewardText .. child.Text .. " "
                end
            end
            
            -- Nếu là phần thưởng có dữ liệu
            if rewardText ~= "" then
                -- Tạo ID để kiểm tra
                local rewardId = createUniqueRewardId(rewardText)
                
                -- Nếu chưa gửi phần thưởng này
                if not sentRewards[rewardId] then
                    sentRewards[rewardId] = true
                    sendWebhook(rewardText, rewardObject, false)
                end
            end
        end
    end
end

-- Kiểm tra khi nhận được phần thưởng mới
checkReceivedRewards = function(receivedContainer)
    if not receivedContainer then return end
    
    -- Đọc số lượng item hiện tại
    readActualItemQuantities()
    
    -- Ghi nhận đã kiểm tra RECEIVED
    local receivedMarked = false
    
    for _, rewardObject in pairs(receivedContainer:GetChildren()) do
        if rewardObject:IsA("Frame") or rewardObject:IsA("ImageLabel") then
            local rewardText = ""
            
            for _, child in pairs(rewardObject:GetDescendants()) do
                if child:IsA("TextLabel") then
                    rewardText = rewardText .. child.Text .. " "
                end
            end
            
            -- Nếu là phần thưởng có dữ liệu và chưa ghi nhận RECEIVED
            if rewardText ~= "" and not receivedMarked then
                receivedMarked = true
                
                -- Không gửi webhook từ phần RECEIVED nữa, chỉ ghi nhận đã đọc
                -- Webhook sẽ được gửi từ NEW REWARD hoặc REWARDS
                
                -- Đánh dấu tất cả phần thưởng từ RECEIVED đã được xử lý
                local rewardId = createUniqueRewardId("RECEIVED:" .. rewardText)
                sentRewards[rewardId] = true
            end
        end
    end
end

-- Tìm kiếm các phần tử UI ban đầu
local function findAllUIElements()
    print("Đang tìm kiếm các phần tử UI...")
    local rewardsUI = findRewardsUI()
    local receivedUI = findReceivedFrame()
    local newRewardUI = findNewRewardNotification()
    
    -- Đọc số lượng item hiện tại
    readActualItemQuantities()
    
    -- Kiểm tra thông báo phần thưởng mới trước tiên
    if newRewardUI then
        print("Đã tìm thấy thông báo YOU GOT A NEW REWARD!")
        checkNewRewardNotification(newRewardUI)
    else
        print("Chưa tìm thấy thông báo phần thưởng mới")
        
        -- Nếu không có thông báo NEW REWARD, kiểm tra REWARDS
        if rewardsUI then
            print("Đã tìm thấy UI phần thưởng")
            checkNewRewards(rewardsUI)
        else
            warn("Không tìm thấy UI phần thưởng")
        end
    end
    
    -- Luôn đọc RECEIVED để cập nhật số lượng item hiện tại
    if receivedUI then
        print("Đã tìm thấy UI RECEIVED")
        checkReceivedRewards(receivedUI)
    end
    
    return rewardsUI, receivedUI, newRewardUI
end

-- Theo dõi thay đổi trong PlayerGui
local playerGuiConnection
playerGuiConnection = Player.PlayerGui.ChildAdded:Connect(function(child)
    if not scriptRunning then
        playerGuiConnection:Disconnect()
        return
    end
    
    if child:IsA("ScreenGui") then
        delay(2, function()
            if scriptRunning then
                findAllUIElements()
            end
        end)
    end
end)

-- Theo dõi sự xuất hiện của thông báo phần thưởng mới
spawn(function()
    while scriptRunning and wait(2) do
        if not scriptRunning then break end
        
        local newRewardUI = findNewRewardNotification()
        if newRewardUI then
            checkNewRewardNotification(newRewardUI)
        end
    end
end)

-- Theo dõi phần thưởng mới liên tục (với tần suất thấp hơn)
spawn(function()
    while scriptRunning and wait(5) do
        if not scriptRunning then break end
        
        -- Đọc số lượng item định kỳ
        readActualItemQuantities()
        
        -- Chỉ kiểm tra REWARDS nếu không có NEW REWARD
        local newRewardUI = findNewRewardNotification()
        if not newRewardUI then
            local rewardsUI = findRewardsUI()
            if rewardsUI then
                checkNewRewards(rewardsUI)
            end
        end
        
        -- Luôn kiểm tra RECEIVED để cập nhật số lượng
        local receivedUI = findReceivedFrame()
        if receivedUI then
            checkReceivedRewards(receivedUI)
        end
    end
end)

-- Gửi một webhook về tất cả phần thưởng hiện có trong UI RECEIVED khi khởi động script
local function sendInitialReceivedWebhook()
    print("Đang gửi webhook ban đầu về các phần thưởng hiện có...")
    
    -- Tìm UI RECEIVED và đọc dữ liệu
    local receivedUI = findReceivedFrame()
    if not receivedUI then 
        print("Không tìm thấy UI RECEIVED - thử phương án dự phòng...")
        
        -- Phương án dự phòng sẽ được giữ nguyên
        -- ...
    else
        -- Nếu tìm thấy RECEIVED UI, tiếp tục xử lý
        print("Đã tìm thấy UI RECEIVED, đang đọc dữ liệu...")
        
        -- Tạo danh sách phần thưởng thủ công bằng cách duyệt toàn bộ UI
        local receivedItems = {}
        local foundAny = false
        
        -- Tìm tất cả TextLabel trong RECEIVED UI
        for _, textLabel in pairs(receivedUI:GetDescendants()) do
            if textLabel:IsA("TextLabel") then
                local text = textLabel.Text
                
                -- Nếu chứa GEMS, POWDER hoặc TICKETS
                if (text:find("GEMS") or text:find("POWDER") or text:find("TICKETS")) and not isCashReward(text) then
                    print("Tìm thấy item text: " .. text)
                    table.insert(receivedItems, text)
                    foundAny = true
                end
            end
        end
        
        -- Không gửi webhook nếu không tìm thấy item nào
        if not foundAny then
            print("Không tìm thấy phần thưởng nào trong UI RECEIVED")
            
            -- Vẫn cập nhật lại playerItems để dùng cho lần sau
            readActualItemQuantities()
            return
        end
        
        -- Đánh dấu đang xử lý
        isProcessingReward = true
        
        local allItemsText = ""
        for _, itemText in ipairs(receivedItems) do
            allItemsText = allItemsText .. "- " .. itemText .. "\n"
        end
        
        -- Đọc số lượng item chính xác
        readActualItemQuantities()
        
        -- Hiển thị thông tin từ playerItems thay vì receivedItems
        local itemListText = ""
        if next(playerItems) ~= nil then
            for itemType, amount in pairs(playerItems) do
                itemListText = itemListText .. "- " .. amount .. " " .. itemType .. "\n"
            end
        else
            -- Sử dụng receivedItems nếu không đọc được từ playerItems
            itemListText = allItemsText
        end
        
        local data = {
            content = nil,
            embeds = {
                {
                    title = "🎮 Arise Crossover - Phần thưởng hiện có",
                    description = "Danh sách phần thưởng đã nhận khi bắt đầu chạy script",
                    color = 7419530, -- Màu xanh biển
                    fields = {
                        {
                            name = "Phần thưởng đã nhận",
                            value = itemListText ~= "" and itemListText or "Không có phần thưởng nào",
                            inline = false
                        },
                        {
                            name = "Thời gian",
                            value = os.date("%d/%m/%Y %H:%M:%S"),
                            inline = true
                        },
                        {
                            name = "Người chơi",
                            value = Player.Name,
                            inline = true
                        }
                    },
                    footer = {
                        text = "Arise Crossover Rewards Tracker - Khởi động"
                    }
                }
            }
        }
        
        -- Chuyển đổi dữ liệu thành chuỗi JSON
        local jsonData = HttpService:JSONEncode(data)
        
        print("Chuẩn bị gửi webhook với dữ liệu: " .. jsonData:sub(1, 100) .. "...")
        
        -- Sử dụng HTTP request từ executor thay vì HttpService
        local success, err = pcall(function()
            -- Synapse X
            if syn and syn.request then
                syn.request({
                    Url = CONFIG.WEBHOOK_URL,
                    Method = "POST",
                    Headers = {
                        ["Content-Type"] = "application/json"
                    },
                    Body = jsonData
                })
                print("Đã gửi webhook qua syn.request")
            -- KRNL, Script-Ware và nhiều executor khác
            elseif request then
                request({
                    Url = CONFIG.WEBHOOK_URL,
                    Method = "POST",
                    Headers = {
                        ["Content-Type"] = "application/json"
                    },
                    Body = jsonData
                })
                print("Đã gửi webhook qua request")
            -- Các Executor khác
            elseif http and http.request then
                http.request({
                    Url = CONFIG.WEBHOOK_URL,
                    Method = "POST",
                    Headers = {
                        ["Content-Type"] = "application/json"
                    },
                    Body = jsonData
                })
                print("Đã gửi webhook qua http.request")
            -- JJSploit và một số executor khác
            elseif httppost then
                httppost(CONFIG.WEBHOOK_URL, jsonData)
                print("Đã gửi webhook qua httppost")
            else
                error("Không tìm thấy HTTP API nào được hỗ trợ bởi executor hiện tại")
            end
        end)
        
        if success then
            print("Đã gửi webhook ban đầu thành công với " .. #receivedItems .. " phần thưởng")
        else
            warn("Lỗi gửi webhook ban đầu: " .. tostring(err))
        end
        
        -- Kết thúc xử lý
        wait(0.5)
        isProcessingReward = false
        lastWebhookTime = tick() -- Cập nhật thời gian gửi webhook cuối cùng
    end
end

-- Khởi tạo tìm kiếm ban đầu và tạo UI
delay(3, function()
    print("Bắt đầu tìm kiếm UI và chuẩn bị gửi webhook khởi động...")
    
    -- Tạo UI Webhook
    createWebhookUI()
    
    -- Tìm các UI
    findAllUIElements()
    
    -- Gửi webhook ban đầu ngay lập tức
    sendInitialReceivedWebhook()
    
    -- Đặt lịch kiểm tra lại sau một khoảng thời gian nếu lần đầu không thành công
    delay(5, function()
        print("Kiểm tra lại và gửi webhook khởi động lần 2...")
        sendInitialReceivedWebhook()
    end)
end)

print("Script theo dõi phần thưởng AFKRewards đã được nâng cấp:")
print("- Gửi webhook khi khởi động để thông báo các phần thưởng hiện có")
print("- Chỉ gửi MỘT webhook cho mỗi phần thưởng mới")
print("- Không hiển thị và không gửi webhook cho CASH")
print("- Kiểm tra số lượng item thực tế từ RECEIVED")
print("- Hiển thị tổng phần thưởng chính xác trong webhook")
print("- Giao diện cấu hình Webhook dễ dàng thay đổi URL và kiểm tra kết nối")
print("- Cấu hình riêng biệt cho từng tài khoản: " .. CONFIG_FILE)
print("- Giám sát phần thưởng mới với cooldown " .. WEBHOOK_COOLDOWN .. " giây") 
