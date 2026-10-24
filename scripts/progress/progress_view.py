"""進捗の木から表示の木を作る（純関数。入力の木を書き換えない）。

規則の原本は .spec/issues/194-progress-collapse.md §3・§4-2。木は progress_tree.build の戻り値（dict）だけを受け取る
（progress_tree・server・progress_gh を import しない）。
"""

import re

OPEN_AT = {"epic": 1, "task": 2, "issue": 3}   # 一括で開く段（§4-2）
NUMBER_QUERY = re.compile(r"^#(\d{1,9})$")      # 固定の regex。利用者の入力を regex にしない
DROPPED = {"NOT_PLANNED", "DUPLICATE"}         # progress_tree.DROPPED と同じ（import しないので写す）


def view(tree, closed=False, label="", q=""):
    """§4-2 の戻り値 {"query", "epics", "lone"} を返す。"""
    nodes = tree["nodes"]
    needle = (q or "").strip().lower()
    number = NUMBER_QUERY.match(needle)
    filtering = bool(label or needle)

    def shown(n):
        return closed or n["state"] == "OPEN"

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
            has_open[num] = any(nodes[c]["state"] == "OPEN" or open_below(c) for c in nodes[num]["children"])
        return has_open[num]

    def excluded(num):
        """§3-2 の除くノード: 消えるノード（closed で open の子孫なし）のうち、epic・task か子を持つもの。"""
        n = nodes[num]
        return (n["state"] == "CLOSED" and not open_below(num)
                and (n["kind"] in ("epic", "task") or bool(n["children"])))

    def count_progress(num, under_dropped):
        n = nodes[num]
        gone = under_dropped or (n["state"] == "CLOSED" and n.get("stateReason") in DROPPED)
        if not n["children"]:
            return (0, 0, 1) if gone else ((1 if n["state"] == "CLOSED" else 0), 1, 0)
        sums = [count_progress(c, gone) for c in n["children"] if not excluded(c)]
        return tuple(sum(x) for x in zip(*sums)) if sums else (0, 0, 0)

    def progress_of(n):
        if closed or n["progress"] is None:
            return n["progress"]
        done, total, skipped = count_progress(n["number"], False)
        return {"completed": done, "total": total, "notPlanned": skipped}

    def item(num, parent_shown):
        n = nodes[num]
        kids = [k for k in (item(c, num) for c in expand(n["children"])) if k is not None]
        if filtering and not (match(n) and shown(n)) and not kids:
            return None
        lifted = n["parent"] if n["parent"] is not None and n["parent"] != parent_shown else None
        return {"number": num, "children": kids, "count": len(kids), "progress": progress_of(n),
                "defaultOpen": filtering and bool(kids), "openAt": OPEN_AT[n["kind"]],
                "liftedFrom": None if closed else lifted}

    epics, lone = [], []
    for num in expand(tree["roots"]):
        it = item(num, None)
        if it is not None:
            (epics if nodes[num]["kind"] == "epic" else lone).append(it)
    return {"query": {"closed": closed, "label": label, "q": q},
            "epics": epics,
            "lone": {"count": len(lone), "items": lone, "defaultOpen": filtering and bool(lone)}}
