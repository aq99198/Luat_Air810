--[[
模块名称：程序运行框架
模块功能：初始化，程序运行框架、消息分发处理、定时器接口
模块最后修改时间：2017.02.17
]]

--定义模块,导入依赖库
require"patch"

local base = _G
local table = require"table"
local rtos = require"rtos"
local uart = require"uart"
local io = require"io"
local os = require"os"
local watchdog = require"watchdog"
local bit = require"bit"
module("sys")

--加载常用的全局函数至本地
local print = base.print
local unpack = base.unpack
local ipairs = base.ipairs
local type = base.type
local pairs = base.pairs
local assert = base.assert
local isn = 65535

-- 定时器管理,自动分配定时器id
--定时器支持的单步最大时长，单位毫秒
local MAXMS = 0x7fffffff/17
--定时器id
local uniquetid = 0
--定时器id表
local tpool = {}
--定时器参数表
local para = {}
--定时器是否循环表
local loop = {}
--lprfun：用户自定义的“低电关机处理程序”
--lpring：是否已经启动自动关机定时器
local lprfun,lpring
updateflag=false
--错误信息文件以及错误信息内容
local LIB_ERR_FILE,liberr = "/lib_err.txt",""

--[[
函数名：timerfnc
功能  ：处理底层core上报的外部定时器消息
参数  ：
		utid：定时器id
返回值：无
]]
local function timerfnc(utid)
  local tid,sn= bit.band(utid, 0xffff),bit.band((bit.rshift(utid,16)), 0xffff)

	if tpool[tid] ~= nil then
		local cb = tpool[tid].cb
		
		if tpool[tid].sn ~= sn or not cb then
		  print("ljd invalid timerfnc tid:",tid,"sn:",sn,"realsn:",tpool[tid].sn)
		  return
		end

		local tval = tpool[tid]
		if tval.times and tval.total and tval.step then
			tval.times = tval.times+1
			--拆分的几个定时器还未执行完毕，继续执行下一个
			if tval.times < tval.total then
				rtos.timer_start(tid,tval.step)
				return
			end
		end
		--如果不是循环定时器，从定时器id表中清除此定时器id位置的内容
		if not loop[tid] then tpool[tid] = nil end
		--存在自定义可变参数
		if para[tid] ~= nil then
			local pval = para[tid]
			--如果不是循环定时器，从定时器参数表中清除此定时器id位置的内容
			if not loop[tid] then para[tid] = nil end
			--执行定时器回调函数
			cb(unpack(pval))
		--不存在自定义可变参数
		else
			--执行定时器回调函数
			cb()
		end
		if loop[tid] then 
		  isn = isn==65535 and 0 or isn+1
		  tpool[tid].sn = isn
		  local lptid = bit.bor(bit.lshift(isn,16),tid)
		  rtos.timer_start(lptid,loop[tid]) 
		end
	end
end

--[[
函数名：comp_table
功能  ：比较两个table的内容是否相同，注意：table中不能再包含table
参数  ：
		t1：第一个table
		t2：第二个table
返回值：相同返回true，否则false
]]
local function comp_table(t1,t2)
	if not t2 then
	  if not t1 then return #t1 == 0 end
	  return true
	end
	if #t1 == #t2 then
		for i=1,#t1 do
			if unpack(t1,i,i) ~= unpack(t2,i,i) then
				return false
			end
		end
		return true
	end
	return false
end

