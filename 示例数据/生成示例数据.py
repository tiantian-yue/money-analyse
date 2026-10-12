# -*- coding: utf-8 -*-
"""生成「示例数据」—— 完全虚构的账单样本，用来演示导入脚本。

为什么要有这个脚本
------------------
作品集需要发布可运行的示例数据，但真实账单含个人消费明细（日期、时间精确到秒、
金额、余额链），一旦上传就无法撤回。所以示例数据必须**完全虚构**，
而且要能证明它是虚构的 —— 这个脚本就是那份证明：
固定随机种子，任何人重跑都能得到同一份内容。

⚠ 历史教训（2026-10-12）
    上一版示例数据是「拿真实账单改的」：把商户名替换成"示例XX"，
    但日期、时间、金额、余额链原样保留。
    实测与真实账单的重合率：工行 94%、支付宝 55%。
    换个商户名不等于脱敏 —— 时间+金额的组合本身就能定位到具体交易。

生成的文件
----------
    微信支付账单_示例.csv      67 行，11 列，UTF-8 BOM
    支付宝交易明细_示例.csv    20 行，13 列（末列空），UTF-8 BOM
    工商银行历史明细_示例.csv  ~47 行，11 列，UTF-8 BOM

数据是按「真实机理」成对造的，不是各自独立随机
----------------------------------------------
    支付宝/微信用工行卡付款时，同一笔交易在渠道侧和银行侧各留一条记录，
    银行侧落账晚 5~20 秒 —— 这正是项目里 `is_dup` 跨源去重要处理的镜像重复。
    另外还造了若干「微信零钱提现」（银行侧正数进账），用于验证
    「长得像重复但绝不能剔」这个反例。
    这样示例数据才能跑出去重、退款、一次性大额、转账细分等全部判定。

刻意保留的真实格式缺陷
----------------------
  1. 三份文件都是 UTF-8 BOM —— 导入脚本若不处理 BOM，第一列名会带隐形字符
  2. 支付宝的列比表头多一个（末尾空列）
  3. 工行的日期有「日期与时间粘连」的写法（2026-03-2917:09:47），
     保留它用于验证导入脚本的 STR_TO_DATE 修复
  4. 工行的「账号」是 19 位掩码 0，「序号」「地区」是 00000 / 0000，
     且**没有「对方户名」列**（对应真实中那份 11 列的导出）

注：示例文件的表头在第 1 行。真实微信账单表头在第 17 行（前面是标题区），
    导入脚本按「扫描表头」实现，两种都能吃，示例用干净版便于人眼核对。

运行：python 示例数据/生成示例数据.py
"""
import csv
import os
import random
from datetime import datetime, timedelta

SEED = 20261012
HERE = os.path.dirname(os.path.abspath(__file__))

WECHAT_HEADER = ["交易时间", "交易类型", "交易对方", "商品", "收/支", "金额(元)",
                 "支付方式", "当前状态", "交易单号", "商户单号", "备注"]
ALIPAY_HEADER = ["交易时间", "交易分类", "交易对方", "对方账号", "商品说明", "收/支",
                 "金额", "收/付款方式", "交易状态", "交易订单号", "商家订单号", "备注", ""]
ICBC_HEADER = ["交易日期", "序号", "账号", "储种", "币种", "钞汇", "地区",
               "收入/支出金额", "余额", "摘要", "渠道"]

