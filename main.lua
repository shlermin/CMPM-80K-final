-- gun and bullets logic
local guns = {}

local function spawnBullet(x, y, angle, speed, damage, life)
    table.insert(bullets, {
        x = x, y = y,
        angle = angle,
        speed = speed,
        damage = damage,
        life = life or 1      -- seconds before it disappears
    })
end

guns.pistol = {
    name = "Pistol",
    damage = 6,
    maxAmmo = 60,
    cooldown = 0.25,          -- seconds between shots
    bulletSpeed = 2000,
    fire = function(self, x, y, angle)
        spawnBullet(x, y, angle, self.bulletSpeed, self.damage)
    end
}

guns.shotgun = {
    name = "Shotgun",
    damage = 3,               -- per pellet
    maxAmmo = 2,
    cooldown = 0.8,
    bulletSpeed = 1000,
    pellets = 7,
    spread = math.rad(30),    -- total cone width
    fire = function(self, x, y, angle)
        for i = 1, self.pellets do
            local offset = (math.random() - 0.5) * self.spread
            spawnBullet(x, y, angle + offset, self.bulletSpeed, self.damage, 0.4)
        end
    end
}

guns.hunting_rifle = {
    name = "Hunting Rifle",
    damage = 100,
    maxAmmo = 3,
    cooldown = 1.0,
    bulletSpeed = 5000,
    automatic = true,         -- hold to keep firing
    fire = function(self, x, y, angle)
        spawnBullet(x, y, angle, self.bulletSpeed, self.damage)
    end
}

local function newGun(template)
    local g = setmetatable({}, { __index = template })  -- falls back to template fields
    g.ammo = template.maxAmmo
    g.cooldownTimer = 0
    return g
end


function love.load()
    anim8 = require 'libraries/anim8'
    camera = require 'libraries/camera'
    sti = require 'libraries/sti'
    npc = require 'libraries/npc'
    narrator = require 'libraries/narrator'
    enemies = require 'enemies'
    screens = {main = "game", current = "title"}


    --load in all audio files
    music = love.audio.newSource("audio/background_main.mp3", "stream")
    music:setLooping(true)
    music:setVolume(0.3)
    music:play()

    pistol_shot = love.audio.newSource("audio/Pistol02.ogg", "static")
    pistol_shot:setVolume(0.3)

    player_hit = love.audio.newSource("audio/hit_sound.mp3.mov", "static")
    player_hit:setVolume(0.3)

    gameMap = sti('map_test/testmap.lua')

    title = love.graphics.newImage('sprites_test/title.png')

    player = {}
    player.x = 8
    player.xtile = 2
    player.y = 64
    player.ytile = 2
    player.test = 0
    player.looking = "left"
    player.sprite = love.graphics.newImage('sprites_test/slug.png')
    player.spriteSheet = love.graphics.newImage('sprites_test/player-sheet-resized.png')
    player.grid = anim8.newGrid(48, 72, player.spriteSheet:getWidth(), player.spriteSheet:getHeight())

    player.animations = {}
    player.animations.down  = anim8.newAnimation(player.grid('1-4', 1), 0.2)
    player.animations.left  = anim8.newAnimation(player.grid('1-4', 2), 0.2)
    player.animations.right = anim8.newAnimation(player.grid('1-4', 3), 0.2)
    player.animations.up    = anim8.newAnimation(player.grid('1-4', 4), 0.2)
    player.anim = player.animations.left

    cam = camera(player.x + 24, player.y + 36)

    hole = npc.new('sprites_test/player-sheet.png', (64*4)+8,(64*5)-4, 0, 0)

    narrator:init()

    charHole = narrator:newCharacter("Hole", "sprites_test/slug.png")

    narrator:bindNPC(hole, charHole, "mysteriousHole.ink")

    background = love.graphics.newImage('sprites_test/background.png')
    bullets = {}

    reload = {
        active = false,
        phase = "enter",            -- "enter" or "load"
        enterSeq = { "lshift", "w" },    -- main sequence: starts reload mode
        loadSeq = { "a", "d" },     -- repeatable: +1 bullet each time
        closeKey = "q",        -- exits reload mode
        index = 1,
        timeout = 0.5,              -- max seconds between keys inside a sequence
        timer = 0
    }
    inventory = { newGun(guns.pistol), newGun(guns.shotgun), newGun(guns.hunting_rifle) }
    currentGunIndex = 1
    gun = inventory[currentGunIndex]  
    
    --load enemies
    enemies.load(player)

    enemies.onEnemyKilled = function(enemy)
        score = score + enemy.points
        kills = kills + 1
        if score > highscore then highscore = score end
    end

    score, kills, highscore = 0, 0, 0
    loadGame()

end

function love.quit()
    saveGame()

end

