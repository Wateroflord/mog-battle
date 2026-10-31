"""Настраивает сгенерированный Android-проект Mog Battle: интернет, название, доступ к камере/галерее."""
import pathlib
import re

ROOT = pathlib.Path("android/app")
manifest = ROOT / "src/main/AndroidManifest.xml"
text = manifest.read_text(encoding="utf-8")

for p in ["android.permission.INTERNET"]:
    if p not in text:
        text = re.sub(r"(<manifest[^>]*>)", rf'\1\n    <uses-permission android:name="{p}"/>', text, count=1)

# Чтобы открывались камера и ссылки (Android 11+)
queries = (
    "        <intent>\n"
    '            <action android:name="android.media.action.IMAGE_CAPTURE"/>\n'
    "        </intent>\n"
    "        <intent>\n"
    '            <action android:name="android.intent.action.VIEW"/>\n'
    '            <data android:scheme="https"/>\n'
    "        </intent>\n"
)
if "IMAGE_CAPTURE" not in text:
    if "<queries>" in text:
        text = text.replace("<queries>", "<queries>\n" + queries.rstrip("\n"), 1)
    else:
        text = text.replace("</manifest>", "    <queries>\n" + queries + "    </queries>\n</manifest>")

text = re.sub(r'android:label="[^"]*"', 'android:label="Mog Battle"', text, count=1)
manifest.write_text(text, encoding="utf-8")
print(text)
