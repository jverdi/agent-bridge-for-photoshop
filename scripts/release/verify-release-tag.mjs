#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import process from "node:process";

const repoRoot = process.cwd();
const packageJsonPath = path.join(repoRoot, "package.json");
const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, "utf8"));

const packageVersion = String(packageJson.version || "").trim();
const rawTag = String(process.env.RELEASE_TAG || process.env.GITHUB_REF_NAME || "").trim();
const normalizedTag = rawTag.startsWith("v") ? rawTag.slice(1) : rawTag;

if (!rawTag) {
  console.error("release tag is required (RELEASE_TAG or GITHUB_REF_NAME)");
  process.exit(1);
}

if (!packageVersion) {
  console.error("package.json version is missing");
  process.exit(1);
}

if (normalizedTag !== packageVersion) {
  console.error(
    `release tag/version mismatch: tag=${rawTag} (normalized=${normalizedTag}) package.json=${packageVersion}`
  );
  process.exit(1);
}

console.log(`release tag matches package version: ${rawTag} -> ${packageVersion}`);
