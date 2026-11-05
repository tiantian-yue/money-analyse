-- ============================================================
-- 账单分析查询（sqlpractice.v_bill —— 已去重去退款的分析视图）
-- 用法：双击 F:\allstudy\SQL练习.cmd 进库后，逐段复制执行
--      或：mysql -u root --default-character-set=utf8mb4 < 本文件
-- ============================================================

USE sqlpractice;

-- 口径提醒（三条铁律）：
--   ① 所有查询一律 FROM v_bill —— 该视图已自动剔除退款(is_refund=1)
--      和跨源重复(is_dup=1)，不要再手写这些条件
--   ② 「真实消费」一律 FROM v_spend —— 该视图在 v_bill 上再排除
--      一次性大额(is_oneoff=1) 和 资金搬运类转账（卡间划转）
--      ⚠ 注意：人情往来（红包/送礼/请客）**算消费**，不要剔
--   ③ 视图定义在「账单建表.sql」里，改口径只改一处

-- ============================================================
-- 查询 1 · 月度支出趋势
--   练：GROUP BY + SUM + COUNT + 日期函数
-- ============================================================
SELECT
  DATE_FORMAT(trade_time, '%Y-%m')    AS 月份,
  COUNT(*)                            AS 笔数,
  ROUND(SUM(amount), 2)               AS 支出合计,
  ROUND(SUM(amount) / COUNT(DISTINCT DATE(trade_time)), 2) AS 日均
FROM v_spend
GROUP BY DATE_FORMAT(trade_time, '%Y-%m')
ORDER BY 月份;

-- ============================================================
-- 查询 2 · 消费分类排行（真实日常消费口径）
--   练：CASE WHEN 分类 + 占比子查询
-- ============================================================
SELECT
  category                          AS 分类,
  COUNT(*)                          AS 笔数,
  ROUND(SUM(amount), 2)             AS 金额,
  ROUND(AVG(amount), 2)             AS 客单价,
  ROUND(SUM(amount) * 100.0 /
        (SELECT SUM(amount) FROM v_spend), 1) AS 占比
FROM v_spend
GROUP BY category
ORDER BY 金额 DESC;

-- ============================================================
-- 查询 3 · 消费时段画像 ← 【题目里的核心问题】
--   练：CASE WHEN 把小时切成餐别
-- ============================================================
SELECT
  CASE
    WHEN HOUR(trade_time) BETWEEN  5 AND  9 THEN '1_早餐 05-10'
    WHEN HOUR(trade_time) BETWEEN 10 AND 14 THEN '2_午餐 10-15'
    WHEN HOUR(trade_time) BETWEEN 15 AND 20 THEN '3_晚餐 15-21'
    ELSE '4_夜宵 21-05'
  END                               AS 时段,
  COUNT(*)                          AS 笔数,
  ROUND(SUM(amount), 2)             AS 金额,
  ROUND(AVG(amount), 2)             AS 客单价
FROM v_spend
GROUP BY 时段
ORDER BY 时段;

-- ============================================================
-- 查询 4 · 逐小时消费分布（找出最密集的一小时）
-- ============================================================
SELECT
  HOUR(trade_time)                  AS 小时,
  COUNT(*)                          AS 笔数,
  ROUND(SUM(amount), 2)             AS 金额
FROM v_spend
GROUP BY HOUR(trade_time)
ORDER BY 笔数 DESC
LIMIT 8;

-- ============================================================
-- 查询 5 · 花钱最多的 10 个商户 ← 【回答「我的钱都去哪了」】
-- ============================================================
SELECT
  counterparty                      AS 商户,
  COUNT(*)                          AS 笔数,
  ROUND(SUM(amount), 2)             AS 金额,
  ROUND(AVG(amount), 2)             AS 客单价
FROM v_spend
GROUP BY counterparty
ORDER BY 金额 DESC
LIMIT 10;

