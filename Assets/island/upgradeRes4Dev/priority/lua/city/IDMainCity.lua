-- 基地
IDMainCity = {}
require("public.class")
---@type IDLGridTileSide
local IDLGridTileSide = require("city.IDLGridTileSide")
---@class IDMainCity
IDMainCity = class("IDMainCity")
---@type Coolape.CLBaseLua
local csSelf
local transform
---@type CLGrid
IDMainCity.grid = nil
---@type SimpleAI.Grid
local grid
local tiles = {}
local buildings = {}
local gridState4Tile = {}
local gridState4Building = {}
IDMainCity.selectedUnit = nil
IDMainCity.newBuildUnit = nil
IDMainCity.buildingProc = nil
IDMainCity.ExtendTile = nil
local finishCallback, progressCallback
---@type MirrorReflection
local ocean
local oceanTransform
local lookAtTarget = MyCfg.self.lookAtTarget
IDMainCity.offset4Tile = 0.25 * Vector3.up
IDMainCity.offset4Building = 0.3 * Vector3.up
IDMainCity.astar4Ocean = nil -- A星寻路->海面
IDMainCity.astar4Tile = nil     -- A星寻路->地面
IDMainCity.astar4Worker = nil     -- A星寻路->地面
IDMainCity.totalTile = 0
IDMainCity.totalBuilding = 0
IDMainCity.Headquarters = nil -- 主基地
--IDMainCity.shadowRoot = nil
--IDMainCity.tileShadowRoot = nil
IDMainCity.fogOfWarInfluence = nil
local seabed
local buildingsCount = {} -- 每种建筑的数量统计
local idelWorkers = CLLQueue.new()  -- 空闲工人
local buildingsWithWorkers = {}  -- 工人与建筑的关系
local drag4World = CLUIDrag4World.self
local smoothFollow = IDLCameraMgr.smoothFollow
local preGameMode = GameMode.city
local scaleCityHeighMax = 0
local scaleCityHeighMin = 0

local function _init()
    if csSelf then
        return
    end
    csSelf = GameObject("CityRoot"):AddComponent(typeof(CLBaseLua))
    IDMainCity.csSelf = csSelf
    csSelf.luaTable = IDMainCity
    transform = csSelf.transform
    transform.parent = MyMain.self.transform
    transform.localPosition = Vector3.zero
    transform.localScale = Vector3.one
    IDMainCity.transform = transform

    local go = GameObject("grid")
    go.transform.parent = transform
    IDMainCity.grid = go:AddComponent(typeof(CLGrid))
    IDMainCity.grid.gridLineHight = IDMainCity.offset4Tile.y
    grid = IDMainCity.grid.grid


    local uvWave = csSelf.gameObject:AddComponent(typeof(CS.Wave))
    IDMainCity.gridTileSidePorc = IDLGridTileSide
    IDLGridTileSide.init(grid, uvWave)

    CLThingsPool.borrowObjAsyn("FourWayArrow",
            function(name, obj, orgs)
                obj.transform.parent = transform
            end)

    IDMainCity.astar4Ocean = getCC(MyMain.self.transform, "AStar1", "CLAStarPathSearch")
    IDMainCity.astar4Ocean.transform.parent = transform
    IDMainCity.astar4Tile = getCC(MyMain.self.transform, "AStar2", "CLAStarPathSearch")
    IDMainCity.astar4Tile.transform.parent = transform
    IDMainCity.astar4Worker = getCC(MyMain.self.transform, "AStar3", "CLAStarPathSearch")
    IDMainCity.astar4Worker.transform.parent = transform
end

