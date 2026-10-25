import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { compareVersions, updateManifest } from "./refresh-release-tracking.mjs";

test("identical commit-suffixed releases are current without guessing their order", () => {
  assert.equal(compareVersions("2024.10.22-7ca5933", "v2024.10.22-7ca5933"), 0);
  assert.equal(compareVersions("2024.10.22-7ca5933", "v2024.10.22-abcdef0"), null);
});

test("an older maintenance release preserves the last known recipe release check", async () => {
  const source = await readFile(new URL("../apps/nextcloud/manifest.yaml", import.meta.url), "utf8");
  const result = updateManifest(source, "v33.0.10", "2026-10-25T14:00:00Z");
  assert.equal(result.changed, false);
  assert.equal(result.source, source);
});

test("a new upstream release preserves checks of the unchanged recipe", async () => {
  const source = await readFile(new URL("../apps/uptime-kuma/manifest.yaml", import.meta.url), "utf8");
  assert.match(source, /critical_vulnerabilities:\n    status: findings/);
  const result = updateManifest(source, "v99.0.0", "2026-10-25T14:00:00Z");
  assert.equal(result.changed, true);
  assert.match(result.source, /status: update_available/);
  assert.match(result.source, /latest_version: "99.0.0"/);
  assert.equal(result.source.slice(result.source.indexOf("  critical_vulnerabilities:")), source.slice(source.indexOf("  critical_vulnerabilities:")));
  assert.equal(result.source.split("update_tracking:")[0], source.split("update_tracking:")[0]);
  const repeated = updateManifest(result.source, "v99.0.0", "2026-10-26T14:00:00Z");
  assert.equal(repeated.changed, false);
  assert.equal(repeated.source, result.source);
});
