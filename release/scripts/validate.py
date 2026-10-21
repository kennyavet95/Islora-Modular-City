#!/usr/bin/env python3
"""Validate local release identity, schemes and store text limits; never uploads."""
import json
import plistlib
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

root = Path(__file__).resolve().parents[2]
release = root / "release"
config = json.loads((release / "release.json").read_text())
project = (root / config["project"] / "project.pbxproj").read_text()
assert project.count("PRODUCT_BUNDLE_IDENTIFIER = " + config["bundle_id"] + ";") == 2
assert project.count("PRODUCT_BUNDLE_IDENTIFIER = " + config["test_bundle_id"] + ";") == 2
assert 'INFOPLIST_KEY_CFBundleDisplayName = Islora;' in project
assert 'INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO;' in project
ET.parse(root / config["project"] / "xcshareddata/xcschemes" / (config["scheme"] + ".xcscheme"))
for locale in [config["primary_locale"], *config["additional_locales"]]:
    for field, limit in {"name": 30, "subtitle": 30, "promotional_text": 170,
                         "keywords": 100, "description": 4000, "release_notes": 4000}.items():
        value = (release / "metadata" / locale / (field + ".txt")).read_text().strip()
        assert value and len(value) <= limit, f"{locale}/{field}: {len(value)} > {limit}"
        assert "blockora" not in value.lower(), f"Old brand in {locale}/{field}"
        if field == "keywords":
            assert len(value.encode("utf-8")) <= 100, f"{locale}: keywords exceed 100 bytes"
        print(f"{locale}/{field}: {len(value)}/{limit}")
for field in ["review_notes", "testflight_description", "testflight_what_to_test"]:
    value = (release / "metadata" / (field + ".txt")).read_text().strip()
    assert value and len(value) <= 4000
if len(sys.argv) > 1:
    archive = Path(sys.argv[1])
    apps = list((archive / "Products/Applications").glob("*.app"))
    assert len(apps) == 1, "Expected one archived application"
    with (apps[0] / "Info.plist").open("rb") as source:
        info = plistlib.load(source)
    assert info["CFBundleIdentifier"] == config["bundle_id"]
    assert info["CFBundleDisplayName"] == config["display_name"]
    assert info["CFBundleShortVersionString"] == config["version"]
    assert info["ITSAppUsesNonExemptEncryption"] is False
    print("Archive identity and export declaration match release.json")
print("Local release checks passed. Registration, signing and submission are separate steps.")