-- ============================================================
-- 查询 6 · 平台对比：微信 vs 支付宝 vs 银行卡
-- ============================================================
SELECT
  source                            AS 来源,
  COUNT(*)                          AS 笔数,
  ROUND(SUM(amount), 2)             AS 金额,
  ROUND(SUM(amount) * 100.0 / (SELECT SUM(amount) FROM v_spend), 1) AS 占比
FROM v_spend
GROUP BY source
ORDER BY 金额 DESC;

-- ============================================================
-- 查询 7 · 高频低额陷阱 ← 【拼多多那类】
--   思路：笔数多、客单价低的商户就是「拿铁因子」
-- ============================================================
SELECT
  counterparty                      AS 商户,
  COUNT(*)                          AS 笔数,
  ROUND(SUM(amount), 2)             AS 总金额,
  ROUND(AVG(amount), 2)             AS 客单价
FROM v_spend
GROUP BY counterparty
HAVING COUNT(*) >= 10
ORDER BY 笔数 DESC;

-- ============================================================
-- 查询 8 · 工作日 vs 周末
--   练：DAYOFWEEK / WEEKDAY
-- ============================================================
SELECT
  CASE WHEN WEEKDAY(trade_time) < 5 THEN '工作日' ELSE '周末' END AS 时段,
  COUNT(*)                          AS 笔数,
  ROUND(SUM(amount), 2)             AS 金额,
  ROUND(SUM(amount) / COUNT(DISTINCT DATE(trade_time)), 2) AS 日均
FROM v_spend
GROUP BY 时段;

-- ============================================================
-- 查询 9 · 一次性大额 vs 日常（口径对账）
-- ============================================================
SELECT
  CASE is_oneoff WHEN 1 THEN '一次性大额' ELSE '日常消费' END AS 口径,
  COUNT(*)                          AS 笔数,
  ROUND(SUM(amount), 2)             AS 金额,
  ROUND(SUM(amount) * 100.0 / (SELECT SUM(amount) FROM v_bill), 1) AS 占比
FROM v_bill
GROUP BY 口径;

-- ============================================================
-- 查询 9b · 转账细分：哪些转账是我的开销？← 【口径改过 3 版的坑】
--   资金搬运 = 卡间划转 / 提现，钱换个口袋，不算开销
--   人情往来 = 红包 / 送礼 / 请客，钱真出去了 → **算消费**
--   零星对账 = 单笔 < 1 元（如 0.10 元附言对账），噪声，单列
--   ⚠ 我犯过的错：曾用「金额带不带零头」猜 AA 分账，还把人情往来整个剔掉。
--     前者站不住（朋友之间凑整转也很常见），后者是把「消费」和「支出」
--     混为一谈（请客吃饭就是消费）。现在只区分「钱有没有真的离开我」。
-- ============================================================
SELECT
  transfer_kind                     AS 转账细分,
  COUNT(*)                          AS 笔数,
  ROUND(SUM(amount), 2)             AS 金额,
  ROUND(AVG(amount), 2)             AS 均价,
  CASE WHEN transfer_kind = '人情往来' THEN '✅ 计入消费'
       WHEN transfer_kind = '零星对账' THEN '❌ 噪声，单列'
       ELSE '❌ 非开销' END          AS 口径
FROM v_bill
WHERE category = '转账红包'
GROUP BY transfer_kind
ORDER BY 金额 DESC;

-- ============================================================
-- 查询 9c · 人情往来单独看（被误剔过的那 19 笔）
--   这个分类值得单独立一条，因为它既是消费、又跟「嘴上的开销」不同，
--   复盘时可以拿它看「我在人际上花了多少」
-- ============================================================
SELECT
  counterparty                      AS 对方,
  COUNT(*)                          AS 笔数,
  ROUND(SUM(amount), 2)             AS 金额
FROM v_spend
WHERE category = '转账红包'
GROUP BY counterparty
ORDER BY 金额 DESC;

