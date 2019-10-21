﻿---@class IDLBattleSearcher 战场寻敌器
local IDLBattleSearcher = {}

---@class BuildingRangeInfor
---@field public index number 网格的index
---@field public dis number 距离

-- 建筑攻击范围数据 key=IDLBuilding.instanceID, val = BuildingRangeInfor
local buildingsRange = {}
-- 建筑数据，是从城市里取的原始数据
local buildings = {}

-- 每个角色所在网格的index数据。key=角色对象，val=网格的index
local rolesIndex = {}
-- 进攻方（舰船），记录的是每个网格上有哪些舰船
local offense = {}
-- 防守方（舰船），记录的是每个网格上有哪些舰船
local defense = {}
-- 距离缓存,key=两个网格的index拼接，val=距离
local disCache = {}

---@type CLGrid
local grid

-- 初始化
---@param city IDMainCity
function IDLBattleSearcher.init(city)
    grid = city.grid
    IDLBattleSearcher.wrapBuildingInfor(city.getBuildings())
end

---@public 包装建筑的数据
function IDLBattleSearcher.wrapBuildingInfor(_buildings)
    buildings = _buildings
    ---@param b IDLBuilding
    for k, b in pairs(buildings) do
        if bio2Int(b.attr.GID) == IDConst.BuildingGID.defense then -- 防御炮
            local MaxAttackRange =
                DBCfg.getGrowingVal(
                bio2number(b.attr.AttackRangeMin) / 100,
                bio2number(b.attr.AttackRangeMax) / 100,
                bio2number(b.attr.AttackRangeCurve),
                bio2number(b.serverData.lev) / bio2number(b.attr.MaxLev)
            )
            local size = IDLBattleSearcher.calculateSize(MaxAttackRange)
            -- 取得可攻击范围内的格子
            local cells = grid:getOwnGrids(b.gridIndex, size)

            local MinAttackRange = bio2Int(b.attr.MinAttackRange) / 100
            -- 按照离建筑的远近排序
            local list = IDLBattleSearcher.sortGridCells(b, MinAttackRange, MaxAttackRange, cells)
            buildingsRange[b.instanceID] = list
        elseif bio2Int(b.attr.GID) == IDConst.BuildingGID.trap or bio2Int(b.attr.ID) == IDConst.BuildingID.dockyardBuildingID then -- 陷阱\造船厂，主要处理触发半径
            local triggerR =
                DBCfg.getGrowingVal(
                bio2number(b.attr.TriggerRadiusMin) / 100,
                bio2number(b.attr.TriggerRadiusMax) / 100,
                bio2number(b.attr.TriggerRadiusCurve),
                bio2number(b.serverData.lev) / bio2number(b.attr.MaxLev)
            )
            local size = IDLBattleSearcher.calculateSize(triggerR)
            -- 取得可攻击范围内的格子
            local cells = grid:getOwnGrids(b.gridIndex, size)

            -- 按照离建筑的远近排序
            local list = IDLBattleSearcher.sortGridCells(b, 0, 0, cells)
            buildingsRange[b.instanceID] = list
        end
    end
end

---@public 按照离建筑的远近排序
---@param building IDLBuilding
function IDLBattleSearcher.sortGridCells(building, min, max, cells)
    local count = cells.Count
    local list = {}
    local buildingPos = building.transform.position
    buildingPos.y = 0
    local index, pos, dis
    -- 准备要排序的数据
    for i = 0, count - 1 do
        index = cells[i]
        pos = grid.grid:GetCellCenter(index)
        pos.y = 0
        dis = Vector3.Distance(buildingPos, pos)
        if dis >= min and (dis <= max or max <= 0) then
            -- 只有可攻击范围的才处理
            table.insert(list, {index = index, dis = dis})
        end
    end
    CLQuickSort.quickSort(
        list,
        function(a, b)
            return a.dis < b.dis
        end
    )

    return list
end

