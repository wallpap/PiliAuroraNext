"""离线汇总 stutter_validation.dart 报告；按帧真实时刻归段，不读取对象正文。"""
import argparse
from bisect import bisect_left
import csv
import json
from datetime import datetime
from pathlib import Path


def distribution(values):
    values = sorted(values)
    if not values:
        return {"count": 0, "p50": None, "p95": None, "max": None}
    return {"count": len(values), "p50": values[(len(values) - 1) // 2],
            "p95": values[int((len(values) - 1) * .95)], "max": values[-1]}


def utc_us(value):
    return int(datetime.fromisoformat(value).timestamp() * 1e6)


def timed_operations(report, records):
    categories = {
        "http", "grpcDecode", "imageFile", "imageDecode", "imageFrame",
        "inactivePaintCleanup",
    }
    return sorted(
        (utc_us(record["time"]), record["category"], record["details"]["durationMs"])
        for record in records
        if record.get("category") in categories
        and record.get("time")
        and record.get("processId", report.get("pid")) == report.get("pid")
        and isinstance((record.get("details") or {}).get("durationMs"), (int, float))
    )


def operation_summary(operations, start, end, tracing):
    if not tracing:
        return None
    durations = {}
    for timestamp, category, duration in operations:
        if start <= timestamp < end:
            durations.setdefault(category, []).append(duration)
    return {
        category: {"totalMs": round(sum(samples), 3), **distribution(samples)}
        for category, samples in durations.items()
    }


def navigation_summary(report, operations, window_ms=600):
    events = sorted(
        (event["utcUs"], event["name"])
        for event in report.get("events", ())
        if event["name"].startswith(("first:", "revisit:", "routes:"))
    )
    frames = sorted(report["frames"], key=lambda frame: frame["startUtcUs"])
    starts = [frame["startUtcUs"] for frame in frames]
    refresh = report.get("refreshRateHz") or 60
    budget_ms = 1000 / refresh
    result = []
    for index, (start, name) in enumerate(events):
        end = start + window_ms * 1000
        if index + 1 < len(events):
            end = min(end, events[index + 1][0])
        samples = frames[bisect_left(starts, start):bisect_left(starts, end)]
        finishes = [
            frame["rasterFinishUtcUs"] for frame in samples
            if frame.get("rasterFinishUtcUs") is not None
        ]
        stage = next((
            stage for stage in report["stages"]
            if stage["startUtcUs"] <= start < stage["endUtcUs"]
        ), {})
        result.append({
            "name": name,
            "stage": stage.get("name"),
            "frames": len(samples),
            "firstRasterFinishMs": (min(finishes) - start) / 1000 if finishes else None,
            "buildMs": distribution(frame["buildMs"] for frame in samples),
            "rasterMs": distribution(frame["rasterMs"] for frame in samples),
            "overDisplayBudget": sum(
                max(frame["buildMs"], frame["rasterMs"]) > budget_ms for frame in samples
            ),
            "operations": operation_summary(
                operations, start, end, not stage.get("name", "").endswith(":off"),
            ),
        })
    return {"windowMs": window_ms, "frameBudgetMs": budget_ms, "switches": result}


def summarize(report, records=()):
    stages = []
    operations = timed_operations(report, records)
    for stage in report["stages"]:
        start, end = stage["startUtcUs"], stage["endUtcUs"]
        frames = [f for f in report["frames"] if start <= f["startUtcUs"] < end]
        stages.append({
            "name": stage["name"], "seconds": (end - start) / 1e6,
            "frames": len(frames),
            "buildMs": distribution(f["buildMs"] for f in frames),
            "rasterMs": distribution(f["rasterMs"] for f in frames),
            "totalMs": distribution(f["totalMs"] for f in frames),
            "over16ms": sum(max(f["buildMs"], f["rasterMs"]) > 16.67 for f in frames),
            "over33ms": sum(max(f["buildMs"], f["rasterMs"]) > 33.33 for f in frames),
            "timerGapsMs": distribution(g["gapMs"] for g in report["timerGaps"]
                                        if start <= g["utcUs"] < end),
            "cleanupMs": distribution(duration for timestamp, category, duration in operations
                                      if category == "inactivePaintCleanup" and start <= timestamp < end),
            "operations": operation_summary(operations, start, end, not stage["name"].endswith(":off")),
            "process": stage.get("process"),
            "windowVisible": stage.get("windowVisible"),
        })
    fields = ("bytes", "background", "quotaWaitMs", "parseMs", "consumeMs", "durationMs")
    return {"state": report["state"], "validWorkload": report["validWorkload"],
            "windowVisible": report.get("windowVisible"), "refreshRateHz": report.get("refreshRateHz"),
            "visits": report.get("visits", []), "finalProcess": report.get("finalProcess"),
            "navigation": navigation_summary(report, operations),
            "stages": stages,
            "grpc": [{"time": r["time"], **{k: r["details"][k] for k in fields
                                             if k in r["details"]}}
                     for r in records if r.get("category") == "grpcDecode"]}


def present_stages(report, rows, anchor, frequency):
    if frequency <= 0:
        raise ValueError("QPC frequency must be positive")
    timed = [(anchor["utcNs"] / 1000 +
              (int(r["TimeInQPC"]) / frequency * 1e9 - anchor["qpcNs"]) / 1000, r)
             for r in rows]
    result = []
    for stage in report["stages"]:
        rr = [r for t, r in timed if stage["startUtcUs"] <= t < stage["endUtcUs"]]
        values = [float(r["MsBetweenPresents"]) for r in rr
                  if r.get("MsBetweenPresents", "NA") != "NA"]
        # NA 保留为缺测，不能用零填补后宣称已完成屏幕呈现测量。
        displayed = [float(r["MsUntilDisplayed"]) for r in rr
                     if r.get("MsUntilDisplayed", "NA") != "NA"]
        result.append({"name": stage["name"], "presents": len(rr),
                       "submissionGapMs": distribution(values),
                       "submissionGapsOver12ms": sum(x > 12 for x in values),
                       "displayLatencyMs": distribution(displayed)})
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--logs", type=Path)
    parser.add_argument("--present", type=Path)
    parser.add_argument("--qpc-anchor", type=Path)
    parser.add_argument("--qpc-frequency", type=int)
    args = parser.parse_args()
    report = json.loads(args.input.read_text(encoding="utf-8-sig"))
    records = []
    if args.logs:
        for path in sorted(args.logs.glob("runtime.jsonl*")):
            records.extend(json.loads(line) for line in path.read_text(encoding="utf-8-sig").splitlines()
                           if line.strip())
    result = summarize(report, records)
    if args.present:
        if not args.qpc_anchor or not args.qpc_frequency:
            parser.error("--present requires --qpc-anchor and --qpc-frequency")
        with args.present.open(encoding="utf-8-sig", newline="") as stream:
            rows = list(csv.DictReader(stream))
        result["present"] = present_stages(
            report, rows, json.loads(args.qpc_anchor.read_text()), args.qpc_frequency)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"state={result['state']}; validWorkload={result['validWorkload']}; stages={len(result['stages'])}")


if __name__ == "__main__":
    main()
