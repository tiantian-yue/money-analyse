@echo off
chcp 936 >nul
set MYSQL_PWD=123456
title 账单分析库 - sqlpractice
echo ============================================================
echo   账单分析工作台  (作品集 #1)
echo   库: sqlpractice   表: bill_wechat / bill_alipay / bill_icbc / bill_all
echo                     视图: v_bill(去重去退款) / v_spend(真实消费)
echo ------------------------------------------------------------
echo   常用命令:
echo     SHOW TABLES;                          看有哪些表
echo     SELECT * FROM bill_all LIMIT 5;       看合并总表
echo     SELECT * FROM v_spend LIMIT 5;        看真实消费口径
echo     SOURCE F:/作品集/money analyse/账单分析查询.sql;   跑全部分析
echo     EXIT;                                 退出
echo ============================================================
echo   口径三条铁律:
echo     ① 查数据一律 FROM v_bill（已自动剔退款 + 剔跨源重复）
echo     ② 查「真实消费」一律 FROM v_spend（再剔一次性大额 + 非消费转账）
echo     ③ 口径只写在「账单建表.sql」的视图里，改一处即可
echo ------------------------------------------------------------
echo   已知缺陷（查询 11 可复现）:
echo     · 去重判据 v1「时间完全相等」漏判 14 笔，已改 60 秒容差
echo     · 改后仍有 1 笔漏判 —— 阈值本身待业务方确认
echo     · 结论：规则是从 618 笔反推的，放量到 100 人会成片失效
echo ============================================================
echo.
"F:\allstudy\mysql\server\bin\mysql.exe" -u root --default-character-set=utf8mb4 sqlpractice
echo.
echo (已退出，按任意键关闭窗口)
pause >nul
