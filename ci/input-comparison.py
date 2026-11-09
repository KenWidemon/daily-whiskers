"""Isolated A/B harness; not production test logic. Exactly three iterations per arm."""
import os
from pathlib import Path
arm = os.environ["INPUT_ARM"]
if arm not in {"tap", "press150"}:
    raise SystemExit("Unknown arm")
changes = {
    "DailyWhiskersUITests/MischievousCardsTests.swift": ("            control.tap()", "            control.press(forDuration: 0.15)"),
    "DailyWhiskersUITests/ReminderUITests.swift": ("XCTAssertTrue(native.exists); native.tap()", "XCTAssertTrue(native.exists); native.press(forDuration: 0.15)"),
}
for filename, (old, new) in changes.items():
    path = Path(filename)
    text = path.read_text()
    if text.count(old) != 1:
        raise SystemExit(f"Unexpected input helper in {filename}")
    if arm == "press150":
        path.write_text(text.replace(old, new))
print(f"Input arm: {arm}; one action per requested transition; no retries")