function IDMainCity.init(onFinishCallback, onProgress)
    _init()

    finishCallback = onFinishCallback
    progressCallback = onProgress

    scaleCityHeighMax = IDWorldMap.scaleCityHeighMax
    scaleCityHeighMin = IDWorldMap.scaleCityHeighMin

    transform.localScale = Vector3.one
    ocean = IDWorldMap.ocean
    oceanTransform = IDWorldMap.oceanTransform

    local gridIndex = bio2number(IDDBCity.curCity.pos)
    transform.position = IDWorldMap.grid.grid:GetCellCenter(gridIndex)

    -- 屏幕拖动代理
    --drag4World.onDragMoveDelegate = IDMainCity.onDragMove
    --drag4World.onDragScaleDelegate = IDMainCity.onScaleGround

    local size = bio2number(DBCfg.getConstCfg().GridCity)
    IDMainCity.grid.numRows = size
    IDMainCity.grid.numCols = size
    IDMainCity.grid.numGroundRows = size
    IDMainCity.grid.numGroundCols = size
    IDMainCity.grid.cellSize = 1
    IDMainCity.grid.transform.localPosition = Vector3(-size / 2, 0, -size / 2)
    IDMainCity.grid.showGrid = false
    IDMainCity.grid.showGridRange = true
    IDMainCity.grid:Start()

    if not IDMainCity.astar4Ocean.isIninted then
        IDMainCity.astar4Ocean.numRows = size * 2
        IDMainCity.astar4Ocean.numCols = size * 2
        IDMainCity.astar4Ocean.cellSize = 0.5
        IDMainCity.astar4Ocean.transform.localPosition = Vector3(-size / 2, 0, -size / 2)
        IDMainCity.astar4Ocean:init()
    end
    if not IDMainCity.astar4Tile.isIninted then
        IDMainCity.astar4Tile.numRows = size * 2
        IDMainCity.astar4Tile.numCols = size * 2
        IDMainCity.astar4Tile.cellSize = 0.5
        IDMainCity.astar4Tile.transform.localPosition = Vector3(-size / 2, 0, -size / 2)
        IDMainCity.astar4Tile:init()
    end
    --if not IDMainCity.astar4Worker.isIninted then
    --    IDMainCity.astar4Worker.numRows = size * 2
    --    IDMainCity.astar4Worker.numCols = size * 2
    --    IDMainCity.astar4Worker.cellSize = 0.5
    --    IDMainCity.astar4Worker.transform.position = Vector3(-size / 2, 0, -size / 2)
    --    IDMainCity.astar4Worker:init()
    --end

    if IDMainCity.buildingProc == nil then
        CLUIOtherObjPool.borrowObjAsyn("BuildingProc",
                function(name, obj, orgs)
                    IDMainCity.buildingProc = obj:GetComponent("CLCellLua")
                    obj.transform.parent = MyCfg.self.hud3dRoot
                    obj.transform.localScale = Vector3.one
                    SetActive(obj, false)
                end)
    end

    if seabed == nil then
        CLThingsPool.borrowObjAsyn("seabed",
                function(name, obj, orgs)
                    seabed = obj
                    seabed.transform.parent = transform
                    seabed.transform.localEulerAngles = Vector3(90, 0, 0)
                    seabed.transform.localScale = Vector3.one
                    seabed.transform.localPosition = Vector3.up * -6
                    SetActive(seabed, true)
                end)
    else
        SetActive(seabed, true)
    end

    IDMainCity.loadTiles(
            function()
                IDMainCity.loadBuildings(
                        function()
                            IDMainCity.onChgMode(GameMode.city, GameMode.map)
                            IDMainCity.onScaleScreen()
                            finishCallback()
                        end
                )
            end)
end

function IDMainCity.onDragMove(delta)
    oceanTransform.position = lookAtTarget.position + IDWorldMap.offset4Ocean
end

function IDMainCity.onScaleScreen(delta, offset)
    --drag4World:procScaler(offset)

    IDMainCity.scaleCity()
    IDMainCity.scaleHeadquarters()
end

function IDMainCity.onChgMode(oldMode, curMode)
    local isShowBuilding = true
    local isShowTile = true
    if curMode == GameMode.city then
        preGameMode = oldMode
        isShowBuilding = true
        isShowTile = true
        IDMainCity.setOtherUnitsColiderState(nil, true)
    elseif curMode == GameMode.mapBtwncity then
        preGameMode = oldMode
        isShowBuilding = false
        isShowTile = true
        IDMainCity.onClickOcean()
        IDMainCity.setOtherUnitsColiderState(nil, false)
    elseif curMode == GameMode.map then
        preGameMode = oldMode
        isShowBuilding = false
        isShowTile = false
        IDMainCity.onClickOcean()
        IDMainCity.setOtherUnitsColiderState(nil, false)
    end
    for k, v in pairs(tiles) do
        SetActive(v.gameObject, isShowTile)
    end
    if isShowTile then
        IDLGridTileSide.show()
    else
        IDLGridTileSide.hide()
    end

    for k, v in pairs(buildings) do
        if v.id ~= IDConst.headquartersBuildingID then
            -- 主基地跳过
            v:SetActive(isShowBuilding)
        end
    end

end

function IDMainCity.scaleCity()
    local maxVal = scaleCityHeighMax
    local minVal = scaleCityHeighMin

    local diffVal = maxVal - minVal
    local cityRootDiff = 0.15 - 1

    local curVal = smoothFollow.height
    if curVal > maxVal then
        curVal = maxVal
    end
    if curVal < minVal then
        curVal = minVal
    end
    local currDiff = curVal - minVal
    local persent = currDiff / diffVal
    transform.localScale = Vector3.one * (1 + cityRootDiff * persent)
    if preGameMode == GameMode.map and MyCfg.mode == GameMode.mapBtwncity then
        lookAtTarget.position = lookAtTarget.position + (transform.position - lookAtTarget.position) * (1 + cityRootDiff * persent)
    end
end

function IDMainCity.scaleHeadquarters()
    local maxVal = scaleCityHeighMax
    local minVal = scaleCityHeighMin

    local diffVal = maxVal - minVal
    local baseBuildingDiff = 13.33 - 1
    local cityRootDiff = 0.15 - 1

    local fromPos = grid:GetCellCenter(IDMainCity.Headquarters.gridIndex) + IDMainCity.offset4Building
    local baseBuildingPosDiff = transform.position - fromPos

    local curVal = smoothFollow.height
    if curVal > maxVal then
        curVal = maxVal
    end
    if curVal < minVal then
        curVal = minVal
    end
    local currDiff = curVal - minVal
    local persent = currDiff / diffVal
    local scaleCityVal = (1 + cityRootDiff * persent)
    local maxScaleVal = 2 / scaleCityVal
    local scaleBaseVal = (1 + baseBuildingDiff * persent)
    if scaleBaseVal > maxScaleVal then
        scaleBaseVal = maxScaleVal
    end
    IDMainCity.Headquarters.transform.localScale = Vector3.one * scaleBaseVal
    IDMainCity.Headquarters.transform.position = fromPos + baseBuildingPosDiff * persent
    IDMainCity.Headquarters:onScaleScreen(scaleBaseVal * scaleCityVal)
