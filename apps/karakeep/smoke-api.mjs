import assert from "node:assert/strict";
import { readFile, writeFile } from "node:fs/promises";
import { randomBytes } from "node:crypto";

const [base, phase, stateFile] = process.argv.slice(2);
const call = async (path, method = "GET", body, key) => {
  const response = await fetch(`${base}${path}`, {
    method,
    headers: { "content-type": "application/json", origin: base, ...(key ? { authorization: `Bearer ${key}` } : {}) },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  if (!response.ok) throw new Error(`${method} ${path}: ${response.status} ${(await response.text()).slice(0, 150)}`);
  return response.json();
};
if (phase === "seed") {
  assert.equal((await call("/api/health")).status, "ok");
  const account = { name: "Recovery Test", email: "recovery@example.com", password: randomBytes(24).toString("hex") };
  await call("/api/auth/sign-up/email", "POST", account);
  const exchanged = await call("/api/trpc/apiKeys.exchange", "POST", { json: { ...account, keyName: "recovery" } });
  const key = exchanged.result.data.json.key;
  assert.ok(key);
  const bookmark = await call("/api/v1/bookmarks", "POST", { type: "text", title: "Recovery checklist", text: "Keep the complete library and search index from the same stopped state.", favourited: true }, key);
  const png = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAAAKklEQVR4nGOwaYqnKWIYtWDUglELRi0YtWDUglELRi0YtWDUglELhooFAFUgdD1F9KL/AAAAAElFTkSuQmCC", "base64");
  const form = new FormData();
  form.append("file", new File([png], "recovery.png", { type: "image/png" }));
  const upload = await fetch(`${base}/api/v1/assets`, { method: "POST", headers: { authorization: `Bearer ${key}` }, body: form });
  assert.ok(upload.ok, `asset upload: ${upload.status}`);
  const asset = await upload.json();
  await call("/api/v1/bookmarks", "POST", { type: "asset", assetType: "image", assetId: asset.assetId, fileName: "recovery.png" }, key);
  let indexed = false;
  for (let attempt = 0; attempt < 60; attempt++) {
    const results = await call("/api/v1/bookmarks/search?q=Recovery", "GET", null, key);
    if (results.bookmarks.some((item) => item.id === bookmark.id)) { indexed = true; break; }
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
  assert.ok(indexed, "the note must be searchable before backup");
  await writeFile(stateFile, JSON.stringify({ account, bookmark, key, asset, png: png.toString("base64") }), { mode: 0o600 });
} else if (phase === "verify") {
  const { account, bookmark, key, asset, png } = JSON.parse(await readFile(stateFile, "utf8"));
  assert.equal((await call("/api/v1/users/me", "GET", null, key)).email, account.email);
  const saved = await call(`/api/v1/bookmarks/${bookmark.id}`, "GET", null, key);
  assert.equal(saved.title, bookmark.title);
  assert.equal(saved.content.text, bookmark.content.text);
  await call("/api/auth/sign-in/email", "POST", { email: account.email, password: account.password });
  const image = await fetch(`${base}/api/v1/assets/${asset.assetId}`, { headers: { authorization: `Bearer ${key}` } });
  assert.ok(image.ok, `restored asset: ${image.status}`);
  assert.equal(Buffer.from(await image.arrayBuffer()).toString("base64"), png);
  const results = await call("/api/v1/bookmarks/search?q=Recovery", "GET", null, key);
  assert.ok(results.bookmarks.some((item) => item.id === bookmark.id), "restored search index must find the note");
  const anonymous = await fetch(`${base}/api/v1/bookmarks/${bookmark.id}`);
  assert.equal(anonymous.status, 401);
} else if (phase === "closed") {
  const response = await fetch(`${base}/api/auth/sign-up/email`, { method: "POST", headers: { "content-type": "application/json", origin: base }, body: JSON.stringify({ name: "Blocked", email: "blocked@example.com", password: randomBytes(24).toString("hex") }) });
  assert.ok([400,403].includes(response.status), `registration unexpectedly returned ${response.status}`);
} else throw new Error(`Unknown phase ${phase}`);
console.log(`Karakeep API ${phase} passed`);