-- ============================================================
-- 查询 10 · 学习成长投入 ← 【最该改的那条】
-- ============================================================
SELECT
  source AS 来源, counterparty AS 对方, goods AS 商品, amount AS 金额, trade_time AS 时间
FROM v_spend
WHERE category = '学习成长'
ORDER BY trade_time;

-- ============================================================
-- 查询 11 · 去重判据压力测试 ← 【自己揭自己的短】
--   为什么要有这条：我的跨源去重规则写的是「trade_time 完全相等」。
--   这条查询专门用来检验它到底抓没抓全、有没有误伤。
--   结论写在下面 —— 结果对我不利，但必须留着。
-- ============================================================

-- 11a. 三源时间精度核对（时间字段是秒级还是只到分？）
SELECT
  source AS 来源, COUNT(*) AS 笔数,
  MIN(trade_time) AS 最早, MAX(trade_time) AS 最晚,
  SUM(CASE WHEN SECOND(trade_time) = 0 THEN 1 ELSE 0 END) AS 秒位为0的笔数
FROM bill_all GROUP BY source;

-- 11b. 同秒同额碰撞清单：看「同来源巧合」有没有出现
--   · 来源数 = 2 → 跨源，真重复，剔得对
--   · 来源数 = 1 → 同源同秒同额，是巧合，我的规则会误伤
SELECT 秒, 金额, 笔数, 来源数, 来源
FROM (
  SELECT DATE_FORMAT(trade_time,'%Y-%m-%d %H:%i:%s') AS 秒, amount AS 金额,
         COUNT(*) AS 笔数, COUNT(DISTINCT source) AS 来源数,
         GROUP_CONCAT(source) AS 来源
  FROM bill_all GROUP BY 1, 2 HAVING COUNT(*) >= 2
) g ORDER BY 笔数 DESC;

-- 11c. ★ 关键：支付宝走工行卡的笔数（应被去重，实际抓到了几笔？）
--   实测 18 笔 / ¥142.43 —— 但 is_dup 只命中 4 笔 → 漏判 14 笔
SELECT COUNT(*) AS 支付宝走工行的笔数, ROUND(SUM(amount), 2) AS 金额
FROM bill_alipay WHERE pay_method LIKE '%工商银行%';

-- 11d. ★ 漏判证据：同金额 + 时间差 ≤ 60 秒的配对
--   秒差列直接暴露问题：0 秒的抓到了，1~16 秒的全漏了
SELECT
  a.trade_time AS 支付宝时间, a.amount AS 金额, a.counterparty AS 对方,
  i.trade_time AS 工行时间,
  TIMESTAMPDIFF(SECOND, a.trade_time, i.trade_time) AS 秒差
FROM bill_alipay a
JOIN bill_icbc i
  ON ABS(a.amount) = ABS(i.amount_signed)
 AND ABS(TIMESTAMPDIFF(SECOND, a.trade_time, i.trade_time)) <= 60
ORDER BY a.trade_time;

-- 11e. ★ 反例：「零钱提现」看起来是重复，其实不是
--   微信侧 12 笔「零钱提现」↔ 工行侧 11 笔「微信零钱提现」，两边都有。
--   但它绝不能剔，三条理由：
--     ① 微信侧 in_out = '/'，从未进过支出统计
--     ② 工行侧金额是**正数**（进账），不是支出
--     ③ 两边金额差 0.1% 提现手续费（微信 ¥200.20 / 工行到账 ¥200.00）
--   → 它是「资金搬运」，不是「重复记账」。
--   注意窗口取 5 秒而非 60 秒：提现是两笔相邻的独立操作（09:20:08 和 09:20:20），
--   窗口放大会造成交叉配对，反而制造出假的「4 条记录」。
SELECT w.trade_time AS 微信时间, w.amount AS 微信记的, i.amount_signed AS 工行记的,
       ROUND(w.amount - i.amount_signed, 2) AS 差额_手续费
