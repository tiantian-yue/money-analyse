@echo off
chcp 936 >nul
setlocal
set MYSQL_PWD=123456
title 账单分析库 - sqlpractice

:menu
cls
echo ============================================================
echo   账单分析工作台  (作品集 #1)
echo   库: sqlpractice   表: bill_wechat / bill_alipay / bill_icbc / bill_all
echo                     视图: v_bill(去重去退款) / v_spend(真实消费)
echo ------------------------------------------------------------
echo   [1] 一键跑全部分析查询（带注释，滚完后往上翻）
echo   [2] 进入交互工作台（自己敲 SQL）
echo   [0] 退出
echo ------------------------------------------------------------
echo   口径三条铁律:
echo     (1) 查数据一律 FROM v_bill（已自动剔退款 + 剔跨源重复）
echo     (2) 查「真实消费」一律 FROM v_spend（转账类分叉判：留人情往来、剔大额非转账）
echo     (3) 口径只写在视图定义里，查询不得重复写过滤条件
echo ------------------------------------------------------------
echo   已知缺陷（查询 11 可复现去重；查询 12 是摘要白名单校验）:
echo     · 去重判据 v1「时间完全相等」漏判 14 笔，已改 60 秒容差
echo     · 改后仍有 1 笔漏判 —— 阈值本身待业务方确认（AC-11）
echo     · is_oneoff 字段超载：医疗小额误标（§8.2 已拍板待实施）
echo ============================================================
set /p sel=请输入序号后回车（直接回车=1）: 
if "%sel%"=="2" goto workbench
if "%sel%"=="0" goto end

echo.
echo ===== 正在跑全部分析查询（结果较长，跑完请往上滚动查看）=====
echo.
"F://allstudy//mysql//server//bin//mysql.exe" -u root --default-character-set=utf8mb4 --table --comments sqlpractice < "%~dp0账单分析查询.sql"
echo.
echo ===== 跑完。按任意键回菜单 =====
pause >nul
goto menu

:workbench
"F://allstudy//mysql//server//bin//mysql.exe" -u root --default-character-set=utf8mb4 sqlpractice

:end
endlocal
echo (已退出，按任意键关闭窗口)
pause >nul
