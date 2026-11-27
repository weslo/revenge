"""Tests for review_log.py, with saved variables written the way the game writes them.

Run: python -I -m unittest discover -s tools -p "test_*.py"
"""

from __future__ import annotations

import io
import tempfile
import time
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

import review_log

T = 1795700000  # server time of the sample's first line

# Lines as Revenge writes them (the texts tests/test_log.lua checks).
LOG = [
    f"{T} session Revenge 0.5.0, client 1.60.1 (70938); Anna Bright, level 40, Alliance; in a guild: yes; stored: 2 deaths (1 from Revenge), 0 Wanted marks",
    f"{T} session switches: sharing guild on, friends on, Battle.net on; alerts nearby on, killed on, popup on, chat on, sound on; skulls on, map pins on; expiry 7 days",
    f"{T + 5} others the module is loaded",
    f"{T + 60} death recorded: killed by Gorvak Ashmane in Duskwood (map 1431, with position), new; 1 messages queued to share",
    f"{T + 60} out your death: 1 messages queued to guild",
    f"{T + 90} in Mira Thornwood's death by guild (live): killed by Gorvak Ashmane in Duskwood, new",
    f"{T + 91} alert killed: Mira Thornwood (guild) by Gorvak Ashmane in Duskwood (popup, chat)",
    f"{T + 95} in hello from Mira Thornwood by guild, asking since 1d ago",
    f"{T + 120} alert nearby: Gorvak Ashmane: (2) You, Mira (popup, chat, sound)",
    f"{T + 121} skull Gorvak Ashmane: (2) You, Mira",
    f"{T + 130} pins 2 on Duskwood (map 1431)",
    f"{T + 140} others Revenge Book from Tavish by GUILD: 1 of 1 taken: Tavish Reed's death by Orin in Barrens: new, live",
    f"{T + 150} in dropped a whisper from Stranger, who isn't an online friend",
    f"{T + 160} error Tooltip error: boom",
    "not a log line",
    f"{T + 3600} session Revenge 0.5.0, client 1.60.1 (70938); Anna Bright, level 40, Alliance; in a guild: yes; stored: 3 deaths",
    f"{T + 3700} death not recorded: in an instance (pvp)",
]


def lua_string(text: str) -> str:
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def saved_file(log=LOG) -> str:
    """RevengeTrackerDB as the game writes it: keyed entries, arrays with index comments."""
    lines = ["", "RevengeTrackerDB = {", '["lastSeen"] = 1795760359,', '["settings"] = {',
             '["diagnosticLog"] = true,', '["expiryDays"] = 7,', "},", '["kills"] = {', '["k1"] = {',
             '["own"] = true,', '["at"] = 1795700060,', '["x"] = 0.42,', '["sources"] = {', '["self"] = true,',
             "},", "},", '["k2"] = {', '["at"] = 1795700140,', '["sources"] = {', '["revengebook"] = true,', "},",
             "},", "},", '["wanted"] = {', "},", '["log"] = {']
    lines += [f"{lua_string(line)}, -- [{i}]" for i, line in enumerate(log, 1)]
    lines += ["},", "}", ""]
    return "\n".join(lines)


BUGSY = """
BugsyDB = {
["errors"] = {
{
["message"] = "Interface/AddOns/RevengeTracker/Tooltip.lua:12: attempt to index a nil value",
["count"] = 2,
["stack"] = "[Interface/AddOns/RevengeTracker/Tooltip.lua]:12: in function <...>",
}, -- [1]
{
["message"] = "Interface/AddOns/OpenMap/Map.lua:3: something else",
["count"] = 1,
}, -- [2]
},
}
"""


class ParseTests(unittest.TestCase):
    def test_values_tables_arrays_and_escapes(self):
        data = review_log.parse_saved_variables(
            'A = {\n["s"] = "say \\"hi\\"\\n\\\\ \\65",\n["n"] = -12,\n["f"] = 0.5,\n["e"] = 1e+15,\n'
            '["t"] = true,\n["no"] = false,\n[3] = "three",\n["list"] = {\n"a", -- [1]\nnil, -- [2]\n"c", -- [3]\n},\n}\n'
            "B = 7\n")
        a = data["A"]
        self.assertEqual(a["s"], 'say "hi"\n\\ A')
        self.assertEqual((a["n"], a["f"], a["e"], a["t"], a["no"], a[3]), (-12, 0.5, 1e15, True, False, "three"))
        self.assertEqual(a["list"], {1: "a", 3: "c"})
        self.assertEqual(review_log.as_list(a["list"]), ["a"], "an array stops at its first hole")
        self.assertEqual(data["B"], 7)

    def test_junk_is_an_error_not_code(self):
        with self.assertRaises(review_log.ParseError):
            review_log.parse_saved_variables("A = os.execute('x')")

    def test_the_sample_file(self):
        db = review_log.parse_saved_variables(saved_file())["RevengeTrackerDB"]
        self.assertEqual(len(review_log.log_lines(db)), len(LOG) - 1, "the malformed line is skipped")
        self.assertEqual(review_log.log_lines(db)[0][1], "session")


