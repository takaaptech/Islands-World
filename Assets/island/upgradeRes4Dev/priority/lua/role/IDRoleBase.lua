﻿--[[
//                    ooOoo
//                   8888888
//                  88" . "88
//                  (| -_- |)
//                  O\  =  /O
//               ____/`---'\____
//             .'  \\|     |//  `.
//            /  \\|||  :  |||//  \
//           /  _||||| -:- |||||-  \
//           |   | \\\  -  /// |   |
//           | \_|  ''\---/''  |_/ |
//            \ .-\__  `-`  ___/-. /
//         ___ `. .' /--.--\  `. . ___
//      ."" '<  `.___\_<|>_/___.'  >' "".
//     | | : ` - \`.`\ _ /`.`/- ` : | |
//     \ \ `-.    \_ __\ /__ _/   .-` / /
//======`-.____`-.___\_____/___.-`____.-'======
//                   `=---='
//^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
//           佛祖保佑       永无BUG
//           游戏大卖       公司腾飞
//^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
--]]

require("public.class")
-- 角色基础相关
---@class IDRoleBase
IDRoleBase = class("IDRoleBase")

function IDRoleBase:ctor(csSelf)
    self.csSelf = csSelf        -- cs对象
    self.transform = nil
    self.gameObject = nil
    self.isOffense = false      -- 是进攻方
    self.id = 0

    -----@type IDDBBuilding
    self.serverData = nil       -- 服务器数据
    self.attr = nil             -- 属性
    self.isFinishInited = false
end

function IDRoleBase:init (selfObj, id, star, lev, _isOffense, other)
    self:__init(selfObj, other)
    self.isOffense = _isOffense
    self.id = id

    -- 取得属性配置
    if other then
        self.serverData = other.serverData
    end
    self.attr = DBCfg.getRoleByID(id)
    self:loadShadow()
end
function IDRoleBase:__init(selfObj, other)
    if self.isFinishInited then
        return
    end
    self.isFinishInited = true
    self.csSelf = selfObj
    self.transform = selfObj.transform
    self.gameObject = selfObj.gameObject
    self.body = selfObj.mbody
    if self.body and (not self.body:IsNull()) then
        self.action = self.body:GetComponent("CLRoleAction")
    end
end


---@public 加载影子
function IDRoleBase:loadShadow()
    if self.attr == nil then
        return
    end
    if self.shadow == nil then
        local shadowType = bio2number(self.attr.ShadowType)
        if shadowType < 1 then
            return
        end
        local shadowName = joinStr("shadow", shadowType)
        CLUIOtherObjPool.borrowObjAsyn(shadowName,
                function(name, obj, orgs)
                    if (not self.gameObject.activeInHierarchy) or self.shadow ~= nil then
                        CLUIOtherObjPool.returnObj(obj)
                        SetActive(obj, false)
                        return
                    end
                    self.shadow = obj.transform;
                    self.shadow.parent = MyCfg.self.shadowRoot
                    self.shadow.localEulerAngles = Vector3.zero
                    self.shadow.localScale = Vector3.one * bio2number(self.attr.ShadowSize) / 10
                    self.shadow.position = self.transform.position + Vector3.up * 0.01
                    SetActive(self.shadow.gameObject, true)
                end)
    end
end

---@public 播放动作
function IDRoleBase:playAction(actionName, onCompleteMotion)
    if self.action == nil then
        printe("self.action is nil")
        return
    end
    if onCompleteMotion == nil then
        onCompleteMotion = ActCBtoList(100, self:wrapFunction4CS(self.onActionFinish))
    end
    self.action:setAction(getAction(actionName), onCompleteMotion)
end

---@public 当动作播放完的通用回调
function IDRoleBase:onActionFinish(act)
    local actVal = act.currActionValue
    if getAction("idel") == actVal then
    elseif getAction("idel2") == actVal then
    elseif getAction("idel3") == actVal then
    elseif getAction("dead") == actVal then
    elseif getAction("dizzy") == actVal then
    elseif getAction("run") == actVal then
    elseif getAction("walk") == actVal then
        return
    end
    self:idel()
end

function IDRoleBase:idel()
    self:playAction("idel")
end

function IDRoleBase:clean()
    if self.shadow then
        CLUIOtherObjPool.returnObj(self.shadow.gameObject)
        SetActive(self.shadow.gameObject, false)
        self.shadow = nil
    end
end

--------------------------------------------
return IDRoleBase