--[[
函数名：timer_start
功能  ：开启一个定时器
参数  ：
		fnc：定时器的回调函数
		ms：定时器时长，单位为毫秒
		...：自定义可变参数
		注意：fnc和可变参数...共同标记唯一的一个定时器
返回值：定时器的ID，如果失败返回nil
]]
function timer_start(fnc,ms,...)
	assert(fnc ~= nil,"timer_start:callback function == nil")
	if ms==nil then
        print("sys.timer_start",fnc)
        return
	end
	if arg.n == 0 then
		timer_stop(fnc)
	else
		timer_stop(fnc,unpack(arg))
	end
	isn = isn==65535 and 0 or isn+1
	
	--如果时长超过单步支持的最大时长，则拆分为几个定时器
	if ms > MAXMS then
		local count = ms/MAXMS + (ms%MAXMS == 0 and 0 or 1)
		local step = ms/count
		tval = {cb = fnc, step = step, total = count, times = 0,sn = isn}
		ms = step
	--时长未超过单步支持的最大时长
	else
		tval = {cb = fnc,sn = isn}
	end
	uniquetid = 1
	
	while true do
		if tpool[uniquetid] == nil then
			tpool[uniquetid] = tval
			break
		end
		uniquetid = uniquetid + 1
	end
	local tid = bit.bor(bit.lshift(isn,16),uniquetid)
	if rtos.timer_start(tid,ms) ~= 1 then print("ljd rtos.timer_start error") return end
	if arg.n ~= 0 then
		para[uniquetid] = arg
	end
	return tid,uniquetid,tpool[uniquetid].sn
end

--[[
函数名：timer_loop_start
功能  ：开启一个循环定时器
参数  ：
		fnc：定时器的回调函数
		ms：定时器时长，单位为毫秒
		...：自定义可变参数
		注意：fnc和可变参数...共同标记唯一的一个定时器
返回值：定时器的ID，如果失败返回nil
]]
function timer_loop_start(fnc,ms,...)
	local tid,utid,sn = timer_start(fnc,ms,unpack(arg))
	if utid then loop[utid] = ms end
	return tid
end

--[[
函数名：timer_stop
功能  ：关闭一个定时器
参数  ：
		val：有两种形式：
		     一种是开启定时器时返回的定时器id，此形式时不需要再传入可变参数...就能唯一标记一个定时器
			 另一种是开启定时器时的回调函数，此形式时必须再传入可变参数...才能唯一标记一个定时器
		...：自定义可变参数，与timer_start和timer_loop_start中的可变参数意义相同
返回值：无
]]
function timer_stop(val,...)
	--val为定时器id
	if type(val) == "number" then
		tpool[val],para[val],loop[val] = nil
	else
		for k,v in pairs(tpool) do
			--回调函数相同
			if type(v) == "table" and v.cb == val then
				--自定义可变参数相同
				if comp_table(arg,para[k])then
					rtos.timer_stop(k)
					tpool[k],para[k],loop[k] = nil
					break
				end
			end
		end
	end
end

--[[
函数名：timer_stop_all
功能  ：关闭某个回调函数标记的所有定时器，无论开启定时器时有没有传入自定义可变参数
参数  ：
		fnc：开启定时器时的回调函数
返回值：无
]]
function timer_stop_all(fnc)
	for k,v in pairs(tpool) do
		if type(v) == "table" and v.cb == fnc then
			rtos.timer_stop(k)
			tpool[k],para[k],loop[k] = nil
		end
	end
end

--[[
函数名：timer_is_active
功能  ：判断某个定时器是否处于开启状态
参数  ：
		val：有两种形式：
		     一种是开启定时器时返回的定时器id，此形式时不需要再传入可变参数...就能唯一标记一个定时器
			 另一种是开启定时器时的回调函数，此形式时必须再传入可变参数...才能唯一标记一个定时器
		...：自定义可变参数，与timer_start和timer_loop_start中的可变参数意义相同
返回值：开启返回true，否则false
]]
function timer_is_active(val,...)
	if type(val) == "number" then
		return tpool[val] ~= nil
	else
		for k,v in pairs(tpool) do
			if type(v) == "table" and v.cb == val or v == val then
				if comp_table(arg,para[k]) then
					return true
				end
			end
		end
		return false
	end
end

function timer_is_active_anyone(val,...)
	if type(val) == "number" then
		return tpool[val] ~= nil
	else
		for k,v in pairs(tpool) do
			if type(v) == "table" and v.cb == val or v == val then
				--if comp_table(arg,para[k]) then
					return true
				--end
			end
		end
		return false
	end
end

--[[
函数名：readtxt
功能  ：读取文本文件中的全部内容
参数  ：
		f：文件路径
返回值：文本文件中的全部内容，读取失败为空字符串或者nil
]]
local function readtxt(f)
	local file,rt = io.open(f,"r")
	if not file then print("sys.readtxt no open",f) return "" end
	rt = file:read("*a")
	file:close()
	return rt