FROM bill_wechat w
JOIN bill_icbc i
  ON ABS(w.amount - i.amount_signed) <= 1
 AND ABS(TIMESTAMPDIFF(SECOND, w.trade_time, i.trade_time)) <= 5
WHERE w.trade_type = '零钱提现'
ORDER BY w.trade_time;

-- 11f. ★ 更根本的问题：数据可见性 —— 有源可匹配吗？
--   工行「消费 快捷支付」39 笔，到底有多少能在微信/支付宝找到来源？
--   找不到的 22 笔经核实是【抖音等 App 内消费】—— 平台不提供账单导出，
--   所以不是"我漏判了"，是"这份数据根本不存在于任何可导出的账单里"。
--   ⚠ 关键区分：还有一种"0 条"是【本期根本没用该渠道】（如支付宝 2026-08），
--     它和"真缺失"在表里长得一模一样 —— SQL 无法分辨，只能靠业务方确认。
SELECT
  COUNT(*) AS 工行消费总数,
  SUM(CASE WHEN EXISTS(SELECT 1 FROM bill_alipay a
        WHERE ABS(a.amount)=ABS(i.amount_signed)
          AND ABS(TIMESTAMPDIFF(SECOND,a.trade_time,i.trade_time))<=60)
      THEN 1 ELSE 0 END) AS 能在支付宝找到,
  SUM(CASE WHEN EXISTS(SELECT 1 FROM bill_wechat w
        WHERE ABS(w.amount)=ABS(i.amount_signed)
          AND ABS(TIMESTAMPDIFF(SECOND,w.trade_time,i.trade_time))<=60
          AND w.in_out='支出')
      THEN 1 ELSE 0 END) AS 能在微信找到,
  COUNT(*) - SUM(CASE WHEN EXISTS(SELECT 1 FROM bill_alipay a
        WHERE ABS(a.amount)=ABS(i.amount_signed)
          AND ABS(TIMESTAMPDIFF(SECOND,a.trade_time,i.trade_time))<=86400)
      THEN 1 ELSE 0 END) AS 放宽到1天也找不到
FROM bill_icbc i WHERE i.summary = '消费';

-- 11g. ★ 区分「未发生」与「没拿到」：按月看各源的覆盖
--   「0 笔」有两种可能：①本期没用该渠道（不是缺失）②数据没导出（真缺失）。
--   看这张表 + 回忆「那个月我到底用没用」，才能区分。系统自己分辨不了。
SELECT DATE_FORMAT(trade_time,'%Y-%m') AS 月份,
       SUM(source='微信') AS 微信, SUM(source='支付宝') AS 支付宝, SUM(source='工商银行') AS 工行,
       COUNT(*) AS 合计
FROM bill_all GROUP BY 1 ORDER BY 1;

-- ------------------------------------------------------------
-- 【压力测试结论 · 2026-10-06 实测】
--   ① 时间精度：三源均为秒级，无「只到分」问题（秒位为0的最多 11 笔，属正常整点）
--   ② 误伤风险：现有数据中「同源同秒同额」巧合 = 0 笔 → 实际未误伤
--   ③ 真正失效：漏判。支付宝走工行卡 18 笔，is_dup 仅命中 4 笔，漏 14 笔 ¥71.94
--      原因：第三方渠道落账存在 0~16 秒延迟，我用「完全相等」判据太严
--   ④ 本质：这不是技术 bug，是**需求定义错误** ——
--      「同一笔交易在不同渠道落账时间允许延迟」是业务事实，我没先问就走了一步
--   ⑤ 待业务方拍板：阈值放宽到 60 秒可抓全 18 笔，但误伤风险随之上升。
--      放宽到多少、误判谁负责 —— 这是业务规则，不该由写 SQL 的人自己定。
-- ------------------------------------------------------------