WECHAT_TYPES = [("商户消费", 70), ("扫二维码付款", 18), ("转账", 8), ("微信红包", 4)]
WECHAT_PAY = [("零钱", 55), ("零钱通", 30), ("工商银行储蓄卡(0000)", 15)]
WECHAT_SHOPS = [
    ("示例早餐店", "示例包子豆浆", (6.0, 12.0)),
    ("示例食堂", "示例食堂午餐", (12.0, 22.0)),
    ("示例超市", "示例日用采购", (30.0, 96.0)),
    ("示例奶茶店", "示例珍珠奶茶", (9.0, 18.0)),
    ("示例水果店", "示例时令水果", (15.0, 48.0)),
    ("示例打印店", "示例复印装订", (1.5, 8.0)),
    ("示例地铁", "示例乘车码", (2.0, 5.0)),
    ("示例快餐", "示例套餐", (18.0, 32.0)),
    ("示例文具店", "示例笔与本", (8.0, 30.0)),
    ("示例书店", "示例教辅资料", (25.0, 88.0)),
    ("示例电商平台", "示例日用小物", (19.9, 129.0)),
    ("示例电影院", "示例电影票", (35.0, 55.0)),
    ("示例咖啡店", "示例美式咖啡", (15.0, 26.0)),
    ("示例烧烤", "示例夜宵", (30.0, 68.0)),
    ("示例服装店", "示例换季衣物", (89.0, 259.0)),
    ("示例医院", "示例门诊挂号", (20.0, 60.0)),
]

ALIPAY_CATS = [
    ("生活服务", "示例洗衣", "示例洗烘服务", (2.5, 9.0)),
    ("交通出行", "示例单车", "示例骑行费用", (1.5, 4.0)),
    ("交通出行", "示例打车", "示例打车订单", (12.0, 32.0)),
    ("餐饮美食", "示例外卖平台", "示例外卖订单", (18.0, 45.0)),
    ("购物消费", "示例购物平台", "示例日用品", (9.0, 88.0)),
    ("文化休闲", "示例云盘", "示例会员试用", (1.8, 15.0)),
]


def pick(weighted):
    total = sum(w for _, w in weighted)
    r = random.uniform(0, total)
    acc = 0.0
    for item, w in weighted:
        acc += w
        if r <= acc:
            return item
    return weighted[-1][0]


def amount(low, high):
    """生成带零头的金额，避开整元堆积。"""
    return round(random.uniform(low, high), 2)


def digits(n):
    return "".join(random.choice("0123456789") for _ in range(n))


def timeseries(count, start, days, hours=(6, 23)):
    """在给定区间内生成递增的虚构时间点（秒数随机，避免整齐的 :00）。"""
    span = days * 24 * 60
    offsets = sorted(random.randint(0, span) for _ in range(count))
    out = []
    for off in offsets:
        moment = start + timedelta(minutes=off, seconds=random.randint(0, 59))
        if not (hours[0] <= moment.hour <= hours[1]):
            moment = moment.replace(hour=random.randint(*hours), minute=random.randint(0, 59))
        out.append(moment)
    return out


def gen_wechat():
    """微信账单。返回 (行, 用工行卡付款的镜像列表)。"""
    rows, mirrors = [], []
    for t in timeseries(67, datetime(2026, 3, 20), 190):
        shop, goods, band = random.choice(WECHAT_SHOPS)
        ttype = pick(WECHAT_TYPES)
        pay = pick(WECHAT_PAY)
        if ttype == "转账":
            shop, goods, band = "示例同学" + "甲乙丙丁"[random.randint(0, 3)], "/", (20.0, 200.0)
            status, note = "已存入零钱", random.choice(["示例随礼", "示例AA", "/"])
        elif ttype == "微信红包":
            shop, goods, band = "示例同学" + "甲乙丙丁"[random.randint(0, 3)], "/", (5.0, 66.0)
            status, note = "已存入零钱", "示例红包"
        else:
            status, note = "支付成功", "/"
        amt = amount(*band)
        rows.append([
            t.strftime("%Y-%m-%d %H:%M:%S"), ttype, shop, goods, "支出",
            f"{amt:g}", pay, status, "WX" + digits(26), "MCH" + digits(28), note,
        ])
        if pay.startswith("工商银行储蓄卡") and ttype in ("商户消费", "扫二维码付款"):
            mirrors.append((t + timedelta(seconds=random.randint(5, 20)), amt, "消费"))
    return rows, mirrors