end

---@public 加载地块
function IDMainCity.loadTiles(cb)
    local list = {}
    local tiles = IDDBCity.curCity.tiles
    for idx, v in pairs(tiles) do
        table.insert(list, v)
    end
    IDMainCity.totalTile = #list
    if IDMainCity.totalTile == 0 then
        if cb then
            cb()
        end
    else
        IDMainCity.doLoadTile({ 1, list, cb })
    end
end

function IDMainCity.doLoadTile(orgs)
    CLThingsPool.borrowObjAsyn("Tiles.Tile_1", IDMainCity.onLoadTile, orgs)
end

---@param obj UnityEngine.GameObject
---@param d IDDBTile
function IDMainCity.onLoadTile(name, obj, orgs)
    local i = orgs[1]
    local list = orgs[2]
    local cb = orgs[3]
    local d = list[i]
    local index = bio2number(d.pos)
    obj.transform.parent = transform
    obj.transform.localScale = Vector3.one
    obj.transform.position = grid:GetCellPosition(index) + IDMainCity.offset4Tile
    SetActive(obj, true)
    local index2 = grid:GetCellIndex(obj.transform.position)
    IDMainCity.refreshGridState(index2, 2, true, gridState4Tile)

    local tile = obj:GetComponent("CLCellLua")
    tile:init(d, nil)
    tiles[bio2number(d.idx)] = tile.luaTable

    Utl.doCallback(progressCallback, IDMainCity.totalBuilding + IDMainCity.totalTile, i)
    if i == #list then
        IDLGridTileSide.refreshAndShow(cb)
    else
        InvokeEx.invokeByUpdate(IDMainCity.doLoadTile, { i + 1, list, cb }, 0.01)
    end
end

function IDMainCity.loadBuildings(cb)
    local bs = IDDBCity.curCity.buildings
    ---@type IDDBBuilding
    local dbBuilding
    local list = {}
    for idx, v in pairs(bs) do
        dbBuilding = v
        if bio2number(dbBuilding.attrid) == IDConst.headquartersBuildingID then
            -- 要先加载主基地，因为其它建筑可能要用到
            table.insert(list, 1, v)
        else
            table.insert(list, v)
        end
        --attr = DBCfg.getBuildingByID(bio2number(dbBuilding.attrid))
    end

    IDMainCity.totalBuilding = #list
    IDMainCity.loadbuilding({ list, 1, cb })
end

function IDMainCity.loadbuilding(param)
    local list = param[1]
    local i = param[2]
    local cb = param[3]
    ---@type IDDBBuilding
    local dbb = list[i]
    CLThingsPool.borrowObjAsyn(joinStr("Buildings.", bio2number(dbb.attrid)), IDMainCity.onLoadBuilding, param)
end

---@param obj UnityEngine.GameObject
---@param d IDDBBuilding
function IDMainCity.onLoadBuilding(name, obj, param)
    local list = param[1]
    local i = param[2]
    local cb = param[3]
    ---@type IDDBBuilding
    local d = list[i]

    local index = bio2number(d.pos)
    if obj then
        obj.transform.parent = transform
        obj.transform.localScale = Vector3.one

        local attr = DBCfg.getBuildingByID(bio2number(d.attrid))
        local size = bio2Int(attr.Size)
        local posOffset
        if IDMainCity.isOnTheLand(index, size) then
            posOffset = IDMainCity.offset4Building
        else
            posOffset = IDWorldMap.offset4Ocean
        end

        if (size % 2 == 0) then
            obj.transform.position = grid:GetCellPosition(index) + posOffset
        else
            obj.transform.position = grid:GetCellCenter(index) + posOffset
        end
        SetActive(obj, true)
        ---@type Coolape.CLUnit
        local unit = obj:GetComponent("MyUnit")
        ---@type IDLBuilding
        local buildingLua = nil
        if unit.luaTable == nil then
            buildingLua = IDUtl.newBuildingLua(attr)
            unit.luaTable = buildingLua
            unit:initGetLuaFunc()
        else
            buildingLua = unit.luaTable
        end

        buildingLua:init(unit, bio2number(d.attrid), 0,
                bio2number(d.lev), true,
                { index = index, serverData = d })

        local attr = DBCfg.getBuildingByID(bio2number(d.attrid))
        IDMainCity.refreshGridState(index, bio2number(attr.Size), true, gridState4Building)
        buildings[bio2number(d.idx)] = buildingLua
        -- 统计每种建筑的数据
        buildingsCount[bio2number(d.attrid)] = buildingsCount[bio2number(d.attrid)] and (buildingsCount[bio2number(d.attrid)] + 1) or 1

        if bio2number(d.attrid) == IDConst.headquartersBuildingID then
            -- 说明是主基地
            IDMainCity.Headquarters = buildingLua
        end
    end

    Utl.doCallback(progressCallback, IDMainCity.totalBuilding + IDMainCity.totalTile, IDMainCity.totalTile + i)

    if i == #list then
        -- 完成
        IDMainCity.astar4Ocean:scan()
        IDMainCity.astar4Tile:scan()
        --IDMainCity.astar4Worker:scan()
        Utl.doCallback(cb)
    else
        InvokeEx.invokeByUpdate(IDMainCity.loadbuilding, { list, i + 1, cb }, 0.01)
    end
end

