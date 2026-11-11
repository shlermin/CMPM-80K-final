-- enemies.lua: one-file enemy system (classes + spawning + collisions)
--
--   enemies = require 'enemies'
--   enemies.load(player)                          -- once, in love.load
--   enemies.update(dt, player, bullets, gameMap)  -- every frame
--   enemies.draw()                                -- between cam:attach()/detach()
--
-- To add an enemy type: copy one of the classes in the "ENEMY TYPES"
-- section, change its fields/methods, and add it to the `register` list.

local anim8 = require 'libraries/anim8'

local M = {
    list = {},                    -- live enemies
    classes = {},                 -- registered types
    spawnTimer = 0,
    spawnInterval = 1.5,
    maxEnemies = 15,
    playerW = 48, playerH = 72,   -- player hitbox
    playerInvulnTime = 1.0,
    score = 0,
    projectiles = {}  

}

-- ======================= BASE CLASS =======================
local Enemy = {}
Enemy.__index = Enemy

Enemy.name = "enemy"
Enemy.w, Enemy.h = 64, 64
Enemy.speed = 100
Enemy.maxHp = 10
Enemy.damage = 1                 -- contact damage to the player
Enemy.weight = 1                 -- relative spawn chance
Enemy.color = { 1, 0, 0 }        -- used when there is no image
Enemy.imagePath = nil            -- optional single static image
Enemy.despawnDistance = 2500
Enemy.points = 10   

-- Animation (anim8). Set spriteSheet to enable; otherwise the static image
-- or coloured rectangle is used.
--   spriteSheet = "path.png"
--   frameW, frameH = size of ONE frame in the sheet (in pixels)
--   animations = { name = { frames = '1-4', row = 1, duration = 0.15 }, ... }
-- The "move" animation is the default. States can switch with setAnimation().
Enemy.spriteSheet = nil
Enemy.frameW, Enemy.frameH = 32, 32
Enemy.animations = {}
Enemy.facesRight = false         -- which way the sprite art faces by default

function Enemy:extend(name)
    local cls = setmetatable({}, { __index = self })
    cls.__index = cls
    cls.super = self
    cls.name = name or cls.name
    return cls
end

function Enemy:loadAssets()
    if rawget(self, "_loaded") then return end
    self._loaded = true
    if self.imagePath then
        local ok, img = pcall(love.graphics.newImage, self.imagePath)
        if ok then self.image = img end
    end

    if self.spriteSheet then
        local ok, img = pcall(love.graphics.newImage, self.spriteSheet)
        if not ok then
            print("[enemies] could not load " .. self.spriteSheet)
            return
        end
        self.sheet = img
        self.animTemplates = {}
        local grid = anim8.newGrid(self.frameW, self.frameH,
                                   img:getWidth(), img:getHeight())
        for name, def in pairs(self.animations) do
            local good, anim = pcall(function()
                return anim8.newAnimation(grid(def.frames, def.row), def.duration)
            end)
            if good then
                self.animTemplates[name] = anim
            else
                print("[enemies] " .. self.name .. " animation '" .. name ..
                      "' does not fit the sheet: " .. tostring(anim))
            end
        end
    end
end

function Enemy:new(x, y)
    local o = setmetatable({}, self)
    o.x, o.y = x, y
    o.hp = self.maxHp
    o.dead = false
    o.faceX = -1
    o:setupAnimations()
    o:init()
    return o
end

-- Hooks to override
function Enemy:init() end
function Enemy:onSpawn(target) end       -- target = {x=, y=} player centre
function Enemy:update(dt, target) end
function Enemy:onDeath() 
end

-- Helpers
function Enemy:angleTo(tx, ty)
    local cx, cy = self:center()
    return math.atan2(ty - cy, tx - cx)
end

-- Fire a projectile from this enemy's centre
function Enemy:shoot(angle, speed, damage, life)
    local cx, cy = self:center()
    table.insert(M.projectiles, {
        x = cx, y = cy, angle = angle,
        speed = speed or 400,
        damage = damage or 1,
        life = life or 3,          -- seconds before it disappears
        radius = 15,
    })
end
function Enemy:center() return self.x + self.w / 2, self.y + self.h / 2 end

function Enemy:directionTo(tx, ty)
    local cx, cy = self:center()
    local dx, dy = tx - cx, ty - cy
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1e-6 then return 0, 0 end
    return dx / len, dy / len
end

