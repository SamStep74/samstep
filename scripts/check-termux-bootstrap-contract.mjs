#!/usr/bin/env node
import { lstatSync, readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const bootstrap = readFileSync(path.join(repoRoot, "bootstrap.sh"), "utf8");
const startServices = readFileSync(path.join(repoRoot, "start-services"), "utf8");
const readme = readFileSync(path.join(repoRoot, "README.md"), "utf8");

const errors = [];

function requireMatch(label, text, pattern) {
  if (!pattern.test(text)) errors.push(label);
}

function requireExecutable(label, relativePath) {
  const mode = statSync(path.join(repoRoot, relativePath)).mode;
  if ((mode & 0o111) === 0) errors.push(`${label} must be executable`);
}

function walkTextFiles(dir, prefix = "") {
  const entries = [];
  for (const name of readdirSync(dir)) {
    const relativePath = path.join(prefix, name);
    if (
      relativePath === ".git"
      || relativePath === "evals/karpathy/results"
      || relativePath.startsWith(`.git${path.sep}`)
      || relativePath.startsWith(`evals${path.sep}karpathy${path.sep}results${path.sep}`)
    ) {
      continue;
    }
    const fullPath = path.join(dir, name);
    const stats = lstatSync(fullPath);
    if (stats.isSymbolicLink()) continue;
    if (stats.isDirectory()) {
      entries.push(...walkTextFiles(fullPath, relativePath));
      continue;
    }
    if (stats.size > 256 * 1024) continue;
    const ext = path.extname(name);
    if (["", ".md", ".json", ".mjs", ".sh", ".txt"].includes(ext) || name.startsWith(".")) {
      entries.push({ relativePath, text: readFileSync(fullPath, "utf8") });
    }
  }
  return entries;
}

function stripCommentLines(text) {
  return text
    .split("\n")
    .filter((line) => !line.trimStart().startsWith("#"))
    .join("\n");
}

function requireGuardBeforeSideEffects(text) {
  const guardPattern = /^if \[ ! -d \/data\/data\/com\.termux \]; then\n\s+echo "This script must be run inside Termux\." >&2\n\s+exit 1\nfi$/m;
  const guardMatch = text.match(guardPattern);
  if (!guardMatch || guardMatch.index === undefined) {
    errors.push("bootstrap must guard Termux runtime before side effects");
    return;
  }

  const beforeGuard = text.slice(0, guardMatch.index);
  const allowedPreamble = beforeGuard
    .split("\n")
    .every((line) => {
      const trimmed = line.trim();
      return trimmed === ""
        || trimmed.startsWith("#!")
        || trimmed.startsWith("#")
        || trimmed === "set -eu";
    });
  if (!allowedPreamble) {
    errors.push("bootstrap must not run side effects before the Termux runtime guard");
  }
}

const secretSentinels = [
  { label: "github token", pattern: /\b(?:github_pat|gh[pousr])_[A-Za-z0-9_]{16,}/i },
  { label: "openai-style key", pattern: /\bsk-[A-Za-z0-9_-]{16,}/i },
  { label: "private ssh key", pattern: /-----BEGIN [A-Z ]*PRIVATE KEY-----/ },
  { label: "tailscale auth key", pattern: /\btskey-[A-Za-z0-9_-]{16,}/i },
  { label: "bearer token", pattern: /\bbearer\s+[-._~+/=a-z0-9]{16,}/i },
];

requireExecutable("bootstrap.sh", "bootstrap.sh");
requireExecutable("start-services", "start-services");

requireMatch("bootstrap must use Termux bash shebang", bootstrap, /^#!\/data\/data\/com\.termux\/files\/usr\/bin\/bash\n/);
requireMatch("bootstrap must fail on unset vars and command errors", bootstrap, /^set -eu$/m);
requireGuardBeforeSideEffects(bootstrap);
requireMatch("bootstrap must run apt noninteractively", bootstrap, /DEBIAN_FRONTEND=noninteractive/);
requireMatch("bootstrap must preserve new package config defaults safely", bootstrap, /--force-confnew/);
requireMatch("bootstrap must install openssh", bootstrap, /\$APT install\b[^\n]*\bopenssh\b/);
requireMatch("bootstrap must prepare .ssh directory", bootstrap, /mkdir -p ~\/\.ssh/);
requireMatch("bootstrap must chmod .ssh 700", bootstrap, /chmod 700 ~\/\.ssh/);
requireMatch("bootstrap must create authorized_keys", bootstrap, /touch ~\/\.ssh\/authorized_keys/);
requireMatch("bootstrap must chmod authorized_keys 600", bootstrap, /chmod 600 ~\/\.ssh\/authorized_keys/);
requireMatch("bootstrap must install Termux boot hook", bootstrap, /cp -f "\$\(dirname "\$0"\)\/start-services" ~\/\.termux\/boot\/start-services/);
requireMatch("bootstrap must chmod Termux boot hook executable", bootstrap, /chmod \+x ~\/\.termux\/boot\/start-services/);
requireMatch("bootstrap must start sshd", bootstrap, /(^|\n)sshd\n/);

requireMatch("start-services must use Termux sh shebang", startServices, /^#!\/data\/data\/com\.termux\/files\/usr\/bin\/sh\n/);
requireMatch("start-services must hold a wake lock", startServices, /(^|\n)termux-wake-lock\n/);
requireMatch("start-services must restart sshd cleanly", startServices, /pkill sshd 2>\/dev\/null/);
requireMatch("start-services must start sshd", startServices, /(^|\n)sshd\n?$/);

requireMatch("README must document Termux:Boot", readme, /Termux:Boot/);
requireMatch("README must document Tailscale remote access", readme, /Tailscale/);
requireMatch("README must document port 8022", readme, /\b8022\b/);
requireMatch("README must document authorized_keys", readme, /authorized_keys/);
requireMatch("README must document ColorOS battery whitelist", readme, /ColorOS battery whitelist/);

const scannedText = walkTextFiles(repoRoot)
  .map((entry) => `\n# file: ${entry.relativePath}\n${entry.text}`)
  .join("\n");
const leaked = secretSentinels.find((sentinel) => sentinel.pattern.test(scannedText));
if (leaked) errors.push(`secret sentinel leaked in Termux bootstrap files: ${leaked.label}`);
const uncommentedText = stripCommentLines(scannedText);
if (/\b(?:curl|wget)\b[^\n|]*\|\s*(?:(?:\/[^\s|]+\/)?(?:sh|bash)|(?:env|command)\s+(?:sh|bash)|\/data\/data\/com\.termux\/files\/usr\/bin\/(?:sh|bash))\b/.test(uncommentedText)) {
  errors.push("bootstrap must not pipe downloaded scripts into a shell");
}

console.log(`failing_checks=${errors.length ? 1 : 0}`);
if (errors.length) {
  console.error(`report_validation_error=${errors[0]}`);
}
process.exitCode = errors.length ? 1 : 0;