---@public 新建筑
function IDMainCity.createBuilding(data)
    showHotWheel()
    IDMainCity.onClickOcean()
    CLThingsPool.borrowObjAsyn(joinStr("Buildings.", bio2number(data.ID)), IDMainCity.onGetBuilding4New, data);
end

function IDMainCity.onGetBuilding4New(name, obj, orgs)
    local attr = orgs
    local index = IDMainCity.getFreePos(bio2number(attr.Size), attr.PlaceGround, attr.PlaceSea)
    obj.transform.parent = transform
    obj.transform.position = grid:GetCellCenter(index) + IDMainCity.offset4Building
    obj.transform.localScale = Vector3.one
    SetActive(obj, true)
    ---@type Coolape.CLUnit
    local unit = obj:GetComponent("MyUnit")
    ---@type IDLBuilding
    local buildingLua = nil
    if unit.luaTable == nil then
        buildingLua = IDUtl.newBuildingLua(attr)
        unit.luaTable = buildingLua
        unit:initGetLuaFunc()
    else
        buildingLua = unit.luaTable
    end
    buildingLua:init(unit, bio2number(attr.ID), 0,
            0, true,
            { index = index })
    IDMainCity.newBuildUnit = buildingLua
    IDMainCity.onClickBuilding(buildingLua)
    hideHotWheel()
end

---@public 取得网格
function IDMainCity.getGrid()
    return grid
end

function IDMainCity.clean()
    if csSelf == nil then
        return
    end
    IDMainCity.onClickOcean()

    for k, v in pairs(tiles) do
        v.csSelf:clean()
        CLThingsPool.returnObj(v.gameObject)
        SetActive(v.gameObject, false)
    end
    tiles = {}
    for k, v in pairs(buildings) do
        v.csSelf:clean()
        CLThingsPool.returnObj(v.csSelf.gameObject)
        SetActive(v.csSelf.gameObject, false)
    end
    buildings = {}

    for k, v in pairs(buildingsWithWorkers) do
        v.luaTable.clean()
        CLRolePool.returnObj(v)
        SetActive(v.gameObject, false)
    end
    buildingsWithWorkers = {}

    while idelWorkers:size() > 0 do
        local worker = idelWorkers:deQueue()
        worker:clean()
        CLRolePool.returnObj(worker.csSelf)
        SetActive(worker.gameObject, false)
    end

    if seabed then
        CLThingsPool.returnObj(seabed)
        SetActive(seabed, false)
        seabed = nil
    end

    if IDMainCity.buildingProc then
        CLUIOtherObjPool.returnObj(IDMainCity.buildingProc.gameObject)
        SetActive(IDMainCity.buildingProc.gameObject, false)
        IDMainCity.buildingProc = nil
    end
    IDLGridTileSide.clean()

    gridState4Building = {}
    gridState4Tile = {}
    buildingsCount = {}
end

function IDMainCity.destory()
    IDMainCity.clean()
    if IDMainCity.buildingProc then
        CLUIOtherObjPool.returnObj(IDMainCity.buildingProc.gameObject)
        SetActive(IDMainCity.buildingProc.gameObject, false)
        IDMainCity.buildingProc = nil
    end
    if SFourWayArrow.self ~= nil then
        CLThingsPool.returnObj(SFourWayArrow.self.gameObject)
        SetActive(SFourWayArrow.self.gameObject, false)
    end
    GameObject.DestroyImmediate(csSelf.gameObject, true)
end

function IDMainCity.onPress(isPressed)

end

---@public 点击了海
function IDMainCity.onClickOcean()
    if IDMainCity.ExtendTile then
        SetActive(IDMainCity.ExtendTile.gameObject, false)
    end

    if (IDMainCity.selectedUnit ~= nil) then
        IDMainCity.setSelected(IDMainCity.selectedUnit, false)

        if (IDMainCity.newBuildUnit == IDMainCity.selectedUnit) then
            -- 说明是新建
            CLThingsPool.returnObj(IDMainCity.selectedUnit.csSelf.gameObject)
            IDMainCity.selectedUnit:clean()
            SetActive(IDMainCity.selectedUnit.csSelf.gameObject, false)
            IDMainCity.newBuildUnit = nil
        end
        NGUITools.SetActive(IDMainCity.buildingProc.gameObject, false)
        IDMainCity.selectedUnit = nil
    end

    IDLGridTileSide.show()
end

---@public 点击了建筑
function IDMainCity.onClickBuilding(building)
    if (IDMainCity.selectedUnit == building) then
        return
    end
    if IDMainCity.ExtendTile then
        SetActive(IDMainCity.ExtendTile.gameObject, false)
    end
    if (IDMainCity.selectedUnit ~= nil) then
        IDMainCity.setSelected(IDMainCity.selectedUnit, false)
        if (IDMainCity.newBuildUnit == IDMainCity.selectedUnit) then
            -- 说明是新建
            NGUITools.SetActive(IDMainCity.buildingProc.gameObject, false)
            IDMainCity.selectedUnit.csSelf:clean()
            CLThingsPool.returnObj(IDMainCity.selectedUnit.csSelf.gameObject)
            SetActive(IDMainCity.selectedUnit.csSelf.gameObject, false)
            IDMainCity.newBuildUnit = nil
        end
    end
    IDMainCity.selectedUnit = building
    if (IDMainCity.selectedUnit ~= nil) then
        IDMainCity.setSelected(building, true)
    end

    IDMainCity.showhhideBuildingProc(building)
