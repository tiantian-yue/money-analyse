-- ============================================================
-- 账单合并总表 bill_all 构建脚本
-- 把微信 / 支付宝 / 工行三张表统一成同一口径，并打上分类标签
-- 用法：mysql -u root --default-character-set=utf8mb4 < 本文件
-- 可反复重跑（先 TRUNCATE）
-- ============================================================

USE sqlpractice;

TRUNCATE TABLE bill_all;

-- ============================================================
-- 一、微信：只取「支出」且非退款
--   口径说明：微信原始「支出」标记含退款冲正，必须剔除，
--             否则合计比实际多算（实测多 1176.97 元）
-- ============================================================
INSERT INTO bill_all (source, trade_time, category, counterparty, goods,
                      in_out, amount, is_refund, is_oneoff, is_dup, pay_method, status)
SELECT
  '微信',
  w.trade_time,
  CASE
    -- ① 学费缴费
    WHEN w.counterparty IN ('山西财经大学') OR w.goods LIKE '%平台缴费%' THEN '学费缴费'
    -- ② 医疗健康
    WHEN w.counterparty LIKE '%医院%' OR w.goods LIKE '%医疗%'
         OR w.goods LIKE '%门诊%' OR w.goods LIKE '%体检%' THEN '医疗健康'
    -- ③ 驾校考证
    WHEN w.counterparty LIKE '%驾校%' OR w.counterparty LIKE '%交警%'
         OR w.counterparty LIKE 'A远景%' OR w.counterparty LIKE '%赵鹏%' THEN '驾校考证'
    -- ④ 兴趣乐器
    WHEN w.goods LIKE '%钢琴%' OR w.counterparty LIKE '%钢琴%' THEN '兴趣乐器'
    -- ⑤ 学习成长
    WHEN w.goods LIKE '%网盘%' OR w.counterparty LIKE '%夸克%'
         OR w.counterparty LIKE '%文学%' OR w.counterparty LIKE '%图书%'
         OR w.goods LIKE '%课程%' OR w.goods LIKE '%教育%' THEN '学习成长'
    -- ⑥ 通讯（话费流量）
    WHEN w.counterparty LIKE '%广电%' OR w.counterparty LIKE '%移动%'
         OR w.goods LIKE '%话费%' OR w.goods LIKE '%流量%' THEN '通讯'
    -- ⑦ 交通出行
    WHEN w.goods LIKE '%12306%' OR w.counterparty LIKE '%铁路%'
         OR w.counterparty LIKE '%中铁%' OR w.counterparty LIKE '%地铁%'
         OR w.counterparty LIKE '%轨交%' OR w.counterparty LIKE '%单车%'
         OR w.counterparty LIKE '%打车%' OR w.counterparty LIKE '%出行%'
         OR w.counterparty LIKE '%加油%' THEN '交通出行'
    -- ⑧ 电商购物（拼多多为主）
    WHEN w.counterparty LIKE '%拼多多%' OR w.goods LIKE '%先用后付%'
         OR w.counterparty LIKE '%淘宝%' OR w.counterparty LIKE '%京东%'
         OR w.counterparty LIKE '%vivo%' OR w.goods LIKE '%耳机%'
         OR w.counterparty LIKE '%服饰%' OR w.counterparty LIKE '%服装%' THEN '电商购物'
    -- ⑨ 餐饮外卖（含到店、奶茶、零食、水果、早餐摊）
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
         -- 第二轮补充：从「其他消费」里捞回来的餐饮类
         OR w.counterparty LIKE '%羊肉汤%' OR w.counterparty LIKE '%虾滑%'
         OR w.counterparty LIKE '%早点%' OR w.counterparty LIKE '%早餐%'
         OR w.counterparty LIKE '%小吃%' OR w.counterparty LIKE '%面馆%'
         OR w.counterparty LIKE '%米粉%' OR w.counterparty LIKE '%烧烤%'
         OR w.counterparty LIKE '%咖啡%' OR w.counterparty LIKE '%koi%'
         OR w.counterparty LIKE '%蛋糕%' OR w.counterparty LIKE '%甜品%'
         OR w.counterparty LIKE '%水果%' OR w.counterparty LIKE '%干果%'
         OR w.counterparty LIKE '%饭店%' OR w.counterparty LIKE '%餐饮%' THEN '餐饮外卖'
    -- ⑩ 商超日用
    WHEN w.goods LIKE '%超市%' OR w.goods LIKE '%购物广场%'
         OR w.counterparty LIKE '%便利店%' OR w.counterparty LIKE '%商贸%'
         OR w.counterparty LIKE '%百货%' OR w.counterparty LIKE '%惠民%'
         OR w.counterparty LIKE '%惠亿家%' OR w.counterparty LIKE '%万绣城%'
         OR w.counterparty LIKE '%无人零售%' OR w.counterparty LIKE '%洗衣%' THEN '商超日用'
    -- ⑪ 转账红包
    WHEN w.trade_type LIKE '%转账%' OR w.trade_type LIKE '%红包%' THEN '转账红包'
    -- ⑫ 文印服务
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
  0,                                  -- 微信侧不可能是重复（重复的是工行镜像）
  w.pay_method,
  w.status
