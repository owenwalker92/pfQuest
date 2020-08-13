-- table.getn doesn't return sizes on tables that
-- are using a named index on which setn is not updated
local function tablesize(tbl)
  local count = 0
  for _ in pairs(tbl) do count = count + 1 end
  return count
end

function modulo(val, by)
  return val - math.floor(val/by)*by;
end

local function GetNearest(xstart, ystart, db, blacklist)
  local nearest = nil
  local best = nil

  for id, data in pairs(db) do
    if data[1] and data[2] and not blacklist[id] then
      local x,y = xstart - data[1], ystart - data[2]
      local distance = ceil(math.sqrt(x*x+y*y)*100)/100

      if not nearest or distance < nearest then
        nearest = distance
        best = id
      end
    end
  end

  if not best then return end

  blacklist[best] = true
  return db[best]
end

-- connection between objectives
local objectivepath = {}

-- connection between player and the first objective
local playerpath = {}

local function ClearPath(path)
  for id, tex in pairs(path) do
    tex.enable = nil
    tex:Hide()
  end
end

local function DrawLine(path,x,y,nx,ny,hl)
  local dx,dy = x - nx, y - ny
  local dots = ceil(math.sqrt(dx*1.5*dx*1.5+dy*dy))

  for i=2, dots-2 do
    local xpos = nx + dx/dots*i
    local ypos = ny + dy/dots*i

    xpos = xpos / 100 * WorldMapButton:GetWidth()
    ypos = ypos / 100 * WorldMapButton:GetHeight()

    WorldMapButton.routes = WorldMapButton.routes or CreateFrame("Frame", nil, pfQuest.route.drawlayer)
    WorldMapButton.routes:SetAllPoints()

    local nline = tablesize(path) + 1
    for id, tex in pairs(path) do
      if not tex.enable then nline = id break end
    end

    path[nline] = path[nline] or WorldMapButton.routes:CreateTexture(nil, "OVERLAY")
    path[nline]:SetWidth(4)
    path[nline]:SetHeight(4)
    path[nline]:SetTexture(pfQuestConfig.path.."\\img\\route")
    if hl then path[nline]:SetVertexColor(.3,1,.8,1) end
    path[nline]:ClearAllPoints()
    path[nline]:SetPoint("CENTER", WorldMapButton, "TOPLEFT", xpos, -ypos)
    path[nline]:Show()
    path[nline].enable = true
  end
end

pfQuest.route = CreateFrame("Frame", "pfQuestRoute", UIParent)
pfQuest.route.firstnode = nil
pfQuest.route.coords = {}

pfQuest.route.Reset = function(self)
  self.coords = {}
  self.firstnode = nil
end

pfQuest.route.AddPoint = function(self, tbl)
  table.insert(self.coords, tbl)
  self.firstnode = nil
end

local lastpos, completed = 0, 0
pfQuest.route:SetScript("OnUpdate", function()
  local xplayer, yplayer = GetPlayerMapPosition("player")
  local wrongmap = xplayer == 0 and yplayer == 0 and true or nil
  local curpos = xplayer + yplayer

  -- limit distance and route updates to once per .1 seconds
  if ( this.tick or 5) > GetTime() and lastpos == curpos then return else this.tick = GetTime() + 1 end

  -- save current position
  lastpos = curpos

  -- update distances to player
  for id, data in pairs(this.coords) do
    if data[1] and data[2] then
      local x, y = (xplayer*100 - data[1])*1.5, yplayer*100 - data[2]
      this.coords[id][4] = ceil(math.sqrt(x*x+y*y)*100)/100
    end
  end

  -- sort all coords by distance
  table.sort(this.coords, function(a,b) return a[4] < b[4] end)

  -- show arrow when route exists and is stable
  if not wrongmap and this.coords[1] and this.coords[1][4] and not this.arrow:IsShown() and pfQuest_config["arrow"] == "1" and GetTime() > completed + 1 then
    this.arrow:Show()
  end

  -- abort without any nodes or distances
  if not this.coords[1] or not this.coords[1][4] or pfQuest_config["routes"] == "0" then
    ClearPath(objectivepath)
    ClearPath(playerpath)
    return
  end

  -- check first node for changes
  if this.firstnode ~= tostring(this.coords[1][1]..this.coords[1][2]) then
    this.firstnode = tostring(this.coords[1][1]..this.coords[1][2])

    -- recalculate objective paths
    local route = { [1] = this.coords[1] }
    local blacklist = { [1] = true }
    for i=2, table.getn(this.coords) do
      route[i] = GetNearest(route[i-1][1], route[i-1][2], this.coords, blacklist)

      -- remove other item requirement gameobjects of same type from route
      if route[i] and route[i][3] and route[i][3].itemreq then
        for id, data in pairs(this.coords) do
          if not blacklist[id] and data[1] and data[2] and data[3]
            and data[3].itemreq and data[3].itemreq == route[i][3].itemreq
          then
            blacklist[id] = true
          end
        end
      end
    end

    ClearPath(objectivepath)
    for i, data in pairs(route) do
      if i > 1 then
        DrawLine(objectivepath, route[i-1][1],route[i-1][2],route[i][1],route[i][2])
      end
    end

    -- route calculation timestamp
    completed = GetTime()
  end

  if wrongmap then
    -- hide player-to-object path
    ClearPath(playerpath)
  else
    -- draw player-to-object path
    ClearPath(playerpath)
    DrawLine(playerpath,xplayer*100,yplayer*100,this.coords[1][1],this.coords[1][2],true)
  end
end)

