-- ============================================================
-- 账单分析查询 · 两年期版（2024-09-01 ~ 2026-08-31，3,789 条）
-- 对应表：bill2_all / v2_bill / v2_spend（与半年版 bill_* / v_* 并存）
-- 用法：mysql -u root -p --default-character-set=utf8mb4 < 本文件
-- 建立于 2026-11-14，由「吃透作品 #1」转入 v2 重跑时新增
-- ------------------------------------------------------------
-- 与半年版的差别（不是复制粘贴，三处必须改）：
--   ① 窗口 7 个月 → 24 个月，2024-09 是入学首月，不是残缺月（数据完整）
--   ② 工行流水多了「对方户名」列 → bill2_all.counterparty 对工行不再等于摘要，
--      「钱去哪了」第一次有答案
--   ③ 三年跨度的理财/银证转账 / 学费摘要损坏，旧口径在这批数据上会崩（见查询 12、13）
-- ============================================================

USE sqlpractice;

-- 口径提醒（与半年版一致的三条铁律）：
--   ① 全部支出 FROM v2_bill（已剔退款 + 跨源重复）
--   ② 日常开销 FROM v2_spend（转账看性质、非转账看金额 —— 分叉判，不是层层相减）
--   ③ 改口径只改 账单合并总表_两年.sql 里的视图，查询不重复写条件

-- ============================================================
-- 查询 1 · 月度支出趋势（24 个月）
--   练：GROUP BY + 日期函数
--   ⚠ 看这条不要只找极值：趋势查询的价值在**突变点**。
--     2024-09 是入学首月（买电脑/铺盖），不是"我乱花钱的月份"。
-- ============================================================
SELECT
  DATE_FORMAT(trade_time, '%Y-%m')    AS 月份,
  COUNT(*)                            AS 笔数,
  ROUND(SUM(amount), 2)               AS 支出合计,
  ROUND(SUM(amount) / COUNT(DISTINCT DATE(trade_time)), 2) AS 日均
FROM v2_spend
GROUP BY DATE_FORMAT(trade_time, '%Y-%m')
ORDER BY 月份;

-- ============================================================
-- 查询 2 · 消费分类排行
--   同一句「花得最多」，按金额和按笔数是两类答案（见 07 文档）
-- ============================================================
SELECT
  category                            AS 分类,
  COUNT(*)                            AS 笔数,
  ROUND(SUM(amount), 2)               AS 金额,
  ROUND(AVG(amount), 2)               AS 客单价,
  ROUND(SUM(amount) * 100.0 /
        (SELECT SUM(amount) FROM v2_spend), 1) AS 占比
FROM v2_spend
GROUP BY category
ORDER BY 金额 DESC;

-- ============================================================
-- 查询 3 · 时段画像（全品类）
--   ⚠ 标签用中性时段名，不用「早餐/午餐」——本查询没有 category 过滤，
--     统计对象是全部消费。半年版踩过这个坑（见 01_指标字典「名称不得暗示品类」）
-- ============================================================
SELECT
  CASE
    WHEN HOUR(trade_time) BETWEEN  5 AND  9 THEN '1_上午 05-10'
    WHEN HOUR(trade_time) BETWEEN 10 AND 14 THEN '2_午后 10-15'
    WHEN HOUR(trade_time) BETWEEN 15 AND 20 THEN '3_傍晚 15-21'
    ELSE '4_深夜 21-05'
  END                                 AS 时段,
  COUNT(*)                            AS 笔数,
  ROUND(SUM(amount), 2)               AS 金额,
  ROUND(AVG(amount), 2)               AS 客单价
FROM v2_spend
GROUP BY 时段
ORDER BY 时段;

-- ============================================================
-- 查询 4 · 逐小时分布（哪一小时最密 / 哪一小时最贵）
-- ============================================================
SELECT
  HOUR(trade_time)                    AS 小时,
  COUNT(*)                            AS 笔数,
  ROUND(SUM(amount), 2)               AS 金额,
  ROUND(AVG(amount), 2)               AS 客单价
