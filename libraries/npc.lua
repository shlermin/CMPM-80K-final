--
-- npc.lua  –  A simple wandering NPC for Love2D + anim8
--
-- Usage (in main.lua):
--
--   love.load:
--       NPC = require 'npc'
--       myNPC = NPC.new('sprites/player-sheet.png', 600, 400, 80, 80)
--
--   love.update(dt):
--       myNPC:update(dt)
--
--   love.draw (inside cam:attach / cam:detach):
--       myNPC:draw()
--
--   work out position to spawn npc at
--       love.graphics.print("x = " .. math.floor(player.x) .. " y = " .. math.floor(player.y), 10, 10)


local NPC = {}
NPC.__index = NPC

--- Create a new NPC.
-- @param spriteSheetPath  path to a 4-column × 4-row sprite sheet
--                         (rows: down, left, right, up — same layout as the player)
-- @param x               starting x position in the world
-- @param y               starting y position in the world
-- @param wanderX         how far (pixels) the NPC can wander left/right from its start
-- @param wanderY         how far (pixels) the NPC can wander up/down from its start
function NPC.new(spriteSheetPath, x, y, wanderX, wanderY)
    local self = setmetatable({}, NPC)

    -- Position
    self.x = x
    self.y = y
    self.originX = x
    self.originY = y
    self.speed = 2

    -- Wander bounds (positive number of pixels in each direction)
    self.wanderX = wanderX or 60
    self.wanderY = wanderY or 60

    -- Sprite & animation (uses the global anim8 set up in main.lua)
    self.spriteSheet = love.graphics.newImage(spriteSheetPath)
    local imgW, imgH = self.spriteSheet:getDimensions()
    self.grid = anim8.newGrid(12, 18, imgW, imgH)

    self.animations = {
        down  = anim8.newAnimation(self.grid('1-4', 1), 0.2),
        left  = anim8.newAnimation(self.grid('1-4', 2), 0.2),
        right = anim8.newAnimation(self.grid('1-4', 3), 0.2),
        up    = anim8.newAnimation(self.grid('1-4', 4), 0.2),
    }
    self.anim = self.animations.down

    -- Wander state: "moving" or "paused"
    self.state = "paused"
    self.pauseTimer = 0
    self.pauseDuration = 1          -- seconds to stand still
    self.targetX = x
    self.targetY = y

    return self
end

--- Pick a new random target within the wander bounds.
function NPC:pickTarget()
    self.targetX = self.originX + math.random(-self.wanderX, self.wanderX)
    self.targetY = self.originY + math.random(-self.wanderY, self.wanderY)
end

--- Choose the animation that best matches the direction to the target.
function NPC:faceTarget()
    local dx = self.targetX - self.x
    local dy = self.targetY - self.y

    -- Pick the axis with the larger difference
    if math.abs(dx) > math.abs(dy) then
        self.anim = dx > 0 and self.animations.right or self.animations.left
    else
        self.anim = dy > 0 and self.animations.down or self.animations.up
    end
end

--- Update the NPC each frame.
function NPC:update(dt)
    if self.state == "paused" then
        -- Stand still, show idle frame
        self.anim:gotoFrame(2)
        self.pauseTimer = self.pauseTimer + dt
        if self.pauseTimer >= self.pauseDuration then
            self:pickTarget()
            self:faceTarget()
            self.state = "moving"
        end

    elseif self.state == "moving" then
        -- Move toward the target
        local dx = self.targetX - self.x
        local dy = self.targetY - self.y
        local dist = math.sqrt(dx * dx + dy * dy)

        if dist < self.speed then
            -- Arrived — snap to target and pause
            self.x = self.targetX
            self.y = self.targetY
            self.state = "paused"
            self.pauseTimer = 0
            self.pauseDuration = 1 + math.random() * 2   -- 1-3 seconds
        else
            -- Normalise and move
            self.x = self.x + (dx / dist) * self.speed
            self.y = self.y + (dy / dist) * self.speed
        end

        self.anim:update(dt)
    end
end

--- Draw the NPC (call inside cam:attach / cam:detach).
function NPC:draw()
    self.anim:draw(self.spriteSheet, self.x, self.y, nil, 5, nil, 6, 9)
end

return NPC
