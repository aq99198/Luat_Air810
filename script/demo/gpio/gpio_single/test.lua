module(...,package.seeall)

--[[
��������print
����  ����ӡ�ӿڣ����ļ��е����д�ӡ�������testǰ׺
����  ����
����ֵ����
]]
local function print(...)
	_G.print("test",...)
end

-------------------------PIN31���Կ�ʼ-------------------------
local pin31flg = true
--[[
��������pin31set
����  ������PIN31���ŵ������ƽ��1�뷴תһ��
����  ����
����ֵ����
]]
local function pin31set()
	pins.set(pin31flg,pins.PIN31)
	pin31flg = not pin31flg
	print("pin31set",pin31flg and "low" or "high")
end
--����1���ѭ����ʱ��������PIN31���ŵ������ƽ
sys.timer_loop_start(pin31set,1000)
-------------------------PIN31���Խ���-------------------------


-------------------------PIN32���Կ�ʼ-------------------------
local pin32flg = true
--[[
��������pin32set
����  ������PIN32���ŵ������ƽ��1�뷴תһ��
����  ����
����ֵ����
]]
local function pin32set()
	pins.set(pin32flg,pins.PIN32)
	pin32flg = not pin32flg
	print("pin32set",pin32flg and "low" or "high")
end
--����1���ѭ����ʱ��������PIN32���ŵ������ƽ
sys.timer_loop_start(pin32set,1000)
-------------------------PIN32���Խ���-------------------------


-------------------------PIN25���Կ�ʼ-------------------------
--[[
��������ind
����  ������PIN25�����߼��жϴ���
����  ��
        e����Ϣ��"PIN_PIN25_IND"
		v�����Ϊtrue����ʾ�ߵ�ƽ�жϣ�false��ʾ�͵�ƽ�ж�
����ֵ����
]]
local function ind(e,v)
	print("ind",e,v)
end
--ע��PIN25�����߼��жϵĴ�������
sys.regapp(ind,"PIN_"..pins.PIN25.name.."_IND")
-------------------------PIN25���Խ���-------------------------


-------------------------PIN38���Կ�ʼ-------------------------
--[[
��������pin38get
����  ����ȡPIN38���ŵ������ƽ
����  ����
����ֵ����
]]
local function pin38get()
	local v = pins.get(pins.PIN38)
	print("pin38get",v and "low" or "high")
end
--����1���ѭ����ʱ������ȡPIN38���ŵ������ƽ
sys.timer_loop_start(pin38get,1000)
-------------------------PIN38���Խ���-------------------------