FROM v2_spend
GROUP BY HOUR(trade_time)
ORDER BY 笔数 DESC
LIMIT 10;

-- ============================================================
-- 查询 5 · 花钱最多的 15 个商户 ← 【钱都去哪了】
-- ============================================================
SELECT
  counterparty                        AS 商户,
  COUNT(*)                            AS 笔数,
  ROUND(SUM(amount), 2)               AS 金额,
  ROUND(AVG(amount), 2)               AS 客单价
FROM v2_spend
GROUP BY counterparty
ORDER BY 金额 DESC
LIMIT 15;

-- ============================================================
-- 查询 6 · 平台对比
-- ============================================================
SELECT
  source                              AS 来源,
  COUNT(*)                            AS 笔数,
  ROUND(SUM(amount), 2)               AS 金额,
  ROUND(SUM(amount) * 100.0 / (SELECT SUM(amount) FROM v2_spend), 1) AS 占比
FROM v2_spend
GROUP BY source
ORDER BY 金额 DESC;

-- ============================================================
-- 查询 7 · 高频低额陷阱（拿铁因子）
-- ============================================================
SELECT
  counterparty                        AS 商户,
  COUNT(*)                            AS 笔数,
  ROUND(SUM(amount), 2)               AS 总金额,
  ROUND(AVG(amount), 2)               AS 客单价
FROM v2_spend
GROUP BY counterparty
HAVING COUNT(*) >= 15
ORDER BY 笔数 DESC;

-- ============================================================
-- 查询 8 · 工作日 vs 周末
-- ============================================================
SELECT
  CASE WHEN WEEKDAY(trade_time) < 5 THEN '工作日' ELSE '周末' END AS 时段,
  COUNT(*)                            AS 笔数,
  ROUND(SUM(amount), 2)               AS 金额,
  ROUND(SUM(amount) / COUNT(DISTINCT DATE(trade_time)), 2) AS 日均
FROM v2_spend
GROUP BY 时段;

-- ============================================================
-- 查询 9 · 三口径对账 + 恒等式自检 ← 【每次改口径都要跑这条】
--   L1 全部支出 = 一次性大额 + L2 高频小额
--   L3 日常开销 = L2 高频小额 + 人情往来      ← 分叉判，不是层层相减
--   2026-11-14 实测：2,485 = 181 + 2,304；2,406 = 2,304 + 102（口径已含工行退款回流）
-- ============================================================
SELECT 'L1 全部支出'        AS 口径, COUNT(*) AS 笔数, ROUND(SUM(amount),2) AS 金额 FROM v2_bill
UNION ALL SELECT '  ├ 一次性大额', COUNT(*), ROUND(SUM(amount),2) FROM bill2_all
           WHERE is_oneoff = 1 AND is_dup = 0 AND is_refund = 0
UNION ALL SELECT '  └ L2 高频小额', COUNT(*), ROUND(SUM(amount),2) FROM bill2_all
           WHERE is_oneoff = 0 AND is_dup = 0 AND is_refund = 0
UNION ALL SELECT 'L3 日常开销', COUNT(*), ROUND(SUM(amount),2) FROM v2_spend
UNION ALL SELECT '  ├ 其中人情往来', COUNT(*), ROUND(SUM(amount),2) FROM v2_spend WHERE category = '转账红包'
UNION ALL SELECT '  └ 其余（= L2）', COUNT(*), ROUND(SUM(amount),2) FROM v2_spend WHERE category <> '转账红包';

-- ============================================================
-- 查询 9b · 转账细分：哪些转账是我的开销？
--   资金搬运 = 卡间划转 / 理财 / 提现，钱换个口袋，不算开销
--   人情往来 = 红包 / 送礼 / 请客，钱真出去了 → 算消费
--   零星对账 = 单笔 < 1 元，噪声，单列
-- ============================================================
SELECT
  transfer_kind                       AS 转账细分,
  COUNT(*)                            AS 笔数,
  ROUND(SUM(amount), 2)               AS 金额,
  ROUND(AVG(amount), 2)               AS 均价,
  CASE WHEN transfer_kind = '人情往来' THEN '✅ 计入消费'
       WHEN transfer_kind = '零星对账' THEN '❌ 噪声，单列'
       ELSE '❌ 非开销' END            AS 口径