pfQuest.route.drawlayer = CreateFrame("Frame", "pfQuestRouteDrawLayer", WorldMapButton)
pfQuest.route.drawlayer:SetFrameLevel(113)
pfQuest.route.drawlayer:SetAllPoints()

pfQuest.route.arrow = CreateFrame("Frame", "pfQuestRouteArrow", UIParent)
pfQuest.route.arrow:SetPoint("CENTER", 0, -100)
pfQuest.route.arrow:SetWidth(56)
pfQuest.route.arrow:SetHeight(42)
pfQuest.route.arrow:SetClampedToScreen(true)
pfQuest.route.arrow:SetMovable(true)
pfQuest.route.arrow:EnableMouse(true)
pfQuest.route.arrow:RegisterForDrag('LeftButton')
pfQuest.route.arrow:SetScript("OnDragStart", function()
  if IsShiftKeyDown() then
    this:StartMoving()
  end
end)

pfQuest.route.arrow:SetScript("OnDragStop", function()
  this:StopMovingOrSizing()
end)

local invalid
pfQuest.route.arrow:SetScript("OnUpdate", function()
  local xplayer, yplayer = GetPlayerMapPosition("player")
  local wrongmap = xplayer == 0 and yplayer == 0 and true or nil
  local target = this.parent.coords and this.parent.coords[1] and this.parent.coords[1][4] and this.parent.coords[1] or nil

  -- disable arrow on invalid map/route
  if not target or wrongmap or pfQuest_config["arrow"] == "0" then
    if invalid and invalid < GetTime() then
      this:Hide()
    elseif not invalid then
      invalid = GetTime() + 1
    end

    return
  else
    invalid = nil
  end

  -- arrow positioning stolen from TomTomVanilla.
  -- all credits to the original authors:
  -- https://github.com/cralor/TomTomVanilla
  local xDelta = (target[1] - xplayer*100)*1.5
  local yDelta = (target[2] - yplayer*100)
  local dir = atan2(xDelta, -(yDelta))
  dir = dir > 0 and (math.pi*2) - dir or -dir

  local degtemp = dir
  if degtemp < 0 then degtemp = degtemp + 360 end
  local angle = math.rad(degtemp)
  local player = pfQuestCompat.GetPlayerFacing()
  angle = angle - player
  local perc = math.abs(((math.pi - math.abs(angle)) / math.pi))
  local r, g, b = pfUI.api.GetColorGradient(perc)
  cell = modulo(floor(angle / (math.pi*2) * 108 + 0.5), 108)
  local column = modulo(cell, 9)
  local row = floor(cell / 9)
  local xstart = (column * 56) / 512
  local ystart = (row * 42) / 512
  local xend = ((column + 1) * 56) / 512
  local yend = ((row + 1) * 42) / 512

  -- guess area based on node count
  local area = target[3].priority and target[3].priority or 1
  area = max(1, area)
  area = min(20, area)
  area = (area / 10) + 1

  local alpha = target[4] - area
  alpha = alpha > 1 and 1 or alpha
  alpha = alpha < .5 and .5 or alpha

  local texalpha = (1 - alpha) * 2
  texalpha = texalpha > 1 and 1 or texalpha
  texalpha = texalpha < 0 and 0 or texalpha

  r, g, b = r + texalpha, g + texalpha, b + texalpha

  -- calculate difficulty color
  local color = "|cffffcc00"
  if tonumber(target[3]["qlvl"]) then
    color = pfMap:HexDifficultyColor(tonumber(target[3]["qlvl"]))
  end

  -- update arrow
  this.model:SetTexCoord(xstart,xend,ystart,yend)
  this.model:SetVertexColor(r,g,b)
  this.distance:SetTextColor(r+.2,g+.2,b+.2)

  if target[3].texture then
    this.texture:SetTexture(target[3].texture)

    local r, g, b = unpack(target[3].vertex or {0,0,0})
    if r > 0 or g > 0 or b > 0 then
      this.texture:SetVertexColor(unpack(target[3].vertex))
    else
      this.texture:SetVertexColor(1,1,1,1)
    end
  else
    this.texture:SetTexture(pfQuestConfig.path.."\\img\\node")
    this.texture:SetVertexColor(pfMap.str2rgb(target[3].title))
  end

  -- update arrow texts
  this.title:SetText(color..target[3].title.."|r")
  this.description:SetText(target[3].description or "")
  this.distance:SetText("|cffaaaaaaDistance: "..string.format("%.1f", floor(target[4]*10)/10))

  -- update transparencies
  this.texture:SetAlpha(texalpha)
  this.model:SetAlpha(alpha)
end)

