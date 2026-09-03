# Suivi sécurité — Solo & Communauté (Lots A, B, D) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give a Solo rider's trusted contact a live map of their position, and let up to 20 riders in a Community group see each other on the map — replacing the fake `SoloProvider.trackingUrl` and the never-wired `FirebaseGroupService` with a real self-hosted hub on the Hetzner server.

**Architecture:** A new, isolated Node/Express service (`moto-tracker`) runs on the existing Hetzner box behind its own nginx vhost and domain, storing sessions/members/positions in SQLite. The Flutter app talks to it over HTTPS: `SoloProvider` creates a solo session and uploads positions every 5 s; a public watch page (no login) shows the trusted contact a Leaflet map. `GroupProvider` is rewritten to use the same hub instead of Firebase, uploading every 3 s and polling peers every 3 s; `map_screen.dart` renders peer markers that fade after 30 s and disappear after 2 min.

**Tech Stack:** Server: Node 18, Express, `better-sqlite3`, `node:test` (no extra test deps). App: existing Flutter stack (`http`, `provider`, `flutter_foreground_task`, `flutter_map`) — no new Flutter dependencies. `firebase_core`, `firebase_database`, `firebase_auth` are removed.

**Spec:** `docs/superpowers/specs/2026-09-03-suivi-securite-personne-de-confiance-design.md` — this plan implements **Lots A, B and D only**. Lot C (chute et chaîne d'alerte) and Lot E (déjà fusionné) are out of scope.

## Deliberate deviations from the spec (documented, not oversights)

1. **`alert` table dropped; `alert_kind`/`alerted_at` columns on `session` instead.** The spec's `alert` table stores a `channels` JSON column that only Lot C's phone/email/SMS/voice channel chain would ever read. With Lot C out of scope, that table would be write-only and never read — exactly the "written but never called" trap flagged in this project's memory. Deadman/immobility state is instead recorded directly on `session.alerted_at` / `session.alert_kind`, which the watch page *does* read (to show "silencieux" / "alerte").
2. **`altitude` and `accuracy` are not stored server-side.** Nothing in Lots A/B/D reads them (the watch page shows position, trace, speed, last-seen; group markers show name/speed). `GpsSnapshot` still has them locally for the GPX recorder (lot 1); they just aren't part of the uplink payload.
3. **No `deadman_after` setting/slider is added.** The spec lists "Silence avant alerte homme mort" as a Lot C setting. Since Lot C isn't built, there's no UI to change it; the hub uses a fixed constant (`DEFAULT_DEADMAN_AFTER_SEC = 900`, 15 min) per solo session. Only `immobile_after` stays user-configurable, via the slider that already exists in `SoloScreen`.
4. **The `moto-tracker` container uses the `node:18` (Debian/glibc) image, not `node:18-alpine`.** `better-sqlite3` is a native addon; Alpine's musl libc means npm has to compile it from source (needs `python3 make g++`), which the sibling `rtmp-server` never needed because it has no native deps. Using `node:18` avoids the build-toolchain dance for one low-traffic container; disk headroom on the box (28 GB free per the spec) comfortably covers the larger image.
5. **`POST /api/sessions/:id/alert` from the spec's route table is not implemented.** It exists only to be called by Lot C's fall/SOS detection. Adding it now would be exactly the pattern this project's memory warns about (a route with no caller). It can be added when Lot C is planned.

## Global Constraints

- Flutter floor: `>=3.10.0` (pubspec `environment.flutter`) — no API introduced after that floor (e.g. keep using `.withOpacity()`, not `.withValues()`, per the existing project decision).
- No new Flutter dependencies. `http`, `provider`, `flutter_foreground_task`, `shared_preferences`, `latlong2`, `flutter_map`, `uuid`, `crypto` are already present and sufficient.
- Server dependencies limited to `express` and `better-sqlite3`. No test framework dependency — use Node's built-in `node:test` + `node:assert/strict`.
- Every networked Flutter service call must never throw past its own boundary — callers get `null`/`false`/`[]` on failure, matching the existing convention in `UpdateChecker.fetchLatest` and `AutoReplyService`.
- Position upload cadence: **5 s solo**, **3 s group** (spec §5.6). Both tolerate offline gaps by buffering and sending the backlog in one batch on the next successful tick.
- `watch_token`: 16 random URL-safe characters. `join_code`: 6 uppercase alphanumeric characters.
- Server domain: `motooffroad.duckdns.org`, internal port `3100`, directory `/root/moto-tracker` on the Hetzner box — fully separate from `/root/rtmp-server` (different Docker Compose project, different nginx vhost, different Git repo, different Let's Encrypt cert). Nothing under `/root/rtmp-server` is touched by this plan.
- GUI-producing tasks (the watch page, and any new/changed Flutter screen visuals) are flagged **[GUI — use impeccable skill]** in their title. When executing those tasks, invoke the `impeccable` skill for the visual/UX pass before considering the task done; the code in this plan gives a correct, functional baseline to refine, not a placeholder.

---

# Part 1 — Server: Lot A (hub de positions)

New repository: `barbarescomarc/moto-tracker-server` (private, mirroring the access pattern of `drone31-server`). All server tasks below assume the working directory is a fresh clone of this repo, created in Task 1.

### Task 1: Repo scaffold, SQLite schema, secrets, palette

**Files:**
- Create: `package.json`
- Create: `.gitignore`
- Create: `src/db.js`
- Create: `src/secrets.js`
- Create: `src/palette.js`
- Test: `test/db.test.js`
- Test: `test/secrets.test.js`

**Interfaces:**
- Produces: `openDb(path: string): Database` (from `src/db.js`) — opens (creating if needed) a `better-sqlite3` database and ensures the schema exists. Passing `':memory:'` gives an isolated in-memory DB for tests.
- Produces: `randomToken(length: number): string` and `randomJoinCode(): string` (from `src/secrets.js`).
- Produces: `colorForIndex(index: number): string` (from `src/palette.js`) — returns a hex color, cycling through a 20-color palette.

- [ ] **Step 1: Write the failing tests**

`test/db.test.js`:
```js
const test = require('node:test');
const assert = require('node:assert/strict');
const { openDb } = require('../src/db');

test('openDb creates the expected tables', () => {
  const db = openDb(':memory:');
  const tables = db
    .prepare("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
    .all()
    .map((r) => r.name);
  assert.deepEqual(tables, ['member', 'position', 'session']);
  db.close();
});

test('session row accepts solo and group kinds', () => {
  const db = openDb(':memory:');
  const now = Date.now();
  db.prepare(
    `INSERT INTO session (id, kind, owner_key, created_at, expires_at, immobile_after)
     VALUES (?, 'solo', 'ok', ?, ?, 1800)`
  ).run('s1', now, now + 3600000);
  db.prepare(
    `INSERT INTO session (id, kind, owner_key, created_at, expires_at)
     VALUES (?, 'group', 'ok', ?, ?)`
  ).run('s2', now, now + 3600000);
  const count = db.prepare('SELECT COUNT(*) AS n FROM session').get().n;
  assert.equal(count, 2);
  db.close();
});

test('position rows are capped at 500 per member by the app layer, not the schema', () => {
  // The cap is enforced in the positions route (Task 3), not a DB trigger —
  // this test only asserts the table has no artificial row limit itself.
  const db = openDb(':memory:');
  db.prepare(
    `INSERT INTO session (id, kind, owner_key, created_at, expires_at) VALUES ('s1','solo','ok',0,1)`
  ).run();
  db.prepare(
    `INSERT INTO member (id, session_id, device_key, name, color, joined_at, last_seen)
     VALUES ('m1','s1','dk','Pilote','#000',0,0)`
  ).run();
  const insert = db.prepare(
    `INSERT INTO position (session_id, member_id, lat, lng, recorded_at, received_at)
     VALUES ('s1','m1',?,?,?,?)`
  );
  for (let i = 0; i < 501; i++) insert.run(45, 5, i, i);
  const count = db.prepare('SELECT COUNT(*) AS n FROM position').get().n;
  assert.equal(count, 501);
  db.close();
});
```

`test/secrets.test.js`:
```js
const test = require('node:test');
const assert = require('node:assert/strict');
const { randomToken, randomJoinCode } = require('../src/secrets');

test('randomToken returns the requested length, url-safe', () => {
  const t = randomToken(16);
  assert.equal(t.length, 16);
  assert.match(t, /^[A-Za-z0-9_-]+$/);
});

test('randomToken values are not repeated across calls', () => {
  assert.notEqual(randomToken(16), randomToken(16));
});

test('randomJoinCode is 6 uppercase alphanumeric characters', () => {
  const c = randomJoinCode();
  assert.equal(c.length, 6);
  assert.match(c, /^[A-Z0-9]{6}$/);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npm test` (will fail: modules don't exist yet)
Expected: FAIL with "Cannot find module '../src/db'"

- [ ] **Step 3: Write the implementation**

`package.json`:
```json
{
  "name": "moto-tracker-server",
  "version": "1.0.0",
  "private": true,
  "engines": { "node": ">=18" },
  "scripts": {
    "start": "node src/server.js",
    "test": "node --test test/"
  },
  "dependencies": {
    "better-sqlite3": "^11.3.0",
    "express": "^4.19.2"
  }
}
```

`.gitignore`:
```
node_modules/
data/
*.db
```

`src/db.js`:
```js
const Database = require('better-sqlite3');

const SCHEMA = `
CREATE TABLE IF NOT EXISTS session (
  id             TEXT PRIMARY KEY,
  kind           TEXT NOT NULL CHECK (kind IN ('solo','group')),
  watch_token    TEXT UNIQUE,
  join_code      TEXT UNIQUE,
  owner_key      TEXT NOT NULL,
  created_at     INTEGER NOT NULL,
  expires_at     INTEGER NOT NULL,
  ended_at       INTEGER,
  deadman_after  INTEGER,
  immobile_after INTEGER,
  alerted_at     INTEGER,
  alert_kind     TEXT,
  rally_lat      REAL,
  rally_lng      REAL
);

CREATE TABLE IF NOT EXISTS member (
  id         TEXT PRIMARY KEY,
  session_id TEXT NOT NULL REFERENCES session(id) ON DELETE CASCADE,
  device_key TEXT NOT NULL,
  name       TEXT NOT NULL,
  color      TEXT NOT NULL,
  joined_at  INTEGER NOT NULL,
  last_seen  INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS position (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id  TEXT NOT NULL REFERENCES session(id) ON DELETE CASCADE,
  member_id   TEXT NOT NULL REFERENCES member(id) ON DELETE CASCADE,
  lat         REAL NOT NULL,
  lng         REAL NOT NULL,
  speed_kmh   REAL,
  heading     REAL,
  recorded_at INTEGER NOT NULL,
  received_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_position_member ON position(member_id, id);
CREATE INDEX IF NOT EXISTS idx_member_session ON member(session_id);
`;

function openDb(path) {
  const db = new Database(path);
  db.pragma('journal_mode = WAL');
  db.pragma('foreign_keys = ON');
  db.exec(SCHEMA);
  return db;
}

module.exports = { openDb };
```

`src/secrets.js`:
```js
const crypto = require('crypto');

function randomToken(length) {
  return crypto
    .randomBytes(length)
    .toString('base64url')
    .slice(0, length);
}

const JOIN_CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // sans 0/O/1/I

function randomJoinCode() {
  let code = '';
  const bytes = crypto.randomBytes(6);
  for (let i = 0; i < 6; i++) {
    code += JOIN_CODE_ALPHABET[bytes[i] % JOIN_CODE_ALPHABET.length];
  }
  return code;
}

module.exports = { randomToken, randomJoinCode };
```

`src/palette.js`:
```js
const PALETTE = [
  '#E8601C', '#1565C0', '#2E7D32', '#C62828', '#6A1B9A',
  '#00838F', '#F9A825', '#4E342E', '#546E7A', '#AD1457',
  '#00695C', '#EF6C00', '#283593', '#558B2F', '#D84315',
  '#4527A0', '#00ACC1', '#F4511E', '#3949AB', '#7CB342',
];

function colorForIndex(index) {
  return PALETTE[index % PALETTE.length];
}

module.exports = { colorForIndex, PALETTE };
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npm test`
Expected: PASS (all tests in `db.test.js` and `secrets.test.js`)

Note: `randomJoinCode`'s regex assertion `/^[A-Z0-9]{6}$/` holds because `JOIN_CODE_ALPHABET` is a subset of `[A-Z0-9]`.

- [ ] **Step 5: Commit**

```bash
git init
git add package.json .gitignore src/db.js src/secrets.js src/palette.js test/db.test.js test/secrets.test.js
git commit -m "feat: schema SQLite, secrets et palette du hub de positions"
```

---

### Task 2: Sessions — create and join

**Files:**
- Create: `src/routes/sessions.js`
- Test: `test/sessions.test.js`

**Interfaces:**
- Consumes: `openDb` (Task 1), `randomToken`/`randomJoinCode` (Task 1), `colorForIndex` (Task 1).
- Produces: `createSessionsRouter(db: Database): express.Router`, mounted at `/api/sessions` by `server.js` (Task 8). Routes added in this task:
  - `POST /` — body `{ kind: 'solo'|'group', name: string, immobileAfterSec?: number }` → `201 { sessionId, ownerKey, deviceKey, memberId, color, watchToken?, joinCode? }`
  - `POST /join/:joinCode` — body `{ name: string }` → `200 { sessionId, deviceKey, memberId, color }` or `404` if the code doesn't match an open group session.
- Later tasks (3, 4) attach more routes to the same router.

- [ ] **Step 1: Write the failing test**

`test/sessions.test.js`:
```js
const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const { openDb } = require('../src/db');
const { createSessionsRouter } = require('../src/routes/sessions');

function buildApp() {
  const db = openDb(':memory:');
  const app = express();
  app.use(express.json());
  app.use('/api/sessions', createSessionsRouter(db));
  return { app, db };
}

async function listen(app) {
  const server = app.listen(0);
  await new Promise((r) => server.once('listening', r));
  const port = server.address().port;
  return { server, base: `http://127.0.0.1:${port}` };
}

test('creating a solo session returns a watch token and no join code', async () => {
  const { app } = buildApp();
  const { server, base } = await listen(app);
  const res = await fetch(`${base}/api/sessions`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ kind: 'solo', name: 'Marc', immobileAfterSec: 1800 }),
  });
  const body = await res.json();
  assert.equal(res.status, 201);
  assert.ok(body.watchToken);
  assert.equal(body.joinCode, undefined);
  assert.ok(body.sessionId);
  assert.ok(body.ownerKey);
  assert.ok(body.deviceKey);
  assert.ok(body.memberId);
  server.close();
});

test('creating a group session returns a join code and no watch token', async () => {
  const { app } = buildApp();
  const { server, base } = await listen(app);
  const res = await fetch(`${base}/api/sessions`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ kind: 'group', name: 'Marc' }),
  });
  const body = await res.json();
  assert.equal(res.status, 201);
  assert.ok(body.joinCode);
  assert.equal(body.watchToken, undefined);
  server.close();
});