---@param building IDLBuilding
function IDLBattleSearcher.debugBuildingAttackRange(building)
    for k, obj in ipairs(IDLBattleSearcher._debugRangs or {}) do
        CLThingsPool.returnObj(obj)
        SetActive(obj, false)
    end
    IDLBattleSearcher._debugRangs = {}

    local cells = buildingsRange[building.instanceID]
    -- local cellList = grid:getOwnGrids(building.gridIndex, 20*2)
    -- cells = {}
    -- for i=0, cellList.Count -1 do
    --     table.insert(cells, {index =cellList[i]})
    -- end

    for i, v in ipairs(cells or {}) do
        CLThingsPool.borrowObjAsyn(
            "MapTileSize",
            function(name, obj, orgs)
                obj.transform.position = grid.grid:GetCellCenter(v.index)
                obj.transform.localScale = Vector3.one * 0.1
                obj.transform.localEulerAngles = Vector3.zero
                SetActive(obj, true)
                table.insert(IDLBattleSearcher._debugRangs, obj)
            end
        )
    end
end

---@public 要取得圆的范围，因此取得了圆的外切正方形的边长
function IDLBattleSearcher.calculateSize(r)
    return r * 2
    -- return NumEx.getIntPart(math.sqrt(2 * (r * r)) + 0.5)
end

---@public 刷新舰船的位置
---@param unit IDRoleBase
function IDLBattleSearcher.refreshUnit(unit)
    --//TODO:注意所有移动的战斗单元需要定时刷新
    local index = grid.grid:GetCellIndex(unit.transform.position)
    if unit.isOffense then
        local oldIndex = rolesIndex[unit]
        if oldIndex and oldIndex ~= index then
            -- 先清除掉旧的数据
            local map = offense[oldIndex] or {}
            map[unit] = nil
            offense[oldIndex] = map
        end
        local map = offense[index] or {}
        map[unit] = unit
        offense[index] = map
    else
        local oldIndex = rolesIndex[unit]
        if oldIndex and oldIndex ~= index then
            -- 先清除掉旧的数据
            local map = defense[oldIndex] or {}
            map[unit] = nil
            defense[oldIndex] = map
        end
        local map = defense[index] or {}
        map[unit] = unit
        defense[index] = map
    end
    -- 最后再更新舰船的位置
    rolesIndex[unit] = index
end

---@public 取得两个网格间的距离
function IDLBattleSearcher.getDistance(index1, index2)
    local key = joinStr(index1, "_", index2)
    local dis = disCache[key]
    if dis then
        return dis
    else
        local pos1 = grid.grid:GetCellCenter(index1)
        local pos2 = grid.grid:GetCellCenter(index2)
        dis = Vector3.Distance(pos1, pos2)
        disCache[key] = dis
        return dis
    end
end

---@public 寻敌
function IDLBattleSearcher.searchTarget(unit)
    if unit.isBuilding then
        -- 说明是建筑的防御设施
        return IDLBattleSearcher.buildingSearchRole4Def(unit)
    else
        -- 说明是角色
        IDLBattleSearcher.searchTarget4Role(unit)
    end
end

---@public 防御设施寻敌人
---@param building IDLBuilding
function IDLBattleSearcher.buildingSearchRole4Def(building)
    local cells = buildingsRange[building.instanceID]
    local target, preferedTarget
    local PreferedTargetType = bio2number(building.attr.PreferedTargetType)
    -- local AirTargets = building.attr.AirTargets
    -- local GroundTargets = building.attr.GroundTargets
    ---@param v BuildingRangeInfor
    for i, v in ipairs(cells or {}) do
        local map = offense[v.index]
        if map then
            ---@param role IDRoleBase
            for role, v2 in pairs(map) do
                if role then
                    -- 可攻击地面、飞行单位否？
                    if IDLBattleSearcher.isTarget(building, role) then
                        if not target then
                            target = role
                        end
                        if PreferedTargetType > 0 then
                            -- 有优先攻击类型
                            if bio2Int(role.attr.GID) == PreferedTargetType then
                                PreferedTargetType = role
                                return PreferedTargetType
                            end
                        else
                            return target
                        end
                    end
                end
            end
        end
    end

    return preferedTarget or target