end

---@public 点击地块
function IDMainCity.onClickTile(tile)
    if (IDMainCity.selectedUnit == tile) then
        return
    end

    if IDMainCity.ExtendTile then
        SetActive(IDMainCity.ExtendTile.gameObject, false)
    end
    -- 处理之前的选中
    if (IDMainCity.selectedUnit ~= nil) then
        IDMainCity.setSelected(IDMainCity.selectedUnit, false)
        if (IDMainCity.newBuildUnit == IDMainCity.selectedUnit) then
            -- 说明是新建
            NGUITools.SetActive(IDMainCity.buildingProc.gameObject, false)
            IDMainCity.selectedUnit.csSelf:clean()
            CLThingsPool.returnObj(IDMainCity.selectedUnit.csSelf.gameObject)
            SetActive(IDMainCity.selectedUnit.csSelf.gameObject, false)
            IDMainCity.newBuildUnit = nil
        end
    end

    -- 判断能否操作
    if tile then
        local cell = tile
        local index = cell.gridIndex
        local isOK = IDMainCity.isSizeInFreeCell(index, cell.size, true, false)
        if not isOK then
            CLAlert.add(LGet("CannotProcTile"), Color.yellow, 1)
            local newPos = grid:GetCellPosition(index)
            newPos = newPos + IDMainCity.offset4Tile
            IDLBuildingSize.show(cell.size, Color.red, newPos)
            IDLBuildingSize.setLayer("Top")
            InvokeEx.invoke(IDLBuildingSize.hide, 0.15)
            IDMainCity.selectedUnit = nil
            IDMainCity.showhhideBuildingProc(nil)
            return
        else
            cell.jump()
        end
    end

    -- 设置为当前选中
    IDMainCity.selectedUnit = tile
    if (IDMainCity.selectedUnit ~= nil) then
        IDMainCity.setSelected(tile, true)
    end

    IDMainCity.showhhideBuildingProc(tile)
end

function IDMainCity.onDragOcean()

end

---@public 显示建筑操作hud
function IDMainCity.showhhideBuildingProc(building)
    if building == nil then
        SetActive(IDMainCity.buildingProc.gameObject, false)
    else
        local d = { target = building, offset = Vector3.zero }
        SetActive(IDMainCity.buildingProc.gameObject, true)
        IDMainCity.buildingProc:init(d, nil)
    end
end

function IDMainCity.doCreateBuilding(d)
    ---@type IDLBuilding
    local building = d.target
    showHotWheel()
    net:send(NetProtoIsland.send.newBuilding(building.id, building.gridIndex))
end

function IDMainCity.onfinsihCreateBuilding(d)
    ---@type IDDBBuilding
    local b = IDDBCity.curCity.buildings[bio2number(d.idx)]
    if IDMainCity.newBuildUnit.id == bio2number(b.attrid) then
        IDMainCity.newBuildUnit:init(IDMainCity.newBuildUnit,
                bio2number(b.attrid), 0, bio2number(b.lev), true,
                { index = bio2number(b.pos), serverData = b })
        SetActive(IDMainCity.buildingProc.gameObject, false)
        buildings[bio2number(b.idx)] = IDMainCity.newBuildUnit
        -- 统计每种建筑的数据
        buildingsCount[bio2number(b.attrid)] = buildingsCount[bio2number(b.attrid)] and (buildingsCount[bio2number(b.attrid)] + 1) or 1
        IDMainCity.refreshGridState(bio2number(b.pos), IDMainCity.newBuildUnit.size, true, gridState4Building)
        IDMainCity.newBuildUnit = nil
        IDMainCity.onClickOcean()
    end
end

function IDMainCity.cancelCreateBuilding(d)
    IDMainCity.onClickBuilding(nil)
end

---@public 释放建筑
function IDMainCity.onReleaseBuilding(building, hadMoved)
    if IDMainCity.newBuildUnit == building then
    elseif IDMainCity.selectedUnit == building then
        -- 要先加载地块边，后面的a*刷新才正确
        IDLGridTileSide.show()

        if hadMoved then
            -- 通知服务器
            local blua = building
            ---@type IDDBBuilding
            local d = blua.serverData
            local gidx = blua.gridIndex

            -- 刷新a星网格
            local oldIndex = bio2number(d.pos)
            local oldPos
            if blua.size % 2 == 0 then
                oldPos = grid:GetCellPosition(oldIndex)
            else
                oldPos = grid:GetCellCenter(oldIndex)
            end
            IDMainCity.astar4Tile:scanRange(oldPos, 6)
            --IDMainCity.astar4Worker:scanRange(oldPos, 5)
            IDMainCity.astar4Ocean:scanRange(oldPos, 6)
            -- 新位置
            IDMainCity.astar4Tile:scanRange(building.transform.position, 6)
            --IDMainCity.astar4Worker:scanRange(building.transform.position, 5)
            IDMainCity.astar4Ocean:scanRange(building.transform.position, 6)
            -- 修改数据
            d.pos = number2bio(gidx)
            net:send(NetProtoIsland.send.moveBuilding(bio2number(d.idx), gidx))
        end
    end
end