end

--[[
函数名：writetxt
功能  ：写文本文件
参数  ：
		f：文件路径
		v：要写入的文本内容
返回值：无
]]
local function writetxt(f,v)
	local file = io.open(f,"w")
	if not file then print("sys.writetxt no open",f) return end	
	local rt = file:write(v)
	if not rt then
		removegpsdat()
		file:write(v)		
	end
	file:close()
end

--[[
函数名：restart
功能  ：追加错误信息到LIB_ERR_FILE文件中
参数  ：
		s：错误信息，用户自定义，一般是string类型，重启后的trace中会打印出此错误信息
返回值：无
]]
local function appenderr(s)
	liberr = liberr..s
	writetxt(LIB_ERR_FILE,liberr)	
end

--[[
函数名：initerr
功能  ：打印LIB_ERR_FILE文件中的错误信息
参数  ：无
返回值：无
]]
local function initerr()
	liberr = readtxt(LIB_ERR_FILE) or ""
	print("sys.initerr",liberr)
	--liberr = ""
	--os.remove(LIB_ERR_FILE)
end

local poweroffcb
function regpoweroffcb(cb)
	poweroffcb = cb
end

--[[
函数名：restart
功能  ：软件重启
参数  ：
		r：重启原因，用户自定义，一般是string类型，重启后的trace中会打印出此重启原因
返回值：无
]]
function restart(r)
	base.print("sys restart:",r)
	assert(r and r ~= "","sys.restart cause null")
	appenderr("restart["..r.."];")
	if poweroffcb then poweroffcb() end
	rtos.restart()	
end

function poweroff(r)
	base.print("sys poweroff:",r)
	if r then appenderr("poweroff["..r.."];") end
	if poweroffcb then poweroffcb() end
	rtos.poweroff()
end


--[[
函数名：init
功能  ：lua应用程序初始化
参数  ：
		mode：充电开机是否启动GSM协议栈，1不启动，否则启动
		lprfnc：用户应用脚本中定义的“低电关机处理函数”，如果有函数名，则低电时，本文件中的run接口不会执行任何动作，否则，会延时1分钟自动关机
返回值：无
]]
function init(mode,lprfnc)
	assert(base.PROJECT and base.PROJECT ~= "" and base.VERSION and base.VERSION ~= "","Undefine PROJECT or VERSION")
	uart.setup(uart.ATC,0,0,uart.PAR_NONE,uart.STOP_1)
	print("init mode :",mode,lprfnc)
	print("poweron reason:",rtos.poweron_reason(),mode,base.PROJECT,base.VERSION)
	-- 模式0 充电器和闹钟开机都不注册网络
	
	-- 模式1 充电器和闹钟开机都注册网络
	if mode == 1 then
		if rtos.poweron_reason() == rtos.POWERON_CHARGER 
			or rtos.poweron_reason() == rtos.POWERON_ALARM  then
			rtos.repoweron()
		end
	--模式2 充电器开机注册网络，闹钟开机不注册网络
	elseif  mode == 2 then
		if rtos.poweron_reason() == rtos.POWERON_CHARGER then
			rtos.repoweron()
		end
	--模式2 闹钟开机注册网络，充电器开机不注册网络
	elseif  mode == 3 then
		if rtos.poweron_reason() == rtos.POWERON_ALARM  then
			rtos.repoweron()
		end
	end
	
	--发送MSG_POWERON_REASON消息
	dispatch("MSG_POWERON_REASON",rtos.poweron_reason())
	local f = io.open("/luaerrinfo.txt","r")
	if f then
		print(f:read("*a") or "")
		f:close()
	end
	lprfun = lprfnc
	initerr()
end

--[[
函数名：poweron
功能  ：启动GSM协议栈。例如在充电开机未启动GSM协议栈状态下，如果用户长按键正常开机，此时调用此接口启动GSM协议栈即可
参数  ：无
返回值：无
]]
function poweron()
	rtos.poweron(1)
end

--应用消息分发,消息通知
local apps = {}

