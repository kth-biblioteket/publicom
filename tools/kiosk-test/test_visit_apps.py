"""Besöksstatistiken per tjänst (visit_tracker.py): klippning till besöket, summering och integritet."""
import importlib.util
import json
import os
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True  # inget __pycache__ i files/
here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("visit_tracker", os.path.join(here, "..", "..", "files", "usr", "local", "bin", "visit_tracker.py"))
vt = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vt)

A, B = "https://a.example.se/", "https://b.example.se/"


class AppUsage(unittest.TestCase):
    def test_summerar_per_tjanst_och_klipper_till_besoket(self):
        ev = [(50, "", ""), (100, A, "A"), (160, B, "B"), (200, A, "A"), (400, "", "")]
        # Besök 120-260: A 120-160 (40) + 200-260 (60) = 100 (A pågick före starten), B 160-200 = 40
        self.assertEqual(vt.app_usage(ev, 120, 260), [{"url": A, "name": "A", "s": 100}, {"url": B, "name": "B", "s": 40}])

    def test_forstasidan_raknas_inte_och_tomt_ger_inget(self):
        self.assertEqual(vt.app_usage([(0, "", "")], 10, 100), [])
        self.assertEqual(vt.app_usage([], 10, 100), [])
        self.assertEqual(vt.app_usage([(0, A, "A")], 100, 100), [])

    def test_slutet_klipper_en_pagaende_tjanst(self):
        self.assertEqual(vt.app_usage([(0, A, "A")], 10, 70), [{"url": A, "name": "A", "s": 60}])

    def test_noll_sekunder_utelamnas_och_taket_ar_36(self):
        ev = [(100, A, "A"), (100.2, B, "B")]
        self.assertEqual([a["url"] for a in vt.app_usage(ev, 100, 160)], [B])
        many = [(i, f"https://t{i}.example.se/", f"T{i}") for i in range(60)]
        self.assertEqual(len(vt.app_usage(many, 0, 60)), 36)

    def test_fil_med_skrap_och_andra_typer_ignoreras(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "u")
            with open(p, "w") as f:
                f.write('{"t": 5, "url": "https://a.example.se/", "name": "A"}\nskräp\n[1]\n{"t": "x", "url": "u", "name": "n"}\n{"t": true, "url": "u", "name": "n"}\n{"t": 9, "url": 1, "name": "n"}\n')
            self.assertEqual(vt.read_app_events(p, os.getuid()), [(5.0, "https://a.example.se/", "A")])
            self.assertEqual(vt.read_app_events(os.path.join(d, "saknas"), os.getuid()), [])

    def test_lanken_foljs_inte(self):
        with tempfile.TemporaryDirectory() as d:
            real = os.path.join(d, "real")
            open(real, "w").write('{"t": 1, "url": "https://a.example.se/", "name": "A"}\n')
            link = os.path.join(d, "link")
            os.symlink(real, link)
            self.assertEqual(vt.read_app_events(link, os.getuid()), [])

    def test_fifo_hardlank_fel_agare_och_stor_fil_ignoreras(self):
        row = '{"t": 1, "url": "https://a.example.se/", "name": "A"}\n'
        with tempfile.TemporaryDirectory() as d:
            me = os.getuid()
            ok = os.path.join(d, "ok")
            open(ok, "w").write(row)
            self.assertEqual(len(vt.read_app_events(ok, me)), 1)
            self.assertEqual(vt.read_app_events(ok, me + 1), [], "annan ägare")
            os.link(ok, os.path.join(d, "andra"))
            self.assertEqual(vt.read_app_events(ok, me), [], "hårda länkar")
            fifo = os.path.join(d, "fifo")
            os.mkfifo(fifo)
            self.assertEqual(vt.read_app_events(fifo, me), [], "fifo blockerar inte")
            big = os.path.join(d, "stor")
            open(big, "w").write(row * (vt.APP_USAGE_MAX_BYTES // len(row) + 10))
            self.assertEqual(vt.read_app_events(big, me), [], "för stor")

    def test_senaste_inmatning_skrivs_bara_till_kataloger_som_finns(self):
        with tempfile.TemporaryDirectory() as d:
            ok = os.path.join(d, "last-input")
            saknas = os.path.join(d, "ingen-katalog", "last-input")
            vt.write_last_input(1234.9, (ok, saknas))
            self.assertEqual(open(ok).read().strip(), "1234")
            self.assertFalse(os.path.exists(saknas))


if __name__ == "__main__":
    unittest.main()
