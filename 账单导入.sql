-- ============================================================
-- 账单数据导入脚本（sqlpractice 库）
-- 前置：CSV 已复制到 F:\allstudy\mysql\data\Uploads\
--       （即 secure_file_priv 白名单目录）
-- 用法：mysql -u root --default-character-set=utf8mb4 < 本文件
-- 注意：可反复重跑（先 TRUNCATE 再导）
-- ============================================================

USE sqlpractice;

-- 清空旧数据，保证可反复重跑
TRUNCATE TABLE bill_wechat;
TRUNCATE TABLE bill_alipay;
TRUNCATE TABLE bill_icbc;

-- ---------- 1. 微信（707 笔） ----------
-- 时间已是 'YYYY-MM-DD HH:MM:SS'，无需再转序列号
LOAD DATA INFILE 'F:/allstudy/mysql/data/Uploads/bill_wechat.csv'
INTO TABLE bill_wechat
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(trade_time, trade_type, counterparty, goods, in_out, amount,
 pay_method, status, trade_no, merchant_no, remark);

-- ---------- 2. 支付宝（23 笔） ----------
LOAD DATA INFILE 'F:/allstudy/mysql/data/Uploads/bill_alipay.csv'
INTO TABLE bill_alipay
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(trade_time, category, counterparty, counterparty_acct, goods, in_out,
 amount, pay_method, status, trade_no, merchant_no, remark);

-- ---------- 3. 工商银行（75 笔） ----------
-- 注意：源 CSV 的「交易日期」列缺了空格（'2026-03-2917:09:47'），
--       这是银行 xlsx 里日期与时间分属两个文本框导致的。
--       这里用 @t_raw 变量接住原值，再用 REPLACE 补空格转成合法 DATETIME。
LOAD DATA INFILE 'F:/allstudy/mysql/data/Uploads/bill_icbc.csv'
INTO TABLE bill_icbc
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(@t_raw, seq_no, account, deposit_type, currency, cash_flag,
 region, @amt_raw, @bal_raw, summary, channel)
SET trade_time = STR_TO_DATE(
      CONCAT(LEFT(@t_raw, 10), ' ', RIGHT(@t_raw, 8)),
      '%Y-%m-%d %H:%i:%s'),
    amount_signed = CAST(REPLACE(REPLACE(@amt_raw, ',', ''), '+', '') AS DECIMAL(12,2)),
    balance       = CAST(REPLACE(@bal_raw, ',', '') AS DECIMAL(14,2));

-- ---------- 校验 ----------
SELECT '微信' AS 来源, COUNT(*) AS 笔数,
       ROUND(SUM(CASE WHEN in_out='支出' THEN amount ELSE 0 END),2) AS 支出合计
FROM bill_wechat
UNION ALL
SELECT '支付宝', COUNT(*),
       ROUND(SUM(CASE WHEN in_out='支出' THEN amount ELSE 0 END),2)
FROM bill_alipay
UNION ALL
SELECT '工商银行', COUNT(*),
       ROUND(SUM(CASE WHEN amount_signed<0 THEN -amount_signed ELSE 0 END),2)
FROM bill_icbc;