test('an invalid kind is rejected', async () => {
  const { app } = buildApp();
  const { server, base } = await listen(app);
  const res = await fetch(`${base}/api/sessions`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ kind: 'nope', name: 'Marc' }),
  });
  assert.equal(res.status, 400);
  server.close();
});

test('joining with a valid code adds a second member with a different color', async () => {
  const { app } = buildApp();
  const { server, base } = await listen(app);
  const created = await (
    await fetch(`${base}/api/sessions`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ kind: 'group', name: 'Marc' }),
    })
  ).json();

  const res = await fetch(`${base}/api/sessions/join/${created.joinCode}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ name: 'Claire' }),
  });
  const body = await res.json();
  assert.equal(res.status, 200);
  assert.equal(body.sessionId, created.sessionId);
  assert.notEqual(body.color, undefined);
  server.close();
});

test('joining with an unknown code returns 404', async () => {
  const { app } = buildApp();
  const { server, base } = await listen(app);
  const res = await fetch(`${base}/api/sessions/join/ZZZZZZ`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ name: 'Claire' }),
  });
  assert.equal(res.status, 404);
  server.close();
});

test('joining a solo session (by watch token, not a join code) returns 404', async () => {
  const { app } = buildApp();
  const { server, base } = await listen(app);
  const created = await (
    await fetch(`${base}/api/sessions`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ kind: 'solo', name: 'Marc' }),
    })
  ).json();
  const res = await fetch(`${base}/api/sessions/join/${created.watchToken}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ name: 'Claire' }),
  });
  assert.equal(res.status, 404);
  server.close();
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test`
Expected: FAIL with "Cannot find module '../src/routes/sessions'"

- [ ] **Step 3: Write the implementation**

`src/routes/sessions.js`:
```js
const express = require('express');
const crypto = require('crypto');
const { randomToken, randomJoinCode } = require('../secrets');
const { colorForIndex } = require('../palette');

const DEFAULT_DEADMAN_AFTER_SEC = 15 * 60;   // fixe — voir "Déviations" du plan
const DEFAULT_IMMOBILE_AFTER_SEC = 30 * 60;
const SESSION_TTL_MS = 12 * 60 * 60 * 1000;  // 12h, purgée par le balayage horaire sinon

function newId() {
  return crypto.randomUUID();
}

function createSessionsRouter(db) {
  const router = express.Router();

  router.post('/', (req, res) => {
    const { kind, name, immobileAfterSec } = req.body ?? {};
    if (kind !== 'solo' && kind !== 'group') {
      return res.status(400).json({ error: 'kind must be "solo" or "group"' });
    }
    if (typeof name !== 'string' || name.trim() === '') {
      return res.status(400).json({ error: 'name is required' });
    }

    const now = Date.now();
    const sessionId = newId();
    const ownerKey = randomToken(24);
    const deviceKey = randomToken(24);
    const memberId = newId();
    const watchToken = kind === 'solo' ? randomToken(16) : null;
    const joinCode = kind === 'group' ? randomJoinCode() : null;

    db.prepare(
      `INSERT INTO session
         (id, kind, watch_token, join_code, owner_key, created_at, expires_at,
          deadman_after, immobile_after)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
    ).run(
      sessionId, kind, watchToken, joinCode, ownerKey, now, now + SESSION_TTL_MS,
      kind === 'solo' ? DEFAULT_DEADMAN_AFTER_SEC : null,
      kind === 'solo' ? (immobileAfterSec ?? DEFAULT_IMMOBILE_AFTER_SEC) : null,
    );

    db.prepare(
      `INSERT INTO member (id, session_id, device_key, name, color, joined_at, last_seen)
       VALUES (?, ?, ?, ?, ?, ?, ?)`
    ).run(memberId, sessionId, deviceKey, name.trim(), colorForIndex(0), now, now);

    const body = { sessionId, ownerKey, deviceKey, memberId, color: colorForIndex(0) };
    if (watchToken) body.watchToken = watchToken;
    if (joinCode) body.joinCode = joinCode;
    res.status(201).json(body);
  });

  router.post('/join/:joinCode', (req, res) => {
    const { name } = req.body ?? {};
    if (typeof name !== 'string' || name.trim() === '') {
      return res.status(400).json({ error: 'name is required' });
    }

    const session = db
      .prepare(`SELECT * FROM session WHERE join_code = ? AND ended_at IS NULL`)
      .get(req.params.joinCode);
    if (!session) return res.status(404).json({ error: 'unknown or closed join code' });

    const now = Date.now();
    const memberId = newId();
    const deviceKey = randomToken(24);
    const memberCount = db
      .prepare('SELECT COUNT(*) AS n FROM member WHERE session_id = ?')
      .get(session.id).n;
    const color = colorForIndex(memberCount);

    db.prepare(
      `INSERT INTO member (id, session_id, device_key, name, color, joined_at, last_seen)
       VALUES (?, ?, ?, ?, ?, ?, ?)`
    ).run(memberId, session.id, deviceKey, name.trim(), color, now, now);

    res.status(200).json({ sessionId: session.id, deviceKey, memberId, color });
  });

  return router;
}

module.exports = { createSessionsRouter };
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test`
Expected: PASS (all tests in `sessions.test.js`, plus Task 1's tests still passing)

- [ ] **Step 5: Commit**

```bash
git add src/routes/sessions.js test/sessions.test.js
git commit -m "feat: creation et adhesion de session (solo/groupe)"
```

---

### Task 3: Positions upload, peers, rally point

**Files:**
- Modify: `src/routes/sessions.js` — add three routes to the router built in Task 2.
- Modify: `test/sessions.test.js` — add tests for the new routes.

**Interfaces:**
- Consumes: same router/db as Task 2.
- Produces (added to the `/api/sessions` router):
  - `POST /:id/positions` — body `{ deviceKey, memberId, points: [{ lat, lng, speedKmh?, heading?, recordedAt }] }` → `200 { accepted: number }`, `403` on bad `deviceKey`/`memberId`.
  - `GET /:id/peers` — query `?deviceKey=&memberId=` → `200 { peers: [{ memberId, name, color, lat, lng, speedKmh, lastSeen }], rally: { lat, lng } | null }`, excludes the caller's own `memberId`.
  - `POST /:id/rally` — body `{ deviceKey, lat, lng }` or `{ deviceKey, clear: true }` → `200 {}`.
  - A shared helper `_authMember(db, sessionId, deviceKey, memberId)` used by all three (and by Task 4's routes).

- [ ] **Step 1: Write the failing test**

Append to `test/sessions.test.js` (same file, new `test(...)` blocks — reuses `buildApp`/`listen` already defined there):
```js
test('uploading positions is rejected with a wrong device key', async () => {
  const { app } = buildApp();
  const { server, base } = await listen(app);
  const created = await (
    await fetch(`${base}/api/sessions`, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ kind: 'solo', name: 'Marc' }),
    })
  ).json();

  const res = await fetch(`${base}/api/sessions/${created.sessionId}/positions`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      deviceKey: 'wrong', memberId: created.memberId,
      points: [{ lat: 45.1, lng: 5.7, recordedAt: Date.now() }],
    }),
  });
  assert.equal(res.status, 403);
  server.close();
});

test('uploaded positions are accepted and capped at 500 per member', async () => {
  const { app } = buildApp();
  const { server, base } = await listen(app);
  const created = await (
    await fetch(`${base}/api/sessions`, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ kind: 'solo', name: 'Marc' }),
    })
  ).json();

  const points = Array.from({ length: 520 }, (_, i) => ({
    lat: 45 + i * 0.0001, lng: 5, recordedAt: Date.now() + i,
  }));
  const res = await fetch(`${base}/api/sessions/${created.sessionId}/positions`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ deviceKey: created.deviceKey, memberId: created.memberId, points }),
  });
  const body = await res.json();
  assert.equal(res.status, 200);
  assert.equal(body.accepted, 520);
  server.close();
});

test('peers excludes the caller and returns only fresh members', async () => {
  const { app } = buildApp();
  const { server, base } = await listen(app);
  const owner = await (
    await fetch(`${base}/api/sessions`, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ kind: 'group', name: 'Marc' }),
    })
  ).json();
  const joiner = await (
    await fetch(`${base}/api/sessions/join/${owner.joinCode}`, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ name: 'Claire' }),
    })
  ).json();
  await fetch(`${base}/api/sessions/${owner.sessionId}/positions`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      deviceKey: joiner.deviceKey, memberId: joiner.memberId,
      points: [{ lat: 45.2, lng: 5.8, speedKmh: 42, recordedAt: Date.now() }],
    }),
  });

  const res = await fetch(
    `${base}/api/sessions/${owner.sessionId}/peers?deviceKey=${owner.deviceKey}&memberId=${owner.memberId}`
  );
  const body = await res.json();
  assert.equal(res.status, 200);
  assert.equal(body.peers.length, 1);
  assert.equal(body.peers[0].memberId, joiner.memberId);
  assert.equal(body.peers[0].name, 'Claire');
  assert.equal(body.peers[0].speedKmh, 42);
  assert.equal(body.rally, null);
  server.close();
});

test('rally point is set and cleared, visible to peers', async () => {
  const { app } = buildApp();
  const { server, base } = await listen(app);
  const owner = await (
    await fetch(`${base}/api/sessions`, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ kind: 'group', name: 'Marc' }),
    })
  ).json();

  await fetch(`${base}/api/sessions/${owner.sessionId}/rally`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ deviceKey: owner.deviceKey, lat: 45.5, lng: 6.1 }),
  });
  let peers = await (
    await fetch(`${base}/api/sessions/${owner.sessionId}/peers?deviceKey=${owner.deviceKey}&memberId=${owner.memberId}`)
  ).json();
  assert.deepEqual(peers.rally, { lat: 45.5, lng: 6.1 });

  await fetch(`${base}/api/sessions/${owner.sessionId}/rally`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ deviceKey: owner.deviceKey, clear: true }),
  });
  peers = await (
    await fetch(`${base}/api/sessions/${owner.sessionId}/peers?deviceKey=${owner.deviceKey}&memberId=${owner.memberId}`)
  ).json();
  assert.equal(peers.rally, null);
  server.close();
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test`
Expected: FAIL — routes `/positions`, `/peers`, `/rally` return 404 (not yet defined)

- [ ] **Step 3: Write the implementation**

Insert into `src/routes/sessions.js`, just above `return router;` (still inside `createSessionsRouter`):
```js
  function authMember(sessionId, deviceKey, memberId) {
    return db
      .prepare(
        `SELECT member.id, member.session_id FROM member
         JOIN session ON session.id = member.session_id
         WHERE member.id = ? AND member.device_key = ? AND member.session_id = ?
           AND session.ended_at IS NULL`
      )
      .get(memberId, deviceKey, sessionId);
  }

  router.post('/:id/positions', (req, res) => {
    const { deviceKey, memberId, points } = req.body ?? {};
    const member = authMember(req.params.id, deviceKey, memberId);
    if (!member) return res.status(403).json({ error: 'invalid credentials' });
    if (!Array.isArray(points) || points.length === 0) {
      return res.status(400).json({ error: 'points must be a non-empty array' });
    }

    const now = Date.now();
    const insert = db.prepare(
      `INSERT INTO position (session_id, member_id, lat, lng, speed_kmh, heading, recorded_at, received_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
    );
    const trim = db.prepare(
      `DELETE FROM position WHERE member_id = ? AND id NOT IN (
         SELECT id FROM position WHERE member_id = ? ORDER BY id DESC LIMIT 500
       )`
    );

    const tx = db.transaction((pts) => {
      for (const p of pts) {
        insert.run(req.params.id, memberId, p.lat, p.lng, p.speedKmh ?? null, p.heading ?? null, p.recordedAt, now);
      }
      trim.run(memberId, memberId);
      db.prepare('UPDATE member SET last_seen = ? WHERE id = ?').run(now, memberId);
    });
    tx(points);

    res.status(200).json({ accepted: points.length });
  });

  router.get('/:id/peers', (req, res) => {
    const { deviceKey, memberId } = req.query;
    const member = authMember(req.params.id, deviceKey, memberId);
    if (!member) return res.status(403).json({ error: 'invalid credentials' });

    const peers = db
      .prepare(
        `SELECT m.id AS memberId, m.name, m.color, m.last_seen AS lastSeen,
                p.lat, p.lng, p.speed_kmh AS speedKmh
         FROM member m
         LEFT JOIN position p ON p.id = (
           SELECT id FROM position WHERE member_id = m.id ORDER BY id DESC LIMIT 1
         )
         WHERE m.session_id = ? AND m.id != ?`
      )
      .all(req.params.id, memberId);

    const session = db.prepare('SELECT rally_lat, rally_lng FROM session WHERE id = ?').get(req.params.id);
    const rally = session?.rally_lat != null ? { lat: session.rally_lat, lng: session.rally_lng } : null;

    res.status(200).json({ peers, rally });
  });

  router.post('/:id/rally', (req, res) => {
    const { deviceKey, lat, lng, clear } = req.body ?? {};
    const member = db
      .prepare(
        `SELECT member.id FROM member
         JOIN session ON session.id = member.session_id
         WHERE member.session_id = ? AND member.device_key = ? AND session.ended_at IS NULL`
      )
      .get(req.params.id, deviceKey);
    if (!member) return res.status(403).json({ error: 'invalid credentials' });

    if (clear) {
      db.prepare('UPDATE session SET rally_lat = NULL, rally_lng = NULL WHERE id = ?').run(req.params.id);
    } else {
      db.prepare('UPDATE session SET rally_lat = ?, rally_lng = ? WHERE id = ?').run(lat, lng, req.params.id);
    }
    res.status(200).json({});
  });
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test`
Expected: PASS (all tests in `sessions.test.js`)

- [ ] **Step 5: Commit**

```bash
git add src/routes/sessions.js test/sessions.test.js
git commit -m "feat: upload de positions, peers et point de ralliement"
```

---

### Task 4: Leave group, end session (purge or 7-day retention)

**Files:**
- Modify: `src/routes/sessions.js` — add two routes.
- Modify: `test/sessions.test.js` — add tests.

**Interfaces:**
- Produces (added to the `/api/sessions` router):
  - `DELETE /:id/members/:memberId` — body `{ deviceKey }` → `200 {}`; removes the member and their positions (`ON DELETE CASCADE` handles positions).
  - `POST /:id/end` — body `{ ownerKey }` → `200 {}`; sets `ended_at`. If `alerted_at IS NULL`, deletes members/positions/session immediately. Otherwise leaves rows in place for the hourly sweep (Task 7) to purge after 7 days.

- [ ] **Step 1: Write the failing test**

Append to `test/sessions.test.js`:
```js
test('a member can leave a group without ending it', async () => {
  const { app, db } = buildApp();
  const { server, base } = await listen(app);
  const owner = await (
    await fetch(`${base}/api/sessions`, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ kind: 'group', name: 'Marc' }),
    })
  ).json();
  const joiner = await (
    await fetch(`${base}/api/sessions/join/${owner.joinCode}`, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ name: 'Claire' }),
    })
  ).json();

  const res = await fetch(`${base}/api/sessions/${owner.sessionId}/members/${joiner.memberId}`, {
    method: 'DELETE', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ deviceKey: joiner.deviceKey }),
  });
  assert.equal(res.status, 200);
  const remaining = db.prepare('SELECT COUNT(*) AS n FROM member WHERE session_id = ?').get(owner.sessionId).n;
  assert.equal(remaining, 1);
  server.close();
});

