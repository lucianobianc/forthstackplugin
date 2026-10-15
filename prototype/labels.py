"""Conservative identities reconstructed from actual Gforth observations."""
import re

LABEL_NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_-]{0,63}\Z")
BINARY = {"=", "<>", "<", ">", "<=", ">=", "u<", "u>", "+", "-", "*", "/", "mod"}
UNARY = {"0=", "0<", "0>", "0<>"}


def enrich(events):
    """Attach immutable snapshots; never infer identity by matching equal numbers."""
    stack, frames = [], []
    counter = 0

    def fresh(value, *, label=None, origin=None, literal=False):
        nonlocal counter
        counter += 1
        return dict(id=counter, value=value, label=label, origin=origin, literal=literal)

    def values(elements):
        return [e["value"] for e in elements]

    def reset(actual):
        return [fresh(v) for v in actual]

    def copied(element):
        return fresh(element["value"], label=element["label"], origin=element["id"],
                     literal=element["literal"])

    def operation(before, op, actual):
        # These rules describe known original execution tokens, not word names.
        try:
            if op == "literal" and actual[:len(before)] == values(before) and len(actual) > len(before):
                result = before + [fresh(v, literal=True) for v in actual[len(before):]]
            elif op == "dup" and before:
                result = before + [copied(before[-1])]
            elif op == "drop" and before:
                result = before[:-1]
            elif op == "swap" and len(before) >= 2:
                result = before[:-2] + [before[-1], before[-2]]
            elif op == "over" and len(before) >= 2:
                result = before + [copied(before[-2])]
            elif op == "rot" and len(before) >= 3:
                result = before[:-3] + [before[-2], before[-1], before[-3]]
            elif op == "nip" and len(before) >= 2:
                result = before[:-2] + [before[-1]]
            elif op == "tuck" and len(before) >= 2:
                result = before[:-2] + [before[-1], before[-2], copied(before[-1])]
            elif op in {"1+", "1-"} and before and len(actual) == len(before):
                result = before[:-1] + [dict(before[-1], value=actual[-1], literal=False)]
            elif op in {"+", "-"} and len(before) >= 2 and len(actual) == len(before) - 1:
                left, right = before[-2:]
                # Recognize the literal forms of 1+ and 1-, not arbitrary arithmetic.
                if right["literal"] and right["label"] is None and right["value"] == 1:
                    result = before[:-2] + [dict(left, value=actual[-1], literal=False)]
                elif op == "+" and left["literal"] and left["label"] is None and left["value"] == 1:
                    result = before[:-2] + [dict(right, value=actual[-1], literal=False)]
                else:
                    result = before[:-2] + [fresh(actual[-1])]
            elif op in BINARY and len(before) >= 2 and len(actual) == len(before) - 1:
                result = before[:-2] + [fresh(actual[-1])]
            elif op == "/mod" and len(before) >= 2 and len(actual) == len(before):
                result = before[:-2] + [fresh(v) for v in actual[-2:]]
            elif op in UNARY and before and len(actual) == len(before):
                result = before[:-1] + [fresh(actual[-1])]
            else:
                return reset(actual)
            return result if values(result) == actual else reset(actual)
        except IndexError:
            return reset(actual)

    for event in events:
        phase, actual = event["phase"], event["stack"]
        if phase == "before":
            if values(stack) != actual:
                stack = reset(actual)  # Opaque gap: do not guess which identities survived.
            for frame in frames:
                frame["children"] = True
            frames.append(dict(site=event["site"], before=list(stack), children=False,
                               op=event["source"].get("operation", "call")))
        elif phase == "after":
            if not frames or frames[-1]["site"] != event["site"]:
                stack, frames = reset(actual), []
            else:
                frame = frames.pop()
                if frame["children"]:
                    if values(stack) != actual:
                        stack = reset(actual)
                else:
                    stack = operation(frame["before"], frame["op"], actual)
        elif phase == "opaque":
            stack = reset(actual)
            for frame in frames:
                frame["children"] = True
        elif phase == "label":
            if values(stack) != actual:
                stack = reset(actual)
            if not stack:
                raise ValueError("Cannot assign a label to an empty stack")
            for frame in frames:
                frame["children"] = True
            name = event["source"]["label"]
            stack[-1] = dict(stack[-1], label=name)
        else:
            if values(stack) != actual:
                stack = reset(actual)
        event["elements"] = [{k: e[k] for k in ("id", "value", "label", "origin")} for e in stack]
