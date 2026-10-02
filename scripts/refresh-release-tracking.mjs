#!/usr/bin/env node
import { readdir, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";

const appsDirectory = process.argv[2] ?? "apps";
const apiBase = process.env.GITHUB_API_URL ?? "https://api.github.com";
const headers = {
  Accept: "application/vnd.github+json",
  "X-GitHub-Api-Version": "2022-11-28",
  ...(process.env.GITHUB_TOKEN ? { Authorization: `Bearer ${process.env.GITHUB_TOKEN}` } : {}),
};

function valueIn(section, key, indent = "  ") {
  return new RegExp(`^${indent}${key}:\\s*(.+?)\\s*$`, "m").exec(section)?.[1]?.replace(/^['"]|['"]$/g, "") ?? null;
}

function comparable(version) {
  const numbers = version.replace(/^v/i, "").split(".");
  return numbers.every((part) => /^\d+$/.test(part)) ? numbers.map(Number) : null;
}

export function compareVersions(left, right) {
  const a = comparable(left);
  const b = comparable(right);
  if (!a || !b) return null;
  const length = Math.max(a.length, b.length);
  for (let index = 0; index < length; index += 1) {
    const difference = (a[index] ?? 0) - (b[index] ?? 0);
    if (difference) return Math.sign(difference);
  }
  return 0;
}

function catalogVersion(recipeVersion, releaseTag) {
  return /^v/i.test(recipeVersion)
    ? releaseTag.replace(/^v/i, "v")
    : releaseTag.replace(/^v/i, "");
}

export function updateManifest(source, tagName, checkedAt) {
  const recipe = /^recipe:\n[\s\S]*?(?=^upstream:)/m.exec(source)?.[0];
  const upstream = /^upstream:\n[\s\S]*?(?=^update_tracking:)/m.exec(source)?.[0];
  if (!recipe || !upstream || valueIn(upstream, "release_source") !== "github") return null;
  const current = valueIn(recipe, "application_version");
  const repository = valueIn(upstream, "repository");
  const comparison = current ? compareVersions(current, tagName) : null;
  if (!repository || comparison === null) return null;
  const latestVersion = catalogVersion(current, tagName);
  const status = comparison < 0 ? "update_available" : "current";
  const release = /^update_tracking:\n[\s\S]*?^  releases:\n[\s\S]*?(?=^  \S|^\S)/m.exec(source)?.[0];
  const previousStatus = release ? valueIn(release, "status", "    ") : null;
  const previousVersion = release ? valueIn(release, "latest_version", "    ") : null;
  // A successful unchanged check is useful in the workflow log, but must not
  // create a daily metadata-only pull request.
  if (previousStatus === status && previousVersion === latestVersion) {
    return { repository, changed: false, source };
  }
  const replacement = `$1$2${status}$3\"${checkedAt}\"$4\"${latestVersion}\"`;
  const updated = source.replace(
    /(^update_tracking:\n[\s\S]*?^  releases:\n)(    status: )[^\n]+(\n    checked_at: )[^\n]+(\n    latest_version: )[^\n]+/m,
    replacement,
  );
  return updated === source ? { repository, changed: false, source } : { repository, changed: true, source: updated };
}

async function latestRelease(repository) {
  const response = await fetch(`${apiBase}/repos/${repository}/releases/latest`, { headers });
  if (!response.ok) throw new Error(`${repository}: GitHub returned ${response.status}`);
  const release = await response.json();
  if (!release.tag_name) throw new Error(`${repository}: latest release has no tag_name`);
  return release.tag_name;
}

async function main() {
  const checkedAt = new Date().toISOString();
  const directories = await readdir(appsDirectory, { withFileTypes: true });
  let changed = 0;
  const failures = [];
  for (const directory of directories.filter((entry) => entry.isDirectory()).sort((a, b) => a.name.localeCompare(b.name))) {
    const path = join(appsDirectory, directory.name, "manifest.yaml");
    const source = await readFile(path, "utf8");
    const upstream = /^upstream:\n[\s\S]*?(?=^update_tracking:)/m.exec(source)?.[0];
    if (!upstream || valueIn(upstream, "release_source") !== "github") continue;
    const repository = valueIn(upstream, "repository");
    if (!repository) continue;
    try {
      const result = updateManifest(source, await latestRelease(repository), checkedAt);
      if (!result) {
        failures.push(`${directory.name}: unsupported version format`);
      } else if (result.changed) {
        await writeFile(path, result.source);
        changed += 1;
        console.log(`${directory.name}: ${result.repository} updated`);
      }
    } catch (error) {
      failures.push(`${directory.name}: ${error.message}`);
    }
  }
  console.log(`Release tracking changed for ${changed} app(s).`);
  if (failures.length) throw new Error(`Release checks failed:\n${failures.join("\n")}`);
}

if (import.meta.main) main();