test('ending a session with no alert purges everything immediately', async () => {
  const { app, db } = buildApp();
  const { server, base } = await listen(app);
  const owner = await (
    await fetch(`${base}/api/sessions`, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ kind: 'solo', name: 'Marc' }),
    })
  ).json();

  const res = await fetch(`${base}/api/sessions/${owner.sessionId}/end`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ ownerKey: owner.ownerKey }),
  });
  assert.equal(res.status, 200);
  const session = db.prepare('SELECT * FROM session WHERE id = ?').get(owner.sessionId);
  assert.equal(session, undefined);
  server.close();
});

test('ending an alerted session keeps rows for later retention cleanup', async () => {
  const { app, db } = buildApp();
  const { server, base } = await listen(app);
  const owner = await (
    await fetch(`${base}/api/sessions`, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ kind: 'solo', name: 'Marc' }),
    })
  ).json();
  db.prepare('UPDATE session SET alerted_at = ?, alert_kind = ? WHERE id = ?')
    .run(Date.now(), 'deadman', owner.sessionId);

  const res = await fetch(`${base}/api/sessions/${owner.sessionId}/end`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ ownerKey: owner.ownerKey }),
  });
  assert.equal(res.status, 200);
  const session = db.prepare('SELECT * FROM session WHERE id = ?').get(owner.sessionId);
  assert.ok(session);
  assert.ok(session.ended_at);
  server.close();
});

test('ending with the wrong owner key is rejected', async () => {
  const { app } = buildApp();
  const { server, base } = await listen(app);
  const owner = await (
    await fetch(`${base}/api/sessions`, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ kind: 'solo', name: 'Marc' }),
    })
  ).json();
  const res = await fetch(`${base}/api/sessions/${owner.sessionId}/end`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ ownerKey: 'wrong' }),
  });
  assert.equal(res.status, 403);
  server.close();
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test`
Expected: FAIL — 404 on the new routes

- [ ] **Step 3: Write the implementation**

Insert into `src/routes/sessions.js`, just above `return router;`:
```js
  router.delete('/:id/members/:memberId', (req, res) => {
    const { deviceKey } = req.body ?? {};
    const member = authMember(req.params.id, deviceKey, req.params.memberId);
    if (!member) return res.status(403).json({ error: 'invalid credentials' });
    db.prepare('DELETE FROM member WHERE id = ?').run(req.params.memberId);
    res.status(200).json({});
  });

  router.post('/:id/end', (req, res) => {
    const { ownerKey } = req.body ?? {};
    const session = db
      .prepare('SELECT * FROM session WHERE id = ? AND owner_key = ?')
      .get(req.params.id, ownerKey);
    if (!session) return res.status(403).json({ error: 'invalid credentials' });

    if (session.alerted_at == null) {
      db.prepare('DELETE FROM session WHERE id = ?').run(req.params.id); // cascades member+position
    } else {
      db.prepare('UPDATE session SET ended_at = ? WHERE id = ?').run(Date.now(), req.params.id);
    }
    res.status(200).json({});
  });
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test`
Expected: PASS (all tests in `sessions.test.js`)

- [ ] **Step 5: Commit**

```bash
git add src/routes/sessions.js test/sessions.test.js
git commit -m "feat: quitter un groupe et cloturer une session (purge ou retention 7j)"
```

---

### Task 5: Watch endpoints (JSON state + SSE)

**Files:**
- Create: `src/routes/watch.js`
- Test: `test/watch.test.js`

**Interfaces:**
- Consumes: `openDb` (Task 1).
- Produces: `createWatchRouter(db: Database): express.Router`, mounted at `/` by `server.js` (Task 8). Routes:
  - `GET /api/watch/:watchToken` → `200 { name, lastPoint: {lat,lng,speedKmh,recordedAt}|null, track: [{lat,lng}], state: 'active'|'silent'|'alert', silentForSec: number }`, `404` for an unknown token.
  - `GET /api/watch/:watchToken/stream` → SSE; writes one `data: <json>` event immediately (same shape as the JSON endpoint) and one every 3 s while the connection is open.
- Shared helper `buildWatchState(db, watchToken)` returns the JSON payload or `null`, used by both routes.

- [ ] **Step 1: Write the failing test**

`test/watch.test.js`:
```js
const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const { openDb } = require('../src/db');
const { createSessionsRouter } = require('../src/routes/sessions');
const { createWatchRouter } = require('../src/routes/watch');

function buildApp() {
  const db = openDb(':memory:');
  const app = express();
  app.use(express.json());
  app.use('/api/sessions', createSessionsRouter(db));
  app.use('/', createWatchRouter(db));
  return { app, db };
}

async function listen(app) {
  const server = app.listen(0);
  await new Promise((r) => server.once('listening', r));
  return { server, base: `http://127.0.0.1:${server.address().port}` };
}

test('unknown watch token returns 404', async () => {
  const { app } = buildApp();
  const { server, base } = await listen(app);
  const res = await fetch(`${base}/api/watch/doesnotexist`);
  assert.equal(res.status, 404);
  server.close();
});

test('a fresh solo session with no positions is "active" with a null last point', async () => {
  const { app } = buildApp();
  const { server, base } = await listen(app);
  const created = await (
    await fetch(`${base}/api/sessions`, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ kind: 'solo', name: 'Marc' }),
    })
  ).json();

  const res = await fetch(`${base}/api/watch/${created.watchToken}`);
  const body = await res.json();
  assert.equal(res.status, 200);
  assert.equal(body.name, 'Marc');
  assert.equal(body.lastPoint, null);
  assert.equal(body.state, 'active');
  server.close();
});

test('a session with a recent position reports it and stays active', async () => {
  const { app } = buildApp();
  const { server, base } = await listen(app);
  const created = await (
    await fetch(`${base}/api/sessions`, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ kind: 'solo', name: 'Marc' }),
    })
  ).json();
  await fetch(`${base}/api/sessions/${created.sessionId}/positions`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      deviceKey: created.deviceKey, memberId: created.memberId,
      points: [{ lat: 45.1, lng: 5.9, speedKmh: 30, recordedAt: Date.now() }],
    }),
  });

  const res = await fetch(`${base}/api/watch/${created.watchToken}`);
  const body = await res.json();
  assert.equal(body.lastPoint.lat, 45.1);
  assert.equal(body.lastPoint.speedKmh, 30);
  assert.equal(body.state, 'active');
  assert.equal(body.track.length, 1);
  server.close();
});

test('an alerted session reports state alert', async () => {
  const { app, db } = buildApp();
  const { server, base } = await listen(app);
  const created = await (
    await fetch(`${base}/api/sessions`, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ kind: 'solo', name: 'Marc' }),
    })
  ).json();
  db.prepare('UPDATE session SET alerted_at = ? WHERE id = ?').run(Date.now(), created.sessionId);

  const res = await fetch(`${base}/api/watch/${created.watchToken}`);
  const body = await res.json();
  assert.equal(body.state, 'alert');
  server.close();
});

test('the SSE stream sends one event immediately on connect', async () => {
  const { app } = buildApp();
  const { server, base } = await listen(app);
  const created = await (
    await fetch(`${base}/api/sessions`, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ kind: 'solo', name: 'Marc' }),
    })
  ).json();

  const controller = new AbortController();
  const res = await fetch(`${base}/api/watch/${created.watchToken}/stream`, {
    signal: controller.signal,
  });
  assert.equal(res.headers.get('content-type'), 'text/event-stream');
  const reader = res.body.getReader();
  const { value } = await reader.read();
  const text = Buffer.from(value).toString('utf8');
  assert.match(text, /^data: /);
  const json = JSON.parse(text.replace(/^data: /, '').trim());
  assert.equal(json.name, 'Marc');
  controller.abort();
  server.close();
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test`
Expected: FAIL with "Cannot find module '../src/routes/watch'"

- [ ] **Step 3: Write the implementation**

`src/routes/watch.js`:
```js
const express = require('express');

function buildWatchState(db, watchToken) {
  const session = db.prepare('SELECT * FROM session WHERE watch_token = ?').get(watchToken);
  if (!session) return null;

  const member = db.prepare('SELECT * FROM member WHERE session_id = ? LIMIT 1').get(session.id);
  const track = db
    .prepare('SELECT lat, lng FROM position WHERE session_id = ? ORDER BY id ASC')
    .all(session.id);
  const last = db
    .prepare('SELECT lat, lng, speed_kmh AS speedKmh, recorded_at AS recordedAt FROM position WHERE session_id = ? ORDER BY id DESC LIMIT 1')
    .get(session.id);

  let state = 'active';
  let silentForSec = 0;
  if (session.alerted_at != null) {
    state = 'alert';
  } else if (last) {
    silentForSec = Math.floor((Date.now() - last.recordedAt) / 1000);
    if (session.deadman_after && silentForSec >= session.deadman_after) state = 'silent';
  }

  return {
    name: member?.name ?? 'Pilote',
    lastPoint: last ?? null,
    track,
    state,
    silentForSec,
  };
}

function createWatchRouter(db) {
  const router = express.Router();

  router.get('/api/watch/:watchToken', (req, res) => {
    const state = buildWatchState(db, req.params.watchToken);
    if (!state) return res.status(404).json({ error: 'unknown watch token' });
    res.status(200).json(state);
  });

  router.get('/api/watch/:watchToken/stream', (req, res) => {
    const initial = buildWatchState(db, req.params.watchToken);
    if (!initial) return res.status(404).json({ error: 'unknown watch token' });

    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      Connection: 'keep-alive',
    });
    res.write(`data: ${JSON.stringify(initial)}\n\n`);

    const timer = setInterval(() => {
      const state = buildWatchState(db, req.params.watchToken);
      if (!state) return clearInterval(timer);
      res.write(`data: ${JSON.stringify(state)}\n\n`);
    }, 3000);

    req.on('close', () => clearInterval(timer));
  });

  router.get('/s/:watchToken', (req, res, next) => next()); // servi en statique, Task 6

  return router;
}

module.exports = { createWatchRouter, buildWatchState };
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test`
Expected: PASS (all tests in `watch.test.js`)

- [ ] **Step 5: Commit**

```bash
git add src/routes/watch.js test/watch.test.js
git commit -m "feat: etat JSON et flux SSE de la page de suivi"
```

---

### Task 6: Watch page **[GUI — use impeccable skill]**

**Files:**
- Create: `public/watch.html`
- Create: `public/watch.js`
- Create: `public/watch.css`
- Modify: `src/server.js` — not created until Task 8; this task's static-serving wiring is verified there. This task itself only produces the static files plus a standalone manual check.

**Interfaces:**
- Produces: a self-contained page that, given a `?t=<watchToken>` query string (server rewrites `/s/:watchToken` to serve this file — wired in Task 8), fetches `/api/watch/:watchToken/stream` and renders: last point, trace polyline, speed, last-seen time, and a state banner (`active` / `silent` / `alert`, red banner + "Appeler" button on `alert`).
- Consumes: Leaflet + OpenStreetMap tiles, loaded from a CDN (no build step — this is a static page served by Express, not part of the Flutter app).

- [ ] **Step 1: There is no automated test for this task.**

A static HTML/CSS/JS page with no build step has nothing a `node:test` run can meaningfully assert beyond "the files exist," which the deploy smoke-check (Task 9) already covers by loading the live URL. Verification here is manual: open the file in a browser via a local static server and confirm it renders against a real running instance of Tasks 1–5 (see Step 3).

- [ ] **Step 2: Write the page**

`public/watch.html`:
```html
<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Suivi — Moto Offroad 4x4</title>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css">
<link rel="stylesheet" href="/watch.css">
</head>
<body>
  <div id="banner" class="banner" hidden></div>
  <div id="map"></div>
  <div id="panel">
    <div id="riderName">—</div>
    <div id="statusLine">Connexion…</div>
    <div id="speedLine"></div>
  </div>
  <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
  <script src="/watch.js"></script>
</body>
</html>
```

`public/watch.css`:
```css
:root { color-scheme: dark; }
html, body { margin: 0; height: 100%; background: #0D1117; font-family: system-ui, sans-serif; }
#map { position: absolute; inset: 0; }
#panel {
  position: absolute; left: 12px; right: 12px; bottom: 12px; z-index: 1000;
  background: rgba(18, 18, 31, 0.92); border: 1px solid #2A2A3E; border-radius: 12px;
  padding: 14px 16px; color: #fff; box-shadow: 0 4px 16px rgba(0,0,0,.4);
}
#riderName { font-size: 18px; font-weight: 700; }
#statusLine { font-size: 13px; color: #9E9E9E; margin-top: 4px; }
#speedLine { font-size: 13px; color: #4CAF50; margin-top: 2px; }
.banner {
  position: absolute; top: 0; left: 0; right: 0; z-index: 1100;
  background: #C62828; color: #fff; text-align: center; padding: 10px;
  font-weight: 700; display: flex; align-items: center; justify-content: center; gap: 12px;
}
.banner a {
  background: #fff; color: #C62828; padding: 6px 14px; border-radius: 8px;
  text-decoration: none; font-weight: 700;
}
```

`public/watch.js`:
```js
const params = new URLSearchParams(location.search);
const token = params.get('t');

const map = L.map('map', { zoomControl: true }).setView([46.6, 2.5], 5);
L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
  attribution: '&copy; OpenStreetMap',
  maxZoom: 19,
}).addTo(map);

const trace = L.polyline([], { color: '#E8601C', weight: 3.5 }).addTo(map);
let marker = null;
let hasCentered = false;