function IDMainCity.onReleaseTile(tile, hadMoved)
    if IDMainCity.newBuildUnit == tile then
    elseif IDMainCity.selectedUnit == tile then
        IDLGridTileSide.refreshAndShow(nil)
        if hadMoved then
            -- 通知服务器
            local blua = tile
            ---@type IDDBTile
            local d = blua.mData
            local gidx = blua.gridIndex

            -- 刷新a星网格
            local oldIndex = bio2number(d.pos)
            IDMainCity.astar4Tile:scanRange(oldIndex, 2)
            IDMainCity.astar4Ocean:scanRange(oldIndex, 2)
            -- 新位置
            IDMainCity.astar4Tile:scanRange(tile.transform.position, 2)
            IDMainCity.astar4Ocean:scanRange(tile.transform.position, 2)

            net:send(NetProtoIsland.send.moveTile(bio2number(d.idx), gidx))
        end
    end
end

function IDMainCity.getState4Tile()
    return gridState4Tile
end

---@public 选中状态
function IDMainCity.setSelected(unit, selected)
    if unit == nil then
        return
    end

    local cell = unit
    local isTile = cell.isTile
    if (selected) then
        SFourWayArrow.show(unit.csSelf, cell.size)  --设置箭头
        SFourWayArrow.setMatToon()
        if unit ~= IDMainCity.newBuildUnit then
            if isTile then
                IDMainCity.refreshGridState(cell.gridIndex, cell.size, false, gridState4Tile)
            else
                IDMainCity.refreshGridState(cell.gridIndex, cell.size, false, gridState4Building)
            end
        end
    else
        -- todo:释放技能范围的圈
        IDMainCity.setOtherUnitsColiderState(nil, true)
        SFourWayArrow.hide()
        IDLBuildingSize.hide()

        local grid = IDMainCity.getGrid()
        local index = grid:GetCellIndex(unit.transform.position)
        local placeGround, placeSea
        if isTile then
            placeGround = false
            placeSea = true
        else
            placeGround = cell.attr.PlaceGround
            placeSea = cell.attr.PlaceSea
        end

        if (IDMainCity.isSizeInFreeCell(index, cell.size, placeGround, placeSea)) then
            cell.gridIndex = index

            if unit ~= IDMainCity.newBuildUnit then
                if isTile then
                    IDMainCity.refreshGridState(cell.gridIndex, cell.size, true, gridState4Tile)
                else
                    IDMainCity.refreshGridState(cell.gridIndex, cell.size, true, gridState4Building)
                end
            end
        else
            local pos = Vector3.zero
            if (cell.size % 2 == 0) then
                pos = grid:GetCellPosition(cell.gridIndex)
            else
                pos = grid:GetCellCenter(cell.gridIndex)
            end
            if unit.isTile then
                pos = pos + IDMainCity.offset4Tile
            else
                local posOffset
                if IDMainCity.isOnTheLand(cell.gridIndex, cell.size) then
                    posOffset = IDMainCity.offset4Building
                else
                    posOffset = IDWorldMap.offset4Ocean
                end
                pos = pos + posOffset
            end
            unit.transform.position = pos
            if unit.shadow then
                unit.shadow.position = pos + Vector3.up * 0.01
            end

            if unit ~= IDMainCity.newBuildUnit then
                if isTile then
                    IDMainCity.refreshGridState(cell.gridIndex, cell.size, true, gridState4Tile)
                else
                    IDMainCity.refreshGridState(cell.gridIndex, cell.size, true, gridState4Building)
                end
            end
        end

        IDLCameraMgr.setPostProcessingProfile("normal")
        if isTile then
            NGUITools.SetLayer(unit.gameObject, LayerMask.NameToLayer("Tile"))
        else
            NGUITools.SetLayer(unit.body.gameObject, LayerMask.NameToLayer("Building"))
        end
        IDLBuildingSize.setLayer("Default")
    end
end

function IDMainCity.setOtherUnitsColiderState(target, activeCollider)
    for k, v in pairs(buildings) do
        if v ~= target then
            v:setCollider(activeCollider)
        end
    end
    for k, v in pairs(tiles) do
        if v ~= target then
            v.setCollider(activeCollider)
        end
    end
end

---@public 刷新网格的状态
function IDMainCity.refreshGridState(center, size, val, gridstate)
    --gridstate = gridstate or gridState4Building
    local list = IDMainCity.grid:getOwnGrids(center, size)
    local count = list.Count
    for i = 0, count - 1 do
        gridstate[NumEx.getIntPart(list[i])] = val
    end
end

---@public grid中index位置在的size个格子是都是空闲的
function IDMainCity.isSizeInFreeCell(index, size, canOnLand, canOnWater)
    local list = IDMainCity.grid:getOwnGrids(index, size)
    local count = list.Count
    local cellIndex = 0
    local haveland = false
    local havewater = false
    for i = 0, count - 1 do
        cellIndex = NumEx.getIntPart(list[i])
        if (not grid:IsInBounds(cellIndex)) then
            return false
        end
        if (gridState4Building[cellIndex] == true) then
            return false
        end
        if (not canOnLand) and gridState4Tile[cellIndex] == true then
            return false
        end
        if (not canOnWater) and (gridState4Tile[cellIndex] ~= true) then
            return false
        end
        if haveland or gridState4Tile[cellIndex] == true then
            haveland = true
        end
        if havewater or (gridState4Tile[cellIndex] ~= true) then
            havewater = true
        end
    end
    if haveland and havewater then
        return false
    end
    return true
end

function IDMainCity.hideGrid()
    IDMainCity.grid:hide()
end

