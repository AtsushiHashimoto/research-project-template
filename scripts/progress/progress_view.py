"""進捗の木から表示の木を作る（純関数。入力の木を書き換えない）。

規則の原本は .spec/issues/194-progress-collapse.md §3・§4-2 と .spec/issues/201-progress-cards.md §3-3・§4-2。
木は progress_tree.build の戻り値（dict）だけを受け取る（progress_work 以外を import しない）。
出す・出さないは node の gone（closed か完了扱い）だけで決め、state を直接見ない。
"""

import re

from progress_work import DROPPED, sum_steps

OPEN_AT = {"epic": 1, "task": 2, "issue": 3}   # 一括で開く段（§4-2）
NUMBER_QUERY = re.compile(r"^#(\d{1,9})$", re.ASCII)   # 固定の regex。利用者の入力を regex にしない（全角の数字は番号にしない）


def view(tree, closed=False, label="", q=""):
    """§4-2 の戻り値 {"query", "epics", "lone"} を返す。"""
    nodes = tree["nodes"]
    needle = (q or "").strip().lower()
    number = NUMBER_QUERY.match(needle)
    filtering = bool(label or needle)

    def shown(n):
        return closed or not n["gone"]

    def match(n):
        if label and label not in n["labels"]:
            return False
        if not needle:
            return True
        return n["number"] == int(number.group(1)) if number else needle in n["title"].lower()

    def expand(nums):
        """出さないノードを、その出す子孫の列で置き換える（先行順）。"""
        out = []
        for num in nums:
            if shown(nodes[num]):
                out.append(num)
            else:
                out.extend(expand(nodes[num]["children"]))
        return out

    has_open = {}

    def open_below(num):
        if num not in has_open:
            has_open[num] = any(not nodes[c]["gone"] or open_below(c) for c in nodes[num]["children"])
        return has_open[num]

    def excluded(num):
        """§3-2 の除くノード: 消えるノード（gone で gone でない子孫なし）のうち、epic・task か子を持つもの。"""
        n = nodes[num]
        return (n["gone"] and not open_below(num)
                and (n["kind"] in ("epic", "task") or bool(n["children"])))

    def count_progress(num, under_dropped):
        n = nodes[num]
        gone = under_dropped or (n["state"] == "CLOSED" and n.get("stateReason") in DROPPED)
        if not n["children"]:
            return (0, 0, 1) if gone else ((1 if n["state"] == "CLOSED" else 0), 1, 0)
        # 数える葉が 1 枚も無い部分木は None（子が全部除くノードの open な task 等。親の和にも入れない）
        sums = [x for x in (count_progress(c, gone) for c in n["children"] if not excluded(c)) if x is not None]
        return tuple(sum(x) for x in zip(*sums)) if sums else None

    def progress_of(n):
        if closed or n["progress"] is None:
            return n["progress"]
        counted = count_progress(n["number"], False)
        if counted is None:          # 木の上の子が全部除くノード。「0/0」を出すと隠した epic・task の気配になる
            return None
        done, total, skipped = counted
        return {"completed": done, "total": total, "notPlanned": skipped}

    def tasks_below(num):
        for c in nodes[num]["children"]:
            if nodes[c]["kind"] == "task" and shown(nodes[c]):
                yield nodes[c]
            yield from tasks_below(c)

    def steps_of(n):
        """201 §3-3: task は自分の帯、epic は出す task の帯の集計、issue は None。"""
        return sum_steps(tasks_below(n["number"])) if n["kind"] == "epic" else n["steps"]

    def item(num, parent_shown):
        n = nodes[num]
        kids = [k for k in (item(c, num) for c in expand(n["children"])) if k is not None]
        if filtering and not (match(n) and shown(n)) and not kids:
            return None
        lifted = n["parent"] if n["parent"] is not None and n["parent"] != parent_shown else None
        return {"number": num, "children": kids, "count": len(kids), "progress": progress_of(n), "steps": steps_of(n),
                "defaultOpen": filtering and bool(kids), "openAt": OPEN_AT[n["kind"]],
                "liftedFrom": None if closed else lifted}

    epics, lone = [], []
    for num in expand(tree["roots"]):
        it = item(num, None)
        if it is not None:
            (epics if nodes[num]["kind"] == "epic" else lone).append(it)
    return {"query": {"closed": closed, "label": label, "q": q},
            "epics": epics,
            "lone": {"count": len(lone), "items": lone, "defaultOpen": filtering and bool(lone), "openAt": 1}}