function riderIcon() {
  return L.divIcon({
    className: '',
    html: '<div style="width:20px;height:20px;border-radius:50%;background:#1565C0;border:2.5px solid #fff;box-shadow:0 0 8px rgba(21,101,192,.6)"></div>',
    iconSize: [20, 20],
  });
}

function render(state) {
  document.getElementById('riderName').textContent = state.name;

  const banner = document.getElementById('banner');
  if (state.state === 'alert') {
    banner.hidden = false;
    banner.innerHTML = '⚠️ Alerte déclenchée <a href="tel:">Appeler</a>';
  } else {
    banner.hidden = true;
  }

  const statusText = {
    active: 'En route',
    silent: `Silencieux depuis ${Math.floor(state.silentForSec / 60)} min`,
    alert: 'ALERTE',
  }[state.state];
  document.getElementById('statusLine').textContent = statusText;

  if (state.lastPoint) {
    document.getElementById('speedLine').textContent = `${Math.round(state.lastPoint.speedKmh ?? 0)} km/h`;
    const latlng = [state.lastPoint.lat, state.lastPoint.lng];
    if (!marker) marker = L.marker(latlng, { icon: riderIcon() }).addTo(map);
    else marker.setLatLng(latlng);
    if (!hasCentered) { map.setView(latlng, 14); hasCentered = true; }
  }

  if (state.track.length > 1) {
    trace.setLatLngs(state.track.map((p) => [p.lat, p.lng]));
  }
}

if (!token) {
  document.getElementById('statusLine').textContent = 'Lien invalide.';
} else {
  const source = new EventSource(`/api/watch/${token}/stream`);
  source.onmessage = (ev) => render(JSON.parse(ev.data));
  source.onerror = () => {
    document.getElementById('statusLine').textContent = 'Connexion perdue — nouvelle tentative…';
  };
}
```

- [ ] **Step 3: Manual verification**

```bash
node src/server.js &   # nécessite Task 8 terminée pour que /s/:watchToken serve ce fichier
# créer une session solo via curl (Task 2), envoyer un point (Task 3),
# ouvrir http://localhost:3100/s/<watchToken> dans un navigateur
# et vérifier que le point, la trace et l'état s'affichent.
kill %1
```

- [ ] **Step 4: Apply the impeccable skill**

Invoke the `impeccable` skill against `public/watch.html`/`watch.css`/`watch.js` to review and refine hierarchy, spacing, the alert banner's urgency, and the offline/loading states, keeping the dark palette consistent with `lib/app/theme.dart`'s `AppColors` (already used above: `#0D1117`, `#E8601C`, `#1565C0`, `#C62828`, `#4CAF50`).

- [ ] **Step 5: Commit**

```bash
git add public/watch.html public/watch.css public/watch.js
git commit -m "feat: page web de suivi pour la personne de confiance"
```

---

### Task 7: Deadman/immobility sweep + hourly purge

**Files:**
- Create: `src/sweep.js`
- Test: `test/sweep.test.js`

**Interfaces:**
- Produces: `checkDeadmanAndImmobility(db: Database, now: number): void` and `purgeExpired(db: Database, now: number): void` — both pure functions of `(db, now)` so tests don't need to fake timers; `startSweeps(db: Database): { stop(): void }` wires them to `setInterval` (30 s / 1 h) for production use, called from `server.js` (Task 8).

- [ ] **Step 1: Write the failing test**

`test/sweep.test.js`:
```js
const test = require('node:test');
const assert = require('node:assert/strict');
const { openDb } = require('../src/db');
const { checkDeadmanAndImmobility, purgeExpired } = require('../src/sweep');

function makeSoloSession(db, { deadmanAfter = 900, immobileAfter = 1800 } = {}) {
  const now = Date.now();
  db.prepare(
    `INSERT INTO session (id, kind, watch_token, owner_key, created_at, expires_at, deadman_after, immobile_after)
     VALUES ('s1','solo','tok','ok',?,?,?,?)`
  ).run(now, now + 3600000, deadmanAfter, immobileAfter);
  db.prepare(
    `INSERT INTO member (id, session_id, device_key, name, color, joined_at, last_seen)
     VALUES ('m1','s1','dk','Marc','#000',?,?)`
  ).run(now, now);
  return now;
}

test('a session silent past deadman_after gets alerted_at=deadman', () => {
  const db = openDb(':memory:');
  const now = makeSoloSession(db, { deadmanAfter: 900 });
  db.prepare(
    `INSERT INTO position (session_id, member_id, lat, lng, recorded_at, received_at)
     VALUES ('s1','m1',45,5,?,?)`
  ).run(now - 1000 * 1000, now - 1000 * 1000); // 1000s ago > 900s deadman

  checkDeadmanAndImmobility(db, now);

  const session = db.prepare('SELECT * FROM session WHERE id = ?').get('s1');
  assert.equal(session.alert_kind, 'deadman');
  assert.ok(session.alerted_at);
});

test('a session moving normally is left alone', () => {
  const db = openDb(':memory:');
  const now = makeSoloSession(db);
  db.prepare(
    `INSERT INTO position (session_id, member_id, lat, lng, recorded_at, received_at)
     VALUES ('s1','m1',45,5,?,?)`
  ).run(now - 5000, now - 5000);

  checkDeadmanAndImmobility(db, now);

  const session = db.prepare('SELECT * FROM session WHERE id = ?').get('s1');
  assert.equal(session.alert_kind, null);
});

test('a session with recent positions but no movement gets alerted_at=immobile', () => {
  const db = openDb(':memory:');
  const now = makeSoloSession(db, { deadmanAfter: 900, immobileAfter: 1800 });
  const insert = db.prepare(
    `INSERT INTO position (session_id, member_id, lat, lng, recorded_at, received_at)
     VALUES ('s1','m1',45.0001,5.0001,?,?)`
  );
  // positions still arriving (so not deadman) but stuck in one spot for 2000s > 1800s immobile_after
  for (let i = 0; i < 5; i++) insert.run(now - 2000000 + i * 400000, now - 2000000 + i * 400000);

  checkDeadmanAndImmobility(db, now);

  const session = db.prepare('SELECT * FROM session WHERE id = ?').get('s1');
  assert.equal(session.alert_kind, 'immobile');
});

test('an already-alerted session is not re-evaluated', () => {
  const db = openDb(':memory:');
  const now = makeSoloSession(db, { deadmanAfter: 900 });
  db.prepare('UPDATE session SET alerted_at = ?, alert_kind = ? WHERE id = ?').run(now - 500, 'deadman', 's1');

  checkDeadmanAndImmobility(db, now);

  const session = db.prepare('SELECT * FROM session WHERE id = ?').get('s1');
  assert.equal(session.alerted_at, now - 500); // unchanged
});

test('purgeExpired removes sessions past expires_at with no alert', () => {
  const db = openDb(':memory:');
  const now = Date.now();
  db.prepare(
    `INSERT INTO session (id, kind, owner_key, created_at, expires_at) VALUES ('s1','solo','ok',?,?)`
  ).run(now - 10000, now - 1000); // already expired

  purgeExpired(db, now);

  assert.equal(db.prepare('SELECT * FROM session WHERE id = ?').get('s1'), undefined);
});

test('purgeExpired keeps an alerted session until 7 days after the alert', () => {
  const db = openDb(':memory:');
  const now = Date.now();
  const sixDaysAgo = now - 6 * 24 * 3600 * 1000;
  const eightDaysAgo = now - 8 * 24 * 3600 * 1000;

  db.prepare(
    `INSERT INTO session (id, kind, owner_key, created_at, expires_at, ended_at, alerted_at)
     VALUES ('recent','solo','ok',?,?,?,?)`
  ).run(now - 20000, now - 10000, now - 10000, sixDaysAgo);
  db.prepare(
    `INSERT INTO session (id, kind, owner_key, created_at, expires_at, ended_at, alerted_at)
     VALUES ('old','solo','ok',?,?,?,?)`
  ).run(now - 20000, now - 10000, now - 10000, eightDaysAgo);

  purgeExpired(db, now);

  assert.ok(db.prepare('SELECT * FROM session WHERE id = ?').get('recent'));
  assert.equal(db.prepare('SELECT * FROM session WHERE id = ?').get('old'), undefined);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test`
Expected: FAIL with "Cannot find module '../src/sweep'"

- [ ] **Step 3: Write the implementation**

`src/sweep.js`:
```js
const IMMOBILE_RADIUS_METERS = 50;

function haversineMeters(a, b) {
  const R = 6371000;
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const lat1 = toRad(a.lat);
  const lat2 = toRad(b.lat);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

function checkDeadmanAndImmobility(db, now) {
  const sessions = db
    .prepare(`SELECT * FROM session WHERE kind = 'solo' AND ended_at IS NULL AND alerted_at IS NULL`)
    .all();

  for (const session of sessions) {
    const last = db
      .prepare('SELECT lat, lng, recorded_at FROM position WHERE session_id = ? ORDER BY id DESC LIMIT 1')
      .get(session.id);

    if (!last) continue; // pas encore de position, rien à évaluer

    const silentForSec = (now - last.recorded_at) / 1000;
    if (session.deadman_after && silentForSec >= session.deadman_after) {
      db.prepare('UPDATE session SET alerted_at = ?, alert_kind = ? WHERE id = ?').run(now, 'deadman', session.id);
      continue;
    }

    if (!session.immobile_after) continue;
    const windowStart = now - session.immobile_after * 1000;
    const recent = db
      .prepare('SELECT lat, lng FROM position WHERE session_id = ? AND recorded_at >= ? ORDER BY id ASC')
      .all(session.id, windowStart);
    if (recent.length < 2) continue; // pas assez d'historique sur la fenêtre pour juger

    const origin = recent[0];
    const strayed = recent.some((p) => haversineMeters(origin, p) > IMMOBILE_RADIUS_METERS);
    if (!strayed) {
      db.prepare('UPDATE session SET alerted_at = ?, alert_kind = ? WHERE id = ?').run(now, 'immobile', session.id);
    }
  }
}

const RETENTION_MS = 7 * 24 * 3600 * 1000;
const ORPHAN_GRACE_MS = 24 * 3600 * 1000;

function purgeExpired(db, now) {
  db.prepare(
    `DELETE FROM session WHERE alerted_at IS NULL AND expires_at < ? AND ended_at IS NULL`
  ).run(now);

  db.prepare(
    `DELETE FROM session WHERE alerted_at IS NULL AND ended_at IS NOT NULL AND ended_at < ?`
  ).run(now - ORPHAN_GRACE_MS);

  db.prepare(
    `DELETE FROM session WHERE alerted_at IS NOT NULL AND alerted_at < ?`
  ).run(now - RETENTION_MS);
}

function startSweeps(db) {
  const fast = setInterval(() => checkDeadmanAndImmobility(db, Date.now()), 30 * 1000);
  const slow = setInterval(() => purgeExpired(db, Date.now()), 60 * 60 * 1000);
  return { stop: () => { clearInterval(fast); clearInterval(slow); } };
}

module.exports = { checkDeadmanAndImmobility, purgeExpired, startSweeps };
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test`
Expected: PASS (all tests in `sweep.test.js`)

- [ ] **Step 5: Commit**

```bash
git add src/sweep.js test/sweep.test.js
git commit -m "feat: surveillance homme mort/immobilite et purge horaire"
```

---

### Task 8: server.js wiring, healthz, static serving

**Files:**
- Create: `src/server.js`
- Test: `test/server.test.js`

**Interfaces:**
- Consumes: `openDb`, `createSessionsRouter`, `createWatchRouter`, `startSweeps`.
- Produces: `createApp(db: Database): express.Express` (importable for tests without binding a port); when run directly (`node src/server.js`) opens `process.env.DB_PATH ?? './data/tracker.db'`, starts sweeps, and listens on `process.env.PORT ?? 3100`.

- [ ] **Step 1: Write the failing test**

`test/server.test.js`:
```js
const test = require('node:test');
const assert = require('node:assert/strict');
const { openDb } = require('../src/db');
const { createApp } = require('../src/server');

async function listen(app) {
  const server = app.listen(0);
  await new Promise((r) => server.once('listening', r));
  return { server, base: `http://127.0.0.1:${server.address().port}` };
}

test('GET /healthz returns ok', async () => {
  const app = createApp(openDb(':memory:'));
  const { server, base } = await listen(app);
  const res = await fetch(`${base}/healthz`);
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { ok: true });
  server.close();
});

test('GET /s/:watchToken serves the watch page with noindex', async () => {
  const app = createApp(openDb(':memory:'));
  const { server, base } = await listen(app);
  const res = await fetch(`${base}/s/anything`);
  assert.equal(res.status, 200);
  assert.equal(res.headers.get('x-robots-tag'), 'noindex');
  const text = await res.text();
  assert.match(text, /<title>Suivi/);
  server.close();
});

test('the full flow works end-to-end through createApp', async () => {
  const app = createApp(openDb(':memory:'));
  const { server, base } = await listen(app);

  const created = await (
    await fetch(`${base}/api/sessions`, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ kind: 'solo', name: 'Marc' }),
    })
  ).json();
  await fetch(`${base}/api/sessions/${created.sessionId}/positions`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      deviceKey: created.deviceKey, memberId: created.memberId,
      points: [{ lat: 45, lng: 5, recordedAt: Date.now() }],
    }),
  });
  const watch = await (await fetch(`${base}/api/watch/${created.watchToken}`)).json();
  assert.equal(watch.lastPoint.lat, 45);

  server.close();
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test`
Expected: FAIL with "Cannot find module '../src/server'"

- [ ] **Step 3: Write the implementation**

`src/server.js`:
```js
const path = require('node:path');
const express = require('express');
const { openDb } = require('./db');
const { createSessionsRouter } = require('./routes/sessions');
const { createWatchRouter } = require('./routes/watch');
const { startSweeps } = require('./sweep');

function createApp(db) {
  const app = express();
  app.use(express.json());

  app.get('/healthz', (_req, res) => res.status(200).json({ ok: true }));

  app.use('/api/sessions', createSessionsRouter(db));
  app.use('/', createWatchRouter(db));

  app.get('/s/:watchToken', (_req, res) => {
    res.set('X-Robots-Tag', 'noindex');
    res.sendFile(path.join(__dirname, '..', 'public', 'watch.html'));
  });

  app.use(express.static(path.join(__dirname, '..', 'public')));

  return app;
}

if (require.main === module) {
  const db = openDb(process.env.DB_PATH ?? './data/tracker.db');
  startSweeps(db);
  const port = process.env.PORT ?? 3100;
  createApp(db).listen(port, () => {
    console.log(`moto-tracker listening on :${port}`);
  });
}

