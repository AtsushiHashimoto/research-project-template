#!/usr/bin/env python3
"""判断ゲートの述語（markdown を読むもの）。scripts/check-discipline.sh だけが呼ぶ。

  goal         <TASK>        goal の空欄・goal ゲートの判定・未確定の担当・記録・再照合
  verdict-task <TASK>        task の判定コメントの形（結果: 行と成功条件の引用）
  all-negative <EPIC>        閉じた task が全部 negative なら、全部 negative の確認を求める
  conformance  <N> <種類>    PR 本文の ## 仕様整合 節

出力は check-discipline.sh と同じ形（`  ok   …` / `!!! FAILED: …`）。落ちた項目は
**全部**出してから終わる（1 つずつ止めない）。`書く行:` が、そのまま書けばよい行。
終了コード: 0 全て PASS / 1 いずれか FAIL / 2 gh・git が失敗した（検査が壊れた）
"""
import re
import sys

from check_discipline_md import (FAILS, check_undecided, children, fail, goal_values, issue,
                                 last_edited, latest, ok, records, run, section)


def mode_goal(task):
    d = issue(task)
    sec, vals = goal_values(d["body"])
    if sec is None:
        fail(f"task #{task} の本文に「## 目標の状態」節が無い（何を作り何を測れば終わりかが書かれていない）",
             "## 目標の状態", "- 成功条件: <1 文の合否の述語>", "- negative の意味: <失敗したら何が分かるか>")
    else:
        for key, hint in (("成功条件", "<1 文の合否の述語>"), ("negative の意味", "<失敗したら何が分かるか>")):
            v = vals.get(key)
            if not v:
                fail(f"「## 目標の状態」に「{key}」の行が無い", f"- {key}: {hint}")
            elif None in v:
                fail(f"「## 目標の状態」の「{key}」が空（空白・<…> の雛形のまま・TBD・未定）", f"- {key}: {hint}")
            else:
                ok(f"{key}: {v[0][:40]}")
    edited = last_edited(task, d)
    gate = latest(d["comments"], "## goal ゲート")
    want = {"G1b": "成功条件が 1 文の合否の述語になっている",
            "G3": "未確定に言及する語を削っても、何を作り何を測るかが残る",
            "G4": "解釈が 1 つに定まる"}
    if gate is None:
        fail("goal ゲートの判定コメント（「## goal ゲート」）が無い"
             "（goal の中身を verification のサブエージェントが判定していない）",
             *(f"- {k}: PASS — <根拠。{v}か>" for k, v in want.items()))
    elif gate["createdAt"] <= edited:
        fail(f"goal ゲートの判定（{gate['createdAt']}）が本文の最終編集（{edited}）より古い"
             "（編集後の goal を判定し直していない）", *(f"- {k}: PASS — <根拠>" for k in want))
    else:
        for k, v in want.items():
            if re.search(rf"^- {k}: PASS — .+$", gate["body"].replace("\r", ""), re.M):
                ok(f"goal ゲート {k}（{v}）: PASS")
            else:
                fail(f"goal ゲートに「{k}（{v}）が PASS」の行が無い", f"- {k}: PASS — <根拠>")
    kids = children(task)
    names = check_undecided(task, d, kids)
    gone = sorted(records(d["comments"]) - set(names))
    for g in gone:
        fail(f"未確定「{g}」が本文の「## 未確定」から消えている（記録にはある。行を消して逃げない）",
             f"- {g} 解消済み（→ #<closed な issue>, <根拠のファイル>）", f"- {g} 解消不能（理由: <理由>）")
    if not FAILS:
        new = [x for x in names if x not in records(d["comments"])]
        if new:
            body = "## 未確定（記録）\n\n" + "\n".join(f"- {x}" for x in sorted(records(d["comments"]) | set(names)))
            run("gh", "issue", "comment", str(task), "--body", body)
            ok(f"未確定の項目名を task #{task} に記録した（{len(new)} 件。以後この行を消すと止まる）")


