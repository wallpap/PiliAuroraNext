import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("stutter", Path(__file__).with_name("analyze_stutter.py"))
analysis = importlib.util.module_from_spec(spec)
spec.loader.exec_module(analysis)


class StutterAnalysisTest(unittest.TestCase):
    def test_frame_start_and_half_open_stage_boundaries(self):
        report = {"state": "completed", "validWorkload": True,
                  "stages": [{"name": "a", "startUtcUs": 100, "endUtcUs": 200},
                             {"name": "b", "startUtcUs": 200, "endUtcUs": 300}],
                  "timerGaps": [], "frames": [
                      {"startUtcUs": 199, "buildMs": 40, "rasterMs": 1, "totalMs": 60},
                      {"startUtcUs": 200, "buildMs": 2, "rasterMs": 1, "totalMs": 70}]}
        rows = analysis.summarize(report)["stages"]
        self.assertEqual([r["frames"] for r in rows], [1, 1])
        self.assertEqual([r["over33ms"] for r in rows], [1, 0])
        self.assertEqual(rows[1]["totalMs"]["max"], 70)

    def test_qpc_alignment_and_missing_display_measurements(self):
        report = {"stages": [{"name": "a", "startUtcUs": 1_000_000, "endUtcUs": 2_000_000}]}
        rows = [{"TimeInQPC": "15000", "MsBetweenPresents": "18", "MsUntilDisplayed": "NA"}]
        result = analysis.present_stages(
            report, rows, {"utcNs": 1_000_000_000, "qpcNs": 1_000_000_000}, 10000)[0]
        self.assertEqual(result["presents"], 1)
        self.assertEqual(result["submissionGapsOver12ms"], 1)
        self.assertEqual(result["displayLatencyMs"]["count"], 0)
        self.assertIsNone(result["displayLatencyMs"]["max"])

    def test_switch_windows_use_engine_budget_and_exclude_next_switch(self):
        report = {
            "refreshRateHz": 120,
            "stages": [{"name": "revisit:0:debug", "startUtcUs": 90, "endUtcUs": 500},
                       {"name": "revisit:1:off", "startUtcUs": 500, "endUtcUs": 900}],
            "events": [{"name": "revisit:0:0:hot", "utcUs": 100},
                       {"name": "revisit:0:0:rank", "utcUs": 300},
                       {"name": "revisit:1:0:hot", "utcUs": 500}],
            "frames": [
                {"startUtcUs": 101, "rasterFinishUtcUs": 140, "buildMs": 9, "rasterMs": 1},
                {"startUtcUs": 300, "rasterFinishUtcUs": 320, "buildMs": 2, "rasterMs": 1},
            ],
        }
        switches = analysis.navigation_summary(
            report, [(300, "imageDecode", 1), (510, "http", 2)],
        )["switches"]
        self.assertEqual([row["frames"] for row in switches], [1, 1, 0])
        self.assertEqual(switches[0]["firstRasterFinishMs"], .04)
        self.assertEqual(switches[0]["overDisplayBudget"], 1)
        self.assertEqual(switches[0]["operations"], {})
        self.assertEqual(switches[1]["operations"]["imageDecode"]["count"], 1)
        self.assertIsNone(switches[2]["operations"])


if __name__ == "__main__":
    unittest.main()