FROM bill_wechat w
WHERE w.in_out = '支出'
  AND w.status NOT LIKE '%退款%'
  AND w.status NOT LIKE '%已全额退款%';

-- ============================================================
-- 二、支付宝：只取「支出」且交易成功
-- ============================================================
INSERT INTO bill_all (source, trade_time, category, counterparty, goods,
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
FROM bill_alipay a
WHERE a.in_out = '支出'
  AND a.status = '交易成功';

-- ============================================================
-- 三、工商银行：只取负向（支出）流水
--   注意 1：工行大额里混着「微信零钱提现 → 转账」这种资金搬运，
--           不是日常开销，标记为 is_oneoff=1 排除在日常口径外
--   注意 2（关键）：工行是「扣款侧镜像」——支付宝/微信绑工行卡付款时，
--           同一笔会在两边各记一次。实测构成（2026-10-06 逐笔核对）：
--             ① 支付宝绑工行卡快捷支付   17 笔 ¥113.42  ← 主力
--             ② 微信扫码/商户消费用工行卡  2 笔 ¥5,520.00
--           这里按「同金额 + 时间差 ≤ 60 秒」判定为重复，工行侧标 is_dup=1，
--           分析一律走 v_bill 视图自动排除。不去重则总支出虚高 24.3%。
--
--   ⚠ 反例警告：有一类记录「长得像重复，但绝不能剔」——
--     微信「零钱提现」12 笔 / 工行「微信零钱提现」11 笔。
--     它不是重复，因为：①微信侧 in_out='/'，从未进过支出统计；
--     ②工行侧是**正数进账**；③两边金额差 0.1% 提现手续费
--     （微信记 ¥200.20，工行到账 ¥200.00）。
--     → 它是「资金搬运」。判重必须看「是否同一笔支出被算两次」，
--       而不是「是否两边都有记录」。
--
--   ⚠ 未解决的边界：工行「消费 快捷支付」共 39 笔，其中 22 笔
--     找不到任何来源（容差放宽到 1 天也新增 0 笔匹配）。
--     → 闸门的能力上限由**数据完整性**决定，不是阈值。详见查询 11e。
--
--   ⚠ 2026-10-06 压力测试发现本规则有漏判（详见「账单分析查询.sql」查询 11）：
--     原判据是 trade_time **完全相等**，实测支付宝走工行卡共 18 笔，
--     仅命中 4 笔，漏判 14 笔（¥71.94）。
--     原因：第三方渠道落账存在延迟 —— U净洗衣机 16 秒、淘宝闪购 10 秒、
--           U净 9~11 秒，实测最大 16 秒。
--     本质：这不是 SQL 写错，是**需求定义错误**。我把「时间相等」
--           当成了业务规则，但业务事实是「同一笔交易在不同渠道的
--           落账时间允许有延迟」，这个容差必须先由业务方确认。
--     处置：下方改用 60 秒容差（可抓全 18 笔），并保留原严格口径注释。
--           60 秒是我按实测最大延迟 16 秒留出的安全边界，不是业务方最终裁决。
-- ============================================================
INSERT INTO bill_all (source, trade_time, category, counterparty, goods,
                      in_out, amount, is_refund, is_oneoff, is_dup, pay_method, status)
SELECT
  '工商银行',
  i.trade_time,
  CASE
    WHEN i.summary IN ('缴费') THEN '学费缴费'
    WHEN i.summary IN ('转账') THEN '转账红包'
    WHEN i.summary IN ('退款') THEN '退款冲正'
    WHEN i.summary IN ('消费') THEN '银行卡消费'
    WHEN i.summary IN ('还款') THEN '信用还款'
    ELSE '其他支出'
  END,
  i.summary,
  CONCAT('余额 ', i.balance),
  '支出',
  ABS(i.amount_signed),
  CASE WHEN i.summary = '退款' THEN 1 ELSE 0 END,
  CASE WHEN i.summary IN ('缴费', '转账', '退款', '还款') THEN 1 ELSE 0 END,
  -- 跨源重复判定：v2 改为「同金额 + 时间差 ≤ 60 秒」（v1 是完全相等，会漏判）
  CASE WHEN EXISTS (
         SELECT 1 FROM bill_all x
         WHERE x.source <> '工商银行'
           AND x.in_out = '支出'
           AND x.amount = ABS(i.amount_signed)
           AND ABS(TIMESTAMPDIFF(SECOND, x.trade_time, i.trade_time)) <= 60
       ) THEN 1 ELSE 0 END,
  i.channel,
  '交易成功'
FROM bill_icbc i
WHERE i.amount_signed < 0;

-- ============================================================
-- 转账细分（第 3 版 —— 前两版都被用户指出了逻辑漏洞，这里如实留着）
--   背景：原来把「转账」一刀切当成非消费，是拍脑袋的。
--         实际看数据，转账里混着三类完全不同的东西：
--     A. 资金搬运  —— 自己卡间划转 / 提现，钱只是从左口袋到右口袋，绝对不算支出
--     B. AA分账    —— 和朋友各付一半 / 先垫后还，是「借垫款」，不是消费
--     C. 人情往来  —— 红包 / 送礼 / 请客，是「单向送出的钱」，属于真实开销
--
--   第 3 版修正了前两版的两个错误：
--     ❌ 第 1 版错在：用「金额有没有角以下零头」当 AA 判据 → 只捞到 6.74 一笔，
--        因为 6.50/22.50/104.50 乘 10 正好是整数，全被漏掉。
--     ❌ 第 2 版错在：改用「是否整元」判 AA，且把人情往来整个剔出消费。
--        用户指出两点，都成立：
--          ① 用户：「有时候A钱也凑整啊」—— 对。廖文钦 12 笔里 5 笔是整元
--             （372/150/57/5/5），从数据上跟带零头的 104.50 没有本质区别，
--             都是同一个人之间的往来。拿「带不带零头」区分同类事物，是自相矛盾。
--          ② 用户：「人情往来不也算日常消费吗」—— 更根本。请客吃饭、发红包、
--             送礼，钱实实在在出去了，属于个人开销。原判据只因「长得像转账」就剔掉，
--             把「消费」和「支出」混为一谈了。
--
--   第 3 版的处理（不猜性质，只分「是不是我的开销」）：
--     ① 工行摘要为「转账」的流水 → 资金搬运（卡间划转，唯一确定非开销的一类）
--     ② 微信/支付宝转账、红包 → 人情往来（我的开销，计入消费）
--        - 「发给XX」前缀 = 单向送出的钱，明确归此
--        - 廖文钦 ¥104.50 那种带零头的，更可能是 AA 垫款，但无法从数据证实，
--          故统一归「人情往来」并在局限里说明「可能含少量 AA 垫款，未单独拆出」
--     ③ 单笔 < 1 元的转账（如 ¥0.10 附言对账）→ is_oneoff 标记为噪声，单独排除
--   为什么不再猜 AA/人情：数据里根本没有可靠特征能区分，硬猜会引入假精度。
--   「无法判断就诚实归一类并写进局限」，比编一个 60% 准确的规则更专业。
-- ============================================================
UPDATE bill_all SET transfer_kind = '资金搬运'
WHERE category = '转账红包' AND source = '工商银行';

-- 转账一律归「人情往来」（属于个人开销，计入消费）
UPDATE bill_all SET transfer_kind = '人情往来'
WHERE category = '转账红包' AND source <> '工商银行';

-- 单笔不足 1 元的转账是附言对账类噪声，单列标记
UPDATE bill_all SET transfer_kind = '零星对账'
WHERE category = '转账红包' AND amount < 1;

-- 兜底：任何还没分类的转账（不应发生，留个保险）
UPDATE bill_all SET transfer_kind = '人情往来'
WHERE category = '转账红包' AND transfer_kind IS NULL;

-- ============================================================
-- 工行退款回流（2026-11-14 业务方拍板：配对窗口 30 天）
--
-- 【为什么需要这一节】
--   三个源对「退款」的建模完全不同：
--     微信   —— 改写原记录状态（已全额退款），原行走不到「支出」分支，天然剔除
--     支付宝 —— 新增「退款成功」行 + 原行改成「交易关闭」，
--               白名单 status='交易成功' 挡在外面，也天然剔除
--     工行   —— 原扣款行原样保留，只追加一条正数流水。
--               没有任何机制把扣款行剔掉 → 扣的钱还留在支出里
--   这是三源建模差异，不是谁算错了。缺陷在合并层的口径。
--
-- 【本窗口的实测规模】
--   半年窗口内命中的 3 笔 ¥85.70（约占 L3 的 0.96%）。
--   两年版（账单合并总表_两年.sql）同一条规则命中的是 39 笔 ¥1,407.89。
--   → 这个缺陷一直在，只是窗口小的时候几乎看不见。
--
-- 【配对窗口 30 天的依据、以及为什么不能直接 EXISTS】
--   完整论证写在 `账单合并总表_两年.sql` 第四·五节（含 4 个金额冲突的实测明细）。
--   一句话：同额扣款与退款并非总是一对一，直接 EXISTS 会误剔真花掉的钱，
--   因此改为「按金额分区、取退款时间差最小的 N 笔，N = 该金额退款笔数」。
-- ============================================================
DROP TEMPORARY TABLE IF EXISTS tmp_g_refund_pair;
CREATE TEMPORARY TABLE tmp_g_refund_pair AS
SELECT b2.id,
       b2.amount,
       (SELECT MIN(DATEDIFF(r.trade_time, b2.trade_time))
          FROM bill_icbc r
         WHERE r.summary = '退款'
           AND r.amount_signed = b2.amount
           AND r.trade_time >= b2.trade_time
           AND DATEDIFF(r.trade_time, b2.trade_time) <= 30) AS min_diff
FROM bill_all b2
WHERE b2.source = '工商银行'
  AND b2.is_refund = 0
  AND b2.is_dup = 0;

UPDATE bill_all b
JOIN (
  SELECT id FROM (
    SELECT id, amount, min_diff,
           ROW_NUMBER() OVER (PARTITION BY amount ORDER BY min_diff, id) AS rn
    FROM tmp_g_refund_pair
    WHERE min_diff IS NOT NULL
  ) ranked
  WHERE ranked.rn <= (
          SELECT COUNT(*) FROM bill_icbc r2
           WHERE r2.summary = '退款' AND r2.amount_signed = ranked.amount
        )
) hit ON hit.id = b.id
SET b.is_refund = 1;

DROP TEMPORARY TABLE IF EXISTS tmp_g_refund_pair;

-- ============================================================
-- 校验：合并后总览
-- ============================================================
SELECT '=== 总览（含重复）===' AS '';
SELECT source AS 来源, COUNT(*) AS 笔数, ROUND(SUM(amount), 2) AS 合计
FROM bill_all GROUP BY source
UNION ALL
SELECT '合计', COUNT(*), ROUND(SUM(amount), 2) FROM bill_all;

SELECT '=== 去重后（v_bill，分析口径）===' AS '';
SELECT source AS 来源, COUNT(*) AS 笔数, ROUND(SUM(amount), 2) AS 合计
FROM v_bill GROUP BY source
UNION ALL
SELECT '合计', COUNT(*), ROUND(SUM(amount), 2) FROM v_bill;

SELECT '=== 转账细分（第 3 版：只区分「是不是我的开销」）===' AS '';
SELECT transfer_kind AS 细分, COUNT(*) AS 笔数, ROUND(SUM(amount), 2) AS 金额,
       ROUND(AVG(amount), 2) AS 均价,
       CASE WHEN transfer_kind = '人情往来' THEN '✅ 计入消费'
            WHEN transfer_kind = '零星对账' THEN '❌ 噪声，单列'
            ELSE '❌ 非开销' END AS 口径
FROM v_bill WHERE category = '转账红包'
GROUP BY transfer_kind ORDER BY 金额 DESC;

SELECT '=== 「人情往来」明细（这就是被误剔的那部分钱）===' AS '';
SELECT DATE(trade_time) AS 日期, counterparty AS 对方, amount AS 金额
FROM v_bill WHERE transfer_kind = '人情往来' ORDER BY amount DESC;

SELECT '=== 口径对比（三级）===' AS '';
SELECT '① 全部支出' AS 口径, COUNT(*) AS 笔数, ROUND(SUM(amount), 2) AS 金额,
       ROUND(SUM(amount) / 6, 2) AS 月均 FROM v_bill
UNION ALL
SELECT '② 剔除一次性大额',
       COUNT(*), ROUND(SUM(amount), 2), ROUND(SUM(amount) / 6, 2)
FROM v_bill WHERE is_oneoff = 0
UNION ALL
SELECT '③ 日常开销（v_spend）',
       COUNT(*), ROUND(SUM(amount), 2), ROUND(SUM(amount) / 6, 2)
FROM v_spend;

SELECT '=== 分类汇总（日常开销口径）===' AS '';
SELECT category AS 分类, COUNT(*) AS 笔数, ROUND(SUM(amount), 2) AS 金额,
       ROUND(SUM(amount) * 100 / (SELECT SUM(amount) FROM v_spend), 1) AS 占比
FROM v_spend
GROUP BY category
ORDER BY 金额 DESC;