-- Each enemy needs its own copy of the animations (they hold frame state)
function Enemy:setupAnimations()
    self.anims = {}
    for name, template in pairs(self.animTemplates or {}) do
        self.anims[name] = template:clone()
    end
    self.animName = nil
    self:setAnimation("move")
    if self.anim then   -- desync enemies spawned together
        self.anim:gotoFrame(love.math.random(#self.anim.frames))
    end
end

function Enemy:setAnimation(name)
    if self.animName == name then return end
    local anim = self.anims[name]
    if not anim then return end        -- missing animation: keep the current one
    self.animName = name
    self.anim = anim
    anim:gotoFrame(1)
end

function Enemy:animate(dt)
    if self.anim then self.anim:update(dt) end
end

-- Set which way the enemy looks (dirX < 0 = left, > 0 = right)
function Enemy:face(dirX)
    if dirX > 0.01 then self.faceX = 1 elseif dirX < -0.01 then self.faceX = -1 end
end

function Enemy:isFlipped()
    return (self.faceX == 1) ~= self.facesRight
end

function Enemy:move(dirX, dirY, speed, dt)
    self:face(dirX)
    self.x = self.x + dirX * speed * dt
    self.y = self.y + dirY * speed * dt
end

function Enemy:takeDamage(amount)
    self.hp = self.hp - amount
    if self.hp <= 0 and not self.dead then
        self.dead = true
        self:onDeath()
    end
end

function Enemy:containsPoint(px, py)
    return px >= self.x and px <= self.x + self.w
       and py >= self.y and py <= self.y + self.h
end

function Enemy:overlaps(x, y, w, h)
    return self.x < x + w and self.x + self.w > x
       and self.y < y + h and self.y + self.h > y
end

function Enemy:shouldDespawn(target)
    local cx, cy = self:center()
    local dx, dy = cx - target.x, cy - target.y
    return dx * dx + dy * dy > self.despawnDistance ^ 2
end

function Enemy:draw()
    love.graphics.setColor(1, 1, 1)

    if self.anim and self.sheet then
        local sx, sy = self.w / self.frameW, self.h / self.frameH
        if self:isFlipped() then
            -- a negative x scale mirrors the sprite to the left of its origin
            self.anim:draw(self.sheet, self.x + self.w, self.y, 0, -sx, sy)
        else
            self.anim:draw(self.sheet, self.x, self.y, 0, sx, sy)
        end
    elseif self.image then
        love.graphics.draw(self.image, self.x, self.y, 0,
            self.w / self.image:getWidth(), self.h / self.image:getHeight())
    else
        love.graphics.setColor(self.color)
        love.graphics.rectangle("fill", self.x, self.y, self.w, self.h)
    end
    love.graphics.setColor(0.2, 0.2, 0.2)
    love.graphics.rectangle("fill", self.x, self.y - 8, self.w, 5)
    love.graphics.setColor(0.9, 0.2, 0.2)
    love.graphics.rectangle("fill", self.x, self.y - 8,
        self.w * math.max(0, self.hp / self.maxHp), 5)
    love.graphics.setColor(1, 1, 1)
end

M.Enemy = Enemy

-- ======================= ENEMY TYPES =======================

local Gunfish = Enemy:extend("gunfish")
Gunfish.w, Gunfish.h = 64, 64
Gunfish.speed, Gunfish.maxHp, Gunfish.points, Gunfish.weight = 100, 25, 40, 1
Gunfish.color = { 0.9, 0.9, 0.2 }
Gunfish.preferredDistance = 250
Gunfish.fireInterval = 1.5
Gunfish.projectileSpeed = 450
Gunfish.projectileDamage = 1
Gunfish.inaccuracy = math.rad(3)       -- total random cone, 0 = perfect aim

function Gunfish:init()
    self.fireTimer = love.math.random() * self.fireInterval   -- stagger shots
end

function Gunfish:update(dt, target)
    local dx, dy = self:directionTo(target.x, target.y)
    local cx, cy = self:center()
    local dist = math.sqrt((target.x - cx) ^ 2 + (target.y - cy) ^ 2)

    -- approach if too far, back away if too close
    if dist > self.preferredDistance + 50 then
        self:move(dx, dy, self.speed, dt)
    elseif dist < self.preferredDistance - 50 then
        self:move(-dx, -dy, self.speed, dt)
    end
    self:face(dx)                      -- always look at the player

    self.fireTimer = self.fireTimer - dt
    if self.fireTimer <= 0 and dist < 900 then
        self.fireTimer = self.fireInterval
        local a = self:angleTo(target.x, target.y)
                + (love.math.random() - 0.5) * self.inaccuracy
        self:shoot(a, self.projectileSpeed, self.projectileDamage)
    end
end

-- Squid: flies in a straight line, locked on at spawn
local Squid = Enemy:extend("squid")
Squid.w, Squid.h = 64, 64
Squid.speed, Squid.maxHp, Squid.weight = 200, 10, 3
Squid.color = { 0.8, 0.3, 0.8 }
Squid.spriteSheet = "sprites_test/ghost-sheet.png"   -- adjust to your art
Squid.frameW, Squid.frameH = 12, 18
Squid.animations = {
    move = { frames = '1-4', row = 1, duration = 0.15 },
}

function Squid:onSpawn(target)
    self.dirX, self.dirY = self:directionTo(target.x, target.y)
    self:face(self.dirX)
end
function Squid:update(dt, target)
    self:move(self.dirX, self.dirY, self.speed, dt)
end

-- Shark: constantly homes in on the player
local Shark = Enemy:extend("shark")
Shark.w, Shark.h = 64, 64
Shark.speed, Shark.maxHp, Shark.weight = 150, 20, 2
Shark.color = { 0.4, 0.5, 0.9 }
Shark.spriteSheet = "sprites_test/ghost-sheet.png"
Shark.frameW, Shark.frameH = 12, 18
Shark.animations = {
    move = { frames = '1-4', row = 1, duration = 0.12 },
}

function Shark:update(dt, target)
    local dx, dy = self:directionTo(target.x, target.y)
    self:move(dx, dy, self.speed, dt)
end

-- Swordfish: winds up, locks direction, dashes, rests, repeats
local Swordfish = Enemy:extend("swordfish")
Swordfish.w, Swordfish.h = 64, 64
Swordfish.speed, Swordfish.maxHp, Swordfish.damage, Swordfish.weight = 200, 15, 2, 1
Swordfish.color = { 0.9, 0.6, 0.2 }
Swordfish.spriteSheet = "sprites_test/ghost-sheet.png"
Swordfish.frameW, Swordfish.frameH = 12, 18
Swordfish.animations = {
    move   = { frames = '1-4', row = 1, duration = 0.2 },    -- resting / idle
    windup = { frames = '1-4', row = 2, duration = 0.1 },    -- optional rows:
    dash   = { frames = '1-2', row = 3, duration = 0.05 },   -- missing ones fall back
}
Swordfish.windupTime, Swordfish.dashTime, Swordfish.restTime = 0.8, 0.6, 0.5
Swordfish.dashMultiplier = 3

function Swordfish:init()
    self.state, self.timer = "windup", self.windupTime
    self.dirX, self.dirY = 0, 0
end
function Swordfish:update(dt, target)
    self.timer = self.timer - dt
    if self.state == "windup" then
        self:setAnimation("windup")
        self:face((target.x - (self.x + self.w / 2)))   -- watch the player
        if self.timer <= 0 then
            self.dirX, self.dirY = self:directionTo(target.x, target.y)
            self.state, self.timer = "dash", self.dashTime
        end
    elseif self.state == "dash" then
        self:setAnimation("dash")
        self:move(self.dirX, self.dirY, self.speed * self.dashMultiplier, dt)
        if self.timer <= 0 then self.state, self.timer = "rest", self.restTime end
    else
        self:setAnimation("move")
        if self.timer <= 0 then self.state, self.timer = "windup", self.windupTime end
    end
end

-- ======================= MANAGER =======================

function M.register(cls)
    cls:loadAssets()
    table.insert(M.classes, cls)
end

-- Replace these for knockback, sounds, game over, etc.
function M.onPlayerHit(player, enemy)
    player.hp = player.hp - enemy.damage
    player_hit:play()
    if player.hp <= 0 then M.onPlayerDeath(player) end
end

function M.onEnemyKilled(enemy) end 

function M.onPlayerDeath(player)
    player.hp = player.maxHp
    player.invuln = 0
    M.list = {}
    love.event.quit()
end

function M.load(player)
    M.list, M.classes = {}, {}
    -- add new enemy types to this list
    for _, cls in ipairs({ Squid, Shark, Swordfish, Gunfish}) do M.register(cls) end

    player.maxHp = player.maxHp or 5
    player.hp = player.hp or player.maxHp
    player.invuln = 0

end

local function pickClass()
    local total = 0
    for _, c in ipairs(M.classes) do total = total + c.weight end
    local r = love.math.random() * total
    for _, c in ipairs(M.classes) do
        r = r - c.weight
        if r <= 0 then return c end
    end
    return M.classes[#M.classes]
end

function M.spawn(cls, x, y, target)
    local e = cls:new(x, y)
    e:onSpawn(target)
    table.insert(M.list, e)
    return e
end

local function spawnAroundPlayer(target, gameMap)
    if #M.classes == 0 then return end
    local cls = pickClass()
    local w, h = love.graphics.getDimensions()
    local radius = math.sqrt(w * w + h * h) / 2 + 80   -- just outside the view
    local a = love.math.random() * math.pi * 2
    local x = target.x + math.cos(a) * radius - cls.w / 2
    local y = target.y + math.sin(a) * radius - cls.h / 2
    local mapW = gameMap.width * gameMap.tilewidth
    local mapH = gameMap.height * gameMap.tileheight
    M.spawn(cls, math.max(0, math.min(x, mapW - cls.w)),
                 math.max(0, math.min(y, mapH - cls.h)), target)
end

-- Test along the bullet's path this frame so fast bullets can't tunnel through
local function bulletHits(b, e, dt)
    local dx = math.cos(b.angle) * b.speed * dt
    local dy = math.sin(b.angle) * b.speed * dt
    local steps = math.max(1, math.ceil(math.sqrt(dx * dx + dy * dy) / 16))
    for s = 0, steps do
        local f = s / steps
        if e:containsPoint(b.x - dx * (1 - f), b.y - dy * (1 - f)) then return true end
    end
    return false
end

local function circleHitsRect(c, rx, ry, rw, rh)
    local nx = math.max(rx, math.min(c.x, rx + rw))   -- closest point on the rect
    local ny = math.max(ry, math.min(c.y, ry + rh))
    local dx, dy = c.x - nx, c.y - ny
    return dx * dx + dy * dy <= c.radius * c.radius
end

function M.update(dt, player, bullets, gameMap)
    local target = { x = player.x + M.playerW / 2, y = player.y + M.playerH / 2 }

    if player.invuln > 0 then player.invuln = player.invuln - dt end

    M.spawnTimer = M.spawnTimer - dt
    if M.spawnTimer <= 0 and #M.list < M.maxEnemies then
        spawnAroundPlayer(target, gameMap)
        M.spawnTimer = M.spawnInterval
    end

    for _, e in ipairs(M.list) do
        e:update(dt, target)
        e:animate(dt)
    end

    -- bullets vs enemies
    for bi = #bullets, 1, -1 do
        local b = bullets[bi]
        for _, e in ipairs(M.list) do
            if not e.dead and bulletHits(b, e, dt) then
                e:takeDamage(b.damage)
                if e.dead then M.onEnemyKilled(e) end
                table.remove(bullets, bi)
                break
            end
        end
    end

    -- enemies vs player
    if player.invuln <= 0 then
        for _, e in ipairs(M.list) do
            if not e.dead and e:overlaps(player.x, player.y, M.playerW, M.playerH) then
                player.invuln = M.playerInvulnTime
                M.onPlayerHit(player, e)
                break
            end
        end
    end

    -- enemy projectiles vs player
    for i = #M.projectiles, 1, -1 do
        local p = M.projectiles[i]
        p.x = p.x + math.cos(p.angle) * p.speed * dt
        p.y = p.y + math.sin(p.angle) * p.speed * dt
        p.life = p.life - dt

        if p.life <= 0 then
            table.remove(M.projectiles, i)
        elseif player.invuln <= 0
           and circleHitsRect(p, player.x, player.y, M.playerW, M.playerH) then
            table.remove(M.projectiles, i)
            player.invuln = M.playerInvulnTime
            M.onPlayerHit(player, p)   -- p has .damage, like an enemy does
            break                      -- onPlayerHit may reset the lists
        end
    end

    -- cleanup
    for i = #M.list, 1, -1 do
        local e = M.list[i]
        if e.dead or e:shouldDespawn(target) then table.remove(M.list, i) end
    end
end

function M.draw()
    for _, e in ipairs(M.list) do e:draw() end
    love.graphics.setColor(1, 0.3, 0.3)

    for _, p in ipairs(M.projectiles) do
        love.graphics.circle("fill", p.x, p.y, p.radius)
    end
    love.graphics.setColor(1, 1, 1)
end

return M