class EvidenceTests(unittest.TestCase):
    def test_each_check_counts_its_lines(self):
        db = review_log.parse_saved_variables(saved_file())["RevengeTrackerDB"]
        found = {(c, w): n for c, w, n, _ in review_log.evidence(review_log.log_lines(db))}
        self.assertEqual(found[("V-003", "your open-world deaths recorded")], 1)
        self.assertEqual(found[("V-003", "deaths not recorded, and why")], 1)
        self.assertEqual(found[("V-006", "your own data sent to the guild")], 1)
        self.assertEqual(found[("V-006", "guildmates' Revenge data received")], 1)
        self.assertEqual(found[("V-006", "catch-up: hellos and answers")], 1)
        self.assertEqual(found[("V-007", "friends' data received")], 0, "a dropped whisper isn't evidence")
        self.assertEqual(found[("V-008", "friend or guildmate killed alerts")], 1)
        self.assertEqual(found[("V-009", "nameplate skulls")], 1)
        self.assertEqual(found[("V-010", "killer nearby alerts")], 1)
        self.assertEqual(found[("V-011", "map pins shown")], 1)
        self.assertEqual(found[("V-013", "alerts shown as a popup")], 2)
        self.assertEqual(found[("V-015", "Revenge Book reports")], 1)
        self.assertEqual(found[("V-016", "Grudgekeeper reports")], 0)
        self.assertEqual(found[("V-019", "the module, breakers and summaries")], 1)
        self.assertEqual(found[("-", "messages turned away")], 1)
        self.assertEqual(found[("-", "errors Revenge caught")], 1)


class ReviewTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        folder = Path(self.dir.name) / "WTF" / "Account" / "ME" / "SavedVariables"
        folder.mkdir(parents=True)
        (folder / "RevengeTracker.lua").write_text(saved_file(), encoding="utf-8")
        (folder / "!Bugsy.lua").write_text(BUGSY, encoding="utf-8")
        self.root = Path(self.dir.name)
        self.path = folder / "RevengeTracker.lua"

    def tearDown(self):
        self.dir.cleanup()

    def test_the_listing_checks_stored_data_and_bugsy(self):
        text = review_log.review(self.path)
        self.assertIn("death    recorded: killed by Gorvak Ashmane", text)
        self.assertEqual(text.count("-" * 72), 2, "a rule before each session")
        self.assertIn("log: 16 lines", text)
        self.assertIn("  V-008  friend or guildmate killed alerts: 1", text)
        self.assertIn("alert killed: Mira Thornwood (guild)", text, "the newest example")
        self.assertIn("deaths stored: 2 (1 from Revenge itself)", text)
        self.assertIn("  from revengebook: 1", text)
        self.assertIn("diagnostic log: on", text)
        self.assertIn("RevengeTracker/Tooltip.lua:12: attempt to index a nil value", text)
        self.assertNotIn("OpenMap", text, "only Bugsy's errors that mention Revenge")

    def test_summary_since_and_kinds(self):
        summary = review_log.review(self.path, summary=True)
        self.assertNotIn("death    recorded", summary, "no listing")
        self.assertIn("  V-003  your open-world deaths recorded: 1", summary)
        later = review_log.review(self.path, since=T + 3600)
        self.assertIn("log: 2 lines", later)
        only = review_log.review(self.path, kinds={"alert"})
        self.assertIn("alert    nearby", only)
        self.assertNotIn("death    recorded", only)

    def test_main_finds_files_under_a_folder(self):
        out = io.StringIO()
        with redirect_stdout(out):
            code = review_log.main([str(self.root), "--summary", "--since",
                                    time.strftime("%Y-%m-%d", time.localtime(T))])
        self.assertEqual(code, 0)
        self.assertIn(str(self.path), out.getvalue())

    def test_no_file_is_an_error(self):
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            self.assertEqual(review_log.main([str(Path(self.dir.name) / "nothing")]), 1)


if __name__ == "__main__":
    unittest.main()