module.exports = { createApp };
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test`
Expected: PASS (all tests across every file — full suite green)

- [ ] **Step 5: Commit**

```bash
git add src/server.js test/server.test.js
git commit -m "feat: assemblage du serveur, healthz et service statique"
```

---

### Task 9: Docker Compose, nginx, DNS, deploy — provisioning on Hetzner

**Files:**
- Create: `docker-compose.yml`
- Create: `deploy.sh`
- Create: `nginx/moto-tracker.conf` (reference copy; the live file lives at `/etc/nginx/sites-available/` on the server)

This task is infrastructure provisioning, not application code — there is no unit test for "a DNS record exists" or "nginx reloaded." Verification is the curl check in Step 5.

- [ ] **Step 1: Write the compose file**

`docker-compose.yml`:
```yaml
services:
  moto-tracker:
    image: node:18
    working_dir: /app
    volumes:
      - ./src:/app/src
      - ./public:/app/public
      - ./package.json:/app/package.json
      - ./data:/app/data
    ports:
      - "127.0.0.1:3100:3100"
    environment:
      NODE_ENV: production
      PORT: 3100
      DB_PATH: /app/data/tracker.db
    command: sh -c "npm install --omit=dev && node src/server.js"
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:3100/healthz > /dev/null 2>&1 || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 20s
```

Note: `node:18` (not `-alpine`) — see "Deliberate deviations" §4 at the top of this plan.

- [ ] **Step 2: Write the deploy script**

`deploy.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
MSG="${1:?Usage: ./deploy.sh \"message du commit\"}"

git add -A
git commit -m "$MSG" || echo "Rien à committer localement"
git push origin main

