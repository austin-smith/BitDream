"""Protect existing exports and retry behavior without launching Xcode or the app."""
import importlib.util
import pathlib
import tempfile
import unittest
from unittest import mock


SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "frame-screenshots.py"
SPEC = importlib.util.spec_from_file_location("framing", SCRIPT)
framing = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(framing)


class FramingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = pathlib.Path(self.temporary.name)
        self.staged = self.root / "staged"
        self.staged.mkdir()
        self.output = self.root / "framed"

    def test_existing_exports_require_explicit_replacement(self):
        self.output.mkdir()
        (self.output / "detail.png").write_bytes(b"original")
        (self.staged / "detail.png").write_bytes(b"replacement")
        with self.assertRaises(FileExistsError):
            framing.publish(self.staged, self.output)
        self.assertEqual((self.output / "detail.png").read_bytes(), b"original")

    def test_failed_publish_removes_partial_output_and_can_retry(self):
        (self.staged / "detail.png").write_bytes(b"complete")
        with mock.patch.object(framing.shutil, "copyfileobj", side_effect=OSError("disk full")):
            with self.assertRaises(OSError):
                framing.publish(self.staged, self.output)
        self.assertFalse(self.output.exists())
        self.assertFalse(list(self.root.glob(".framing-*")))
        framing.publish(self.staged, self.output)
        self.assertEqual((self.output / "detail.png").read_bytes(), b"complete")

    def test_failed_replacement_restores_entire_batch_and_other_devices(self):
        self.output.mkdir()
        original = {"a.png": b"old a", "b.json": b"old metadata", "other-device.png": b"unrelated"}
        for name, contents in original.items():
            (self.output / name).write_bytes(contents)
        for name in ("a.png", "b.json"):
            (self.staged / name).write_bytes(b"replacement")
        copy = framing.shutil.copyfileobj
        calls = 0

        def interrupt_second_copy(source, destination):
            nonlocal calls
            calls += 1
            if calls == 2:
                destination.write(b"partial")
                raise KeyboardInterrupt()
            copy(source, destination)

        with mock.patch.object(framing.shutil, "copyfileobj", side_effect=interrupt_second_copy):
            with self.assertRaises(KeyboardInterrupt):
                framing.publish(self.staged, self.output, replace=True)
        self.assertEqual({p.name: p.read_bytes() for p in self.output.iterdir()}, original)
        self.assertFalse(list(self.root.glob(".framing-*")))
        framing.publish(self.staged, self.output, replace=True)
        self.assertEqual((self.output / "other-device.png").read_bytes(), b"unrelated")
        self.assertEqual((self.output / "a.png").read_bytes(), b"replacement")

    def test_failed_render_publishes_nothing_and_can_retry(self):
        for name in ("frame.png", "template.psd", "srgb.icc", "detail-light.png", "detail-dark.png"):
            (self.root / name).write_bytes(b"fixture")
        args = [str(self.root), "--device", "iphone-18-pro", "--frame", str(self.root / "frame.png"),
                "--template", str(self.root / "template.psd"), "--screen", "detail"]

        def render(source, destination, *unused):
            destination.write_bytes(b"rendered")

        with mock.patch.object(framing, "SRGB", self.root / "srgb.icc"), \
                mock.patch.object(framing.shutil, "which", return_value="magick"), \
                mock.patch.object(framing.subprocess, "check_output", return_value="Version: ImageMagick 7.1.2\n"), \
                mock.patch.object(framing, "validate_assets"), \
                mock.patch.object(framing, "dimensions", return_value=(1206, 2622)):
            with mock.patch.object(framing, "render", side_effect=OSError("render failed")):
                with self.assertRaises(OSError):
                    framing.main(args)
            self.assertFalse(self.output.exists())
            self.assertFalse(list(self.root.glob(".framing-*")))
            with mock.patch.object(framing, "render", side_effect=render):
                framing.main(args)
        self.assertEqual({p.name for p in self.output.iterdir()}, {
            "detail-light-iphone-18-pro.png", "detail-dark-iphone-18-pro.png", "iphone-18-pro.json"})


if __name__ == "__main__":
    unittest.main()