FROM v2_bill
WHERE category = '转账红包'
GROUP BY transfer_kind
ORDER BY 金额 DESC;

-- ============================================================
-- 查询 9c · 人情往来单独看
-- ============================================================
SELECT
  counterparty                        AS 对方,
  COUNT(*)                            AS 笔数,
  ROUND(SUM(amount), 2)               AS 金额
FROM v2_spend
WHERE category = '转账红包'
GROUP BY counterparty
ORDER BY 金额 DESC
LIMIT 20;

-- ============================================================
-- 查询 10 · 学习成长投入 ← 【最该改的那条】
-- ============================================================
SELECT
  source AS 来源, counterparty AS 对方, goods AS 商品,
  amount AS 金额, trade_time AS 时间
FROM v2_spend
WHERE category = '学习成长'
ORDER BY trade_time;

-- ============================================================
-- 查询 11 · 跨源去重压力测试 ← 【自己揭自己的短】
--   半年版：18 笔支付宝走工行，60 秒抓 17 笔（后来查清：第 18 笔是退款，应剔的是 17 笔且全中）
--   两年版（2026-11-14 实测）：支付宝侧记「工商银行」的**支出 47 笔**，
--     60 秒抓到 43 笔（91.5%）；
--     漏 4 笔 = 3 笔延迟 81/114/179 秒（容差问题，调阈值能救）
--            + 1 笔工行侧无同额扣款（可见性问题，调什么都没用）
--   这个二分法就是本组查询的全部价值：**"漏了"不是一个问题，是两个。**
-- ============================================================

-- 11a. 三源时间精度
SELECT
  source AS 来源, COUNT(*) AS 笔数,
  MIN(trade_time) AS 最早, MAX(trade_time) AS 最晚,
  SUM(CASE WHEN SECOND(trade_time) = 0 THEN 1 ELSE 0 END) AS 秒位为0
FROM bill2_all GROUP BY source;

-- 11b. 同秒同额碰撞：来源数=2 是真重复，来源数=1 是同源巧合（会误伤）
SELECT 秒, 金额, 笔数, 来源数, 来源 FROM (
  SELECT DATE_FORMAT(trade_time,'%Y-%m-%d %H:%i:%s') AS 秒, amount AS 金额,
         COUNT(*) AS 笔数, COUNT(DISTINCT source) AS 来源数,
         GROUP_CONCAT(source) AS 来源
  FROM bill2_all GROUP BY 1, 2 HAVING COUNT(*) >= 2
) g ORDER BY 笔数 DESC;

-- 11c. 支付宝走工行卡的笔数（应被去重，实际抓到几笔）
--   ⚠ 必须加 in_out='支出'：不加会数成 54 笔，多出来的 7 笔是「退款成功/不计收支」
--     —— 半年版就在这里把退款当成了支出，导致分母错了一整年（见 04 AC-11 订正段）
SELECT COUNT(*) AS 支付宝走工行的支出笔数, ROUND(SUM(amount), 2) AS 金额
FROM bill2_alipay WHERE pay_method LIKE '%工商银行%' AND in_out = '支出';

-- 11d. ★ 逐笔秒差：把「漏」拆成两种
--   秒差 = NULL  → 支付宝账单里根本没有同额记录 → 数据可见性问题，调阈值没用
--   秒差 > 60    → 有记录但落账慢 → 容差问题，调阈值可救
SELECT
  a.trade_time AS 支付宝时间, a.amount AS 金额, a.counterparty AS 对方,
  i.trade_time AS 工行时间,
  TIMESTAMPDIFF(SECOND, a.trade_time, i.trade_time) AS 秒差,
  CASE
    WHEN ABS(TIMESTAMPDIFF(SECOND, a.trade_time, i.trade_time)) <= 60  THEN '✅ 60秒内抓到'
    WHEN ABS(TIMESTAMPDIFF(SECOND, a.trade_time, i.trade_time)) <= 300 THEN '⚠ 60~300秒：容差不足'
    ELSE '⚠ 超300秒'
  END AS 判定