def gen_alipay():
    """支付宝明细。返回 (行, 用工行卡付款的镜像列表)。"""
    rows, mirrors = [], []
    for t in timeseries(20, datetime(2026, 3, 20), 190):
        cat, shop, goods, band = random.choice(ALIPAY_CATS)
        pay = random.choice(["工商银行储蓄卡(0000)", "账户余额", "余额宝", "工商银行储蓄卡(0000)"])
        amt = amount(*band)
        rows.append([
            t.strftime("%Y-%m-%d %H:%M:%S"), cat, shop, "shop***@sample.com", goods, "支出",
            f"{amt:.2f}", pay, "交易成功", "ALI" + digits(24), "SHOP" + digits(26), "", "",
        ])
        if pay.startswith("工商银行储蓄卡"):
            mirrors.append((t + timedelta(seconds=random.randint(5, 20)), amt, "消费"))
    return rows, mirrors


def gen_icbc(mirrors):
    """工行明细：镜像扣款 + 独立消费 + 提现/转账/退款，按时间排序后计算余额链。"""
    events = list(mirrors)  # [(时间, 金额(正数表示金额大小), 摘要)]

    # 独立的工行消费（没有渠道侧对应记录 —— 真实数据里的"找不到来源"那部分）
    for t in timeseries(13, datetime(2026, 3, 20), 190):
        events.append((t, amount(1.5, 96.0), "消费"))

    # 微信零钱提现：银行侧是**正数进账**，绝不能当重复剔除（反例）
    for t in timeseries(9, datetime(2026, 3, 20), 190, hours=(8, 22)):
        events.append((t, round(random.uniform(20, 400), 2), "微信零钱提现"))

    # 转账 / 退款：用于验证 is_oneoff 与 is_refund 判定
    for t in timeseries(3, datetime(2026, 3, 20), 190):
        events.append((t, round(random.uniform(50, 300), 2), "转账"))
    for t in timeseries(2, datetime(2026, 3, 20), 190):
        events.append((t, round(random.uniform(5, 40), 2), "退款"))

    events.sort(key=lambda e: e[0])
    rows, balance = [], round(random.uniform(150, 400), 2)
    for i, (t, mag, summary) in enumerate(events):
        delta = mag if summary in ("微信零钱提现", "退款") else -mag
        balance = round(balance + delta, 2)
        # 前 3 行用「粘连」写法（银行真实缺陷），其余用正常空格写法
        stamp = t.strftime("%Y-%m-%d%H:%M:%S") if i < 3 else t.strftime("%Y-%m-%d %H:%M:%S")
        rows.append([
            stamp, "00000", "0" * 19, "活期", "人民币", "钞", "0000",
            f"{delta:+.2f}", f"{balance:.2f}", summary, "快捷支付",
        ])
    return rows


def write_csv(name, header, rows):
    path = os.path.join(HERE, name)
    with open(path, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f, lineterminator="\r\n")
        w.writerow(header)
        w.writerows(rows)
    return path, len(rows)


if __name__ == "__main__":
    random.seed(SEED)
    wx_rows, wx_mirror = gen_wechat()
    ali_rows, ali_mirror = gen_alipay()
    icbc_rows = gen_icbc(wx_mirror + ali_mirror)

    for name, header, rows in (
        ("微信支付账单_示例.csv", WECHAT_HEADER, wx_rows),
        ("支付宝交易明细_示例.csv", ALIPAY_HEADER, ali_rows),
        ("工商银行历史明细_示例.csv", ICBC_HEADER, icbc_rows),
    ):
        path, n = write_csv(name, header, rows)
        print(f"已生成 {name:30} {n:4} 行 -> {path}")
    print(f"\n其中工行侧含 {len(wx_mirror) + len(ali_mirror)} 条渠道镜像扣款"
          f"（微信 {len(wx_mirror)} + 支付宝 {len(ali_mirror)}），"
          f"用于验证跨源去重。")
    print("全部为虚构数据（固定种子 %d，可复现）。" % SEED)