ssh drone31 "cd /root/moto-tracker && git pull origin main && docker compose up -d --build"
```

```bash
chmod +x deploy.sh
```

- [ ] **Step 3: Write the nginx vhost**

`nginx/moto-tracker.conf`:
```nginx
server {
    listen 80;
    server_name motooffroad.duckdns.org;
    location /.well-known/acme-challenge/ { root /var/www/html; }
    location / { return 301 https://$host$request_uri; }
}

server {
    listen 443 ssl;
    server_name motooffroad.duckdns.org;

    ssl_certificate     /etc/letsencrypt/live/motooffroad.duckdns.org/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/motooffroad.duckdns.org/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    location / {
        proxy_pass http://127.0.0.1:3100;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffering off;    # requis pour le flux SSE de /api/watch/*/stream
        proxy_read_timeout 86400;
    }
}
```

- [ ] **Step 4: Provision on Hetzner (manual, one-time)**

```bash
# 1. Créer le dépôt GitHub (une fois) :
gh repo create barbarescomarc/moto-tracker-server --private --source=. --remote=origin --push

# 2. Sous-domaine DuckDNS — depuis https://www.duckdns.org, ajouter le
#    sous-domaine "motooffroad" au compte déjà utilisé pour drone31, puis :
ssh drone31 "curl -s 'https://www.duckdns.org/update?domains=motooffroad&token=<TOKEN_DUCKDNS>&ip='"

# 3. Cloner le dépôt sur le serveur
ssh drone31 "git clone https://github.com/barbarescomarc/moto-tracker-server.git /root/moto-tracker && mkdir -p /root/moto-tracker/data"

# 4. Certificat TLS (nginx tourne déjà pour drone31.duckdns.org sur le même port 80/443)
ssh drone31 "cp /root/moto-tracker/nginx/moto-tracker.conf /etc/nginx/sites-available/moto-tracker.conf \
  && ln -sf /etc/nginx/sites-available/moto-tracker.conf /etc/nginx/sites-enabled/ \
  && nginx -t && systemctl reload nginx \
  && certbot --nginx -d motooffroad.duckdns.org --non-interactive --agree-tos -m drone-31@hotmail.fr"

# 5. Démarrer le service
ssh drone31 "cd /root/moto-tracker && docker compose up -d"
```

- [ ] **Step 5: Verify the live deployment**

```bash
curl -sf https://motooffroad.duckdns.org/healthz
# Attendu : {"ok":true}
curl -sf -o /dev/null -w '%{http_code}\n' https://drone31.duckdns.org/healthz
# Attendu : toujours 200 (ou l'équivalent existant) — le streaming n'a pas régressé
```

- [ ] **Step 6: Commit**

```bash
git add docker-compose.yml deploy.sh nginx/moto-tracker.conf
git commit -m "chore: docker compose, vhost nginx et script de deploiement"
git push origin main
```

---

# Part 2 — App: Lot B (suivi solo)

All tasks below are in `~/Claude/Projects/APP OFFROAD MOTO 4X4/moto_offroad`.

### Task 10: `TrackerApiClient`

**Files:**
- Create: `lib/services/tracker_api_client.dart`
- Test: `test/services/tracker_api_client_test.dart`

**Interfaces:**
- Consumes: `package:http`, `GpsSnapshot` (`lib/services/location_service.dart`), `LatLng` (`latlong2`).
- Produces:
  - `class SessionCreated { sessionId, ownerKey, deviceKey, memberId, watchToken? }`
  - `class SessionJoined { sessionId, deviceKey, memberId, color }`
  - `class PeerPosition { memberId, name, color, position: LatLng?, speedKmh, lastSeen: DateTime }`
  - `class TrackerApiClient` with methods used by Tasks 12/16/17: `createSoloSession`, `createGroupSession`, `joinGroupSession`, `sendPositions`, `fetchPeers`, `setRally`, `clearRally`, `leaveSession`, `endSession`. Every method returns `null`/`false`/`[]` on any network or parse error — never throws.

- [ ] **Step 1: Write the failing test**

`test/services/tracker_api_client_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_offroad/services/location_service.dart';
import 'package:moto_offroad/services/tracker_api_client.dart';

void main() {
  group('createSoloSession', () {
    test('parses a successful response', () async {
      final client = MockClient((req) async {
        expect(req.url.path, '/api/sessions');
        return http.Response(
          '{"sessionId":"s1","ownerKey":"ok","deviceKey":"dk","memberId":"m1","watchToken":"tok"}',
          201,
        );
      });
      final api = TrackerApiClient(client: client, baseUrl: 'https://example.test');
      final result = await api.createSoloSession(name: 'Marc', immobileAfterSec: 1800);
      expect(result, isNotNull);
      expect(result!.watchToken, 'tok');
      expect(result.sessionId, 's1');
    });

    test('returns null on network failure', () async {
      final client = MockClient((_) async => throw Exception('offline'));
      final api = TrackerApiClient(client: client, baseUrl: 'https://example.test');
      final result = await api.createSoloSession(name: 'Marc', immobileAfterSec: 1800);
      expect(result, isNull);
    });

    test('returns null on a non-2xx response', () async {
      final client = MockClient((_) async => http.Response('{}', 400));
      final api = TrackerApiClient(client: client, baseUrl: 'https://example.test');
      final result = await api.createSoloSession(name: 'Marc', immobileAfterSec: 1800);
      expect(result, isNull);
    });
  });

  group('sendPositions', () {
    test('returns true when the server accepts the batch', () async {
      final client = MockClient((_) async => http.Response('{"accepted":1}', 200));
      final api = TrackerApiClient(client: client, baseUrl: 'https://example.test');
      final ok = await api.sendPositions(
        sessionId: 's1', deviceKey: 'dk', memberId: 'm1',
        points: [GpsSnapshot(
          position: const LatLng(45, 5), accuracyMeters: 5, altitudeMeters: 100,
          speedKmh: 30, headingDeg: 90, timestamp: DateTime.now(),
        )],
      );
      expect(ok, isTrue);
    });

    test('returns false without throwing when offline', () async {
      final client = MockClient((_) async => throw Exception('offline'));
      final api = TrackerApiClient(client: client, baseUrl: 'https://example.test');
      final ok = await api.sendPositions(
        sessionId: 's1', deviceKey: 'dk', memberId: 'm1',
        points: [GpsSnapshot(
          position: const LatLng(45, 5), accuracyMeters: 5, altitudeMeters: 100,
          speedKmh: 30, headingDeg: 90, timestamp: DateTime.now(),
        )],
      );
      expect(ok, isFalse);
    });
  });

  group('fetchPeers', () {
    test('parses peers and excludes nothing itself (server already excludes caller)', () async {
      final client = MockClient((_) async => http.Response(
        '{"peers":[{"memberId":"m2","name":"Claire","color":"#1565C0","lat":45.2,"lng":5.8,"speedKmh":40,"lastSeen":1000}],"rally":null}',
        200,
      ));
      final api = TrackerApiClient(client: client, baseUrl: 'https://example.test');
      final peers = await api.fetchPeers(sessionId: 's1', deviceKey: 'dk', memberId: 'm1');
      expect(peers.length, 1);
      expect(peers.first.name, 'Claire');
      expect(peers.first.position, const LatLng(45.2, 5.8));
    });

    test('returns an empty list on failure', () async {
      final client = MockClient((_) async => http.Response('', 500));
      final api = TrackerApiClient(client: client, baseUrl: 'https://example.test');
      final peers = await api.fetchPeers(sessionId: 's1', deviceKey: 'dk', memberId: 'm1');
      expect(peers, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/tracker_api_client_test.dart`
Expected: FAIL — `tracker_api_client.dart` doesn't exist

- [ ] **Step 3: Write the implementation**

`lib/services/tracker_api_client.dart`:
```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'location_service.dart';

class SessionCreated {
  final String sessionId;
  final String ownerKey;
  final String deviceKey;
  final String memberId;
  final String? watchToken;
  final String? joinCode;

  const SessionCreated({
    required this.sessionId,
    required this.ownerKey,
    required this.deviceKey,
    required this.memberId,
    this.watchToken,
    this.joinCode,
  });
}

class SessionJoined {
  final String sessionId;
  final String deviceKey;
  final String memberId;
  final String color;

  const SessionJoined({
    required this.sessionId,
    required this.deviceKey,
    required this.memberId,
    required this.color,
  });
}

class PeerPosition {
  final String memberId;
  final String name;
  final String color;
  final LatLng? position;
  final double? speedKmh;
  final DateTime lastSeen;

  const PeerPosition({
    required this.memberId,
    required this.name,
    required this.color,
    required this.position,
    required this.speedKmh,
    required this.lastSeen,
  });
}

class TrackerApiClient {
  TrackerApiClient({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? 'https://motooffroad.duckdns.org';

  final http.Client _client;
  final String _baseUrl;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$_baseUrl$path').replace(queryParameters: query);

  Future<SessionCreated?> createSoloSession({
    required String name,
    required int immobileAfterSec,
  }) => _createSession({'kind': 'solo', 'name': name, 'immobileAfterSec': immobileAfterSec});

  Future<SessionCreated?> createGroupSession({required String name}) =>
      _createSession({'kind': 'group', 'name': name});

  Future<SessionCreated?> _createSession(Map<String, dynamic> body) async {
    try {
      final res = await _client.post(
        _uri('/api/sessions'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode(body),
      );
      if (res.statusCode ~/ 100 != 2) return null;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      return SessionCreated(
        sessionId: j['sessionId'] as String,
        ownerKey:  j['ownerKey']  as String,
        deviceKey: j['deviceKey'] as String,
        memberId:  j['memberId']  as String,
        watchToken: j['watchToken'] as String?,
        joinCode:   j['joinCode']   as String?,
      );
    } catch (_) {
      return null;
    }
  }

  Future<SessionJoined?> joinGroupSession({required String joinCode, required String name}) async {
    try {
      final res = await _client.post(
        _uri('/api/sessions/join/$joinCode'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'name': name}),
      );
      if (res.statusCode ~/ 100 != 2) return null;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      return SessionJoined(
        sessionId: j['sessionId'] as String,
        deviceKey: j['deviceKey'] as String,
        memberId:  j['memberId']  as String,
        color:     j['color']     as String,
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> sendPositions({
    required String sessionId,
    required String deviceKey,
    required String memberId,
    required List<GpsSnapshot> points,
  }) async {
    try {
      final res = await _client.post(
        _uri('/api/sessions/$sessionId/positions'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'deviceKey': deviceKey,
          'memberId': memberId,
          'points': points.map((p) => {
            'lat': p.position.latitude,
            'lng': p.position.longitude,
            'speedKmh': p.speedKmh,
            'heading': p.headingDeg,
            'recordedAt': p.timestamp.millisecondsSinceEpoch,
          }).toList(),
        }),
      );
      return res.statusCode ~/ 100 == 2;
    } catch (_) {
      return false;
    }
  }

  Future<List<PeerPosition>> fetchPeers({
    required String sessionId,
    required String deviceKey,
    required String memberId,
  }) async {
    try {
      final res = await _client.get(
        _uri('/api/sessions/$sessionId/peers', {'deviceKey': deviceKey, 'memberId': memberId}),
      );
      if (res.statusCode ~/ 100 != 2) return [];
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      return (j['peers'] as List<dynamic>).map((raw) {
        final m = raw as Map<String, dynamic>;
        final lat = m['lat'] as num?;
        final lng = m['lng'] as num?;
        return PeerPosition(
          memberId: m['memberId'] as String,
          name:     m['name'] as String,
          color:    m['color'] as String,
          position: lat != null && lng != null ? LatLng(lat.toDouble(), lng.toDouble()) : null,
          speedKmh: (m['speedKmh'] as num?)?.toDouble(),
          lastSeen: DateTime.fromMillisecondsSinceEpoch(m['lastSeen'] as int),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<LatLng?> setRally({
    required String sessionId,
    required String deviceKey,
    required LatLng point,
  }) async {
    try {
      final res = await _client.post(
        _uri('/api/sessions/$sessionId/rally'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'deviceKey': deviceKey, 'lat': point.latitude, 'lng': point.longitude}),
      );
      return res.statusCode ~/ 100 == 2 ? point : null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> clearRally({required String sessionId, required String deviceKey}) async {
    try {
      final res = await _client.post(
        _uri('/api/sessions/$sessionId/rally'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'deviceKey': deviceKey, 'clear': true}),
      );
      return res.statusCode ~/ 100 == 2;
    } catch (_) {
      return false;
    }
  }

  Future<bool> leaveSession({
    required String sessionId,
    required String deviceKey,
    required String memberId,
  }) async {
    try {
      final res = await _client.delete(
        _uri('/api/sessions/$sessionId/members/$memberId'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'deviceKey': deviceKey}),
      );
      return res.statusCode ~/ 100 == 2;
    } catch (_) {
      return false;
    }
  }

  Future<bool> endSession({required String sessionId, required String ownerKey}) async {
    try {
      final res = await _client.post(
        _uri('/api/sessions/$sessionId/end'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'ownerKey': ownerKey}),
      );
      return res.statusCode ~/ 100 == 2;
    } catch (_) {
      return false;
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/tracker_api_client_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/tracker_api_client.dart test/services/tracker_api_client_test.dart
git commit -m "feat: client HTTP du hub de positions"
```

---

### Task 11: `PositionUplinkService`

**Files:**
- Create: `lib/services/position_uplink_service.dart`
- Test: `test/services/position_uplink_service_test.dart`

**Interfaces:**
- Consumes: `TrackerApiClient.sendPositions` (Task 10), `GpsSnapshot` (`location_service.dart`).
- Produces: `class PositionUplinkService` with `void start({required Stream<GpsSnapshot> positions, required String sessionId, required String deviceKey, required String memberId, required Duration interval})` and `void stop()`. Buffers incoming snapshots; every `interval` tick, attempts to send the whole buffer in one call; clears the buffer only on success (so a failed tick's points are retried, capped at 200 buffered points to bound memory on a long outage).

- [ ] **Step 1: Write the failing test**

`test/services/position_uplink_service_test.dart`:
```dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_offroad/services/location_service.dart';
import 'package:moto_offroad/services/position_uplink_service.dart';
import 'package:moto_offroad/services/tracker_api_client.dart';

GpsSnapshot _snap() => GpsSnapshot(
  position: const LatLng(45, 5), accuracyMeters: 5, altitudeMeters: 100,
  speedKmh: 20, headingDeg: 0, timestamp: DateTime.now(),
);

class _FakeSender {
  final List<List<GpsSnapshot>> calls = [];
  bool succeed = true;
  Future<bool> call({
    required String sessionId, required String deviceKey, required String memberId,
    required List<GpsSnapshot> points,
  }) async {
    calls.add(points);
    return succeed;
  }
}

void main() {
  test('buffered points are sent and cleared on the next tick when successful', () async {
    final sender = _FakeSender();
    final controller = StreamController<GpsSnapshot>();
    final service = PositionUplinkService(sendPositions: sender.call);

    service.start(
      positions: controller.stream,
      sessionId: 's1', deviceKey: 'dk', memberId: 'm1',
      interval: const Duration(milliseconds: 20),
    );
    controller.add(_snap());
    controller.add(_snap());
    await Future.delayed(const Duration(milliseconds: 60));

    expect(sender.calls, isNotEmpty);
    expect(sender.calls.first.length, 2);

    service.stop();
    await controller.close();
  });

  test('a failed send keeps the points for the next tick', () async {
    final sender = _FakeSender()..succeed = false;
    final controller = StreamController<GpsSnapshot>();
    final service = PositionUplinkService(sendPositions: sender.call);

    service.start(
      positions: controller.stream,
      sessionId: 's1', deviceKey: 'dk', memberId: 'm1',
      interval: const Duration(milliseconds: 20),
    );
    controller.add(_snap());
    await Future.delayed(const Duration(milliseconds: 70));

    expect(sender.calls.length, greaterThan(1));
    // le point du premier échec réapparaît dans un appel suivant
    expect(sender.calls.last, isNotEmpty);

    service.stop();
    await controller.close();
  });

  test('stop() cancels the timer and the subscription', () async {
    final sender = _FakeSender();
    final controller = StreamController<GpsSnapshot>();
    final service = PositionUplinkService(sendPositions: sender.call);

    service.start(
      positions: controller.stream,
      sessionId: 's1', deviceKey: 'dk', memberId: 'm1',
      interval: const Duration(milliseconds: 20),
    );
    service.stop();
    final callsAtStop = sender.calls.length;
    controller.add(_snap());
    await Future.delayed(const Duration(milliseconds: 60));

    expect(sender.calls.length, callsAtStop);
    await controller.close();
  });

  test('an empty buffer sends nothing', () async {
    final sender = _FakeSender();
    final controller = StreamController<GpsSnapshot>();
    final service = PositionUplinkService(sendPositions: sender.call);

    service.start(
      positions: controller.stream,
      sessionId: 's1', deviceKey: 'dk', memberId: 'm1',
      interval: const Duration(milliseconds: 20),
    );
    await Future.delayed(const Duration(milliseconds: 50));

    expect(sender.calls, isEmpty);
    service.stop();
    await controller.close();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/position_uplink_service_test.dart`
Expected: FAIL — `position_uplink_service.dart` doesn't exist

- [ ] **Step 3: Write the implementation**

`lib/services/position_uplink_service.dart`:
```dart
import 'dart:async';
import 'location_service.dart';

typedef SendPositionsFn = Future<bool> Function({
  required String sessionId,
  required String deviceKey,
  required String memberId,
  required List<GpsSnapshot> points,
});

class PositionUplinkService {
  PositionUplinkService({required SendPositionsFn sendPositions}) : _send = sendPositions;

  static const int _maxBuffered = 200;

  final SendPositionsFn _send;
  final List<GpsSnapshot> _buffer = [];
  StreamSubscription<GpsSnapshot>? _sub;
  Timer? _timer;

  void start({
    required Stream<GpsSnapshot> positions,
    required String sessionId,
    required String deviceKey,
    required String memberId,
    required Duration interval,
  }) {
    stop();
    _sub = positions.listen((snap) {
      _buffer.add(snap);
      if (_buffer.length > _maxBuffered) _buffer.removeAt(0);
    });
    _timer = Timer.periodic(interval, (_) async {
      if (_buffer.isEmpty) return;
      final batch = List<GpsSnapshot>.from(_buffer);
      final ok = await _send(
        sessionId: sessionId, deviceKey: deviceKey, memberId: memberId, points: batch,
      );
      if (ok) _buffer.removeRange(0, batch.length);
    });
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _timer?.cancel();
    _timer = null;
    _buffer.clear();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/position_uplink_service_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/position_uplink_service.dart test/services/position_uplink_service_test.dart
git commit -m "feat: envoi tamponne et tolerant aux coupures reseau"
```

---

### Task 12: `SoloProvider` talks to the hub

**Files:**
- Modify: `lib/providers/solo_provider.dart`
- Modify: `test/providers/solo_provider_test.dart` — add new tests (existing ones must keep passing unchanged).

**Interfaces:**
- Consumes: `TrackerApiClient` (Task 10), injected via constructor (matches the `AutoReplyService` DI convention already used in this codebase).
- Produces: `SoloProvider` gains `sessionId`, `deviceKey`, `memberId` getters (null when inactive) so Task 14 can wire `PositionUplinkService` to them; `activate()` becomes `Future<bool>` (false if the hub call fails — activation must not silently "succeed" with a dead tracking link); `trackingUrl` now returns `https://motooffroad.duckdns.org/s/<watchToken>` from the real session.

- [ ] **Step 1: Write the failing test**

Add to `test/providers/solo_provider_test.dart` (new `import` and new `test(...)` blocks; keep the existing three tests as-is):
```dart
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moto_offroad/services/tracker_api_client.dart';

// ... (existing tests unchanged) ...

test('activate() creates a real hub session and exposes the real tracking URL', () async {
  SharedPreferences.setMockInitialValues({});
  final client = MockClient((req) async {
    if (req.url.path == '/api/sessions') {
      return http.Response(
        '{"sessionId":"s1","ownerKey":"ok","deviceKey":"dk","memberId":"m1","watchToken":"tok123"}',
        201,
      );
    }
    return http.Response('', 404);
  });
  final s = SoloProvider(trackerClient: TrackerApiClient(client: client, baseUrl: 'https://example.test'));
  await s.loadContacts();
  await s.addContact(name: 'Claire', phone: '0600000000', relation: 'Sœur');

  final ok = await s.activate([s.contacts.first.id]);

  expect(ok, isTrue);
  expect(s.soloActive, isTrue);
  expect(s.trackingUrl, 'https://motooffroad.duckdns.org/s/tok123');
  expect(s.sessionId, 's1');
  expect(s.deviceKey, 'dk');
  expect(s.memberId, 'm1');
});

test('activate() fails cleanly (no fake link) when the hub is unreachable', () async {
  SharedPreferences.setMockInitialValues({});
  final client = MockClient((_) async => throw Exception('offline'));
  final s = SoloProvider(trackerClient: TrackerApiClient(client: client, baseUrl: 'https://example.test'));
  await s.loadContacts();
  await s.addContact(name: 'Claire', phone: '0600000000', relation: 'Sœur');

  final ok = await s.activate([s.contacts.first.id]);

  expect(ok, isFalse);
  expect(s.soloActive, isFalse);
  expect(s.trackingUrl, isNull);
});

test('deactivate() ends the hub session and clears local session identifiers', () async {
  SharedPreferences.setMockInitialValues({});
  var endCalled = false;
  final client = MockClient((req) async {
    if (req.url.path == '/api/sessions') {
      return http.Response(
        '{"sessionId":"s1","ownerKey":"ok","deviceKey":"dk","memberId":"m1","watchToken":"tok"}',
        201,
      );
    }
    if (req.url.path.endsWith('/end')) {
      endCalled = true;
      return http.Response('{}', 200);
    }
    return http.Response('', 404);
  });
  final s = SoloProvider(trackerClient: TrackerApiClient(client: client, baseUrl: 'https://example.test'));
  await s.loadContacts();
  await s.addContact(name: 'Claire', phone: '0600000000', relation: 'Sœur');
  await s.activate([s.contacts.first.id]);

  s.deactivate();
  await Future.delayed(Duration.zero); // laisse le endSession() fire-and-forget se lancer

  expect(endCalled, isTrue);
  expect(s.sessionId, isNull);
  expect(s.trackingUrl, isNull);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/providers/solo_provider_test.dart`
Expected: FAIL — `SoloProvider` has no `trackerClient` constructor param, `activate` returns `void` not `Future<bool>`, no `sessionId`/`deviceKey`/`memberId` getters

- [ ] **Step 3: Write the implementation**

Replace the top of `lib/providers/solo_provider.dart` (imports and class opening) and the `activate`/`deactivate` methods:
```dart
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/tracker_api_client.dart';

// (TrustedContact class unchanged)

// ── Provider — Mode Solo Sécurisé ────────────────────────────
class SoloProvider extends ChangeNotifier {
  SoloProvider({TrackerApiClient? trackerClient})
      : _tracker = trackerClient ?? TrackerApiClient();

  static const _kContacts = 'trusted_contacts';
  static const String watchBaseUrl = 'https://motooffroad.duckdns.org/s/';

  final _uuid = const Uuid();
  final TrackerApiClient _tracker;

  bool _soloActive = false;
  bool get soloActive => _soloActive;

  String? _watchToken;
  String? get trackingUrl => _watchToken != null ? '$watchBaseUrl$_watchToken' : null;

  String? _sessionId;
  String? get sessionId => _sessionId;
  String? _deviceKey;
  String? get deviceKey => _deviceKey;
  String? _memberId;
  String? get memberId => _memberId;
  String? _ownerKey;

  final List<TrustedContact> _contacts = [];
  List<TrustedContact> get contacts => List.unmodifiable(_contacts);

  int _immobilityThresholdMin = 30;
  int get immobilityThresholdMin => _immobilityThresholdMin;

  DateTime? _sessionStart;
  DateTime? get sessionStart => _sessionStart;

  // (loadContacts, _saveContacts, addContact, removeContact unchanged)

  // ── Activer le mode Solo ──────────────────────────────────
  Future<bool> activate(List<String> contactIds) async {
    if (_contacts.isEmpty) return false;

    final created = await _tracker.createSoloSession(
      name: 'Pilote',
      immobileAfterSec: _immobilityThresholdMin * 60,
    );
    if (created == null || created.watchToken == null) return false;

    _sessionId  = created.sessionId;
    _deviceKey  = created.deviceKey;
    _memberId   = created.memberId;
    _ownerKey   = created.ownerKey;
    _watchToken = created.watchToken;
    _sessionStart = DateTime.now();
    _soloActive = true;

    for (final c in _contacts) {
      c.isNotified = contactIds.contains(c.id);
    }

    notifyListeners();
    return true;
  }

  // ── Désactiver le mode Solo ───────────────────────────────
  void deactivate() {
    final sid = _sessionId;
    final ok = _ownerKey;
    if (sid != null && ok != null) {
      _tracker.endSession(sessionId: sid, ownerKey: ok); // fire-and-forget, échec avalé par le client
    }

    _soloActive = false;
    _watchToken = null;
    _sessionId = null;
    _deviceKey = null;
    _memberId = null;
    _ownerKey = null;
    _sessionStart = null;
    for (final c in _contacts) {
      c.isNotified = false;
    }
    notifyListeners();
  }

  void setImmobilityThreshold(int minutes) {
    _immobilityThresholdMin = minutes;
    notifyListeners();
  }
}
```

Also update `lib/screens/solo/solo_screen.dart`'s activate call site (it currently does `await solo.activate(_selectedContactIds.toList());` with no result check) to surface a failure:
```dart
onPressed: canActivate
    ? () async {
        final ok = await solo.activate(_selectedContactIds.toList());
        if (!ok && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(
              'Impossible de joindre le serveur de suivi — réessayez.')),
          );
        }
      }
    : null,
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/providers/solo_provider_test.dart`
Expected: PASS (all 6 tests: the 3 original persistence tests plus the 3 new hub-integration tests)

- [ ] **Step 5: Commit**

```bash
git add lib/providers/solo_provider.dart lib/screens/solo/solo_screen.dart test/providers/solo_provider_test.dart
git commit -m "feat: SoloProvider cree une vraie session sur le hub"
```

---

### Task 13: "Envoyer par SMS" on `SoloScreen` **[GUI — use impeccable skill]**

**Files:**
- Modify: `lib/screens/solo/solo_screen.dart`
- Test: manual (see Step 3) — `url_launcher`'s SMS intent can't be exercised in `flutter_test`; this matches the existing convention where `url_launcher`-based SOS actions in this codebase (`sos_screen.dart`) also have no widget test for the actual OS handoff.

**Interfaces:**
- Consumes: `url_launcher` (already a dependency), `SoloProvider.trackingUrl`, `SoloProvider.contacts`.

- [ ] **Step 1: Add the share button**

In `lib/screens/solo/solo_screen.dart`, add an import:
```dart
import 'package:url_launcher/url_launcher.dart';
```

Inside `_statusCard`, right after the existing tracking-URL `Container` block (after the "Le lien est chiffré…" `Text`, before the `if (solo.sessionStart != null)` block), add:
```dart
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _shareTrackingLink(solo),
            icon: const Icon(Icons.sms_outlined, size: 18),
            label: const Text('Envoyer le lien par SMS'),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.statusGreen.withOpacity(.5)),
              foregroundColor: AppColors.statusGreen,
            ),
          ),
```

Add the handler method to `_SoloScreenState`:
```dart
  Future<void> _shareTrackingLink(SoloProvider solo) async {
    final url = solo.trackingUrl;
    if (url == null) return;
    final notified = solo.contacts.where((c) => c.isNotified).toList();
    final body = Uri.encodeComponent(
      'Je pars rouler, tu peux me suivre ici : $url');
    final recipients = notified.map((c) => c.phone).join(',');
    final uri = Uri.parse('sms:$recipients?body=$body');
    await launchUrl(uri);
  }
```

- [ ] **Step 2: There is no automated test to run for this step.**

The behavior (opening the phone's SMS app with a pre-filled recipient/body) requires a real Android device/emulator and manual confirmation — the same limitation the existing SOS/`url_launcher` flows in this app already have. Run `flutter analyze lib/screens/solo/solo_screen.dart` to confirm it compiles.

- [ ] **Step 3: Manual verification**

```bash
flutter run
# Activer le mode Solo avec au moins un contact sélectionné,
# appuyer "Envoyer le lien par SMS", vérifier que l'app SMS s'ouvre
# avec le bon numéro et le lien https://motooffroad.duckdns.org/s/... prérempli.
```

- [ ] **Step 4: Apply the impeccable skill**

Invoke the `impeccable` skill on the updated `SoloScreen` status card to review the new button's placement, sizing, and hierarchy against the existing card (icon weight, spacing rhythm, color use of `AppColors.statusGreen`).

- [ ] **Step 5: Commit**

```bash
git add lib/screens/solo/solo_screen.dart
git commit -m "feat: partage du lien de suivi par SMS depuis l ecran Solo"
```

---

### Task 14: Wire the uplink lifecycle in `main.dart`

**Files:**
- Modify: `lib/main.dart`

**Interfaces:**
- Consumes: `SoloProvider` (Task 12), `PositionUplinkService` (Task 11), `LocationService().stream`, `RideRecordingService` (existing, Lot 1) for the foreground-service lifecycle.
- Produces: solo tracking now actually starts/stops the background service and the position uplink when `SoloProvider.soloActive` flips, mirroring the existing `_AutoReplyHost` pattern (a small `StatefulWidget` host that owns the service and reacts to provider changes).

- [ ] **Step 1: There is no isolated unit test for this step.**

`main.dart`'s widget wiring is exercised by the existing `smoke_test.dart`, which pumps the full app. This task only needs that smoke test to keep passing — no new test is added for wiring glue itself, matching how `_AutoReplyHost` (already in this file) has no dedicated test either; its constituent parts (`AutoReplyService`, `SoloProvider`, etc.) are unit-tested individually, same as here (`PositionUplinkService`, `SoloProvider` already are).

- [ ] **Step 2: Write the implementation**

Add imports to `lib/main.dart`:
```dart
import 'services/tracker_api_client.dart';
import 'services/position_uplink_service.dart';
```

Add a new host widget below `_AutoReplyHost` (same file):
```dart
// ── Cycle de vie de l'envoi de position en mode Solo ─────────
class _SoloUplinkHost extends StatefulWidget {
  const _SoloUplinkHost({required this.child});
  final Widget child;

  @override
  State<_SoloUplinkHost> createState() => _SoloUplinkHostState();
}

class _SoloUplinkHostState extends State<_SoloUplinkHost> {
  final _uplink = PositionUplinkService(sendPositions: TrackerApiClient().sendPositions);
  bool _wasActive = false;

  @override
  Widget build(BuildContext context) {
    final solo = context.watch<SoloProvider>();
    if (solo.soloActive && !_wasActive) {
      _wasActive = true;
      RideRecordingService().start(
        title: 'Mode Solo Sécurisé actif',
        text: 'Votre position est envoyée à vos contacts de confiance',
      );
      _uplink.start(
        positions: LocationService().stream,
        sessionId: solo.sessionId!,
        deviceKey: solo.deviceKey!,
        memberId: solo.memberId!,
        interval: const Duration(seconds: 5),
      );
    } else if (!solo.soloActive && _wasActive) {
      _wasActive = false;
      _uplink.stop();
    }
    return widget.child;
  }

  @override
  void dispose() {
    _uplink.stop();
    super.dispose();
  }
}
```

Add the required import for `RideRecordingService` (may already be imported — check before duplicating):
```dart
import 'services/ride_recording_service.dart';
```

Wrap `_AutoReplyHost`'s child in `_SoloUplinkHost` in `MotoOffroadApp.build`:
```dart
      child: _AutoReplyHost(
        child: _SoloUplinkHost(
          child: MaterialApp.router(
            title: 'Moto Offroad 4x4',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.dark,
            routerConfig: appRouter,
          ),
        ),
      ),
```

Note: `RideRecordingService().start(...)` is safe to call even if a ride recording is already running — its implementation (`lib/services/ride_recording_service.dart:59-66`) already checks `if (await isRunning) return true;` before starting, so Solo mode and GPX recording share the one foreground service without conflict, and stopping Solo does **not** call `RideRecordingService().stop()` — only `RecordingProvider` should decide when the foreground service actually stops, otherwise ending Solo mid-ride would silently kill an active GPX recording.

- [ ] **Step 3: Verify**

Run: `flutter test test/smoke_test.dart`
Expected: PASS (app still builds and pumps with the new host in the tree)

Run: `flutter analyze`
Expected: no new errors

- [ ] **Step 4: Commit**

```bash
git add lib/main.dart
git commit -m "feat: demarrage/arret de l envoi de position avec le mode Solo"
```

---

# Part 3 — App: Lot D (communauté)

### Task 15: Remove Firebase

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/main.dart`
- Delete: `lib/config/firebase_options.dart`
- Delete: `lib/services/firebase_group_service.dart`
- Modify: `.github/workflows/build-apk.yml`

**Interfaces:** none — pure removal. Task 16 replaces the functionality.

- [ ] **Step 1: There is no test for a removal step.** Verification is `flutter analyze` finding no more references, done in Step 3.

- [ ] **Step 2: Remove the dependency and its usages**

In `pubspec.yaml`, delete:
```yaml
  # ── Firebase (mode groupe) ───────────────────────────
  firebase_core: ^2.27.0
  firebase_database: ^10.4.0   # Realtime DB positions groupe
  firebase_auth: ^4.17.0       # Auth anonyme
```

In `lib/main.dart`, remove the import `import 'package:firebase_core/firebase_core.dart';`, remove `import 'config/firebase_options.dart';`, and remove the whole initialization block:
```dart
  // Initialisation Firebase (mode groupe temps réel)
  // ⚠️  Nécessite google-services.json dans android/app/
  // ⚠️  Voir lib/config/firebase_options.dart pour le guide de configuration
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    // Firebase non configuré — le mode groupe sera désactivé
    debugPrint('Firebase non initialisé : $e');
  }
```

Delete the files:
```bash
git rm lib/config/firebase_options.dart lib/services/firebase_group_service.dart
```

In `.github/workflows/build-apk.yml`, remove the two steps `Créer firebase_options.dart` and `Créer dummy google-services.json` (steps 5b and 5c in the existing file).

- [ ] **Step 3: Verify**

```bash
flutter pub get
flutter analyze
```
Expected: no remaining reference to `firebase_core`/`firebase_database`/`firebase_auth`/`FirebaseGroupService`/`DefaultFirebaseOptions` anywhere (Task 16 will touch `GroupProvider`, the only remaining consumer).

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/main.dart .github/workflows/build-apk.yml
git commit -m "chore: retrait de Firebase, remplace par le hub de positions"
```

(This commit will fail `flutter analyze` in isolation because `GroupProvider` still imports `FirebaseGroupService` — that's fine, Task 16 is the very next task and fixes it before any CI run occurs on `main`. If executing via subagent-driven-development with a review gate after each task, mention this dependency explicitly to the reviewer.)

---

### Task 16: `GroupProvider` — create/join via the hub, 20 members

**Files:**
- Modify: `lib/providers/group_provider.dart`
- Test: `test/providers/group_provider_test.dart` (new file)

**Interfaces:**
- Consumes: `TrackerApiClient` (Task 10), injected via constructor.
- Produces: `GroupProvider.maxMembers == 20`; `createSession`/`joinSession` become `Future<bool>`; `sessionId` now holds the real 6-character `joinCode` (spec: what's shown/shared); `GroupMember` gains no new fields (`id`, `name`, `color`, `position`, `speedKmh`, `isSharing`, `lastUpdate`, `isOnline` are unchanged so `map_screen.dart` and `group_screen.dart` keep compiling unmodified against this class). New private fields `_deviceKey`, `_myMemberId` track the caller's own credentials for Task 17's polling.

- [ ] **Step 1: Write the failing test**

`test/providers/group_provider_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moto_offroad/providers/group_provider.dart';
import 'package:moto_offroad/services/tracker_api_client.dart';

void main() {
  test('maxMembers is 20', () {
    expect(GroupProvider.maxMembers, 20);
  });

  test('createSession succeeds and exposes the real join code', () async {
    final client = MockClient((req) async {
      if (req.url.path == '/api/sessions') {
        return http.Response(
          '{"sessionId":"s1","ownerKey":"ok","deviceKey":"dk","memberId":"m1","joinCode":"AB12CD"}',
          201,
        );
      }
      return http.Response('', 404);
    });
    final g = GroupProvider(trackerClient: TrackerApiClient(client: client, baseUrl: 'https://example.test'));

    final ok = await g.createSession('Marc');

    expect(ok, isTrue);
    expect(g.groupActive, isTrue);
    expect(g.sessionId, 'AB12CD');
    expect(g.inviteLink, 'https://motooffroad.duckdns.org/g/AB12CD');
    expect(g.members.length, 1);
    expect(g.members.first.name, 'Marc');
  });

  test('createSession failure leaves the group inactive', () async {
    final client = MockClient((_) async => throw Exception('offline'));
    final g = GroupProvider(trackerClient: TrackerApiClient(client: client, baseUrl: 'https://example.test'));

    final ok = await g.createSession('Marc');

    expect(ok, isFalse);
    expect(g.groupActive, isFalse);
  });

  test('joinSession succeeds and adds self as a member', () async {
    final client = MockClient((req) async {
      if (req.url.path.startsWith('/api/sessions/join/')) {
        return http.Response('{"sessionId":"s1","deviceKey":"dk","memberId":"m2","color":"#1565C0"}', 200);
      }
      return http.Response('', 404);
    });
    final g = GroupProvider(trackerClient: TrackerApiClient(client: client, baseUrl: 'https://example.test'));

    final ok = await g.joinSession('AB12CD', 'Claire');

    expect(ok, isTrue);
    expect(g.groupActive, isTrue);
    expect(g.members.single.name, 'Claire');
  });

  test('joinSession failure (bad code) leaves the group inactive', () async {
    final client = MockClient((_) async => http.Response('', 404));
    final g = GroupProvider(trackerClient: TrackerApiClient(client: client, baseUrl: 'https://example.test'));

    final ok = await g.joinSession('ZZZZZZ', 'Claire');

    expect(ok, isFalse);
    expect(g.groupActive, isFalse);
  });

  test('the creator leaving ends the session for everyone', () async {
    var endCalled = false;
    var leaveCalled = false;
    final client = MockClient((req) async {
      if (req.url.path == '/api/sessions') {
        return http.Response(
          '{"sessionId":"s1","ownerKey":"ok","deviceKey":"dk","memberId":"m1","joinCode":"AB12CD"}',
          201,
        );
      }
      if (req.url.path.endsWith('/end')) { endCalled = true; return http.Response('{}', 200); }
      if (req.method == 'DELETE') { leaveCalled = true; return http.Response('{}', 200); }
      return http.Response('', 404);
    });
    final g = GroupProvider(trackerClient: TrackerApiClient(client: client, baseUrl: 'https://example.test'));
    await g.createSession('Marc');

    g.leaveGroup();
    await Future.delayed(Duration.zero);

    expect(endCalled, isTrue);
    expect(leaveCalled, isFalse);
  });

  test('a joiner (not the creator) leaving only removes themselves', () async {
    var endCalled = false;
    var leaveCalled = false;
    final client = MockClient((req) async {
      if (req.url.path.startsWith('/api/sessions/join/')) {
        return http.Response('{"sessionId":"s1","deviceKey":"dk","memberId":"m2","color":"#1565C0"}', 200);
      }
      if (req.url.path.endsWith('/end')) { endCalled = true; return http.Response('{}', 200); }
      if (req.method == 'DELETE') { leaveCalled = true; return http.Response('{}', 200); }
      return http.Response('', 404);
    });
    final g = GroupProvider(trackerClient: TrackerApiClient(client: client, baseUrl: 'https://example.test'));
    await g.joinSession('AB12CD', 'Claire');

    g.leaveGroup();
    await Future.delayed(Duration.zero);

    expect(leaveCalled, isTrue);
    expect(endCalled, isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/providers/group_provider_test.dart`
Expected: FAIL — `GroupProvider` has no `trackerClient` param, `createSession`/`joinSession` return `void`

- [ ] **Step 3: Write the implementation**

Replace `lib/providers/group_provider.dart`'s top and the session-management methods:
```dart
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../services/tracker_api_client.dart';

// (GroupMember class unchanged)

// ── Provider — Mode Groupe collaboratif ──────────────────────
class GroupProvider extends ChangeNotifier {
  GroupProvider({TrackerApiClient? trackerClient})
      : _tracker = trackerClient ?? TrackerApiClient();

  static const String watchBaseUrl = 'https://motooffroad.duckdns.org/g/';

  final TrackerApiClient _tracker;

  bool _groupActive = false;
  bool get groupActive => _groupActive;

  String? _sessionId;
  String? get sessionId => _sessionId;
  String? _ownerKey;
  String? _deviceKey;
  String? get deviceKey => _deviceKey;
  String? _myMemberId;
  String? get myMemberId => _myMemberId;

  String? get inviteLink => _sessionId != null ? '$watchBaseUrl$_sessionId' : null;

  bool _sharingMyPosition = true;
  bool get sharingMyPosition => _sharingMyPosition;

  final List<GroupMember> _members = [];
  List<GroupMember> get members => List.unmodifiable(_members);

  // Jusqu'à 20 motos par groupe (incluant soi-même) — lot D.
  static const int maxMembers = 20;
  bool get isFull => _members.length >= maxMembers;

  LatLng? _rallyPoint;
  LatLng? get rallyPoint => _rallyPoint;

  // ── Créer une session groupe ──────────────────────────────
  Future<bool> createSession(String myName) async {
    final created = await _tracker.createGroupSession(name: myName);
    if (created == null || created.joinCode == null) return false;

    _sessionId = created.joinCode;
    _ownerKey  = created.ownerKey;
    _deviceKey = created.deviceKey;
    _myMemberId = created.memberId;
    _groupActive = true;
    _members
      ..clear()
      ..add(GroupMember(
        id: created.memberId, name: myName, color: '#5C6BC0',
        isSharing: true, isOnline: true,
      ));
    notifyListeners();
    return true;
  }

  // ── Rejoindre une session ─────────────────────────────────
  Future<bool> joinSession(String joinCode, String myName) async {
    final joined = await _tracker.joinGroupSession(joinCode: joinCode, name: myName);
    if (joined == null) return false;

    _sessionId = joined.sessionId;
    _deviceKey = joined.deviceKey;
    _myMemberId = joined.memberId;
    _groupActive = true;
    _members
      ..clear()
      ..add(GroupMember(
        id: joined.memberId, name: myName, color: joined.color,
        isSharing: true, isOnline: true,
      ));
    notifyListeners();
    return true;
  }

  // (updateMemberPosition, toggleMySharing unchanged)

  // ── Envoyer un point de ralliement ────────────────────────
  Future<void> setRallyPoint(LatLng? point) async {
    final sid = _sessionId, dk = _deviceKey;
    if (sid == null || dk == null) return;
    if (point == null) {
      await _tracker.clearRally(sessionId: sid, deviceKey: dk);
    } else {
      await _tracker.setRally(sessionId: sid, deviceKey: dk, point: point);
    }
    _rallyPoint = point;
    notifyListeners();
  }

  // ── Quitter le groupe ─────────────────────────────────────
  // Le créateur qui quitte éteint le groupe pour tout le monde — spec §8 :
  // "L'extinction du groupe purge tout, immédiatement" (critère de réussite
  // #7). Un invité ne fait que se retirer ; le groupe continue pour les
  // autres. Le distinguo tient à _ownerKey : seul le créateur en reçoit un
  // à la création (joinGroupSession n'en renvoie pas).
  void leaveGroup() {
    final sid = _sessionId, dk = _deviceKey, mid = _myMemberId, ok = _ownerKey;
    if (sid != null && ok != null) {
      _tracker.endSession(sessionId: sid, ownerKey: ok);
    } else if (sid != null && dk != null && mid != null) {
      _tracker.leaveSession(sessionId: sid, deviceKey: dk, memberId: mid);
    }
    _groupActive = false;
    _sessionId = null;
    _ownerKey = null;
    _deviceKey = null;
    _myMemberId = null;
    _members.clear();
    _rallyPoint = null;
    _sharingMyPosition = true;
    notifyListeners();
  }

  // (onlineCount unchanged)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/providers/group_provider_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/providers/group_provider.dart test/providers/group_provider_test.dart
git commit -m "feat: GroupProvider cree/rejoint une session sur le hub, 20 pilotes"
```

---

### Task 17: `GroupProvider` — peer polling and position sharing

**Files:**
- Modify: `lib/providers/group_provider.dart`
- Modify: `test/providers/group_provider_test.dart`

**Interfaces:**
- Consumes: `TrackerApiClient.fetchPeers` (Task 10), `PositionUplinkService` (Task 11) for sending my own position, `LocationService().stream`.
- Produces: `GroupProvider` gains `void startLiveSharing({required Stream<GpsSnapshot> positions})` (called by Task 18's wiring once `groupActive` flips true) and stops both the send-uplink and the peer-poll timer in `leaveGroup()`. Peers are merged into `_members` by `memberId`; a peer absent from a response but already known keeps its last known state (fade/expiry is a `map_screen.dart` display concern per Task 19, not deleted here).

- [ ] **Step 1: Write the failing test**

Add to `test/providers/group_provider_test.dart`:
```dart
import 'dart:async';
import 'package:latlong2/latlong.dart';
import 'package:moto_offroad/services/location_service.dart';

// ... inside main(), alongside the existing tests ...

test('startLiveSharing polls peers and merges them into members', () async {
  var peersCallCount = 0;
  final client = MockClient((req) async {
    if (req.url.path == '/api/sessions') {
      return http.Response(
        '{"sessionId":"s1","ownerKey":"ok","deviceKey":"dk","memberId":"m1","joinCode":"AB12CD"}',
        201,
      );
    }
    if (req.url.path.contains('/peers')) {
      peersCallCount++;
      return http.Response(
        '{"peers":[{"memberId":"m2","name":"Claire","color":"#1565C0","lat":45.2,"lng":5.8,"speedKmh":40,"lastSeen":${DateTime.now().millisecondsSinceEpoch}}],"rally":null}',
        200,
      );
    }
    if (req.url.path.contains('/positions')) {
      return http.Response('{"accepted":1}', 200);
    }
    return http.Response('', 404);
  });
  final g = GroupProvider(trackerClient: TrackerApiClient(client: client, baseUrl: 'https://example.test'));
  await g.createSession('Marc');

  final controller = StreamController<GpsSnapshot>();
  g.startLiveSharing(positions: controller.stream, pollInterval: const Duration(milliseconds: 20));
  await Future.delayed(const Duration(milliseconds: 60));

  expect(peersCallCount, greaterThan(0));
  expect(g.members.any((m) => m.id == 'm2' && m.name == 'Claire'), isTrue);

  g.leaveGroup();
  await controller.close();
});

test('leaveGroup stops the peer poll timer', () async {
  var peersCallCount = 0;
  final client = MockClient((req) async {
    if (req.url.path == '/api/sessions') {
      return http.Response(
        '{"sessionId":"s1","ownerKey":"ok","deviceKey":"dk","memberId":"m1","joinCode":"AB12CD"}',
        201,
      );
    }
    if (req.url.path.contains('/peers')) {
      peersCallCount++;
      return http.Response('{"peers":[],"rally":null}', 200);
    }
    return http.Response('', 404);
  });
  final g = GroupProvider(trackerClient: TrackerApiClient(client: client, baseUrl: 'https://example.test'));
  await g.createSession('Marc');
  final controller = StreamController<GpsSnapshot>();
  g.startLiveSharing(positions: controller.stream, pollInterval: const Duration(milliseconds: 20));
  await Future.delayed(const Duration(milliseconds: 30));

  g.leaveGroup();
  final countAtLeave = peersCallCount;
  await Future.delayed(const Duration(milliseconds: 60));

  expect(peersCallCount, countAtLeave);
  await controller.close();
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/providers/group_provider_test.dart`
Expected: FAIL — no `startLiveSharing` method

- [ ] **Step 3: Write the implementation**

Add to `lib/providers/group_provider.dart` (new imports, new fields, new methods; extends the class from Task 16):
```dart
import 'dart:async';
import '../services/location_service.dart';
import '../services/position_uplink_service.dart';
```

```dart
  Timer? _pollTimer;
  PositionUplinkService? _uplink;

  void startLiveSharing({
    required Stream<GpsSnapshot> positions,
    Duration pollInterval = const Duration(seconds: 3),
  }) {
    final sid = _sessionId, dk = _deviceKey, mid = _myMemberId;
    if (sid == null || dk == null || mid == null) return;

    _uplink?.stop();
    _uplink = PositionUplinkService(sendPositions: _tracker.sendPositions)
      ..start(positions: positions, sessionId: sid, deviceKey: dk, memberId: mid, interval: pollInterval);

    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(pollInterval, (_) async {
      if (!_groupActive) return;
      final peers = await _tracker.fetchPeers(sessionId: sid, deviceKey: dk, memberId: mid);
      for (final peer in peers) {
        final idx = _members.indexWhere((m) => m.id == peer.memberId);
        if (idx >= 0) {
          _members[idx].position   = peer.position;
          _members[idx].speedKmh   = peer.speedKmh;
          _members[idx].lastUpdate = peer.lastSeen;
          _members[idx].isOnline   = true;
        } else {
          _members.add(GroupMember(
            id: peer.memberId, name: peer.name, color: peer.color,
            position: peer.position, speedKmh: peer.speedKmh,
            lastUpdate: peer.lastSeen, isOnline: true,
          ));
        }
      }
      notifyListeners();
    });
  }
```

Update `leaveGroup()` (Task 16's version) to also tear these down — add at the top of the method body:
```dart
  void leaveGroup() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _uplink?.stop();
    _uplink = null;
    // ... (rest of the existing leaveGroup body from Task 16 unchanged) ...
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/providers/group_provider_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/providers/group_provider.dart test/providers/group_provider_test.dart
git commit -m "feat: partage et reception en direct des positions du groupe"
```

---

### Task 18: Wire group live-sharing lifecycle + update `GroupScreen` copy

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/screens/group/group_screen.dart`

**Interfaces:**
- Consumes: `GroupProvider.startLiveSharing` (Task 17), `LocationService().stream`.

- [ ] **Step 1: There is no isolated test for this wiring step**, for the same reason as Task 14 — it is exercised by the existing `smoke_test.dart` and by the already-unit-tested `GroupProvider` methods it calls.

- [ ] **Step 2: Write the implementation**

In `lib/main.dart`, extend `_SoloUplinkHostState.build` (renaming the class is unnecessary — group sharing reuses the same host since both only need to react to provider flags) by also watching `GroupProvider`:
```dart
  @override
  Widget build(BuildContext context) {
    final solo = context.watch<SoloProvider>();
    final group = context.watch<GroupProvider>();

    if (solo.soloActive && !_wasActive) {
      _wasActive = true;
      RideRecordingService().start(
        title: 'Mode Solo Sécurisé actif',
        text: 'Votre position est envoyée à vos contacts de confiance',
      );
      _uplink.start(
        positions: LocationService().stream,
        sessionId: solo.sessionId!,
        deviceKey: solo.deviceKey!,
        memberId: solo.memberId!,
        interval: const Duration(seconds: 5),
      );
    } else if (!solo.soloActive && _wasActive) {
      _wasActive = false;
      _uplink.stop();
    }

    if (group.groupActive && !_groupWasActive) {
      _groupWasActive = true;
      group.startLiveSharing(positions: LocationService().stream);
    } else if (!group.groupActive && _groupWasActive) {
      _groupWasActive = false;
    }

    return widget.child;
  }
```

Add the new field alongside `_wasActive`:
```dart
  bool _groupWasActive = false;
```

(`group.leaveGroup()` — already called from `GroupScreen`'s "Quitter le groupe" button — is what actually stops the timers, per Task 17; this host only needs to *start* sharing on activation and reset its own flag on deactivation, mirroring how `_wasActive` works for Solo.)

In `lib/screens/group/group_screen.dart`, update the copy that still says "10" to "20" (two occurrences: the inactive-state description and nowhere else, since `_sessionCard`/member count already read `GroupProvider.maxMembers` dynamically):
```dart
                const Text('Mode groupe — jusqu\'à 20 motos', style: TextStyle(
```

- [ ] **Step 3: Verify**

Run: `flutter test test/smoke_test.dart`
Expected: PASS

Run: `flutter analyze`
Expected: no new errors

- [ ] **Step 4: Commit**

```bash
git add lib/main.dart lib/screens/group/group_screen.dart
git commit -m "feat: demarrage du partage de position a l activation du groupe"
```

---

### Task 19: Peer marker fade/expiry on the map **[GUI — use impeccable skill]**

**Files:**
- Modify: `lib/screens/map/map_screen.dart`

**Interfaces:**
- Consumes: `GroupMember.lastUpdate` (existing field, now actually populated by Task 17).
- Produces: a marker for a peer whose `lastUpdate` is 30–120 s old renders at reduced opacity; past 120 s it is excluded from the `MarkerLayer` entirely (spec §8: "Un marqueur dont la position dépasse 30 secondes est estompé, et retiré au-delà de 2 minutes").

- [ ] **Step 1: There is no widget-test harness in this codebase for `map_screen.dart`** (it depends on `flutter_map`'s `MapController` and live location plumbing with no existing test precedent in `test/`). Verification is manual, in Step 3.

- [ ] **Step 2: Write the implementation**

In `lib/screens/map/map_screen.dart`, replace the `MarkerLayer` block for group members (currently around line 336-346):
```dart
        // ── Membres du groupe ───────────────────────────────
        MarkerLayer(
          markers: groupProv.members
              .where((m) => m.id != 'me' && m.position != null && m.isSharing)
              .where((m) {
                if (m.lastUpdate == null) return true;
                return DateTime.now().difference(m.lastUpdate!) < const Duration(minutes: 2);
              })
              .map((m) => Marker(
                    point: m.position!,
                    width: 36, height: 36,
                    child: _memberMarker(m.name, m.color, _peerOpacity(m.lastUpdate)),
                  ))
              .toList(),
        ),
```

Add the opacity helper near `_memberMarker` (in the "── MARQUEURS ──" section):
```dart
  double _peerOpacity(DateTime? lastUpdate) {
    if (lastUpdate == null) return 1.0;
    final age = DateTime.now().difference(lastUpdate);
    if (age < const Duration(seconds: 30)) return 1.0;
    return 0.4; // au-delà de 30s et jusqu'à 2min (filtré plus haut) : estompé
  }
```

Update `_memberMarker` to accept and apply the opacity:
```dart
  Widget _memberMarker(String name, String colorHex, [double opacity = 1.0]) {
    final color = Color(int.parse('0xFF${colorHex.replaceFirst('#', '')}'));
    return Opacity(
      opacity: opacity,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle, color: color,
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: Center(child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
        )),
      ),
    );
  }
```

- [ ] **Step 3: Manual verification**

```bash
flutter run
# Créer un groupe sur deux appareils (ou un appareil + curl simulant un
# second pilote via POST /api/sessions/join puis /positions), vérifier que :
#  - le marqueur pair apparaît normalement pendant 30s
#  - il s'estompe entre 30s et 2min sans nouvelle position
#  - il disparaît de la carte après 2min
```

- [ ] **Step 4: Apply the impeccable skill**

Invoke the `impeccable` skill on the map's group-marker treatment (fresh vs. faded vs. the rider's own marker vs. the rally marker) to confirm the visual hierarchy stays legible with up to 20 markers on screen at once, adjusting size/contrast/clustering if needed at that density.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/map/map_screen.dart
git commit -m "feat: estompage et expiration des marqueurs pairs sur la carte"
```

---

## Post-plan checklist (not a task — a reminder for whoever merges)

- Run the full Flutter suite (`flutter test`) and `flutter analyze` once after Task 19 — every task above only runs its own test file.
- Build and sideload the APK on a real device for the two things `flutter test` cannot verify: background GPS delivery to the hub with the screen off (Solo), and the `sms:` intent actually opening with a prefilled body on the target phone.
- The server repo (Part 1) and the app repo are deployed independently — pushing the app doesn't touch the Hetzner server, and vice versa; there's no single "done" commit that covers both.