--[[
函数名：regapp
功能  ：注册app
参数  ：可变参数，app的参数，有以下两种形式：
		以函数方式注册的app，例如regapp(fncname,"MSG1","MSG2","MSG3")
		以table方式注册的app，例如regapp({MSG1=fnc1,MSG2=fnc2,MSG3=fnc3})
返回值：无
]]
function regapp(...)
	local app = arg[1]
	--table方式
	if type(app) == "table" then
	--函数方式
	elseif type(app) == "function" then
		app = {procer = arg[1],unpack(arg,2,arg.n)}
	else
		error("unknown app type "..type(app),2)
	end
	--产生一个增加app的内部消息
	dispatch("SYS_ADD_APP",app)
	return app
end

--[[
函数名：deregapp
功能  ：解注册app
参数  ：
		id：app的id，id共有两种方式，一种是函数名，另一种是table名
返回值：无
]]
function deregapp(id)
	--产生一个移除app的内部消息
	dispatch("SYS_REMOVE_APP",id)
end


--[[
函数名：addapp
功能  ：增加app
参数  ：
		app：某个app，有以下两种形式：
		     如果是以函数方式注册的app，例如regapp(fncname,"MSG1","MSG2","MSG3"),则形式为：{procer=arg[1],"MSG1","MSG2","MSG3"}
			 如果是以table方式注册的app，例如regapp({MSG1=fnc1,MSG2=fnc2,MSG3=fnc3}),则形式为{MSG1=fnc1,MSG2=fnc2,MSG3=fnc3}
返回值：无
]] 
local function addapp(app)
	-- 插入尾部
	table.insert(apps,#apps+1,app)
end

--[[
函数名：removeapp
功能  ：移除app
参数  ：
		id：app的id，id共有两种方式，一种是函数名，另一种是table名
返回值：无
]] 
local function removeapp(id)
	--遍历app表
	for k,v in ipairs(apps) do
		--app的id如果是函数名
		if type(id) == "function" then
			if v.procer == id then
				table.remove(apps,k)
				return
			end
		--app的id如果是table名
		elseif v == id then
			table.remove(apps,k)
			return
		end
	end
end

--[[
函数名：callapp
功能  ：处理内部消息
		通过遍历每个app进行处理
参数  ：
		msg：消息
返回值：无
]] 
local function callapp(msg)
	local id = msg[1]
	--增加app消息
	if id == "SYS_ADD_APP" then
		addapp(unpack(msg,2,#msg))
	--移除app消息
	elseif id == "SYS_REMOVE_APP" then
		removeapp(unpack(msg,2,#msg))
	else
		local app
		--遍历app表
		for i=#apps,1,-1 do
			app = apps[i]
			if app.procer then --函数注册方式的app,带id通知
				for _,v in ipairs(app) do
					if v == id then
						if app.procer(unpack(msg)) ~= true then
							return
						end
					end
				end
			elseif app[id] then -- 处理表方式的app,不带id通知
				if app[id](unpack(msg,2,#msg)) ~= true then
					return
				end
			end
		end
	end
end


--内部消息队列
local qmsg = {}

--[[
函数名：dispatch
功能  ：产生内部消息，存储在内部消息队列中
参数  ：可变参数，用户自定义
返回值：无
]] 
function dispatch(...)
	table.insert(qmsg,arg)
end

--[[
函数名：getmsg
功能  ：读取内部消息
参数  ：无
返回值：内部消息队列中的第一个消息，不存在则返回nil
]] 
local function getmsg()
	if #qmsg == 0 then
		return nil
	end

	return table.remove(qmsg,1)
end

--[[
函数名：runqmsg
功能  ：处理内部消息
参数  ：无
返回值：无
]] 
local function runqmsg()
	local inmsg
	while true do
		--读取内部消息
		inmsg = getmsg()
		--内部消息为空
		if  inmsg == nil then 
			--需要刷新界面
			if updateflag then
				updateflag=false
				inmsg={"UIWND_UPDATE"}
			else
				break
			end
		end
		--处理内部消息
		callapp(inmsg)
	end
end

--“除定时器消息、物理串口消息外的其他外部消息（例如AT命令的虚拟串口数据接收消息、音频消息、充电管理消息、按键消息等）”的处理函数表
local handlers = {}
base.setmetatable(handlers,{__index = function() return function() end end,})

--[[
函数名：regmsg
功能  ：注册“除定时器消息、物理串口消息外的其他外部消息（例如AT命令的虚拟串口数据接收消息、音频消息、充电管理消息、按键消息等）”的处理函数
参数  ：
		id：消息类型id
		handler：消息处理函数
返回值：无
]] 
function regmsg(id,handler)
	if not id then return end
	handlers[id] = handler
end

--各个物理串口的数据接收处理函数表
local uartprocs = {}

--[[
函数名：reguart
功能  ：注册物理串口的数据接收处理函数
参数  ：
		id：物理串口号，1表示UART1，2表示UART2
		fnc：数据接收处理函数名
返回值：无
]] 
function reguart(id,fnc)
	uartprocs[id] = fnc
end

--[[
函数名：run
功能  ：lua应用程序运行框架入口
参数  ：无
返回值：无

运行框架基于消息处理机制，目前一共两种消息：内部消息和外部消息
内部消息：lua脚本调用本文件dispatch接口产生的消息，消息存储在qmsg表中
外部消息：底层core软件产生的消息，lua脚本通过rtos.receive接口读取这些外部消息
]] 
function run()
	local msg,v1,v2,v3,v4

	while true do
		--处理内部消息
		runqmsg()
		--阻塞读取外部消息
		msg,v1,v2,v3,v4 = rtos.receive(rtos.INF_TIMEOUT)
		if msg then watchdog.kick() end

		--电池电量为0%，用户应用脚本中没有定义“低电关机处理程序”，并且没有启动自动关机定时器		
		if not lprfun and not lpring and type(msg) == "table" and msg.id == rtos.MSG_PMD and msg.level == 0 then
			--启动自动关机定时器，60秒后关机
			lpring = true
			timer_start(poweroff,60000,"r1")
		end
		
		--外部消息为table类型
		if type(msg) == "table" then
			--定时器类型消息
			if msg.id == rtos.MSG_TIMER then
				timerfnc(msg.timer_id)
			--AT命令的虚拟串口数据接收消息
			elseif msg.id == rtos.MSG_UART_RXDATA and msg.uart_id == uart.ATC then
				handlers.atc()
			else
				--物理串口数据接收消息
				if msg.id == rtos.MSG_UART_RXDATA then
					if uartprocs[msg.uart_id] ~= nil then
						uartprocs[msg.uart_id]()
					else
						handlers[msg.id](msg)
					end
				--其他消息（音频消息、充电管理消息、按键消息等）
				else
					handlers[msg.id](msg)
				end
			end
		--外部消息非table类型
		elseif type(msg) == "number" then
			--定时器类型消息
			if msg == rtos.MSG_TIMER then
				timerfnc(v1)
			elseif msg == rtos.MSG_ALARM then
				--print("ZHY rtos.MSG_ALARM",msg,rtos.MSG_ALARM,type(msg))
				handlers[msg](msg)
			elseif msg == rtos.MSG_UART_RXDATA then
				if v1 == uart.ATC then
					handlers.atc()
				else
					if uartprocs[v1] ~= nil then
						uartprocs[v1]()
					else
						handlers[msg](msg,v1)
					end
				end
			elseif msg >= rtos.MSG_PDP_ACT_CNF and msg <= rtos.MSG_SOCK_CLOSE_IND then
				handlers.sock(msg,v1,v2,v3,v4)
			else
				if handlers[msg] then
					handlers[msg](v1,v2,v3,v4)
				end
			end
		end
		--打印lua脚本程序占用的内存，单位是K字节
		--print("mem:",base.collectgarbage("count"))
	end
end

local DIR,DIR2 = "/EPO_GR_3_","/QG_R_"
function removegpsdat()
	--timer_stop(removegpsdat)
	--timer_start(removegpsdat,3600*1000)
	for i = 0,10 do
		--print("removegpsdat",i,DIR..i..".DAT")
		os.remove(DIR..i..".DAT")
	end
	for i = 0,4 do
		os.remove(DIR2..i..".DAT")		
	end
end

--timer_start(removegpsdat,3600*1000)
