"""Preserve existing Associated Domains metadata with pinned XcodeGen 2.46.0.

Its XcodeProj dependency stringifies nested target attributes. Normalize only
the known representation of our existing capability; reject unknown shapes.
This does not change entitlements, signing settings, or Apple account settings.
"""
from pathlib import Path
import re


SERIALIZED = r'SystemCapabilities = "[\"com.apple.AssociatedDomains\": [\"enabled\": 1]]";'
STRUCTURED = """SystemCapabilities = {
{indent}\tcom.apple.AssociatedDomains = {
{indent}\t\tenabled = 1;
{indent}\t};
{indent}};"""


def normalize(text):
    if text.count("SystemCapabilities =") != 1:
        raise ValueError("Expected exactly one existing SystemCapabilities attribute")
    match = re.search(r"(?m)^([ \t]*)" + re.escape(SERIALIZED) + r"$", text)
    if match:
        indent = match.group(1)
        # Use replacement strings directly, not regex escapes.
        fixed = STRUCTURED.replace("{indent}", indent)
        return text[:match.start()] + indent + fixed + text[match.end():]
    existing = r"SystemCapabilities\s*=\s*\{\s*com\.apple\.AssociatedDomains\s*=\s*\{\s*enabled\s*=\s*1;\s*\};\s*\};"
    if not re.search(existing, text):
        raise ValueError("Unrecognized capability metadata; review before regenerating")
    return text


if __name__ == "__main__":
    project = Path("DailyWhiskers.xcodeproj/project.pbxproj")
    original = project.read_text()
    updated = normalize(original)
    if updated != original:
        project.write_text(updated)