def mode_verdict_task(task):
    d = issue(task)
    c = latest(d["comments"], "## 判定")
    if c is None:
        fail(f"task #{task} に判定コメント（「## 判定」）が無い", "## 判定", "結果: positive | negative | 未達成 のどれか 1 つ")
        return
    if re.search(r"^結果: (positive|negative|未達成)$", c["body"].replace("\r", ""), re.M):
        ok("判定に「結果:」の行がある")
    else:
        fail("判定に「結果: positive」「結果: negative」「結果: 未達成」のどれかの行が無い", "結果: <positive|negative|未達成>")
    _, vals = goal_values(d["body"])
    crit = [v for v in vals.get("成功条件", []) if v]
    if not crit:
        fail("本文の成功条件が読めない（引用を照合できないので通さない）", "- 成功条件: <1 文の合否の述語>")
    for v in crit:
        if v in c["body"]:
            ok(f"成功条件を引用している: {v[:40]}")
        else:
            fail(f"判定が成功条件を引用していない: {v[:60]}", f"- 成功条件: {v} → <満たした/満たさない と根拠>")


def mode_all_negative(epic):
    kids = children(epic)
    results = []
    for k, v in kids.items():
        if "task" not in v["labels"] or v["state"] != "CLOSED":
            continue
        c = latest(v["d"]["comments"], "## 判定")
        m = re.search(r"^結果: (\S+)$", c["body"].replace("\r", ""), re.M) if c else None
        results.append(m.group(1) if m else "?")
    if not results or any(r != "negative" for r in results):
        ok(f"閉じた task の結果: {', '.join(results) or 'なし'}（全部 negative ではない）")
        return
    c = latest(issue(epic)["comments"], "## 判定")
    sec = section(c["body"], "全部 negative の確認", exact=True) if c else None
    if sec and any(x.strip() for x in sec):
        ok("全部 negative の確認（positive control の再確認）が判定にある")
    else:
        fail(f"閉じた task {len(results)} 件の結果がすべて negative なのに、epic #{epic} の判定に"
             "「## 全部 negative の確認」節が無いか空（全部 negative なら、まず検出力と実装を疑う）",
             "## 全部 negative の確認", "<効くはずの状況で検出できることを再確認した記述（positive control）>")


def mode_conformance(n, kind):
    body = run("gh", "pr", "view", "--json", "body", "-q", ".body")
    sec = section(body, "仕様整合")
    if not sec or not any(x.strip() for x in sec):
        fail("PR 本文に「## 仕様整合」節が無いか空（verification のサブエージェントの照合結果を貼っていない）",
             "## 仕様整合", "- goal 書き換え: なし")
        return
    text = "\n".join(sec)
    bad = [x.strip() for x in sec if "❌" in x]
    for x in bad:
        fail(f"仕様整合に ❌ の項目がある: {x[:80]}", "（直してから照合し直す。❌ を消して通さない）")
    if re.search(r"^\s*-?\s*goal 書き換え[:：]\s*なし\s*$", text, re.M):
        ok("goal 書き換え: なし")
    else:
        fail("仕様整合に「goal 書き換え: なし」の行が無い（goal を書き換えていないことの確認）", "- goal 書き換え: なし")
    if kind in ("experiment", "validation"):
        for key in ("positive control", "matched-engineering", "格付け"):
            if re.search(rf"^\s*-?\s*{key}[:：]\s*\S", text, re.M):
                ok(f"{key} の行がある")
            else:
                fail(f"{kind} の仕様整合に「{key}:」の行が無い", f"- {key}: <中身>")
        if re.search(r"格付け[:：]\s*`?unverified-negative", text):
            fail("格付けが unverified-negative（triage していない negative はマージしない）",
                 "- 格付け: verified-negative | implementation-bug（triage を済ませてから）")
    if not bad:
        ok("仕様整合に ❌ が無い")


def main(a):
    modes = {"goal": (2, mode_goal), "verdict-task": (2, mode_verdict_task),
             "all-negative": (2, mode_all_negative), "conformance": (3, mode_conformance)}
    if not a or a[0] not in modes or len(a) != modes[a[0]][0]:
        print(__doc__)
        sys.exit(2)
    modes[a[0]][1](*a[1:])
    sys.exit(1 if FAILS else 0)


if __name__ == "__main__":
    main(sys.argv[1:])
