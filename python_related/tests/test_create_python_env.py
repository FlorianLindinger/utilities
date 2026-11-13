"""Check embedded CUDA selection without running environment setup."""
import ast
import re
import subprocess
import unittest
from types import ModuleType
from pathlib import Path
from unittest.mock import Mock

SOURCE = Path(__file__).resolve().parents[1] / "create_python_env.bat"


class CudaSelectionTests(unittest.TestCase):
    def setUp(self):
        source = SOURCE.read_text(encoding="ascii")
        start = source.index("def has_nvidia_gpu():")
        end = source.index("def run_install(", start)
        self.runner = Mock()
        self.say = Mock()
        self.module = ModuleType("cuda_helpers")
        self.namespace = self.module.__dict__
        self.namespace.update({
            "re": re, "subprocess": self.runner, "say": self.say, "RED": "",
            "NVIDIA_ONLY_PACKAGES": re.compile(
                r"^(cupy(-cuda(\d+x)?)?|nvmath-python)$"
            ),
        })
        self.runner.SubprocessError = subprocess.SubprocessError
        exec(compile(ast.parse(source[start:end]), str(SOURCE), "exec"), self.namespace)

    def select(self, major, specs):
        self.namespace["nvidia_cuda_major"] = lambda: major
        return self.namespace["choose_cupy_build"](specs)

    def test_auto_uses_detected_major_and_preserves_constraints(self):
        for major in (11, 12, 13):
            with self.subTest(major=major):
                self.assertEqual(self.select(major, ["cupy-cuda[ctk]>=13", "numpy"]),
                                 [f"cupy-cuda{major}x[ctk]>=13", "numpy"])
        self.assertIn("cupy-cuda12x", str(self.say.call_args_list))

    def test_explicit_build_is_preserved(self):
        self.assertEqual(self.select(13, ["cupy-cuda12x==13.6", "cupy-cuda11x"]),
                         ["cupy-cuda12x==13.6", "cupy-cuda11x"])

    def test_unknown_or_old_driver_skips_auto_only(self):
        for major in (None, 10):
            with self.subTest(major=major):
                self.assertEqual(self.select(major, ["cupy-cuda", "numpy", "cupy-cuda12x"]),
                                 ["numpy", "cupy-cuda12x"])

    def test_normalized_name_and_package_boundary(self):
        self.assertEqual(self.select(13, ["CuPy_CUDA", "cupy-cuda-helper"]),
                         ["cupy-cuda13x", "cupy-cuda-helper"])

    def test_driver_output(self):
        for label in ("CUDA Version", "CUDA UMD Version"):
            self.runner.run.return_value = Mock(returncode=0, stdout=f"{label}: 13.2")
            self.assertEqual(self.namespace["nvidia_cuda_major"](), 13)
        self.runner.run.return_value = Mock(returncode=1, stdout="CUDA Version: 13.2")
        self.assertIsNone(self.namespace["nvidia_cuda_major"]())

    def test_missing_driver(self):
        self.runner.run.side_effect = FileNotFoundError
        self.assertIsNone(self.namespace["nvidia_cuda_major"]())

    def test_no_gpu_skips_auto_and_explicit_packages(self):
        self.namespace["has_nvidia_gpu"] = lambda: False
        self.assertEqual(self.namespace["select_packages_for_hardware"](
            ["cupy-cuda", "cupy-cuda12x", "numpy"]), ["numpy"])

    def test_real_package_classifier_accepts_auto_name(self):
        source = SOURCE.read_text(encoding="ascii")
        start = source.index("NVIDIA_ONLY_PACKAGES =")
        end = source.index("JsoncMember =", start)
        tree = ast.parse(source[start:end])
        assignment = next(node for node in tree.body if isinstance(node, ast.Assign)
                          and any(isinstance(t, ast.Name) and t.id == "NVIDIA_ONLY_PACKAGES"
                                  for t in node.targets))
        exec(compile(ast.Module(body=[assignment], type_ignores=[]), str(SOURCE), "exec"),
             self.namespace)
        self.assertTrue(self.namespace["needs_nvidia_gpu"]("cupy-cuda[ctk]>=13"))


if __name__ == "__main__":
    unittest.main()