FROM bill2_alipay a
LEFT JOIN bill2_icbc i
  ON ABS(a.amount) = ABS(i.amount_signed) AND i.amount_signed < 0
 AND ABS(TIMESTAMPDIFF(SECOND, a.trade_time, i.trade_time)) <= 300
WHERE a.pay_method LIKE '%工商银行%' AND a.in_out = '支出'
ORDER BY a.trade_time;

-- 11e. 反例：「零钱提现」两边都有记录，但不是重复
--   ① 微信侧 in_out='/' 从未进支出 ② 工行侧是正数进账 ③ 差额=0.1% 手续费
SELECT w.trade_time AS 微信时间, w.amount AS 微信记的, i.amount_signed AS 工行记的,
       ROUND(w.amount - i.amount_signed, 2) AS 差额_手续费
FROM bill2_wechat w
JOIN bill2_icbc i
  ON ABS(w.amount - i.amount_signed) <= 1
 AND ABS(TIMESTAMPDIFF(SECOND, w.trade_time, i.trade_time)) <= 5
WHERE w.trade_type = '零钱提现'
ORDER BY w.trade_time;

-- 11f. 工行消费：有源可匹配吗？（放宽到 1 天仍找不到 = 可见性问题）
SELECT
  COUNT(*) AS 工行消费总数,
  SUM(CASE WHEN EXISTS(SELECT 1 FROM bill2_alipay a
        WHERE ABS(a.amount)=ABS(i.amount_signed)
          AND ABS(TIMESTAMPDIFF(SECOND,a.trade_time,i.trade_time))<=60)
      THEN 1 ELSE 0 END) AS 支付宝60秒内,
  SUM(CASE WHEN EXISTS(SELECT 1 FROM bill2_wechat w
        WHERE ABS(w.amount)=ABS(i.amount_signed) AND w.in_out='支出'
          AND ABS(TIMESTAMPDIFF(SECOND,w.trade_time,i.trade_time))<=60)
      THEN 1 ELSE 0 END) AS 微信60秒内,
  SUM(CASE WHEN EXISTS(SELECT 1 FROM bill2_alipay a
        WHERE ABS(a.amount)=ABS(i.amount_signed)
          AND ABS(TIMESTAMPDIFF(SECOND,a.trade_time,i.trade_time))<=86400)
       OR  EXISTS(SELECT 1 FROM bill2_wechat w
        WHERE ABS(w.amount)=ABS(i.amount_signed) AND w.in_out='支出'
          AND ABS(TIMESTAMPDIFF(SECOND,w.trade_time,i.trade_time))<=86400)
      THEN 0 ELSE 1 END) AS 放宽到1天也找不到
FROM bill2_icbc i WHERE i.summary = '消费' AND i.amount_signed < 0;

-- 11g. 各源按月覆盖（区分「未发生」与「没拿到」）
SELECT DATE_FORMAT(trade_time,'%Y-%m') AS 月份,
       SUM(source='微信') AS 微信, SUM(source='支付宝') AS 支付宝, SUM(source='工商银行') AS 工行,
       COUNT(*) AS 合计
FROM bill2_all GROUP BY 1 ORDER BY 1;

-- ============================================================
-- 查询 12 · 工行摘要白名单校验 ← 【防静默兜底】
--   期望 0 行。出现任何一行 = 银行换了措辞，映射已失效。
--   两年数据实测：**不是 0 行。** 多出一个摘要 = '1'（¥5,550，学费），
--   摘要列解析损坏，只剩一个数字。靠「对方户名：山西财经大学代扣学费专户」
--   才认回来 —— 这就是白名单校验存在的意义：它当场报警了。
-- ============================================================
SELECT summary AS 白名单外的新摘要, COUNT(*) AS 笔数,
       ROUND(SUM(ABS(amount_signed)),2) AS 金额,
       GROUP_CONCAT(DISTINCT counterparty SEPARATOR ' | ') AS 对方户名