end

---@public 角色寻敌
---@param role IDRoleBase
function IDLBattleSearcher.searchTarget4Role(role)
    if role.isOffense then
        -- 取得角色的index
        -- 取得离角色最近的目标，注意要考虑优先攻击目标
    else
        --//TODO:防守方的舰船寻敌
    end
end

---@param attacker IDLUnitBase
---@param unit IDLUnitBase
function IDLBattleSearcher.isTarget(attacker, unit)
    if attacker.isBuilding then
        ---@type IDLBuilding
        local b = attacker
        -- 可攻击地面、飞行单位否？
        if
            ((unit.attr.IsFlying and b.attr.AirTargets) or 
            ((not unit.attr.IsFlying) and b.attr.GroundTargets)) and
                (not unit.isDead)
        then
            return true
        else
            return false
        end
    else
        return (not unit.isDead)
    end
end

---@public 取得范围内的最优目标
---@param attacker IDLUnitBase
---@param pos UnityEngine.Vector3
---@param r number 半径
function IDLBattleSearcher.getTarget(attacker, pos, r)
    pos.y = 0
    local index = grid.grid:GetCellIndex(pos)
    local cells = grid:getOwnGrids(index, r * 2)
    local list = nil
    if attacker.isOffense then
        list = defense
    else
        list = offense
    end
    local m, index2
    for i = 0, cells.Count - 1 do
        index2 = cells[i]
        if IDLBattleSearcher.getDistance(index, index2) <= r then
            m = list[index2]
            if m then
                for k, v in pairs(m) do
                    if IDLBattleSearcher.isTarget(attacker, v) then
                        return v
                    end
                end
            end
        end
    end
    return nil
end

---@public 取得范围内的所有目标
---@param attacker IDLUnitBase
---@param pos UnityEngine.Vector3
---@param r number 半径
function IDLBattleSearcher.getTargetsInRange(attacker, pos, r)
    pos.y = 0
    local index = grid.grid:GetCellIndex(pos)
    local cells = grid:getOwnGrids(index, r * 2)
    local list = nil
    if attacker.isOffense then
        list = defense
    else
        list = offense
    end
    local ret = {}
    local m, index2
    for i = 0, cells.Count - 1 do
        index2 = cells[i]
        if IDLBattleSearcher.getDistance(index, index2) <= r then
            m = list[index2]
            if m then
                ---@param v IDLUnitBase
                for k, v in pairs(m) do
                    if IDLBattleSearcher.isTarget(attacker, v) then
                        table.insert(ret, v)
                    end
                end
            end
        end
    end
    return ret
end

---@param unit IDLUnitBase
function IDLBattleSearcher.someOneDead(unit)
    if unit.isBuilding then
        ---@type IDLBuilding
        local b = unit
        buildingsRange[unit.instanceID] = nil
        buildings[bio2number(b.serverData.idx)] = nil
    else
        if unit.isOffense then
            local index = rolesIndex[unit]
            -- 先清除掉旧的数据
            local map = offense[index] or {}
            map[unit] = nil
            offense[index] = map
        else
            local index = rolesIndex[unit]
            -- 先清除掉旧的数据
            local map = defense[index] or {}
            map[unit] = nil
            defense[index] = map
        end
    end
end

function IDLBattleSearcher.clean()
    buildingsRange = {}
    buildings = nil
    offense = {}
    defense = {}
    rolesIndex = {}

    for k, obj in ipairs(IDLBattleSearcher._debugRangs or {}) do
        CLThingsPool.returnObj(obj)
        SetActive(obj, false)
    end
    IDLBattleSearcher._debugRangs = {}
end

--------------------------------------------
return IDLBattleSearcher