function IDMainCity.showGrid(callback)
    IDMainCity.grid:reShow(callback) --显示网格
end

---@public 取得空闲的位置
function IDMainCity.getFreePos(size, canOnLand, canOnWater)
    local center = MyCfg.self.lookAtTarget.position
    local list = {}
    for i = 0, grid.NumberOfCells - 1 do
        table.insert(list, i)
    end

    local sortGridFunc = function(a, b)
        if (a == nil or b == nil) then
            return true
        end
        local pos1 = grid:GetCellPosition(a)
        local pos2 = grid:GetCellPosition(b)
        local d1 = Vector3.Distance(center, pos1)
        local d2 = Vector3.Distance(center, pos2)

        if (d2 - d1 > 0) then
            return true
        else
            return false
        end
    end
    table.sort(list, sortGridFunc)
    local ret = 0
    for i, v in ipairs(list) do
        if (IDMainCity.isSizeInFreeCell(v, size, canOnLand, canOnWater)) then
            ret = v
            break
        end
    end
    list = nil
    return ret
end

---@public 取得某种建筑的数量
function IDMainCity.getBuildingCountByID(id)
    return buildingsCount[id] or 0
end

---@public 取得当前主基地开放的最大的建筑id=xx的数量
function IDMainCity.getMaxNumOfCurrHeadLev4Building(id)
    local d = IDMainCity.Headquarters.serverData
    local cfg = DBCfg.getHeadquartersLevsDataByLev(bio2number(d.lev))
    if cfg then
        return bio2number(cfg[joinStr("Building", id)])
    end
    return 1
end

---@public 当建筑有变化时
function IDMainCity.onBuildingChg(data)
    local idx = bio2number(data.idx)
    ---@type IDDBBuilding
    local serverData = IDDBCity.curCity.buildings[idx]
    if serverData == nil then
        printe("get building serverdata is nil")
        return
    end
    ---@type MyUnit
    local building = buildings[idx]
    if building == nil then
        printw("get building is nil")
        return
    end

    ---@type IDLBuilding
    building:init(building.csSelf, bio2number(serverData.attrid), 0,
            bio2number(serverData.lev), true,
            { index = bio2number(serverData.pos), serverData = serverData })
end

---@public 扩建地块
function IDMainCity.showExtendTile(data)
    SetActive(IDMainCity.buildingProc.gameObject, false)
    SFourWayArrow.hide()
    if IDMainCity.selectedUnit == nil then
        return
    end
    if IDMainCity.ExtendTile == nil then
        CLUIOtherObjPool.borrowObjAsyn("ExtendTile",
                function(name, go, orgs)
                    if orgs ~= IDMainCity.selectedUnit then
                        CLUIOtherObjPool.returnObj(go)
                        SetActive(go, false)
                        return
                    end
                    IDMainCity.ExtendTile = go:GetComponent("CLCellLua")
                    IDMainCity.ExtendTile.transform.parent = csSelf.transform
                    IDMainCity.ExtendTile.transform.localScale = Vector3.one
                    IDMainCity.ExtendTile.transform.localEulerAngles = Vector3.zero
                    IDMainCity.ExtendTile.transform.position = IDMainCity.selectedUnit.transform.position
                    --SetActive(go, true)
                    IDLGridTileSide.clean()
                    IDMainCity.ExtendTile:init(IDMainCity.selectedUnit, nil)
                end,
                IDMainCity.selectedUnit)
    else
        --SetActive(IDMainCity.ExtendTile.gameObject, true)
        IDLGridTileSide.clean()
        IDMainCity.ExtendTile:init(IDMainCity.selectedUnit, nil)
    end
end

---@public 能否放在一个地块
---@param ...、 可以是index或x、y
function IDMainCity.canPlaceTile(...)
    local param = { ... }
    local index
    if #param > 1 then
        local x = param[1]
        local y = param[2]
        index = grid:GetCellIndex(x, y)
    else
        index = param[1]
    end
    return IDMainCity.isSizeInFreeCell(index, 2, false, true)
end

---@public 给定的中心index及size后判断是否在陆地上
function IDMainCity.isOnTheLand(center, size)
    local list = IDMainCity.grid:getOwnGrids(center, size)
    local count = list.Count
    local cellIndex = 0
    for i = 0, count - 1 do
        cellIndex = NumEx.getIntPart(list[i])
        if not gridState4Tile[cellIndex] then
            return false
        end
    end
    return true
end

---@public 给定的index判断是否在陆地及沙地上
function IDMainCity.isOnTheLandOrBeach(index)
    if gridState4Tile[index] then
        return true
    end
    if IDLGridTileSide.isOnTheBeach(index) then
        return true
    end
    return false
end

---@public 取得数据
function IDMainCity.getPosOffset(index)
    if IDLGridTileSide.isOnTheBeach(index) then
        return Vector3.zero
    end
    if gridState4Tile[index] then
        return IDMainCity.offset4Tile
    end
    return IDWorldMap.offset4Ocean
end