local function shoot()
    if screens.current == "title" then return end
    if not gun then return end
    if gun.ammo <= 0 or gun.cooldownTimer > 0 then return end

    -- sprite is 12x18 drawn at scale 4, so offset to roughly its center
    local px = player.x + 12 * 4 / 2
    local py = player.y + 18 * 4 / 2
    local mx, my = cam:mousePosition()
    local angle = math.atan2(my - py, mx - px)

    pistol_shot:play()
    gun:fire(px, py, angle) -- the gun decides what "firing" means
    gun.ammo = gun.ammo - 1
    gun.cooldownTimer = gun.cooldown

end

function love.mousepressed(x, y, button)
    if reload.active then return end
    if button == 1 and not gun.automatic then shoot() end
end

local function cancelReload()
    reload.active = false
    reload.index = 1
    reload.timer = 0
    reload.gun_closed = True
    reload.phase = "enter"
end

local function handleReloadKey(key)
    if reload.phase == "enter" then
        if key == reload.enterSeq[reload.index] then
            reload.index = reload.index + 1
            reload.timer = reload.timeout

            if reload.index > #reload.enterSeq then
                reload.phase = "load"
                reload.index = 1
                reload.timer = 0
            end
        else
            cancelReload()                 -- wrong key aborts entry
        end

    else -- "load" phase
        if key == reload.closeKey then
            cancelReload()                 -- keep the bullets already loaded
            return
        end

        if key == reload.loadSeq[reload.index] then
            reload.index = reload.index + 1
            reload.timer = reload.timeout

            if reload.index > #reload.loadSeq then
                gun.ammo = gun.ammo + 1  -- one bullet per completed sub-sequence
                reload.index = 1
                reload.timer = 0

                if gun.ammo >= gun.maxAmmo then
                    cancelReload()         -- full, exit automatically
                end
            end
        else
            reload.index = 1             -- typo resets the sub-sequence only
            reload.timer = 0
        end
    end
end
function obstacleAt(x, y)
    local layer = gameMap.layers["Collision"]
    return layer.data[y] and layer.data[y][x]
end 

function love.keypressed(key)
    if key == "escape" then love.event.quit() end
    
    if screens.current == "title" then
        if key == "return" then
            screens.current = "game"
        end
        return
    end

    if key == "p" then gun.ammo = gun.maxAmmo end  -- cheat code for testing

    if reload.active then
            handleReloadKey(key)
            return
        end
            -- Start the sequence
    if key == reload.enterSeq[1] and gun.ammo < gun.maxAmmo then
        reload.active = true
        reload.phase = "enter"
        reload.index = 2
        reload.timer = reload.timeout
        return
    end

    local n = tonumber(key)
    if n and inventory[n] and not reload.active then
        currentGunIndex = n
        gun = inventory[n]
    end

    local talking = narrator:isOpen()
    local mapWidth = 30
    local mapHeight = 20
    if key == "w" and not talking then 
        if player.ytile >= 2 then 
            if  not obstacleAt(player.xtile, player.ytile-1) then 
                player.ytile = player.ytile - 1
            end
        player.anim = player.animations.up
        player.looking = 0
        end
    end
    if key == "a" and not talking then 
        if player.xtile >= 2 then 
            if not  obstacleAt(player.xtile-1, player.ytile) then
                player.xtile = player.xtile - 1
            end
        player.anim = player.animations.left
        player.looking = 1
    end
    end
    if key == "s" and not talking then 
        if player.ytile < mapHeight then 
            if not obstacleAt(player.xtile, player.ytile+1) then
                player.ytile = player.ytile + 1
            end
        player.anim = player.animations.down
        player.looking = 2
        end
    end
    if key == "d" and not talking  then 
        if player.xtile < mapWidth then 
            if not obstacleAt(player.xtile+1, player.ytile)then
                player.xtile = player.xtile + 1
            end
        player.anim = player.animations.right
        player.looking = 3
        end
    end
    local xLook = player.xtile
    local yLook = player.ytile
    if player.looking == 0 then yLook = yLook - 1 end
    if player.looking == 1 then xLook = xLook - 1 end
    if player.looking == 2 then yLook = yLook + 1 end
    if player.looking == 3 then xLook = xLook + 1 end
    if key == "e" and not talking then

        if xLook == 4 and yLook == 5 then -- todo: more robust looking at system
            narrator:startScript(hole)
        end
    end
    if narrator:isOpen() then
        if key == "space" then
            narrator:onAction() end
        if key == "w" then
            narrator:prevOption() end
        if key == "s" then
            narrator:nextOption() end
   
 end
            
end

local function updateCamera(dt)
    local smoothness = 5   -- try 5-12; higher = snappier
    local t = 1 - math.exp(-smoothness * dt)

    -- target = center of the sprite
    local tx = player.x + 24
    local ty = player.y + 36
    cam:move((tx - cam.x) * t, (ty - cam.y) * t)

    -- clamp to map bounds
    local w, h = love.graphics.getDimensions()
    local mapW = gameMap.width * gameMap.tilewidth
    local mapH = gameMap.height * gameMap.tileheight

    local cx, cy = cam.x, cam.y
    if mapW > w then cx = math.max(w/2, math.min(cx, mapW - w/2)) else cx = mapW / 2 end
    if mapH > h then cy = math.max(h/2, math.min(cy, mapH - h/2)) else cy = mapH / 2 end
    cam:lookAt(cx, cy)
