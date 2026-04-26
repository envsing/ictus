local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local AbilityService = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("AbilityService")
local AbilityActivated = AbilityService:WaitForChild("ToServer"):WaitForChild("AbilityActivated____")
local AbilitySelected = AbilityService:WaitForChild("ToServer"):WaitForChild("AbilitySelected")

local REACTION_DISTANCE = 35
local VELOCITY_THRESHOLD = 45 -- Aumentado para evitar falsos positivos (Sprints normais)

local active = true
local debounceTime = 1.5

-- Tentar capturar os módulos do jogo para verificar Cooldowns e Habilidade Atual
local ClientDebounce
local AbilityHandler

pcall(function()
    ClientDebounce = require(LocalPlayer.PlayerScripts:WaitForChild("ModuleScripts"):WaitForChild("ClientDebounce"))
end)

pcall(function()
    -- Procurar o AbilityHandler real do jogo para saber o que o jogador está segurando
    for _, child in ipairs(LocalPlayer.PlayerScripts:GetDescendants()) do
        if child:IsA("ModuleScript") and child.Name:lower():match("ability") then
            local suc, res = pcall(require, child)
            if suc and type(res) == "table" and res.activeAbility ~= nil then
                AbilityHandler = res
                break
            end
        end
    end
end)

local function getRootPart(character)
    if character and character.PrimaryPart then
        return character.PrimaryPart
    end
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function fireReaction(targetCharacter)
    -- 1. Identificar qual habilidade usar (Ictus ou Motus se Ictus estiver em cooldown)
    local abilityToUse = "Ictus"
    if ClientDebounce and ClientDebounce.isAlive then
        if ClientDebounce.isAlive("Ictus") then
            abilityToUse = "Motus"
        end
    end
    
    -- 2. Identificar a habilidade atual para voltar pra ela depois
    local previousAbility = nil
    if AbilityHandler and type(AbilityHandler.activeAbility) == "table" and AbilityHandler.activeAbility._name then
        previousAbility = AbilityHandler.activeAbility._name
    end

    -- 3. Disparar a habilidade defensiva
    AbilitySelected:FireServer(abilityToUse)
    AbilityActivated:FireServer(targetCharacter)
    
    -- 4. Voltar para a habilidade que estava antes do parry
    if previousAbility and previousAbility ~= abilityToUse then
        task.delay(0.2, function()
            -- Devolve a seleção pro servidor
            AbilitySelected:FireServer(previousAbility)
            
            -- Se conseguimos acessar o Handler, tentamos forçar o client a equipar de volta
            if AbilityHandler and type(AbilityHandler.activeAbility) == "table" and AbilityHandler.activeAbility.equip then
                pcall(function()
                    -- Reequipa visualmente/logicamente no client
                    AbilityHandler.activeAbility:equip()
                end)
            end
        end)
    end
end

local function checkThreats()
    if not active then return end
    
    local myChar = LocalPlayer.Character
    local myRoot = getRootPart(myChar)
    if not myRoot then return end

    local entitiesFolder = workspace:FindFirstChild("Entities")
    local targets = entitiesFolder and entitiesFolder:GetChildren() or Players:GetPlayers()

    for _, entity in ipairs(targets) do
        local enemyChar = entity:IsA("Player") and entity.Character or entity
        
        if enemyChar and enemyChar ~= myChar then
            local enemyRoot = getRootPart(enemyChar)
            local enemyHumanoid = enemyChar:FindFirstChild("Humanoid")
            
            if enemyRoot and enemyHumanoid and enemyHumanoid.Health > 0 then
                local distance = (enemyRoot.Position - myRoot.Position).Magnitude
                
                if distance < REACTION_DISTANCE then
                    local velocity = enemyRoot.AssemblyLinearVelocity
                    
                    -- FATOR CRÍTICO: Ignorar a velocidade vertical (quedas) para evitar falsos positivos
                    local flatVelocity = Vector3.new(velocity.X, 0, velocity.Z)
                    local speed = flatVelocity.Magnitude
                    
                    -- Se a velocidade no chão for absurda (Dash do SuperKick/Slap)
                    if speed > VELOCITY_THRESHOLD then
                        local myFlatPos = Vector3.new(myRoot.Position.X, 0, myRoot.Position.Z)
                        local enemyFlatPos = Vector3.new(enemyRoot.Position.X, 0, enemyRoot.Position.Z)
                        
                        -- Vetor direção indo do inimigo para mim
                        local directionToMe = (myFlatPos - enemyFlatPos).Unit
                        local moveDirection = flatVelocity.Unit
                        
                        local dotProduct = directionToMe:Dot(moveDirection)
                        
                        -- Se o inimigo estiver vindo em linha reta na nossa direção (ângulo de investida forte)
                        if dotProduct > 0.85 then
                            fireReaction(enemyChar)
                            
                            active = false
                            task.delay(debounceTime, function()
                                active = true
                            end)
                            break
                        end
                    end
                end
            end
        end
    end
end

RunService.Stepped:Connect(checkThreats)
RunService.RenderStepped:Connect(checkThreats)

print("[AutoIctus] Auto-Parry V2: Cooldown Check, Equip-Restore e Filtro Anti-Queda (Falsos Positivos) ativados.")
