-- AutoIctus V3: Detecção por Animação e Correção de Gastos de Magia
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local AbilityService = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("AbilityService")
local AbilityActivated = AbilityService:WaitForChild("ToServer"):WaitForChild("AbilityActivated____")
local AbilityStateChanged = AbilityService:WaitForChild("ToServer"):WaitForChild("AbilityStateChanged")
local AbilitySelected = AbilityService:WaitForChild("ToServer"):WaitForChild("AbilitySelected")

local active = true
local debounceTime = 1.5
local REACTION_DISTANCE = 60

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

-- Extrai os IDs das animações dinamicamente direto do banco de dados do jogo
local dangerousAnims = {}
pcall(function()
    local AbilityNameEnum = require(ReplicatedStorage.ModuleScripts.Enums.AbilityName)
    local AbilityData = require(ReplicatedStorage.ModuleScripts.Data.AbilityData)

    local function addAnims(abilityEnumName)
        local enumVal = AbilityNameEnum[abilityEnumName]
        if enumVal and AbilityData[enumVal] and AbilityData[enumVal].abilityAnimations then
            for _, animId in pairs(AbilityData[enumVal].abilityAnimations) do
                dangerousAnims[animId] = abilityEnumName
            end
        end
    end

    addAnims("HeartRip")
    addAnims("SuperKick")
    addAnims("SuperSlap")
end)

local function getRootPart(character)
    if character and character.PrimaryPart then
        return character.PrimaryPart
    end
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function fireReaction(targetCharacter)
    if not active then return end
    active = false
    task.delay(debounceTime, function() active = true end)

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

    -- 3. Trocar para a habilidade defensiva no servidor (força a mudança de estado)
    AbilitySelected:FireServer(abilityToUse)
    AbilityStateChanged:FireServer(abilityToUse)
    
    -- Aguarda 1 frame/ms para o servidor processar a troca, senão ele vai gastar a magia da sua habilidade anterior!
    task.delay(0.05, function()
        -- Dispara o Parry
        AbilityActivated:FireServer(targetCharacter)
        
        -- 4. Voltar para a habilidade que estava antes (Aguardamos 0.5s para não cancelar o Ictus no servidor)
        if previousAbility and previousAbility ~= abilityToUse then
            task.delay(0.6, function()
                AbilitySelected:FireServer(previousAbility)
                AbilityStateChanged:FireServer(previousAbility)
                
                -- Se conseguirmos acessar o Handler, forçamos o reequipar visual na sua tela
                if AbilityHandler and type(AbilityHandler.activeAbility) == "table" and AbilityHandler.activeAbility.equip then
                    pcall(function() AbilityHandler.activeAbility:equip() end)
                end
            end)
        end
    end)
end

-- Detectar via Animação (Método muito mais confiável para HeartRip e Ataques sem velocidade)
local function onAnimationPlayed(animTrack, enemyChar)
    if not active then return end
    
    local animId = animTrack.Animation.AnimationId
    -- Se a animação for de SuperKick, SuperSlap ou HeartRip
    if dangerousAnims[animId] then
        local myChar = LocalPlayer.Character
        local myRoot = getRootPart(myChar)
        local enemyRoot = getRootPart(enemyChar)
        
        if myRoot and enemyRoot then
            local distance = (enemyRoot.Position - myRoot.Position).Magnitude
            if distance < REACTION_DISTANCE then
                
                -- Verificar se o inimigo está nos atacando PELA FRENTE
                local enemyLook = enemyRoot.CFrame.LookVector
                local dirToMe = (myRoot.Position - enemyRoot.Position).Unit
                
                -- Se o dotProduct for > 0.4, ele está de frente para nós olhando na nossa direção
                if enemyLook:Dot(dirToMe) > 0.4 then
                    fireReaction(enemyChar)
                end
            end
        end
    end
end

-- Configurar a captura de animação em todos os jogadores inimigos
local function setupCharacter(character)
    local humanoid = character:WaitForChild("Humanoid", 5)
    if humanoid then
        local animator = humanoid:WaitForChild("Animator", 5)
        if animator then
            animator.AnimationPlayed:Connect(function(track)
                onAnimationPlayed(track, character)
            end)
        end
    end
end

for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then
        if player.Character then
            setupCharacter(player.Character)
        end
        player.CharacterAdded:Connect(setupCharacter)
    end
end

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(setupCharacter)
end)

print("[AutoIctus V3] Detecção por Animação")