end


function love.update(dt)
    if screens.current == "title" then return end

    local isMoving = false
    player.x = (player.xtile-1)*64 + 8
    player.y = (player.ytile-1)*64 - 4
    updateCamera(dt)

    enemies.update(dt, player, bullets, gameMap)

    --local dialogueOpen = narrator:isOpen()

    for i = #bullets, 1, -1 do
        local b = bullets[i]
        b.x = b.x + math.cos(b.angle) * b.speed * dt
        b.y = b.y + math.sin(b.angle) * b.speed * dt
        b.life = b.life - dt
        if b.life <= 0 then table.remove(bullets, i) end
    end

    if reload.active then
        local timing = (reload.phase == "enter") or (reload.index > 1)
        if timing then
            reload.timer = reload.timer - dt
            if reload.timer <= 0 then
                if reload.phase == "enter" then
                    cancelReload()         -- took too long to enter
                else
                    reload.index = 1     -- drop the half-typed sub-sequence
                end
            end
        end
        return  -- don't move while reloading
    end 

    if gun.cooldownTimer > 0 then
        gun.cooldownTimer = gun.cooldownTimer - dt
    end

    -- automatic weapons: hold the mouse button
    if gun.automatic and love.mouse.isDown(1) then
        shoot()
    end

    --I love being offset yipee
    player.x=(player.xtile-1)*64+8
    player.y=(player.ytile-1)*64-4

    if not isMoving then
        player.anim:gotoFrame(2)
    end
    

    player.anim:update(dt)
    hole:update(dt)
    narrator:update(dt)
end
--save game state to file
local SAVE_FILE = "saves/high_score.txt"

function saveGame()
    love.filesystem.createDirectory("saves")   -- no-op if it already exists
        local data = string.format("score=%d\nkills=%d\nhighscore=%d\n",
                                score, kills, highscore)
        local ok, err = love.filesystem.write(SAVE_FILE, data)
        if not ok then print("save failed: " .. tostring(err)) end
end

function loadGame()
    if not love.filesystem.getInfo(SAVE_FILE) then return end   -- first run

    local data = {}
    for line in love.filesystem.lines(SAVE_FILE) do
        local key, value = line:match("^(%w+)=(%-?%d+)$")
        if key then data[key] = tonumber(value) end
    end
    highscore = data.highscore or 0
end

function love.draw()
    local w = love.graphics.getWidth()
    local h = love.graphics.getHeight()

    -- Get image dimensions
    local imgW = title:getWidth()
    local imgH = title:getHeight()

    -- Calculate scaling factors to fit the image to the window
    local scaleX = w / imgW
    local scaleY = h / imgH

    if screens.current == "title" then
        love.graphics.draw(title, 0, 0, 0 , scaleX, scaleY)
        love.graphics.print("Press Enter to Start", 350, 500)
        return
    end
    cam:attach()
    gameMap:drawLayer(gameMap.layers["Tile Layer 1"])
    gameMap:drawLayer(gameMap.layers["Collision"])
    gameMap:drawLayer(gameMap.layers["Interactibles"])
    --love.graphics.draw(background, 0, 0)
    player.anim:draw(player.spriteSheet, player.x, player.y, nil, 1)
    --hole:draw()
    for _, b in ipairs(bullets) do
        love.graphics.circle("fill", b.x, b.y, 5)
    end

    enemies.draw()
    cam:detach()

    love.graphics.print("Ammo: " .. gun.ammo .. " (shift W to reload - a d to add bullets)", 10, 10)
    love.graphics.print("switch gun with 1-3", 10, 30)
    love.graphics.print("current gun: " .. inventory[currentGunIndex].name, 10, 50)
    love.graphics.print("xtile: " .. player.xtile .. "ytile: " .. player.ytile, 10, 70)
    love.graphics.print("(x, y): (".. player.x .. ", " .. player.y .. ")", 10, 90)
    love.graphics.print("Score: " .. score .. "  Kills: " .. kills .. "  Best: " .. highscore, 10, 190)
    love.graphics.print("Health: " .. player.hp, 10, 210)
--    local px = player.x + 12 * 4 / 2a
 --   local py = player.y + 18 * 4 / 2
 --   local mx, my = love.mouse.getPosition()
 --   local angle = math.atan2(my - 300, mx - 400) * 57.29578
 --   love.graphics.print("(x, y): (".. mx .. ", " .. my .. ")", 10, 110)
 --   love.graphics.print("(x, y): (".. 400 .. ", " .. 300 .. ")", 10, 130)
    love.graphics.print("looking: " .. player.looking, 10, 150)
    
    -- love.graphics.print("xLook: " .. player.test, 10, 130)
    narrator:draw()
end

