local WarpMouse             = {}
WarpMouse.__index           = WarpMouse

-- Metadata
WarpMouse.name              = "WarpMouse"
WarpMouse.version           = "0.3"
WarpMouse.author            = "Michael Mogenson"
WarpMouse.homepage          = "https://github.com/mogenson/WarpMouse.spoon"
WarpMouse.license           = "MIT - https://opensource.org/licenses/MIT"

local eventTypes <const>    = hs.eventtap.event.types
local isPointInRect <const> = hs.geometry.isPointInRect
local newMouseEvent <const> = hs.eventtap.event.newMouseEvent
WarpMouse.logger            = hs.logger.new(WarpMouse.name)
WarpMouse.margin            = 2
WarpMouse.reverseScreens    = false

-- a global variable that PaperWM can use to disable the eventtap while Mission Control is open
_WarpMouseEventTap          = nil

--- Maps cursor y from current screen center-relative to new screen center-relative.
--- Returns nil if the mapped position falls outside the new screen (no warp).
--- @param y number the y position of the cursor
--- @param current_frame table the frame of the current screen
--- @param new_frame table the frame of the new screen
--- @return number|nil the y position on the new screen, or nil to cancel warp
local function relative_y(y, current_frame, new_frame)
    local offset = y - (current_frame.y + current_frame.h / 2)
    local new_y = new_frame.y + new_frame.h / 2 + offset
    if new_y < new_frame.y or new_y > new_frame.y2 then return nil end
    return new_y
end

--- Warps the mouse from one position to another.
--- @param from table the position to warp from
--- @param to table the position to warp to
local function warp(from, to)
    _WarpMouseEventTap:stop()
    newMouseEvent(eventTypes.mouseMoved, to):post();
    _WarpMouseEventTap:start()
    if WarpMouse.logger.getLogLevel() >= 4 then
        WarpMouse.logger.df("Warping mouse from %s to %s", hs.inspect(from), hs.inspect(to))
    end
end

--- Gets the screen that the cursor is currently on.
--- @param cursor table the position of the cursor
--- @param frames table a list of screen frames
--- @return number the index of the screen that the cursor is on
--- @return table the frame of the screen that the cursor is on
local function get_screen(cursor, frames)
    for index, frame in ipairs(frames) do
        if isPointInRect(cursor, frame) then
            return index, frame
        end
    end
    error("cursor is not in any screen")
end


--- Starts the WarpMouse spoon.
function WarpMouse:start()
    self.screens = hs.screen.allScreens()

    local reverse = self.reverseScreens and -1 or 1
    table.sort(self.screens, function(a, b)
        return reverse * a:fullFrame().y < reverse * b:fullFrame().y
    end)

    for i, screen in ipairs(self.screens) do
        self.screens[i] = screen:fullFrame()
    end

    self.adjacency = {}
    for _, frame in ipairs(self.screens) do
        local left, right = nil, nil
        for _, other in ipairs(self.screens) do
            if other ~= frame then
                if math.abs(other.x2 - frame.x) <= 1 then left = other
                elseif math.abs(other.x - frame.x2) <= 1 then right = other
                end
            end
        end
        self.adjacency[frame] = { left = left, right = right }
    end

    self.logger.f("Starting with screens from left to right: %s",
        hs.inspect(self.screens))

    _WarpMouseEventTap = hs.eventtap.new({
        eventTypes.mouseMoved,
        eventTypes.leftMouseDragged,
        eventTypes.rightMouseDragged,
    }, function(event)
        local cursor = event:location()
        local _, frame = get_screen(cursor, self.screens)
        local adj = self.adjacency[frame]
        if cursor.x == frame.x then
            if adj.left then
                local new_y = relative_y(cursor.y, frame, adj.left)
                if new_y then
                    warp(cursor, { x = adj.left.x2 - self.margin, y = new_y })
                end
            end
        elseif cursor.x > frame.x2 - 0.5 and cursor.x <= frame.x2 then
            if adj.right then
                local new_y = relative_y(cursor.y, frame, adj.right)
                if new_y then
                    warp(cursor, { x = adj.right.x + self.margin, y = new_y })
                end
            end
        end
    end):start()

    self.screen_watcher = hs.screen.watcher.new(function()
        self.logger.d("Screen layout change")
        self:stop()
        self:start()
    end):start()
end

--- Stops the WarpMouse spoon.
function WarpMouse:stop()
    self.logger.i("Stopping")

    if _WarpMouseEventTap then
        _WarpMouseEventTap:stop()
        _WarpMouseEventTap = nil
    end

    if self.screen_watcher then
        self.screen_watcher:stop()
        self.screen_watcher = nil
    end

    self.screens = nil
    self.adjacency = nil
end

return WarpMouse