FROM bill2_icbc
WHERE amount_signed < 0
  AND summary NOT IN ('缴费','转账','退款','消费','还款')
GROUP BY summary;

-- ============================================================
-- 查询 13 · 一次性大额漏标校验 ← 【is_oneoff 超载在两年数据上的实证】
--   半年窗口里最贵的一笔电商是 ¥1,120（已退款），所以「电商购物不算一次性」
--   这条错规则**没被暴露**。两年窗口里有：
--     2025-06-26 拼多多 ¥6,000 / 2024-09-20 京东 ¥4,774 / 2024-09-14 拼多多 ¥1,036
--   三笔全部 is_oneoff=0，全部混在「日常开销」里 → L3 虚高约 22%
--   本查询把「单笔 ≥ ¥500 却仍留在 L3」的挑出来，让人一眼看到规则失效。
-- ============================================================
SELECT trade_time AS 时间, source AS 源, category AS 分类,
       counterparty AS 对方, amount AS 金额, is_oneoff AS 一次性标记
FROM v2_spend
WHERE amount >= 500
ORDER BY amount DESC;

-- ============================================================
-- 查询 14 · 支付宝「交易关闭」自证 ← 【剔得对不对，用退款金额验】
--   支付宝 7 笔「交易关闭」合计 ¥818.22，7 笔「退款成功」也恰好 ¥818.22。
--   两边相等 → 交易关闭 = 钱已退，剔掉是对的。
--   这条的作用：让「为什么剔」变成可验证的等式，而不是我的说法。
-- ============================================================
SELECT status AS 状态, in_out AS 收支, COUNT(*) AS 笔数, ROUND(SUM(amount),2) AS 金额
FROM bill2_alipay
GROUP BY status, in_out
ORDER BY status, in_out;

-- ============================================================
-- 查询 15 · 工行无源消费按「对方户名」归类 ← 【钱去哪了，第一次有答案】
--   半年版只能写「抖音等 App 内消费，平台无导出入口」，因为旧 PDF 没有户名列。
--   两年版有户名：163 笔无源消费里，拼多多系 90 笔（56+34）占一半以上。
--   → 旧的「抖音」归因是错的，且是**在没有证据时凭印象写的**（见 05 文档）。
-- ============================================================
SELECT counterparty AS 对方户名, COUNT(*) AS 笔数, ROUND(SUM(amount),2) AS 金额
FROM bill2_all
WHERE source = '工商银行' AND summary = '消费' AND is_dup = 0
GROUP BY counterparty
ORDER BY 金额 DESC
LIMIT 20;

-- ============================================================
-- 查询 16 · ¥29.01 跨窗口闭环 ← 【同一笔钱，两个窗口看到两个故事】
--   半年窗口（2026-03-29 起）看到的：2026-06-06 支付宝「退款成功」↔ 工行「退款」
--                                    → 这不是支出，所以 AC-11 的「剩 1 笔漏判」是误报
--   两年窗口看到的：2026-03-07 15:51:51 支付宝「交易关闭」↔ 15:54:50 工行「消费」
--                  → 相隔 179 秒，**真的是容差漏判**，只是扣款发生在半年窗口之前
--   用例：回答「你的窗口选择有没有改变结论」——有，而且是相反方向的两次。
-- ============================================================
SELECT '支付宝' AS 源, trade_time AS 时间, amount AS 金额, status AS 状态,
       goods AS 商品_or_摘要, in_out AS 收支
FROM bill2_alipay WHERE amount = 29.01
UNION ALL
SELECT '工行', trade_time, amount_signed, summary, counterparty, ''
FROM bill2_icbc WHERE ABS(amount_signed) = 29.01
ORDER BY 时间;