---@public 添加地块
function IDMainCity.addTile(d)
    local idx = bio2number(d.idx)
    local data = IDDBCity.curCity.tiles[idx]
    if data then
        CLThingsPool.borrowObjAsyn("Tiles.Tile_1",
                function(naem, obj, orgs)
                    local index = bio2number(d.pos)
                    obj.transform.parent = transform
                    obj.transform.position = grid:GetCellPosition(index) + IDMainCity.offset4Tile
                    SetActive(obj, true)
                    local index2 = grid:GetCellIndex(obj.transform.position)
                    IDMainCity.refreshGridState(index2, 2, true, gridState4Tile)

                    local tile = obj:GetComponent("CLCellLua")
                    tile:init(d, nil)
                    local tileLua = tile.luaTable
                    tiles[idx] = tileLua
                    IDMainCity.onClickTile(tileLua)
                    IDMainCity.showExtendTile(tileLua)
                end)
    else
        printe("tile data is nil")
    end
end

---@public 移除地块
function IDMainCity.removeTile(idx)
    SetActive(IDMainCity.buildingProc.gameObject, false)
    SFourWayArrow.hide()
    IDMainCity.selectedUnit = nil
    local tile = tiles[idx]
    if tile then
        local index2 = grid:GetCellIndex(tile.transform.position)
        IDMainCity.refreshGridState(index2, 2, false, gridState4Tile)
        tile.csSelf:clean()
        CLThingsPool.returnObj(tile.gameObject)
        SetActive(tile.gameObject, false)
        IDLGridTileSide.refreshAndShow(nil)
        IDMainCity.astar4Tile:scanRange(tile.transform.position, 5)
        IDMainCity.astar4Ocean:scanRange(tile.transform.position, 5)
        tiles[idx] = nil
    end
    IDDBCity.curCity.tiles[idx] = nil
end

function IDMainCity.removeBuilding(idx)
    SetActive(IDMainCity.buildingProc.gameObject, false)
    SFourWayArrow.hide()
    IDMainCity.selectedUnit = nil
    local building = buildings[idx]
    if building then
        local id = bio2number(building.attr.ID)
        buildingsCount[id] = buildingsCount[id] - 1
        local index2 = grid:GetCellIndex(building.transform.position)
        IDMainCity.refreshGridState(index2, building.size, false, gridState4Building)
        building.csSelf:clean()
        CLThingsPool.returnObj(building.gameObject)
        SetActive(building.gameObject, false)
        buildings[idx] = nil

        IDMainCity.astar4Tile:scanRange(building.transform.position, 5)
        --IDMainCity.astar4Worker:scanRange(building.transform.position, 5)
        IDMainCity.astar4Ocean:scanRange(building.transform.position, 5)
    end
    IDDBCity.curCity.buildings[idx] = nil
end

---@public 当有建筑完成升级
function IDMainCity.onFinishBuildingUpgrade(bData)
    local idx = bio2number(bData.idx)
    local building = buildings[idx]
    if building == nil then
        printe("get building is nil")
        return
    end
    if building == IDMainCity.selectedUnit then
        SetActive(IDMainCity.buildingProc.gameObject, false)
        SFourWayArrow.hide()
        IDMainCity.selectedUnit = nil
    end

    if building then
        building:onFinishBuildingUpgrade()
    end
    IDMainCity.onClickOcean()
end

---@public 雇佣工人
function IDMainCity.employWorker(building, callback)
    ---@type IDLBuilding
    local idx = bio2number(building.serverData.idx)
    ---@type IDRWorker
    local worker = buildingsWithWorkers[idx]
    if worker == nil then
        if idelWorkers:size() > 0 then
            worker = idelWorkers:deQueue()
            buildingsWithWorkers[idx] = worker
            SetActive(worker.gameObject, true)
            worker:gotoWork(building)
            if callback then
                callback(worker)
            end
        else
            CLRolePool.borrowObjAsyn("worker",
                    function(name, role, orgs)
                        local _building = orgs
                        local _idx = bio2number(_building.serverData.idx)
                        local state = bio2number(_building.serverData.state)
                        if (not building.gameObject.activeInHierarchy)
                                or buildingsWithWorkers[_idx]
                                or state ~= IDConst.BuildingState.upgrade then
                            CLRolePool.returnObj(role)
                            SetActive(role.gameObject, false)
                            return
                        end
                        role.transform.parent = IDMainCity.csSelf.transform
                        role.transform.localScale = Vector3.one
                        role.transform.position = IDMainCity.Headquarters.door.position
                        SetActive(role.gameObject, true)

                        if role.luaTable == nil then
                            role.luaTable = IDUtl.newRoleLua(1)
                        end
                        role.luaTable:init(role, 1, 0, 0, true, { building = _building })
                        role.luaTable:gotoWork(_building)
                        buildingsWithWorkers[idx] = role.luaTable
                        if callback then
                            callback(role.luaTable)
                        end
                    end, building)
        end
    else
        SetActive(worker.gameObject, true)
        worker:gotoWork(building)
        if callback then
            callback(worker)
        end
    end
end

---@public 解雇工人
function IDMainCity.fireWorker(building)
    ---@type IDLBuilding
    local idx = bio2number(building.serverData.idx)
    ---@type IDRWorker
    local worker = buildingsWithWorkers[idx]
    if worker then
        worker:finishWork()
        idelWorkers:enQueue(worker)
        buildingsWithWorkers[idx] = nil
    end
end

---@param b IDDBBuilding
function IDMainCity.onFinishCollectRes(b)
    local idx = bio2number(b.idx)
    local building = buildings[idx]
    if building == nil then
        printe("get building is nil")
        return
    end
    building:playCollectResEffect()
end

---@public 取得所有地块对象
function IDMainCity.getTiles()
    return tiles
end
--===========================
return IDMainCity