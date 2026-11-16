-- ============================================================
-- 账单分析建表脚本（sqlpractice 库）
-- 作者：作品集 #1「我的六个月账单分析」
-- 用法：先双击 F:\allstudy\SQL练习.cmd 进库，再 source 本文件
--      或直接：mysql -u root -p sqlpractice < 本文件
-- 注意：本脚本会 DROP 重建 bill_* 表，可反复重跑
-- ============================================================

CREATE DATABASE IF NOT EXISTS sqlpractice
  DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
USE sqlpractice;

-- 先删旧表，保证可反复重跑
DROP TABLE IF EXISTS bill_all;
DROP TABLE IF EXISTS bill_wechat;
DROP TABLE IF EXISTS bill_alipay;
DROP TABLE IF EXISTS bill_icbc;

-- ---------- 1. 微信支付账单（707 笔） ----------
CREATE TABLE bill_wechat (
  id          INT AUTO_INCREMENT PRIMARY KEY COMMENT '自增主键',
  trade_time  DATETIME     NOT NULL             COMMENT '交易时间',
  trade_type  VARCHAR(255)                      COMMENT '交易类型',
  counterparty VARCHAR(255)                     COMMENT '交易对方',
  goods       VARCHAR(255)                      COMMENT '商品',
  in_out      VARCHAR(8)                        COMMENT '收/支',
  amount      DECIMAL(12,2)                     COMMENT '金额(元)',
  pay_method  VARCHAR(255)                      COMMENT '支付方式',
  status      VARCHAR(255)                      COMMENT '当前状态',
  trade_no    VARCHAR(255)                      COMMENT '交易单号',
  merchant_no VARCHAR(255)                      COMMENT '商户单号',
  remark      VARCHAR(255)                      COMMENT '备注',
  INDEX idx_time (trade_time),
  INDEX idx_inout (in_out)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='微信支付账单明细';

-- ---------- 2. 支付宝交易明细（23 笔） ----------
CREATE TABLE bill_alipay (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  trade_time  DATETIME     NOT NULL,
  category    VARCHAR(255)                      COMMENT '交易分类',
  counterparty VARCHAR(255)                     COMMENT '交易对方',
  counterparty_acct VARCHAR(255)                COMMENT '对方账号',
  goods       VARCHAR(255)                      COMMENT '商品说明',
  in_out      VARCHAR(8)                        COMMENT '收/支',
  amount      DECIMAL(12,2)                     COMMENT '金额',
  pay_method  VARCHAR(255)                      COMMENT '收/付款方式',
  status      VARCHAR(255)                      COMMENT '交易状态',
  trade_no    VARCHAR(255)                      COMMENT '交易订单号',
  merchant_no VARCHAR(255)                      COMMENT '商家订单号',
  remark      VARCHAR(255)                      COMMENT '备注',
  INDEX idx_time (trade_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='支付宝交易明细';

-- ---------- 3. 工商银行历史明细（75 笔） ----------
CREATE TABLE bill_icbc (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  trade_time  DATETIME     NOT NULL,
  seq_no      VARCHAR(255)                      COMMENT '序号',
  account     VARCHAR(255)                      COMMENT '账号',
  deposit_type VARCHAR(255)                     COMMENT '储种',
  currency    VARCHAR(255)                      COMMENT '币种',
  cash_flag   VARCHAR(255)                      COMMENT '钞汇',
  region      VARCHAR(255)                      COMMENT '地区',
  amount_signed DECIMAL(12,2)                   COMMENT '收入/支出金额（带正负号）',
  balance     DECIMAL(14,2)                     COMMENT '余额',
  summary     VARCHAR(255)                      COMMENT '摘要',
  channel     VARCHAR(255)                      COMMENT '渠道',
  INDEX idx_time (trade_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='工商银行借记卡历史明细';

-- ---------- 4. 合并总表（三份账单统一口径，分析就用这张） ----------
CREATE TABLE bill_all (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  source      VARCHAR(20)  NOT NULL             COMMENT '来源：微信/支付宝/工商银行',
  trade_time  DATETIME     NOT NULL             COMMENT '交易时间',
  category    VARCHAR(60)                       COMMENT '归类（餐饮/交通/购物/医疗/学习/缴费/转账/其他）',
  counterparty VARCHAR(255)                     COMMENT '交易对方/商户',
  goods       VARCHAR(255)                      COMMENT '商品/摘要',
  in_out      VARCHAR(8)   NOT NULL             COMMENT '收/支',
  amount      DECIMAL(12,2) NOT NULL            COMMENT '金额（正数）',
  is_refund   TINYINT(1)   DEFAULT 0            COMMENT '是否退款/冲正：1 是 0 否',
  is_oneoff   TINYINT(1)   DEFAULT 0            COMMENT '是否一次性大额（学费/医疗/驾校等）：1 是 0 否',
  is_dup      TINYINT(1)   DEFAULT 0            COMMENT '是否跨源重复计数：1 是（工行镜像，分析时须剔除）',
  transfer_kind VARCHAR(20) DEFAULT NULL        COMMENT '转账细分：资金搬运/AA分账/人情往来 —— 只有 AA分账 算真消费',
  pay_method  VARCHAR(120)                      COMMENT '支付方式',
  status      VARCHAR(80)                       COMMENT '状态',
  INDEX idx_time (trade_time),
  INDEX idx_cat (category),
  INDEX idx_inout (in_out),
  INDEX idx_flag (is_refund, is_oneoff, is_dup),
  INDEX idx_dupdept (trade_time, amount),
  INDEX idx_trkind (transfer_kind)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='三份账单合并总表（分析主表）';

-- 去重视图：分析一律走这个视图，不再手写去重条件
DROP VIEW IF EXISTS v_bill;
CREATE VIEW v_bill AS
SELECT * FROM bill_all
WHERE is_refund = 0 AND is_dup = 0;

-- 日常开销视图（这才是「我的钱到底花哪了」的口径）
--   规则：排除两类「钱没有真正离开我」的东西 ——
--     ① 一次性大额（学费/医疗/驾校）—— 是支出，但不是「日常」消费
--     ② 资金搬运（卡间划转/提现）—— 钱只是换了个口袋
--   注意「人情往来」（红包/送礼/请客）**是算消费的** —— 钱实实在在出去了。
--   曾经把它剔掉，是把「消费」和「支出」混为一谈；用户指出后已改。
--   这里用 CASE 分流而不是 AND 叠加，是因为转账的两套标记（is_oneoff /
--   transfer_kind）语义不同，叠加过滤会让细分失效。
DROP VIEW IF EXISTS v_spend;
CREATE VIEW v_spend AS
SELECT * FROM v_bill
WHERE CASE
        WHEN category = '转账红包' THEN transfer_kind = '人情往来'  -- 转账：只算人情往来
        ELSE is_oneoff = 0                                          -- 非转账：排除一次性大额
      END;

SELECT '建表完成' AS msg;
SELECT TABLE_NAME, TABLE_COMMENT
FROM information_schema.TABLES
WHERE TABLE_SCHEMA='sqlpractice' AND TABLE_NAME LIKE 'bill%';