-- ============================================================
-- 查询 17 · 工行「已退款但没被剔」← 【2026-11-14 新发现的真缺陷】
--   机制：微信退款是**改写原记录状态**（已全额退款）→ is_refund 能标；
--         支付宝退款是**新增一行退款记录**，原行变「交易关闭」→ 白名单能挡；
--         工行退款是**新增一笔 +金额 流水**，原扣款行 **原样留着**，没有任何字段
--         表明它后来被退了 —— 于是它一路留在 L1 / L2 / L3 里，被当成真花出去的钱。
--   实测：51 笔 ¥1,550.79（占原 L3 的 2.92%）；其中 39 笔 ¥1,407.89 已按 30 天窗口配对剔除，
--   剩 10 笔 ¥107.01（间隔 30 天以上，疑似同额不同单）记为未解释差异。
--   为什么半年版没暴露：半年窗口只有 4 笔工行退款 ¥101.57，其中 3 笔 ¥85.70
--   同样没被剔（占半年 L3 的 0.96%）—— 缺陷一直存在，只是窗口小的时候看不出来。
--   ⚠ 本查询**只诊断不改数**：配对规则（同额 + 后发生 + 多久内算同一笔）是业务定义，
--     须业务方拍板后才能写进视图。改之前先看这条查询有几笔。
-- ============================================================
SELECT b.trade_time AS 扣款时间, b.amount AS 金额, b.category AS 分类,
       b.counterparty AS 户名,
       (SELECT MIN(r.trade_time) FROM bill2_icbc r
         WHERE r.summary = '退款' AND r.amount_signed = b.amount
           AND r.trade_time >= b.trade_time) AS 退款时间
FROM bill2_all b
WHERE b.source = '工商银行' AND b.is_refund = 0 AND b.is_dup = 0 AND b.is_oneoff = 0
  AND EXISTS (SELECT 1 FROM bill2_icbc r
               WHERE r.summary = '退款' AND r.amount_signed = b.amount
                 AND r.trade_time >= b.trade_time)
ORDER BY b.amount DESC;

-- ============================================================
-- 查询 18 · 判重依赖「已过滤的表」→ 5 笔漏标 ← 【顺序依赖的坑】
--   账单合并总表里，工行侧的判重写的是 EXISTS (SELECT 1 FROM bill2_all ...)，
--   而 bill2_all 自己已经把支付宝「交易关闭」的行剔掉了。
--   于是：工行扣了钱 → 支付宝同额记录存在但是「交易关闭」→ 判重看不见 → 不标重。
--   实测 5 笔 ¥90.21。
--   结果**恰好不错**（那 5 笔支付宝侧被剔了，只剩工行这一份），但原因是错的：
--   靠的是「另一条规则顺手挡住」，不是「判重判对了」—— 与 ¥29.01 同一个毛病。
--   教训：判重必须查**原始表**，不能查已经过滤过的表。
--   （本查询列出这 5 笔，改不改视图同样待业务方拍板）
-- ============================================================
SELECT i.trade_time AS 工行时间, ROUND(ABS(i.amount_signed),2) AS 金额,
       i.counterparty AS 工行户名,
       (SELECT CONCAT(a.trade_time, ' [', a.status, '] ', a.counterparty)
          FROM bill2_alipay a
         WHERE ABS(a.amount) = ABS(i.amount_signed)
           AND ABS(TIMESTAMPDIFF(SECOND, a.trade_time, i.trade_time)) <= 60
         LIMIT 1) AS 支付宝同额记录
FROM bill2_icbc i
WHERE i.amount_signed < 0
  AND EXISTS (SELECT 1 FROM bill2_alipay a
               WHERE ABS(a.amount) = ABS(i.amount_signed)
                 AND ABS(TIMESTAMPDIFF(SECOND, a.trade_time, i.trade_time)) <= 60)
  AND NOT EXISTS (SELECT 1 FROM bill2_all b
                   WHERE b.source = '工商银行' AND b.is_dup = 1
                     AND b.trade_time = i.trade_time
                     AND b.amount = ABS(i.amount_signed))
ORDER BY i.trade_time;
