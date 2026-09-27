#!/usr/bin/env node

// Syncs SayItFlow Homebrew cask into the cloned homebrew-tap repository.
// Usage: TAP_DIR=/path/to/homebrew-tap node scripts/sync-cask.js

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const SOURCE = { owner: "innovatorved", repo: "sayItflow" };
const HOMEBREW = { cask: "sayitflow" };

const root = path.resolve(__dirname, "..");
const tapDir = process.env.TAP_DIR?.trim() || "";
const dmgPath = process.env.DMG_PATH?.trim() || path.join(root, "build", "SayItFlow.dmg");

if (!tapDir) {
  console.error("Set TAP_DIR to cloned homebrew-tap path.");
  process.exit(1);
}

if (!fs.existsSync(dmgPath)) {
  console.error(`DMG not found at ${dmgPath}`);
  process.exit(1);
}

const refName = (
  process.env.RELEASE_TAG?.trim() ||
  process.env.GITHUB_REF_NAME?.trim() ||
  ""
).trim();

let version = refName ? (refName.startsWith("v") ? refName.slice(1) : refName) : "";

if (!version) {
  try {
    const pbxproj = fs.readFileSync(path.join(root, "apps/macos/SayItFlow.xcodeproj/project.pbxproj"), "utf8");
    const m = pbxproj.match(/MARKETING_VERSION = ([0-9.]+);/);
    if (m) version = m[1];
  } catch {}
}

if (!version) {
  console.error("Could not determine version.");
  process.exit(1);
}

const sha256 = crypto
  .createHash("sha256")
  .update(fs.readFileSync(dmgPath))
  .digest("hex");

console.log(`Syncing sayitflow cask: version ${version}, sha256 ${sha256}`);

const caskPath = path.join(tapDir, "Casks", `${HOMEBREW.cask}.rb`);
fs.mkdirSync(path.dirname(caskPath), { recursive: true });

const contents = `# Synced from ${SOURCE.repo} release CI via scripts/sync-cask.js
cask "${HOMEBREW.cask}" do
  version "${version}"
  sha256 "${sha256}"

  url "https://github.com/${SOURCE.owner}/${SOURCE.repo}/releases/download/v#{version}/SayItFlow.dmg"
  name "SayItFlow"
  desc "100% on-device push-to-talk voice dictation for macOS"
  homepage "https://github.com/${SOURCE.owner}/${SOURCE.repo}"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "SayItFlow.app"

  postflight_steps do
    run "/usr/bin/xattr",
        args: ["-dr", "com.apple.quarantine", "{{appdir}}/SayItFlow.app"]
  end

  uninstall quit: "com.innovatorved.sayitflow"

  zap trash: [
    "~/Library/Application Support/com.innovatorved.sayitflow",
    "~/Library/Caches/com.innovatorved.sayitflow",
    "~/Library/Preferences/com.innovatorved.sayitflow.plist",
  ]

  caveats <<~EOS
    SayItFlow is distributed ad-hoc signed for Apple Silicon.
    This cask clears the macOS quarantine attribute on install so the app launches cleanly.

    If macOS still blocks it, run:

      xattr -dr com.apple.quarantine "/Applications/SayItFlow.app"

    Apple Silicon (arm64) only. Requires macOS Sonoma (14.0) or later.

    To update: \`brew update && brew upgrade --cask sayitflow\`
  EOS
end
`;

fs.writeFileSync(caskPath, contents, "utf8");
console.log(`Updated ${caskPath}`);