pfQuest.route.arrow.texture = pfQuest.route.arrow:CreateTexture("pfQuestRouteNodeTexture", "OVERLAY")
pfQuest.route.arrow.texture:SetWidth(32)
pfQuest.route.arrow.texture:SetHeight(32)
pfQuest.route.arrow.texture:SetPoint("BOTTOM", 0, 0)

pfQuest.route.arrow.model = pfQuest.route.arrow:CreateTexture("pfQuestRouteArrow", "MEDIUM")
pfQuest.route.arrow.model:SetTexture(pfQuestConfig.path.."\\img\\arrow")
pfQuest.route.arrow.model:SetTexCoord(0,0,0.109375,0.08203125)
pfQuest.route.arrow.model:SetAllPoints()

pfQuest.route.arrow.title = pfQuest.route.arrow:CreateFontString("pfQuestRouteText", "HIGH", "GameFontWhite")
pfQuest.route.arrow.title:SetPoint("TOP", pfQuest.route.arrow.model, "BOTTOM", 0, -10)
pfQuest.route.arrow.title:SetFont(pfUI.font_default, pfUI_config.global.font_size+1, "OUTLINE")
pfQuest.route.arrow.title:SetTextColor(1,.8,.2)
pfQuest.route.arrow.title:SetJustifyH("CENTER")

pfQuest.route.arrow.description = pfQuest.route.arrow:CreateFontString("pfQuestRouteText", "HIGH", "GameFontWhite")
pfQuest.route.arrow.description:SetPoint("TOP", pfQuest.route.arrow.title, "BOTTOM", 0, -2)
pfQuest.route.arrow.description:SetFont(pfUI.font_default, pfUI_config.global.font_size, "OUTLINE")
pfQuest.route.arrow.description:SetTextColor(1,1,1)
pfQuest.route.arrow.description:SetJustifyH("CENTER")

pfQuest.route.arrow.distance = pfQuest.route.arrow:CreateFontString("pfQuestRouteDistance", "HIGH", "GameFontWhite")
pfQuest.route.arrow.distance:SetPoint("TOP", pfQuest.route.arrow.description, "BOTTOM", 0, -2)
pfQuest.route.arrow.distance:SetFont(pfUI.font_default, pfUI_config.global.font_size-1, "OUTLINE")
pfQuest.route.arrow.distance:SetTextColor(.8,.8,.8)
pfQuest.route.arrow.distance:SetJustifyH("CENTER")

pfQuest.route.arrow.parent = pfQuest.route
