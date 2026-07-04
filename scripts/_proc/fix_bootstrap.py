from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def fix_bootstrap(path):
    text = path.read_text(encoding="utf-8")
    text = re.sub(r"ctx\.(\w+) = ctx\.\1", r"\1 = ctx.\1", text)
    text = text.replace("ctx.graphics.", "graphics.")
    text = re.sub(
        r"function\(value\) unlockedPlotCount_ = value end",
        "ctx.setUnlockedPlotCount",
        text,
    )
    text = re.sub(
        r"function\(plotIndex\) unlockedPlotCount_ = count end",
        "ctx.setUnlockedPlotCount",
        text,
    )
    text = re.sub(
        r"ctx\.StartSinglePlotBounceAnimation\(unlockedPlotCount_\)",
        "ctx.StartSinglePlotBounceAnimation(ctx.getUnlockedPlotCount())",
        text,
    )
    text = re.sub(r"(\w+)\.ctx\.(\w+)", r"\1.\2", text)
    path.write_text(text, encoding="utf-8")
    print("fixed", path.name)


def fix_entry(path):
    text = path.read_text(encoding="utf-8")
    text = text.replace("ffunction Start()", "function Start()")
    path.write_text(text, encoding="utf-8")
    print("fixed", path.name)


if __name__ == "__main__":
    fix_bootstrap(ROOT / "runtime" / "server_bootstrap.lua")
    fix_bootstrap(ROOT / "runtime" / "client_bootstrap.lua")
    fix_entry(ROOT / "server_main.lua")
    fix_entry(ROOT / "main.lua")