-- ------------------------------------------------------------
-- 【修正 + 追加结论 · 2026-10-06 二次核对】
--   ⑥ 机制勘误：重复记账的主力是**支付宝快捷支付 17 笔**，
--      不是原先写的「微信扫码」。微信侧只有 2 笔（¥20 + ¥5,500）。
--      → 文档里的"机制"和百分比一样，不是当下实测的就该被怀疑。
--   ⑦ 数字勘误：不去重虚高 **24.3%**（¥23,160.58 → ¥28,794.00），
--      不是此前沿用的 48%。原因见 01_指标字典.md §4。
--   ⑧ 新增反例（11e）：零钱提现两边都有记录，但**不是重复**。
--      判重必须看语义（是否同一笔支出算两次），不能看形态（是否两边都有）。
--   ⑨ 新增边界（11f/11g）：工行消费 39 笔里 **22 笔找不到任何来源**，
--      容差放宽到 1 天新增匹配 0 笔。
--      → 闸门的能力上限是**数据可见性**，不是阈值。
--      → 这是「放量到 100 人会先崩哪一步」的真正答案。
-- ------------------------------------------------------------

-- ------------------------------------------------------------
-- 【三次核对结论 · 2026-10-07（经业务方本人核实）】
--   ⑩ **我上一版判断错了。** 我把「表里对不上」直接当成「数据缺失」，
--      但核实后发现是两种完全不同的情况：
--        · 支付宝 2026-08 = 0 笔 —— 不是缺失，是**当月根本没用支付宝**
--          （当月微信 87 笔、工行 3 笔，行为分布真实）
--        · 工行那 22 笔无源     —— 是**抖音等 App 内消费，平台无导出入口**
--          （原始记录只有 `消费/快捷支付`，无商户无商品）
--   ⑪ 真正的规格缺陷：**「未发生」与「没拿到」在数据里无法区分** ——
--      两者都是「0 条 / 无匹配」。要分辨，只能引入数据之外的知识
--      （业务方回忆、渠道可用性登记）。**这是需求规格的活，不是 SQL 的活。**
--   ⑫ 结构性事实：**银行流水是唯一「全量」视角，却是信息最贫瘠的视角** ——
--      能证明「钱少了」，不能证明「钱花在哪」。
--      完整分析见 04_需求规格说明书.md §12「数据可见性边界」。
-- ------------------------------------------------------------

-- ============================================================
-- 查询 12 · 工行摘要白名单校验 ← 【防「静默兜底」，2026-11-05 新增】
-- ============================================================
-- 背景：工行的 category 全靠摘要词映射（见 账单合并总表.sql 工行段）：
--     摘要 IN ('缴费','转账','退款','消费','还款') → 各自归类，ELSE '其他支出'
--   其中「转账红包 → 资金搬运」这一链挂着 14 笔 ¥2,708.00，
--   占真实消费 ¥8,920.49 的 **30.4%** —— 比跨源去重虚高（24.3%）还大。
-- 风险：银行哪天换了措辞（如「转账」改叫「网银转出」），该笔会掉进
--   ELSE '其他支出'，category 不再是「转账红包」，transfer_kind 为空，
--   于是一路流进 L3 真实消费 —— **不报错、不告警，数字只是悄悄变大**。
-- 本查询的作用：把「我不知道它会怎么坏」变成「它一坏我就知道」。
--   期望结果：0 行。出现任何一行 = 出现了白名单外的新措辞，
--   说明映射规则已失效，须人工确认后把新词补进 账单合并总表.sql。
-- （2026-11-05 追加：吃透作品中追问「摘要不叫转账会怎样」引出本校验）
-- ------------------------------------------------------------
SELECT summary AS 白名单外的新摘要, COUNT(*) AS 笔数, ROUND(SUM(ABS(amount_signed)),2) AS 金额
FROM bill_icbc
WHERE amount_signed < 0
  AND summary NOT IN ('缴费','转账','退款','消费','还款')
GROUP BY summary;
