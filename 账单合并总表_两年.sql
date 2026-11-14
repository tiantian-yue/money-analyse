-- ============================================================
-- 两年期合并总表 bill2_all 构建脚本（2024-09-01 ~ 2026-08-31）
--
-- 与旧版（账单合并总表.sql）的关系：
--   ★ 口径原样移植 —— 分类 CASE、is_refund、is_oneoff、is_dup、
--     transfer_kind 全部照抄旧版，一个字不改。
--     目的：先看「同一套规则放到两年 3,789 条上会不会崩」。
--     改规则是下一步的事，不能一边换数据一边换口径，否则差异归因不明。
--
--   ★ 两处有意的差异（都是修已知缺陷，不是换口径）：
--     ① 工行的 counterparty 改用新数据才有的「对方户名」，
--        旧版用摘要当商户 → 会出现一个叫「消费」的假商户（22 笔）。
--        新表用 COALESCE(对方户名, 摘要) 修掉。
--     ② 工行 counterparty 为空或 '/' 时回落到摘要。
--
--   ⚠ 只建 bill2_* 与 v2_*，不触碰旧作品的 bill_* / v_bill / v_spend
-- ============================================================

USE sqlpractice;

DROP TABLE IF EXISTS bill2_all;

CREATE TABLE bill2_all (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  source      VARCHAR(20)  NOT NULL             COMMENT '来源：微信/支付宝/工商银行',
  trade_time  DATETIME     NOT NULL             COMMENT '交易时间',
  category    VARCHAR(60)                       COMMENT '归类',
  counterparty VARCHAR(255)                     COMMENT '交易对方/商户',
  goods       VARCHAR(255)                      COMMENT '商品/摘要',
  in_out      VARCHAR(8)   NOT NULL             COMMENT '收/支',
  amount      DECIMAL(12,2) NOT NULL            COMMENT '金额（正数）',
  is_refund   TINYINT(1)   DEFAULT 0            COMMENT '是否退款/冲正',
  is_oneoff   TINYINT(1)   DEFAULT 0            COMMENT '是否一次性大额（旧口径：按类别打包）',
  is_dup      TINYINT(1)   DEFAULT 0            COMMENT '是否跨源重复计数（工行镜像）',
  transfer_kind VARCHAR(20) DEFAULT NULL        COMMENT '转账细分',
  pay_method  VARCHAR(120)                      COMMENT '支付方式',
  status      VARCHAR(80)                       COMMENT '状态',
  summary     VARCHAR(255)                      COMMENT '工行摘要（消费/转账/理财/银证转账…）—— 旧版放在 counterparty 里，导致出现名为「消费」的假商户',
  balance     DECIMAL(14,2)                     COMMENT '工行余额（旧版塞在 goods 里，这里单列）',
  INDEX idx_time (trade_time),
  INDEX idx_cat (category),
  INDEX idx_inout (in_out),
  INDEX idx_flag (is_refund, is_oneoff, is_dup),
  INDEX idx_dupdept (trade_time, amount),
  INDEX idx_trkind (transfer_kind)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='三源合并总表 两年期';

-- ============================================================
-- 一、微信：只取「支出」且非退款（口径同旧版）
-- ============================================================
INSERT INTO bill2_all (source, trade_time, category, counterparty, goods,
                       in_out, amount, is_refund, is_oneoff, is_dup, pay_method, status)
SELECT
  '微信',
  w.trade_time,
  CASE
    WHEN w.counterparty IN ('山西财经大学') OR w.goods LIKE '%平台缴费%' THEN '学费缴费'
    WHEN w.counterparty LIKE '%医院%' OR w.goods LIKE '%医疗%'
         OR w.goods LIKE '%门诊%' OR w.goods LIKE '%体检%' THEN '医疗健康'
    WHEN w.counterparty LIKE '%驾校%' OR w.counterparty LIKE '%交警%'
         OR w.counterparty LIKE 'A远景%' OR w.counterparty LIKE '%赵鹏%' THEN '驾校考证'
    WHEN w.goods LIKE '%钢琴%' OR w.counterparty LIKE '%钢琴%' THEN '兴趣乐器'
    WHEN w.goods LIKE '%网盘%' OR w.counterparty LIKE '%夸克%'
         OR w.counterparty LIKE '%文学%' OR w.counterparty LIKE '%图书%'
         OR w.goods LIKE '%课程%' OR w.goods LIKE '%教育%' THEN '学习成长'
    WHEN w.counterparty LIKE '%广电%' OR w.counterparty LIKE '%移动%'
         OR w.goods LIKE '%话费%' OR w.goods LIKE '%流量%' THEN '通讯'
    WHEN w.goods LIKE '%12306%' OR w.counterparty LIKE '%铁路%'
         OR w.counterparty LIKE '%中铁%' OR w.counterparty LIKE '%地铁%'
         OR w.counterparty LIKE '%轨交%' OR w.counterparty LIKE '%单车%'
         OR w.counterparty LIKE '%打车%' OR w.counterparty LIKE '%出行%'
         OR w.counterparty LIKE '%加油%' THEN '交通出行'
    WHEN w.counterparty LIKE '%拼多多%' OR w.goods LIKE '%先用后付%'
         OR w.counterparty LIKE '%淘宝%' OR w.counterparty LIKE '%京东%'
         OR w.counterparty LIKE '%vivo%' OR w.goods LIKE '%耳机%'
         OR w.counterparty LIKE '%服饰%' OR w.counterparty LIKE '%服装%' THEN '电商购物'
    WHEN w.counterparty LIKE '%美团%' OR w.goods LIKE '%美团%'
         OR w.goods LIKE '%外卖%' OR w.goods LIKE '%餐%' OR w.goods LIKE '%饭%'
         OR w.goods LIKE '%奶茶%' OR w.goods LIKE '%火锅%' OR w.goods LIKE '%披萨%'
         OR w.goods LIKE '%鸡柳%' OR w.goods LIKE '%水饺%' OR w.goods LIKE '%饼%'
         OR w.goods LIKE '%汤%' OR w.goods LIKE '%麻辣烫%' OR w.goods LIKE '%香锅%'
         OR w.counterparty LIKE '%蜜雪%' OR w.counterparty LIKE '%茶百道%'
         OR w.counterparty LIKE '%零食%' OR w.counterparty LIKE '%炒栗%'
         OR w.counterparty LIKE '%快餐%' OR w.counterparty LIKE '%烤鸭%'
         OR w.counterparty LIKE '%塔斯汀%' OR w.counterparty LIKE '%糕点%'
         OR w.counterparty LIKE '%食品%' OR w.counterparty LIKE '%果香园%'
         OR w.counterparty LIKE '%点心%' OR w.counterparty LIKE '%蔬菜%'
         OR w.counterparty LIKE '%可乐%'
         OR w.counterparty LIKE '%羊肉汤%' OR w.counterparty LIKE '%虾滑%'
         OR w.counterparty LIKE '%早点%' OR w.counterparty LIKE '%早餐%'
         OR w.counterparty LIKE '%小吃%' OR w.counterparty LIKE '%面馆%'
         OR w.counterparty LIKE '%米粉%' OR w.counterparty LIKE '%烧烤%'
         OR w.counterparty LIKE '%咖啡%' OR w.counterparty LIKE '%koi%'
         OR w.counterparty LIKE '%蛋糕%' OR w.counterparty LIKE '%甜品%'
         OR w.counterparty LIKE '%水果%' OR w.counterparty LIKE '%干果%'
         OR w.counterparty LIKE '%饭店%' OR w.counterparty LIKE '%餐饮%' THEN '餐饮外卖'
    WHEN w.goods LIKE '%超市%' OR w.goods LIKE '%购物广场%'
         OR w.counterparty LIKE '%便利店%' OR w.counterparty LIKE '%商贸%'
         OR w.counterparty LIKE '%百货%' OR w.counterparty LIKE '%惠民%'
         OR w.counterparty LIKE '%惠亿家%' OR w.counterparty LIKE '%万绣城%'
         OR w.counterparty LIKE '%无人零售%' OR w.counterparty LIKE '%洗衣%' THEN '商超日用'
    WHEN w.trade_type LIKE '%转账%' OR w.trade_type LIKE '%红包%' THEN '转账红包'
    WHEN w.counterparty LIKE '%复印%' OR w.counterparty LIKE '%打印%' THEN '文印服务'
    ELSE '其他消费'
  END,
  w.counterparty,
  w.goods,
  '支出',
  w.amount,
  0,
  CASE
    WHEN w.counterparty IN ('山西财经大学') OR w.goods LIKE '%平台缴费%'
      OR w.counterparty LIKE '%医院%' OR w.goods LIKE '%医疗%' OR w.goods LIKE '%门诊%'
      OR w.counterparty LIKE '%驾校%' OR w.counterparty LIKE '%交警%'
      OR w.counterparty LIKE 'A远景%' OR w.counterparty LIKE '%赵鹏%'
      OR w.trade_type LIKE '%转账%' OR w.trade_type LIKE '%红包%'
      OR w.counterparty LIKE '%广电%' OR w.goods LIKE '%话费%'
    THEN 1 ELSE 0
  END,
  0,
  w.pay_method,
  w.status
FROM bill2_wechat w
WHERE w.in_out = '支出'
  AND w.status NOT LIKE '%退款%';

-- ============================================================
-- 二、支付宝：只取「支出」且交易成功（口径同旧版）
-- ============================================================
INSERT INTO bill2_all (source, trade_time, category, counterparty, goods,
                       in_out, amount, is_refund, is_oneoff, is_dup, pay_method, status)
SELECT
  '支付宝',
  a.trade_time,
  CASE
    WHEN a.category = '餐饮美食' THEN '餐饮外卖'
    WHEN a.category = '交通出行' THEN '交通出行'
    WHEN a.category = '文化休闲' THEN '学习成长'
    WHEN a.category = '生活服务' THEN '生活服务'
    WHEN a.category = '转账红包' THEN '转账红包'
    ELSE '其他消费'
  END,
  a.counterparty,
  a.goods,
  '支出',
  a.amount,
  0,
  0,
  0,
  a.pay_method,
  a.status
FROM bill2_alipay a
WHERE a.in_out = '支出'
  AND a.status = '交易成功';

-- ============================================================
-- 三、工商银行：只取负向流水（口径同旧版，仅 counterparty 改用对方户名）
--   重复判定：同金额 + 时间差 ≤ 60 秒 → is_dup=1
--   ⚠ 60 秒本身在两年数据上实测不达标（覆盖率 92%，300 秒才 100%），
--     这里仍沿用 60 秒，是为了与旧作品可比。换阈值是独立决策，见 05 文档。
-- ============================================================
INSERT INTO bill2_all (source, trade_time, category, counterparty, goods,
                       in_out, amount, is_refund, is_oneoff, is_dup, pay_method, status,
                       summary, balance)
SELECT
  '工商银行',
  i.trade_time,
  CASE
    -- ⚠ 2026-11-14 新增：新数据才暴露的三类问题（旧 75 笔工行流水里没有）
    -- ① 摘要为「1」的 ¥5,550 —— 摘要列解析异常，但对方户名写着
    --    「山西财经大学代扣学费专户」，靠户名才认出是学费。
    --    没有这一列，它会被当成「其他支出」混进真实消费。
    -- ② 理财 / 银证转账 / 基金购买 —— 钱在自己账户间搬，不是消费。
    --    旧口径没有对应规则，导致 ¥16,929 直接进了 L3（占 22.4%）。
    WHEN i.counterparty LIKE '%学费%' THEN '学费缴费'
    WHEN i.summary IN ('理财', '银证转账', '基金购买', '充值') THEN '资金搬运'
    WHEN i.summary IN ('缴费') THEN '学费缴费'
    WHEN i.summary IN ('转账') THEN '转账红包'
    WHEN i.summary IN ('退款') THEN '退款冲正'
    WHEN i.summary IN ('消费') THEN '银行卡消费'
    WHEN i.summary IN ('还款') THEN '信用还款'
    ELSE '其他支出'
  END,
  COALESCE(NULLIF(i.counterparty, '/'), i.summary),
  i.summary,
  '支出',
  ABS(i.amount_signed),
  CASE WHEN i.summary = '退款' THEN 1 ELSE 0 END,
  CASE
    WHEN i.counterparty LIKE '%学费%' THEN 1
    WHEN i.summary IN ('理财', '银证转账', '基金购买', '充值',
                       '缴费', '转账', '退款', '还款') THEN 1
    ELSE 0
  END,
  CASE WHEN EXISTS (
         SELECT 1 FROM bill2_all x
         WHERE x.source <> '工商银行'
           AND x.in_out = '支出'
           AND x.amount = ABS(i.amount_signed)
           AND ABS(TIMESTAMPDIFF(SECOND, x.trade_time, i.trade_time)) <= 60
       ) THEN 1 ELSE 0 END,
  i.channel,
  '交易成功',
  i.summary,
  i.balance
FROM bill2_icbc i
WHERE i.amount_signed < 0;

-- ============================================================
-- 四、转账细分（第 3 版口径，逐字照抄旧版）
-- ============================================================
UPDATE bill2_all SET transfer_kind = '资金搬运'
WHERE category = '转账红包' AND source = '工商银行';

-- 理财 / 银证转账 / 基金 / 充值 → 资金搬运（钱在账户间搬，不是开销）
UPDATE bill2_all SET transfer_kind = '资金搬运'
WHERE category = '资金搬运';

UPDATE bill2_all SET transfer_kind = '人情往来'
WHERE category = '转账红包' AND source <> '工商银行';

UPDATE bill2_all SET transfer_kind = '零星对账'
WHERE category = '转账红包' AND amount < 1;

UPDATE bill2_all SET transfer_kind = '人情往来'
WHERE category = '转账红包' AND transfer_kind IS NULL;

-- ============================================================
-- 五、视图（口径与旧版完全一致）
-- ============================================================
DROP VIEW IF EXISTS v2_bill;
CREATE VIEW v2_bill AS
SELECT * FROM bill2_all
WHERE is_refund = 0 AND is_dup = 0;

DROP VIEW IF EXISTS v2_spend;
CREATE VIEW v2_spend AS
SELECT * FROM v2_bill
WHERE CASE
        WHEN category = '转账红包' THEN transfer_kind = '人情往来'
        ELSE is_oneoff = 0
      END;

-- ============================================================
-- 六、校验
-- ============================================================
SELECT '=== 合并总览（含重复）===' AS '';
SELECT source AS 来源, COUNT(*) AS 笔数, ROUND(SUM(amount),2) AS 合计
FROM bill2_all GROUP BY source
UNION ALL SELECT '合计', COUNT(*), ROUND(SUM(amount),2) FROM bill2_all;

SELECT '=== 三级口径 ===' AS '';
SELECT '① L1 全部支出（v2_bill）' AS 口径, COUNT(*) AS 笔数, ROUND(SUM(amount),2) AS 金额 FROM v2_bill
UNION ALL
SELECT '② L2 高频小额（is_oneoff=0）', COUNT(*), ROUND(SUM(amount),2) FROM v2_bill WHERE is_oneoff=0
UNION ALL
SELECT '③ L3 真实消费（v2_spend）', COUNT(*), ROUND(SUM(amount),2) FROM v2_spend
UNION ALL
SELECT '④ 人情往来（转账类）', COUNT(*), ROUND(SUM(amount),2) FROM v2_bill WHERE category='转账红包' AND transfer_kind='人情往来';

SELECT '=== 去重命中 ===' AS '';
SELECT 'is_dup=1 笔数' AS 项, COUNT(*) AS 笔, ROUND(SUM(amount),2) AS 金额 FROM bill2_all WHERE is_dup=1;

SELECT '=== 分类分布（L3 口径）—— 重点看「其他消费」占比 ===' AS '';
SELECT category AS 分类, COUNT(*) AS 笔数, ROUND(SUM(amount),2) AS 金额,
       ROUND(SUM(amount)*100/(SELECT SUM(amount) FROM v2_spend),1) AS 占比
FROM v2_spend GROUP BY category ORDER BY 金额 DESC;
