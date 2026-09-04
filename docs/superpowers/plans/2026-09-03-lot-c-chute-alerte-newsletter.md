# Lot C — Chute, chaîne d'alerte et newsletter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detect a real fall (shock, then stop, then frozen tilt), give the rider 15-120s to cancel, and if not cancelled, alert on two channels — a phone-native SMS and a server e-mail to the trusted contacts (with a copy to the pilot) — while adding a strictly opt-in newsletter list, never auto-populated from safety data.

**Architecture:** The app gets a pure, stream-driven `FallDetector` state machine (shock → 20s stillness+no-tilt window → callback), a full-screen cancellable countdown, and an alert orchestrator reusing the already-approved `CallBridge.sendSms` (native SMS) and a new hub endpoint. The server gains e-mail sending (Brevo SMTP via `nodemailer`), triggered from both the existing deadman/immobility sweep and a new `/alert` endpoint, plus a `subscriber` table fed only by explicit opt-in (never by session data).

**Tech Stack:** App: existing Flutter stack only (`sensors_plus` already present for the accelerometer; `SystemSound`/`HapticFeedback` from `flutter/services.dart`, already a transitive Flutter dependency, cover the alarm sound/vibration — no new package). Server: `nodemailer` is the one new dependency (SMTP has no built-in Node alternative).

**Spec:** `docs/superpowers/specs/2026-09-03-suivi-securite-personne-de-confiance-design.md`, §7 (fall detection and alert chain), §9-14 (settings, dependencies, success criteria), and §15 (addendum of 2026-09-03: mandatory pilot/contact e-mails, opt-in-only newsletter, Brevo, no dead SMS-gateway/voice code).

## Deliberate deviations (documented, not oversights)

1. **No SMS-gateway or voice-call integration is written — only the lock and the greyed-out settings.** Per addendum §15.4, writing an integration nothing calls (subscriptions don't exist yet) repeats this project's own "written, never called" mistake, already hit once with `FirebaseGroupService`.
2. **Alarm sound uses `SystemSound.play(SystemSoundType.alert)` on a repeating timer, not a new audio package.** The app has no audio-file player today; adding one (`audioplayers` or similar) for a single repeated alert tone is more than this needs. A system alert sound fired every second, combined with `HapticFeedback.vibrate()` on the same cadence, is an audible+tactile alarm with zero new dependencies — consistent with every prior lot's dependency discipline.
3. **The shock threshold, when calibrated, is a documented formula, not a spec-given constant.** Spec §7.1 gives only the uncalibrated fallback (4g) and says a calibrated threshold is "more accurate than a universal one," without a formula. Task 13 below defines and justifies one concrete formula; it is a judgment call flagged here for visibility, not a hidden assumption.
4. **`session.pilot_email` and a new `alert_contact` table extend the hub's data model beyond the original Lot A design**, per addendum §15.1 — the spec's original "first name only" privacy rule for the hub is explicitly superseded by the addendum for this lot, not silently broken.

## Global Constraints

- No new Flutter dependencies (see deviation #2).
- Server: the only new dependency is `nodemailer` (`^6.9.0` or later).
- Fall detection parameters, exact per spec §7.1-7.2: shock check first, then GPS stop (**< 3 km/h for 20 s**) and frozen tilt (**≤ 5° variation for 20 s**) — both conditions must hold for the *same* 20 s window; countdown **15-120 s, default 30 s**; a single tap cancels; detection has one master on/off switch.
- Alert channels are user-selectable: phone alone, server alone, or both (§7.3). SMS-gateway and voice-call remain locked (§7.4, §15.4) — `AlertChannelUnlock.isUnlocked(...)` always returns `false` in this lot.
- Pilot e-mail is **mandatory** to activate Solo mode (§15.1). Trusted-contact e-mail is a **required** field when adding a contact (§15.1) — existing contacts added before this lot have no e-mail; Task 8 handles the migration explicitly.
- Newsletter subscription is **opt-in only**, from two sources: the pilot's own checkbox (default off) and a contact clicking a link in an alert e-mail or on the watch page (§15.2). No code path may insert into `subscriber` from session/contact data without one of these two explicit actions.
- `deadman_after` becomes a per-session, user-configurable value (§15.5) — no longer the fixed constant from Lot A.
- Server e-mail: Brevo SMTP, credentials via environment variables only, never committed (§15.3).
- A session alerts only once — `alerted_at` already enforces this (Lot A); Task 12's `/alert` endpoint must respect the same rule, not add a second alert path.

---

# Part 1 — Server (moto-tracker-server)

All tasks in this part run in `/Users/marc/Claude/Projects/APP OFFROAD MOTO 4X4/moto-tracker-server`, already a deployed, tested repo (34+ tests passing). This Mac's Xcode Command Line Tools cannot compile `better-sqlite3` — **always run tests via the `node:18` Docker command already established in this project:**
```
docker run --rm -v "/Users/marc/Claude/Projects/APP OFFROAD MOTO 4X4/moto-tracker-server:/app" -w /app node:18 sh -c "npm install && npm test"
```

### Task 1: Schema — pilot e-mail, contact e-mails, configurable deadman

**Files:**
- Modify: `src/db.js`
- Modify: `src/routes/sessions.js`
- Modify: `test/sessions.test.js`

**Interfaces:**
- Produces: `session.pilot_email TEXT` column; new table `alert_contact (id INTEGER PRIMARY KEY, session_id TEXT NOT NULL REFERENCES session(id) ON DELETE CASCADE, email TEXT NOT NULL)`. `POST /api/sessions` for `kind: 'solo'` now requires `pilotEmail` (string) and `contactEmails` (non-empty array of strings, max 3) in the body, and accepts an optional `deadmanAfterSec` (defaults to the existing 15-minute constant). Group sessions are unaffected (no pilot/contact e-mails, no deadman).

- [ ] **Step 1: Write the failing test**

Add to `test/sessions.test.js` (uses the file's existing `buildApp`/`listen` helpers):
```js
test('a solo session requires a pilot email and at least one contact email', async () => {
  const { app } = buildApp();
  const { server, base } = await listen(app);
  const res = await fetch(`${base}/api/sessions`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ kind: 'solo', name: 'Marc' }), // pas d'e-mails
  });
  assert.equal(res.status, 400);
  server.close();
});

test('a solo session stores the pilot email and contact emails, with a configurable deadman', async () => {
  const { app, db } = buildApp();
  const { server, base } = await listen(app);
  const res = await fetch(`${base}/api/sessions`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      kind: 'solo', name: 'Marc',
      pilotEmail: 'marc@example.test',
      contactEmails: ['claire@example.test', 'jean@example.test'],
      deadmanAfterSec: 600,
    }),
  });
  const body = await res.json();
  assert.equal(res.status, 201);

  const session = db.prepare('SELECT pilot_email, deadman_after FROM session WHERE id = ?').get(body.sessionId);
  assert.equal(session.pilot_email, 'marc@example.test');
  assert.equal(session.deadman_after, 600);

  const contacts = db.prepare('SELECT email FROM alert_contact WHERE session_id = ? ORDER BY email').all(body.sessionId);
  assert.deepEqual(contacts.map((c) => c.email), ['claire@example.test', 'jean@example.test']);
  server.close();
});

test('a solo session rejects more than 3 contact emails', async () => {
  const { app } = buildApp();
  const { server, base } = await listen(app);
  const res = await fetch(`${base}/api/sessions`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      kind: 'solo', name: 'Marc', pilotEmail: 'marc@example.test',
      contactEmails: ['a@x.test', 'b@x.test', 'c@x.test', 'd@x.test'],
    }),
  });
  assert.equal(res.status, 400);
  server.close();
});

test('a group session does not require pilot or contact emails', async () => {
  const { app } = buildApp();
  const { server, base } = await listen(app);
  const res = await fetch(`${base}/api/sessions`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ kind: 'group', name: 'Marc' }),
  });
  assert.equal(res.status, 201);
  server.close();
});

test('deleting a session cascades to alert_contact rows', async () => {
  const { app, db } = buildApp();
  const { server, base } = await listen(app);
  const created = await (
    await fetch(`${base}/api/sessions`, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        kind: 'solo', name: 'Marc', pilotEmail: 'marc@example.test',
        contactEmails: ['claire@example.test'],
      }),
    })
  ).json();

  await fetch(`${base}/api/sessions/${created.sessionId}/end`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ ownerKey: created.ownerKey }),
  });

  const remaining = db.prepare('SELECT COUNT(*) AS n FROM alert_contact WHERE session_id = ?').get(created.sessionId).n;
  assert.equal(remaining, 0);
  server.close();
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `docker run --rm -v "/Users/marc/Claude/Projects/APP OFFROAD MOTO 4X4/moto-tracker-server:/app" -w /app node:18 sh -c "npm install && npm test"`
Expected: FAIL — 400 not returned (no validation yet), `pilot_email`/`alert_contact` don't exist.

- [ ] **Step 3: Write the implementation**

In `src/db.js`, add the column to the `session` table definition and the new table to `SCHEMA`:
```sql
CREATE TABLE IF NOT EXISTS session (
  id             TEXT PRIMARY KEY,
  kind           TEXT NOT NULL CHECK (kind IN ('solo','group')),
  watch_token    TEXT UNIQUE,
  join_code      TEXT UNIQUE,
  owner_key      TEXT NOT NULL,
  pilot_email    TEXT,
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
```
(only `pilot_email` is new in this block — every other column is unchanged, keep them exactly as they are in the current file)

Add after the `member` table definition, before `position`:
```sql
CREATE TABLE IF NOT EXISTS alert_contact (
  id         INTEGER PRIMARY KEY,
  session_id TEXT NOT NULL REFERENCES session(id) ON DELETE CASCADE,
  email      TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_alert_contact_session ON alert_contact(session_id);
```

**Also modify the `openDb` function in this same file — this is the part of this task most likely to be missed, and without it, this task's whole feature silently fails against the already-deployed production database.** `CREATE TABLE IF NOT EXISTS` only helps a brand-new database file: the production server's `data/tracker.db` already has a `session` table from before this column existed, and SQLite has no "ADD COLUMN IF NOT EXISTS". Read the current `openDb` function (it currently just runs `db.exec(SCHEMA)` and returns `db`) and change it to:
```js
function openDb(path) {
  const db = new Database(path);
  db.pragma('journal_mode = WAL');
  db.pragma('foreign_keys = ON');
  db.exec(SCHEMA);
  migrate(db);
  return db;
}

// Runs on every openDb call, including every test's fresh :memory: database
// (a harmless no-op there, since a brand-new CREATE TABLE already has the
// column) — this is the only thing that makes the column actually appear
// on the live server's existing database after a deploy.
function migrate(db) {
  const columns = db.prepare('PRAGMA table_info(session)').all().map((c) => c.name);
  if (!columns.includes('pilot_email')) {
    db.exec('ALTER TABLE session ADD COLUMN pilot_email TEXT');
  }
}
```
Add a test for this to `test/db.test.js` (this repo's existing schema test file — check its current content for the exact style). `:memory:` databases can't be reopened by path, and the migration only matters when re-opening an *existing* file, so this test uses a real temp file to genuinely exercise that path:
```js
test('migrate adds pilot_email to a session table created before this column existed', () => {
  const Database = require('better-sqlite3');
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');

  const file = path.join(os.tmpdir(), `migrate-test-${Date.now()}.db`);
  const real = new Database(file);
  real.exec(`CREATE TABLE session (
    id TEXT PRIMARY KEY, kind TEXT NOT NULL, watch_token TEXT UNIQUE, join_code TEXT UNIQUE,
    owner_key TEXT NOT NULL, created_at INTEGER NOT NULL, expires_at INTEGER NOT NULL,
    ended_at INTEGER, deadman_after INTEGER, immobile_after INTEGER, alerted_at INTEGER,
    alert_kind TEXT, rally_lat REAL, rally_lng REAL
  )`);
  real.close();

  const migrated = openDb(file); // le vrai openDb : exec(SCHEMA) + migrate()
  const after = migrated.prepare('PRAGMA table_info(session)').all().map((c) => c.name);
  assert.ok(after.includes('pilot_email'));
  migrated.close();
  fs.unlinkSync(file);
});
```

In `src/routes/sessions.js`, modify the `POST /` handler. Replace:
```js
  router.post('/', (req, res) => {
    const { kind, name, immobileAfterSec } = req.body ?? {};
    if (kind !== 'solo' && kind !== 'group') {
      return res.status(400).json({ error: 'kind must be "solo" or "group"' });
    }
    if (typeof name !== 'string' || name.trim() === '') {
      return res.status(400).json({ error: 'name is required' });
    }

    const now = Date.now();
```
with:
```js
  router.post('/', (req, res) => {
    const { kind, name, immobileAfterSec, deadmanAfterSec, pilotEmail, contactEmails } = req.body ?? {};
    if (kind !== 'solo' && kind !== 'group') {
      return res.status(400).json({ error: 'kind must be "solo" or "group"' });
    }
    if (typeof name !== 'string' || name.trim() === '') {
      return res.status(400).json({ error: 'name is required' });
    }
    if (kind === 'solo') {
      if (typeof pilotEmail !== 'string' || !pilotEmail.includes('@')) {
        return res.status(400).json({ error: 'pilotEmail is required for a solo session' });
      }
      if (!Array.isArray(contactEmails) || contactEmails.length === 0 || contactEmails.length > 3) {
        return res.status(400).json({ error: 'contactEmails must have 1 to 3 entries for a solo session' });
      }
      if (contactEmails.some((e) => typeof e !== 'string' || !e.includes('@'))) {
        return res.status(400).json({ error: 'every contact email must be a valid-looking address' });
      }
    }

    const now = Date.now();
```

Then update the session INSERT (find the existing `INSERT INTO session ...` for creation) to add `pilot_email` and use `deadmanAfterSec`:
```js
    db.prepare(
      `INSERT INTO session
         (id, kind, watch_token, join_code, owner_key, pilot_email, created_at, expires_at,
          deadman_after, immobile_after)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    ).run(
      sessionId, kind, watchToken, joinCode, ownerKey,
      kind === 'solo' ? pilotEmail : null,
      now, now + SESSION_TTL_MS,
      kind === 'solo' ? (deadmanAfterSec ?? DEFAULT_DEADMAN_AFTER_SEC) : null,
      kind === 'solo' ? (immobileAfterSec ?? DEFAULT_IMMOBILE_AFTER_SEC) : null,
    );
```
(the `member` INSERT right after is unchanged)

Then, still inside the `POST /` handler, right after the member INSERT and before building `body`, insert the contact rows:
```js
    if (kind === 'solo') {
      const insertContact = db.prepare('INSERT INTO alert_contact (session_id, email) VALUES (?, ?)');
      for (const email of contactEmails) insertContact.run(sessionId, email);
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `docker run --rm -v "/Users/marc/Claude/Projects/APP OFFROAD MOTO 4X4/moto-tracker-server:/app" -w /app node:18 sh -c "npm install && npm test"`
Expected: PASS — all tests in `sessions.test.js`, plus every pre-existing test file, still green.

- [ ] **Step 5: Commit**

```bash
git add src/db.js src/routes/sessions.js test/sessions.test.js
git commit -m "feat: e-mail pilote/contacts et delai homme-mort configurable"
```

---

### Task 2: Mailer module (Brevo SMTP via nodemailer)

**Files:**
- Modify: `package.json`
- Create: `src/mailer.js`
- Test: `test/mailer.test.js`

**Interfaces:**
- Consumes: `nodemailer` (new dependency).
- Produces: `createTransport(): Transport` (real SMTP, reads `SMTP_HOST`/`SMTP_PORT`/`SMTP_USER`/`SMTP_PASS` from `process.env`) and `createMailer(transport): { sendAlertEmail(params): Promise<void> }`, where `params` is `{ pilotEmail, pilotName, contactEmails, kind, lastPosition: {lat,lng}|null, watchUrl }`. `kind` is one of `'deadman' | 'immobile' | 'fall' | 'sos'`. Later tasks (3, 4) call `createMailer`'s `sendAlertEmail` with a real or fake transport.

- [ ] **Step 1: Write the failing test**

`test/mailer.test.js`:
```js
const test = require('node:test');
const assert = require('node:assert/strict');
const { createMailer } = require('../src/mailer');

function fakeTransport() {
  return { sent: [], async sendMail(opts) { this.sent.push(opts); return {}; } };
}

test('sends one email per contact plus a copy to the pilot', async () => {
  const transport = fakeTransport();
  const mailer = createMailer(transport);
  await mailer.sendAlertEmail({
    pilotEmail: 'marc@example.test',
    pilotName: 'Marc',
    contactEmails: ['claire@example.test', 'jean@example.test'],
    kind: 'fall',
    lastPosition: { lat: 45.5, lng: 6.1 },
    watchUrl: 'https://motooffroad.duckdns.org/s/abc123',
  });

  assert.equal(transport.sent.length, 3); // 2 contacts + 1 copie pilote
  const toContact = transport.sent.filter((m) => m.to !== 'marc@example.test');
  assert.equal(toContact.length, 2);
  assert.ok(toContact.every((m) => m.replyTo === 'marc@example.test'));
  assert.ok(toContact.every((m) => m.text.includes('45.5') && m.text.includes('6.1')));
  assert.ok(toContact.every((m) => m.text.includes('https://motooffroad.duckdns.org/s/abc123')));
  assert.ok(toContact.every((m) => m.subject.includes('Marc')));

  const copy = transport.sent.find((m) => m.to === 'marc@example.test');
  assert.ok(copy.subject.startsWith('[Copie]'));
});

test('a null last position is described in words, not coordinates', async () => {
  const transport = fakeTransport();
  const mailer = createMailer(transport);
  await mailer.sendAlertEmail({
    pilotEmail: 'marc@example.test', pilotName: 'Marc',
    contactEmails: ['claire@example.test'], kind: 'deadman',
    lastPosition: null, watchUrl: 'https://motooffroad.duckdns.org/s/abc123',
  });
  assert.ok(transport.sent[0].text.includes('Position inconnue'));
});

test('the subject names the alert kind in French', async () => {
  const transport = fakeTransport();
  const mailer = createMailer(transport);
  await mailer.sendAlertEmail({
    pilotEmail: 'marc@example.test', pilotName: 'Marc',
    contactEmails: ['claire@example.test'], kind: 'immobile',
    lastPosition: null, watchUrl: 'https://motooffroad.duckdns.org/s/abc123',
  });
  assert.match(transport.sent[0].subject, /immobilit/i);
});

test('a transport failure on one recipient does not stop the others', async () => {
  const transport = {
    sent: [],
    async sendMail(opts) {
      if (opts.to === 'claire@example.test') throw new Error('smtp down');
      this.sent.push(opts);
      return {};
    },
  };
  const mailer = createMailer(transport);
  await mailer.sendAlertEmail({
    pilotEmail: 'marc@example.test', pilotName: 'Marc',
    contactEmails: ['claire@example.test', 'jean@example.test'], kind: 'fall',
    lastPosition: null, watchUrl: 'https://motooffroad.duckdns.org/s/abc123',
  });
  // jean et la copie pilote doivent quand meme partir malgre l'echec pour claire
  assert.ok(transport.sent.some((m) => m.to === 'jean@example.test'));
  assert.ok(transport.sent.some((m) => m.to === 'marc@example.test'));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `docker run --rm -v "/Users/marc/Claude/Projects/APP OFFROAD MOTO 4X4/moto-tracker-server:/app" -w /app node:18 sh -c "npm install && npm test"`
Expected: FAIL with "Cannot find module '../src/mailer'"

- [ ] **Step 3: Write the implementation**

In `package.json`, add to `dependencies`:
```json
    "nodemailer": "^6.9.14"
```

`src/mailer.js`:
```js
const nodemailer = require('nodemailer');

const SUBJECT_BY_KIND = {
  deadman:  'Silence prolongé',
  immobile: 'Immobilité prolongée',
  fall:     'Chute détectée',
  sos:      'Alerte SOS',
};

function createTransport() {
  return nodemailer.createTransport({
    host: process.env.SMTP_HOST,
    port: Number(process.env.SMTP_PORT || 587),
    secure: false,
    auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS },
  });
}

function buildMessage({ pilotName, kind, lastPosition, watchUrl, forContactEmail }) {
  const label = SUBJECT_BY_KIND[kind] ?? 'Alerte';
  const subject = `⚠️ ${label} — ${pilotName}`;
  const positionLine = lastPosition
    ? `Dernière position connue : https://maps.google.com/?q=${lastPosition.lat},${lastPosition.lng}`
    : 'Position inconnue';
  const newsletterLink = forContactEmail
    ? `\n\nRecevoir les nouvelles de MOTO OFFROAD 4X4 : https://motooffroad.duckdns.org/api/newsletter/subscribe-link?email=${encodeURIComponent(forContactEmail)}&source=contact`
    : '';
  const text =
    `${pilotName} a peut-être besoin d'aide.\n\n` +
    `${positionLine}\n` +
    `Suivi en direct : ${watchUrl}\n\n` +
    `Vous recevez cet e-mail car vous êtes enregistré comme contact de confiance de ${pilotName}.` +
    newsletterLink;
  return { subject, text };
}

function createMailer(transport) {
  async function sendAlertEmail({ pilotEmail, pilotName, contactEmails, kind, lastPosition, watchUrl }) {
    const from = process.env.MAIL_FROM;

    await Promise.all(contactEmails.map(async (to) => {
      const { subject, text } = buildMessage({ pilotName, kind, lastPosition, watchUrl, forContactEmail: to });
      try {
        await transport.sendMail({ from, to, replyTo: pilotEmail, subject, text });
      } catch (_) {
        // Un contact injoignable ne doit pas empêcher l'alerte d'atteindre les autres.
      }
    }));

    if (pilotEmail) {
      const { subject, text } = buildMessage({ pilotName, kind, lastPosition, watchUrl, forContactEmail: null });
      try {
        await transport.sendMail({ from, to: pilotEmail, subject: `[Copie] ${subject}`, text });
      } catch (_) {
        // Idem : la copie pilote est un confort, pas la fonction de sécurité elle-même.
      }
    }
  }

  return { sendAlertEmail };
}

module.exports = { createMailer, createTransport };
```

- [ ] **Step 4: Run test to verify it passes**

Run: `docker run --rm -v "/Users/marc/Claude/Projects/APP OFFROAD MOTO 4X4/moto-tracker-server:/app" -w /app node:18 sh -c "npm install && npm test"`
Expected: PASS (all `mailer.test.js` tests, plus every pre-existing test file)

- [ ] **Step 5: Commit**

```bash
git add package.json package-lock.json src/mailer.js test/mailer.test.js
git commit -m "feat: module d envoi d e-mail d alerte (Brevo SMTP)"
```

---

### Task 3: Wire alert e-mails into the deadman/immobility sweep

**Files:**
- Modify: `src/sweep.js`
- Modify: `test/sweep.test.js`

**Interfaces:**
- Consumes: nothing new at the pure-logic level — `onAlert` is an injected callback, so this task has no hard dependency on Task 2's real mailer.
- Produces: `checkDeadmanAndImmobility(db, now, onAlert)` — `onAlert` is `(sessionId: string, kind: 'deadman'|'immobile') => void`, called exactly once per newly-alerted session, synchronously, right after the DB write that sets `alerted_at`. `startSweeps(db, { onAlert })` threads the same callback through on its existing 30s interval. Task 6 (server.js wiring) supplies the production `onAlert` that looks up contacts/position and calls Task 2's `sendAlertEmail`.

- [ ] **Step 1: Write the failing test**

Add to `test/sweep.test.js` (reuses the existing `makeSoloSession` helper):
```js
test('checkDeadmanAndImmobility calls onAlert exactly once when a deadman alert fires', () => {
  const db = openDb(':memory:');
  const now = makeSoloSession(db, { deadmanAfter: 900 });
  db.prepare(
    `INSERT INTO position (session_id, member_id, lat, lng, recorded_at, received_at)
     VALUES ('s1','m1',45,5,?,?)`
  ).run(now - 1000 * 1000, now - 1000 * 1000);

  const calls = [];
  checkDeadmanAndImmobility(db, now, (sessionId, kind) => calls.push([sessionId, kind]));

  assert.deepEqual(calls, [['s1', 'deadman']]);
});

test('checkDeadmanAndImmobility does not call onAlert when nothing fires', () => {
  const db = openDb(':memory:');
  const now = makeSoloSession(db);
  db.prepare(
    `INSERT INTO position (session_id, member_id, lat, lng, recorded_at, received_at)
     VALUES ('s1','m1',45,5,?,?)`
  ).run(now - 5000, now - 5000);

  const calls = [];
  checkDeadmanAndImmobility(db, now, (sessionId, kind) => calls.push([sessionId, kind]));

  assert.deepEqual(calls, []);
});

test('onAlert is optional — omitting it does not throw', () => {
  const db = openDb(':memory:');
  const now = makeSoloSession(db, { deadmanAfter: 900 });
  db.prepare(
    `INSERT INTO position (session_id, member_id, lat, lng, recorded_at, received_at)
     VALUES ('s1','m1',45,5,?,?)`
  ).run(now - 1000 * 1000, now - 1000 * 1000);

  assert.doesNotThrow(() => checkDeadmanAndImmobility(db, now));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `docker run --rm -v "/Users/marc/Claude/Projects/APP OFFROAD MOTO 4X4/moto-tracker-server:/app" -w /app node:18 sh -c "npm install && npm test"`
Expected: FAIL — `onAlert` is never called (current signature ignores a third argument)

- [ ] **Step 3: Write the implementation**

In `src/sweep.js`, change the function signature and both places that set `alerted_at`:
```js
function checkDeadmanAndImmobility(db, now, onAlert) {
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
      onAlert?.(session.id, 'deadman');
      continue;
    }

    if (!session.immobile_after) continue;
    const windowStart = now - session.immobile_after * 1000;
    if (session.created_at > windowStart) continue; // la session n'a pas encore vecu une fenetre complete : trop tot pour juger
    const recent = db
      .prepare('SELECT lat, lng, recorded_at FROM position WHERE session_id = ? AND recorded_at >= ? ORDER BY id ASC')
      .all(session.id, windowStart);
    if (recent.length < 2) continue; // pas assez d'historique sur la fenêtre pour juger

    const origin = recent[0];
    const strayed = recent.some((p) => haversineMeters(origin, p) > IMMOBILE_RADIUS_METERS);
    if (!strayed) {
      db.prepare('UPDATE session SET alerted_at = ?, alert_kind = ? WHERE id = ?').run(now, 'immobile', session.id);
      onAlert?.(session.id, 'immobile');
    }
  }
}
```

And `startSweeps`:
```js
function startSweeps(db, { onAlert } = {}) {
  const fast = setInterval(() => checkDeadmanAndImmobility(db, Date.now(), onAlert), 30 * 1000);
  const slow = setInterval(() => purgeExpired(db, Date.now()), 60 * 60 * 1000);
  return { stop: () => { clearInterval(fast); clearInterval(slow); } };
}
```

(`haversineMeters`, `purgeExpired`, `IMMOBILE_RADIUS_METERS`, `RETENTION_MS`, `ORPHAN_GRACE_MS` are all unchanged — only the two signatures above change.)

- [ ] **Step 4: Run test to verify it passes**

Run: `docker run --rm -v "/Users/marc/Claude/Projects/APP OFFROAD MOTO 4X4/moto-tracker-server:/app" -w /app node:18 sh -c "npm install && npm test"`
Expected: PASS (all `sweep.test.js` tests, plus every pre-existing test file)

- [ ] **Step 5: Commit**

```bash
git add src/sweep.js test/sweep.test.js
git commit -m "feat: le balayage homme-mort/immobilite declenche un rappel d alerte"
```

---

### Task 4: `POST /:id/alert` endpoint (fall/SOS)

**Files:**
- Modify: `src/routes/sessions.js`
- Modify: `test/sessions.test.js`

**Interfaces:**
- Consumes: the same `authMember` helper already in this file.
- Produces: `createSessionsRouter(db, { onAlert } = {})` gains an options parameter (mirrors Task 3's `startSweeps`); the router gains `POST /:id/alert`, body `{ deviceKey, memberId, kind }` where `kind` is `'fall'|'sos'`. Sets `alerted_at`/`alert_kind` only if not already alerted (same one-alert-per-session rule as the sweep), then calls `onAlert(sessionId, kind)` if provided. Existing callers of `createSessionsRouter(db)` (Task 8's `server.test.js`, if it constructs the router directly — check) keep working since the options parameter defaults to `{}`.

- [ ] **Step 1: Write the failing test**

Add to `test/sessions.test.js`. This file's `buildApp()` helper currently does `app.use('/api/sessions', createSessionsRouter(db))` — update it to accept an optional `onAlert` and thread it through, since these new tests need to observe the callback:
```js
function buildApp(onAlert) {
  const db = openDb(':memory:');
  const app = express();
  app.use(express.json());
  app.use('/api/sessions', createSessionsRouter(db, { onAlert }));
  return { app, db };
}
```
(this is a change to the existing helper at the top of the file — every existing test calling `buildApp()` with no argument keeps working unchanged, since `onAlert` becomes `undefined` and the router already treats it as optional per Task 3's pattern)

Then add:
```js
test('POST /:id/alert sets alerted_at and calls onAlert once', async () => {
  const calls = [];
  const { app } = buildApp((sessionId, kind) => calls.push([sessionId, kind]));
  const { server, base } = await listen(app);
  const created = await (
    await fetch(`${base}/api/sessions`, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        kind: 'solo', name: 'Marc', pilotEmail: 'marc@example.test',
        contactEmails: ['claire@example.test'],
      }),
    })
  ).json();

  const res = await fetch(`${base}/api/sessions/${created.sessionId}/alert`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ deviceKey: created.deviceKey, memberId: created.memberId, kind: 'fall' }),
  });
  assert.equal(res.status, 200);
  assert.deepEqual(calls, [[created.sessionId, 'fall']]);
  server.close();
});

test('POST /:id/alert only fires once even if called twice', async () => {
  let callCount = 0;
  const { app } = buildApp(() => callCount++);
  const { server, base } = await listen(app);
  const created = await (
    await fetch(`${base}/api/sessions`, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        kind: 'solo', name: 'Marc', pilotEmail: 'marc@example.test',
        contactEmails: ['claire@example.test'],
      }),
    })
  ).json();

  const call = () => fetch(`${base}/api/sessions/${created.sessionId}/alert`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ deviceKey: created.deviceKey, memberId: created.memberId, kind: 'fall' }),
  });
  await call();
  await call();
  assert.equal(callCount, 1);
  server.close();
});

test('POST /:id/alert rejects an invalid kind', async () => {
  const { app } = buildApp();
  const { server, base } = await listen(app);
  const created = await (
    await fetch(`${base}/api/sessions`, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        kind: 'solo', name: 'Marc', pilotEmail: 'marc@example.test',
        contactEmails: ['claire@example.test'],
      }),
    })
  ).json();
  const res = await fetch(`${base}/api/sessions/${created.sessionId}/alert`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ deviceKey: created.deviceKey, memberId: created.memberId, kind: 'nonsense' }),
  });
  assert.equal(res.status, 400);
  server.close();
});

test('POST /:id/alert rejects bad credentials', async () => {
  const { app } = buildApp();
  const { server, base } = await listen(app);
  const created = await (
    await fetch(`${base}/api/sessions`, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        kind: 'solo', name: 'Marc', pilotEmail: 'marc@example.test',
        contactEmails: ['claire@example.test'],
      }),
    })
  ).json();
  const res = await fetch(`${base}/api/sessions/${created.sessionId}/alert`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ deviceKey: 'wrong', memberId: created.memberId, kind: 'fall' }),
  });
  assert.equal(res.status, 403);
  server.close();
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `docker run --rm -v "/Users/marc/Claude/Projects/APP OFFROAD MOTO 4X4/moto-tracker-server:/app" -w /app node:18 sh -c "npm install && npm test"`
Expected: FAIL — 404 on `/alert` (route doesn't exist), and every OTHER existing test in this file also fails at first because `buildApp()`'s signature changed — fix the helper first (Step 1 already shows its new form), rerun, confirm only the four new tests fail, then proceed to Step 3.

- [ ] **Step 3: Write the implementation**

In `src/routes/sessions.js`, change the exported function's signature:
```js
function createSessionsRouter(db, { onAlert } = {}) {
```

Add the new route just above `return router;`:
```js
  router.post('/:id/alert', (req, res) => {
    const { deviceKey, memberId, kind } = req.body ?? {};
    if (kind !== 'fall' && kind !== 'sos') {
      return res.status(400).json({ error: 'kind must be "fall" or "sos"' });
    }
    const member = authMember(req.params.id, deviceKey, memberId);
    if (!member) return res.status(403).json({ error: 'invalid credentials' });

    const session = db.prepare('SELECT alerted_at FROM session WHERE id = ?').get(req.params.id);
    if (session.alerted_at == null) {
      db.prepare('UPDATE session SET alerted_at = ?, alert_kind = ? WHERE id = ?').run(Date.now(), kind, req.params.id);
      onAlert?.(req.params.id, kind);
    }
    res.status(200).json({});
  });
```

- [ ] **Step 4: Run test to verify it passes**

Run: `docker run --rm -v "/Users/marc/Claude/Projects/APP OFFROAD MOTO 4X4/moto-tracker-server:/app" -w /app node:18 sh -c "npm install && npm test"`
Expected: PASS (all tests in `sessions.test.js`, plus every pre-existing test file — double check `test/server.test.js` and `test/watch.test.js` don't independently construct `createSessionsRouter(db)` in a way this default-argument change would break; if they do, they need no code change since `{ onAlert } = {}` keeps a zero-argument call working identically).

- [ ] **Step 5: Commit**

```bash
git add src/routes/sessions.js test/sessions.test.js
git commit -m "feat: endpoint d alerte chute/SOS"
```

---

### Task 5: Newsletter routes and `subscriber` table

**Files:**
- Modify: `src/db.js`
- Create: `src/routes/newsletter.js`
- Test: `test/newsletter.test.js`

**Interfaces:**
- Consumes: `randomToken` from `src/secrets.js` (already used elsewhere in this repo).
- Produces: table `subscriber (email TEXT PRIMARY KEY, subscribed_at INTEGER NOT NULL, source TEXT NOT NULL CHECK (source IN ('pilot','contact')), unsubscribe_token TEXT UNIQUE NOT NULL)` — deliberately **not** referencing `session`, no cascade, never auto-purged. `createNewsletterRouter(db): express.Router`, mounted at `/api/newsletter` by Task 6 (server.js). Routes: `POST /subscribe` (body `{email, source}`), `GET /subscribe-link` (query `?email=&source=`, one-click from an e-mail), `GET /unsubscribe/:token`, `GET /export?key=` (guarded by `process.env.ADMIN_EXPORT_KEY`).

- [ ] **Step 1: Write the failing test**

`test/newsletter.test.js`:
```js
const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const { openDb } = require('../src/db');
const { createNewsletterRouter } = require('../src/routes/newsletter');

function buildApp() {
  const db = openDb(':memory:');
  const app = express();
  app.use(express.json());
  app.use('/api/newsletter', createNewsletterRouter(db));
  return { app, db };
}

async function listen(app) {
  const server = app.listen(0);
  await new Promise((r) => server.once('listening', r));
  return { server, base: `http://127.0.0.1:${server.address().port}` };
}

test('subscribing adds a row with a unique unsubscribe token', async () => {
  const { app, db } = buildApp();
  const { server, base } = await listen(app);
  const res = await fetch(`${base}/api/newsletter/subscribe`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email: 'marc@example.test', source: 'pilot' }),
  });
  assert.equal(res.status, 201);
  const row = db.prepare('SELECT * FROM subscriber WHERE email = ?').get('marc@example.test');
  assert.equal(row.source, 'pilot');
  assert.ok(row.unsubscribe_token);
  server.close();
});

test('subscribing twice is not an error', async () => {
  const { app } = buildApp();
  const { server, base } = await listen(app);
  const body = JSON.stringify({ email: 'marc@example.test', source: 'pilot' });
  await fetch(`${base}/api/newsletter/subscribe`, { method: 'POST', headers: { 'content-type': 'application/json' }, body });
  const res = await fetch(`${base}/api/newsletter/subscribe`, { method: 'POST', headers: { 'content-type': 'application/json' }, body });
  assert.equal(res.status, 200);
  const j = await res.json();
  assert.equal(j.alreadySubscribed, true);
  server.close();
});

test('an invalid email or source is rejected', async () => {
  const { app } = buildApp();
  const { server, base } = await listen(app);
  const res1 = await fetch(`${base}/api/newsletter/subscribe`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email: 'not-an-email', source: 'pilot' }),
  });
  assert.equal(res1.status, 400);
  const res2 = await fetch(`${base}/api/newsletter/subscribe`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email: 'marc@example.test', source: 'nonsense' }),
  });
  assert.equal(res2.status, 400);
  server.close();
});

test('the one-click subscribe link subscribes and shows a confirmation page', async () => {
  const { app, db } = buildApp();
  const { server, base } = await listen(app);
  const res = await fetch(`${base}/api/newsletter/subscribe-link?email=claire@example.test&source=contact`);
  assert.equal(res.status, 200);
  const html = await res.text();
  assert.match(html, /confirm/i);
  const row = db.prepare('SELECT * FROM subscriber WHERE email = ?').get('claire@example.test');
  assert.equal(row.source, 'contact');
  server.close();
});

test('unsubscribing removes the row', async () => {
  const { app, db } = buildApp();
  const { server, base } = await listen(app);
  await fetch(`${base}/api/newsletter/subscribe`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email: 'marc@example.test', source: 'pilot' }),
  });
  const token = db.prepare('SELECT unsubscribe_token FROM subscriber WHERE email = ?').get('marc@example.test').unsubscribe_token;

  const res = await fetch(`${base}/api/newsletter/unsubscribe/${token}`);
  assert.equal(res.status, 200);
  assert.equal(db.prepare('SELECT * FROM subscriber WHERE email = ?').get('marc@example.test'), undefined);
  server.close();
});

test('export requires the admin key', async () => {
  const { app } = buildApp();
  const { server, base } = await listen(app);
  const res = await fetch(`${base}/api/newsletter/export`);
  assert.equal(res.status, 403);
  server.close();
});

test('export with the right key returns CSV of all subscribers', async (t) => {
  process.env.ADMIN_EXPORT_KEY = 'test-key-123';
  t.after(() => { delete process.env.ADMIN_EXPORT_KEY; });

  const { app } = buildApp();
  const { server, base } = await listen(app);
  await fetch(`${base}/api/newsletter/subscribe`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email: 'marc@example.test', source: 'pilot' }),
  });
  const res = await fetch(`${base}/api/newsletter/export?key=test-key-123`);
  assert.equal(res.status, 200);
  const csv = await res.text();
  assert.match(csv, /email,subscribed_at,source/);
  assert.match(csv, /marc@example\.test/);
  server.close();
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `docker run --rm -v "/Users/marc/Claude/Projects/APP OFFROAD MOTO 4X4/moto-tracker-server:/app" -w /app node:18 sh -c "npm install && npm test"`
Expected: FAIL with "Cannot find module '../src/routes/newsletter'"

- [ ] **Step 3: Write the implementation**

In `src/db.js`, add to `SCHEMA` (anywhere after the other `CREATE TABLE` statements):
```sql
CREATE TABLE IF NOT EXISTS subscriber (
  email             TEXT PRIMARY KEY,
  subscribed_at     INTEGER NOT NULL,
  source            TEXT NOT NULL CHECK (source IN ('pilot','contact')),
  unsubscribe_token TEXT UNIQUE NOT NULL
);
```

`src/routes/newsletter.js`:
```js
const express = require('express');
const { randomToken } = require('../secrets');

function isValidEmail(email) {
  return typeof email === 'string' && email.includes('@');
}

function confirmationPage(message) {
  return `<!doctype html><html><body style="font-family:sans-serif;text-align:center;padding:40px">` +
    `<h2>${message}</h2></body></html>`;
}

function createNewsletterRouter(db) {
  const router = express.Router();

  router.post('/subscribe', (req, res) => {
    const { email, source } = req.body ?? {};
    if (!isValidEmail(email)) return res.status(400).json({ error: 'valid email required' });
    if (source !== 'pilot' && source !== 'contact') {
      return res.status(400).json({ error: 'source must be "pilot" or "contact"' });
    }

    const existing = db.prepare('SELECT 1 FROM subscriber WHERE email = ?').get(email);
    if (existing) return res.status(200).json({ alreadySubscribed: true });

    db.prepare(
      'INSERT INTO subscriber (email, subscribed_at, source, unsubscribe_token) VALUES (?, ?, ?, ?)'
    ).run(email, Date.now(), source, randomToken(24));
    res.status(201).json({});
  });

  router.get('/subscribe-link', (req, res) => {
    const { email, source } = req.query;
    if (!isValidEmail(email)) return res.status(400).send(confirmationPage('Adresse invalide'));

    const existing = db.prepare('SELECT 1 FROM subscriber WHERE email = ?').get(email);
    if (!existing) {
      db.prepare(
        'INSERT INTO subscriber (email, subscribed_at, source, unsubscribe_token) VALUES (?, ?, ?, ?)'
      ).run(email, Date.now(), source === 'pilot' ? 'pilot' : 'contact', randomToken(24));
    }
    res.status(200).send(confirmationPage('Inscription confirmée'));
  });

  router.get('/unsubscribe/:token', (req, res) => {
    db.prepare('DELETE FROM subscriber WHERE unsubscribe_token = ?').run(req.params.token);
    res.status(200).send(confirmationPage('Désinscription effectuée'));
  });

  router.get('/export', (req, res) => {
    const configured = process.env.ADMIN_EXPORT_KEY;
    if (!configured || req.query.key !== configured) {
      return res.status(403).json({ error: 'invalid key' });
    }
    const rows = db.prepare('SELECT email, subscribed_at, source FROM subscriber ORDER BY subscribed_at ASC').all();
    const csv = ['email,subscribed_at,source']
      .concat(rows.map((r) => `${r.email},${new Date(r.subscribed_at).toISOString()},${r.source}`))
      .join('\n');
    res.status(200).set('Content-Type', 'text/csv').send(csv);
  });

  return router;
}

module.exports = { createNewsletterRouter };
```

- [ ] **Step 4: Run test to verify it passes**

Run: `docker run --rm -v "/Users/marc/Claude/Projects/APP OFFROAD MOTO 4X4/moto-tracker-server:/app" -w /app node:18 sh -c "npm install && npm test"`
Expected: PASS (all `newsletter.test.js` tests, plus every pre-existing test file)

- [ ] **Step 5: Commit**

```bash
git add src/db.js src/routes/newsletter.js test/newsletter.test.js
git commit -m "feat: inscription/desinscription/export de la liste de diffusion (opt-in strict)"
```

---

### Task 6: Wire the mailer and newsletter router into `server.js`

**Files:**
- Modify: `src/server.js`
- Modify: `test/server.test.js`

**Interfaces:**
- Consumes: `createMailer`/`createTransport` (Task 2), `createNewsletterRouter` (Task 5), the updated `createSessionsRouter(db, {onAlert})` (Task 4), the updated `startSweeps(db, {onAlert})` (Task 3).
- Produces: `createApp(db, { mailer } = {})` — `mailer` is optional and injectable for tests (defaults to `createMailer(createTransport())` only in the `require.main` production branch, never inside `createApp` itself, so tests never need real SMTP credentials). Internally builds one `handleAlert(sessionId, kind)` function shared by both the sessions router's `onAlert` and the sweep's `onAlert`, looking up the session's pilot e-mail, contact e-mails, last position, and watch URL, then calling `mailer.sendAlertEmail(...)`.

- [ ] **Step 1: Write the failing test**

Add to `test/server.test.js`:
```js
test('an /alert call triggers the mailer with the right recipients', async () => {
  const sent = [];
  const fakeMailer = { sendAlertEmail: async (params) => { sent.push(params); } };
  const app = createApp(openDb(':memory:'), { mailer: fakeMailer });
  const { server, base } = await listen(app);

  const created = await (
    await fetch(`${base}/api/sessions`, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        kind: 'solo', name: 'Marc', pilotEmail: 'marc@example.test',
        contactEmails: ['claire@example.test'],
      }),
    })
  ).json();

  await fetch(`${base}/api/sessions/${created.sessionId}/alert`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ deviceKey: created.deviceKey, memberId: created.memberId, kind: 'fall' }),
  });

  // handleAlert est asynchrone (await sendAlertEmail) — laisse la microtask se resoudre
  await new Promise((r) => setImmediate(r));

  assert.equal(sent.length, 1);
  assert.equal(sent[0].pilotEmail, 'marc@example.test');
  assert.deepEqual(sent[0].contactEmails, ['claire@example.test']);
  assert.equal(sent[0].kind, 'fall');
  assert.equal(sent[0].pilotName, 'Marc');
  assert.ok(sent[0].watchUrl.includes(created.watchToken));

  server.close();
});

test('newsletter routes are reachable through the assembled app', async () => {
  const app = createApp(openDb(':memory:'), { mailer: { sendAlertEmail: async () => {} } });
  const { server, base } = await listen(app);
  const res = await fetch(`${base}/api/newsletter/subscribe`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email: 'marc@example.test', source: 'pilot' }),
  });
  assert.equal(res.status, 201);
  server.close();
});
```

(add `const { openDb } = require('../src/db');` at the top of the file if not already imported — check first)

- [ ] **Step 2: Run test to verify it fails**

Run: `docker run --rm -v "/Users/marc/Claude/Projects/APP OFFROAD MOTO 4X4/moto-tracker-server:/app" -w /app node:18 sh -c "npm install && npm test"`
Expected: FAIL — `createApp` doesn't accept a second argument, `/api/newsletter` 404s.

- [ ] **Step 3: Write the implementation**

Replace `src/server.js` in full:
```js
const path = require('node:path');
const express = require('express');
const { openDb } = require('./db');
const { createSessionsRouter } = require('./routes/sessions');
const { createWatchRouter } = require('./routes/watch');
const { createNewsletterRouter } = require('./routes/newsletter');
const { startSweeps } = require('./sweep');
const { createMailer, createTransport } = require('./mailer');

function createApp(db, { mailer } = {}) {
  const app = express();
  app.use(express.json());

  async function handleAlert(sessionId, kind) {
    if (!mailer) return;
    const session = db.prepare('SELECT * FROM session WHERE id = ?').get(sessionId);
    if (!session) return;
    const member = db.prepare('SELECT name FROM member WHERE session_id = ? LIMIT 1').get(sessionId);
    const contacts = db.prepare('SELECT email FROM alert_contact WHERE session_id = ?').all(sessionId)
      .map((r) => r.email);
    const last = db.prepare('SELECT lat, lng FROM position WHERE session_id = ? ORDER BY id DESC LIMIT 1')
      .get(sessionId);

    await mailer.sendAlertEmail({
      pilotEmail: session.pilot_email,
      pilotName: member?.name ?? 'Pilote',
      contactEmails: contacts,
      kind,
      lastPosition: last ? { lat: last.lat, lng: last.lng } : null,
      watchUrl: `https://motooffroad.duckdns.org/s/${session.watch_token}`,
    });
  }

  app.get('/healthz', (_req, res) => res.status(200).json({ ok: true }));

  app.use('/api/sessions', createSessionsRouter(db, { onAlert: handleAlert }));
  app.use('/api/newsletter', createNewsletterRouter(db));
  app.use('/', createWatchRouter(db));

  app.get('/s/:watchToken', (_req, res) => {
    res.set('X-Robots-Tag', 'noindex');
    res.sendFile(path.join(__dirname, '..', 'public', 'watch.html'));
  });

  app.use(express.static(path.join(__dirname, '..', 'public')));

  app._handleAlert = handleAlert; // exposé pour le branchement du balayage, voir plus bas
  return app;
}

if (require.main === module) {
  const db = openDb(process.env.DB_PATH ?? './data/tracker.db');
  const mailer = createMailer(createTransport());
  const app = createApp(db, { mailer });
  startSweeps(db, { onAlert: app._handleAlert });
  const port = process.env.PORT ?? 3100;
  app.listen(port, () => {
    console.log(`moto-tracker listening on :${port}`);
  });
}

module.exports = { createApp };
```

- [ ] **Step 4: Run test to verify it passes**

Run: `docker run --rm -v "/Users/marc/Claude/Projects/APP OFFROAD MOTO 4X4/moto-tracker-server:/app" -w /app node:18 sh -c "npm install && npm test"`
Expected: PASS (all tests across every file — full suite green)

- [ ] **Step 5: Commit**

```bash
git add src/server.js test/server.test.js
git commit -m "feat: branche le mailer et la liste de diffusion dans le serveur assemble"
```

---

### Task 7: Watch page newsletter opt-in **[GUI — use impeccable skill]**

**Files:**
- Modify: `public/watch.html`
- Modify: `public/watch.css`
- Modify: `public/watch.js`

**Interfaces:**
- Consumes: `POST /api/newsletter/subscribe` (Task 5), already reachable from this page's own origin.
- Produces: a small, unobtrusive opt-in control on the watch page — this is a safety page, the newsletter must never compete visually with the position/alert content.

- [ ] **Step 1: There is no automated test for this task**, matching Task 6 of the earlier plan (a static page with no test harness in this repo). Verify by reading the change and, if a local static server is convenient, loading the page manually.

- [ ] **Step 2: Write the implementation**

Read the current `public/watch.html` in full first. Add, just before the closing `</body>`, below the existing `#panel` element:
```html
  <button id="newsletterToggle" class="newsletter-toggle" type="button">Recevoir les nouvelles de l'app</button>
  <form id="newsletterForm" class="newsletter-form" hidden>
    <input id="newsletterEmail" type="email" placeholder="votre@email.fr" required>
    <button type="submit">S'inscrire</button>
  </form>
```

Read the current `public/watch.css` in full first. Add:
```css
.newsletter-toggle {
  position: absolute; right: 12px; bottom: 12px; z-index: 999;
  background: rgba(18, 18, 31, 0.85); color: var(--text-secondary);
  border: 1px solid #2A2A3E; border-radius: 8px; padding: 6px 10px;
  font-size: 11px; cursor: pointer;
}
.newsletter-form {
  position: absolute; right: 12px; bottom: 48px; z-index: 999;
  background: rgba(18, 18, 31, 0.95); border: 1px solid #2A2A3E; border-radius: 8px;
  padding: 10px; display: flex; gap: 6px;
}
.newsletter-form input {
  background: #0D1117; border: 1px solid #2A2A3E; border-radius: 6px;
  color: #fff; padding: 6px 8px; font-size: 12px; width: 160px;
}
.newsletter-form button {
  background: var(--blue, #1565C0); color: #fff; border: none; border-radius: 6px;
  padding: 6px 10px; font-size: 12px; cursor: pointer;
}
```
(adjust the color variable references to whatever custom properties `watch.css` actually defines — read the file first; if there's no `--blue` token, use the literal `#1565C0` already used elsewhere in that file for the rider marker)

Read the current `public/watch.js` in full first. Add, at the end of the file:
```js
const newsletterToggle = document.getElementById('newsletterToggle');
const newsletterForm = document.getElementById('newsletterForm');
const newsletterEmail = document.getElementById('newsletterEmail');

newsletterToggle.addEventListener('click', () => {
  newsletterForm.hidden = !newsletterForm.hidden;
});

newsletterForm.addEventListener('submit', async (ev) => {
  ev.preventDefault();
  try {
    await fetch('/api/newsletter/subscribe', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ email: newsletterEmail.value, source: 'contact' }),
    });
    newsletterToggle.textContent = 'Inscription confirmée';
    newsletterForm.hidden = true;
  } catch (_) {
    // Echec silencieux : ce n'est pas une fonction de sécurité, pas la peine
    // d'inquiéter quelqu'un qui suit un proche en difficulté.
  }
});
```

- [ ] **Step 3: Apply the impeccable skill**

Invoke the `impeccable` skill on this addition specifically for restraint: confirm it reads as a footnote, not a feature competing with the alert banner or the map — check contrast, size, and that it's the last thing the eye finds on the page, not the first.

- [ ] **Step 4: Commit**

```bash
git add public/watch.html public/watch.css public/watch.js
git commit -m "feat: inscription a la liste de diffusion depuis la page de suivi"
```

---

### Task 8: Ops — Brevo credentials, `.env`, deploy notes

**Files:**
- Create: `.env.example`
- Modify: `.gitignore`
- Modify: `docker-compose.yml`

**Interfaces:** none — pure configuration/ops. No test; verified by the manual deploy checklist in Step 3.

- [ ] **Step 1: Write the files**

`.env.example` (repo root):
```
SMTP_HOST=smtp-relay.brevo.com
SMTP_PORT=587
SMTP_USER=
SMTP_PASS=
MAIL_FROM=drone-31@hotmail.fr
ADMIN_EXPORT_KEY=
```

Add to `.gitignore`:
```
.env
```

In `docker-compose.yml`, add `env_file: .env` to the `moto-tracker` service, alongside the existing `environment:` block (both can coexist — `environment:` for values that are always the same, `env_file` for secrets):
```yaml
services:
  moto-tracker:
    image: node:18
    working_dir: /app
    env_file: .env
    volumes:
      - ./src:/app/src
      - ./public:/app/public
      - ./package.json:/app/package.json
      - ./package-lock.json:/app/package-lock.json
      - ./data:/app/data
    ports:
      - "127.0.0.1:3100:3100"
    environment:
      NODE_ENV: production
      PORT: 3100
      DB_PATH: /app/data/tracker.db
    command: sh -c "npm ci --omit=dev && node src/server.js"
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:3100/healthz > /dev/null 2>&1 || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 20s
```

- [ ] **Step 2: Verify locally**

```bash
docker run --rm -v "/Users/marc/Claude/Projects/APP OFFROAD MOTO 4X4/moto-tracker-server:/app" -w /app node:18 sh -c "npm install && npm test"
```
Expected: still green — `.env` absence has no effect on tests (they inject a fake mailer/transport, never read `process.env.SMTP_*`).

- [ ] **Step 3: Manual deploy step (not automatable — needs a real Brevo account)**

This step is infrastructure, to run once at deploy time, not part of the automated task loop:
```bash
# 1. Créer un compte Brevo (gratuit), vérifier l'expéditeur drone-31@hotmail.fr,
#    récupérer l'identifiant et la clé SMTP dans Brevo (Paramètres > SMTP & API).
# 2. Créer le fichier .env sur le serveur (jamais dans git) :
ssh drone31 "cat > /root/moto-tracker/.env << 'EOF'
SMTP_HOST=smtp-relay.brevo.com
SMTP_PORT=587
SMTP_USER=<identifiant SMTP Brevo>
SMTP_PASS=<cle SMTP Brevo>
MAIL_FROM=drone-31@hotmail.fr
ADMIN_EXPORT_KEY=<une chaine aleatoire choisie a la main>
EOF
chmod 600 /root/moto-tracker/.env"
# 3. Redeployer normalement :
./deploy.sh "feat: lot C — chute, alerte, newsletter"
# 4. Verifier :
curl -sf https://motooffroad.duckdns.org/healthz
```

- [ ] **Step 4: Commit**

```bash
git add .env.example .gitignore docker-compose.yml
git commit -m "chore: configuration Brevo via .env, jamais commite"
```

---

# Part 2 — App (moto_offroad)

All tasks in this part run in `~/Claude/Projects/APP OFFROAD MOTO 4X4/moto_offroad` (or its active worktree if one is set up per `superpowers:using-git-worktrees` at execution time).

### Task 9: `TrustedContact.email` and `SoloProvider` deadman setting

**Files:**
- Modify: `lib/providers/solo_provider.dart`
- Modify: `test/providers/solo_provider_test.dart`

**Interfaces:**
- Produces: `TrustedContact` gains a required `email` field (`toJson`/`fromJson` updated — see Step 3 for the migration of contacts saved before this lot). `SoloProvider` gains `deadmanThresholdMin` (int, default 15, get/set like the existing `immobilityThresholdMin`) and `pilotEmail` (String?, read from a new constructor-injected getter — see Task 11 for how `SettingsProvider` supplies it). `addContact` gains a required `email` parameter.

- [ ] **Step 1: Write the failing test**

Add to `test/providers/solo_provider_test.dart` (existing tests must keep passing unchanged — this only adds new assertions and extends existing `addContact` calls with the new required parameter):
```dart
test('a contact stores and reloads its email', () async {
  SharedPreferences.setMockInitialValues({});
  final s = SoloProvider();
  await s.loadContacts();
  await s.addContact(name: 'Claire', phone: '+33600000000', relation: 'Sœur', email: 'claire@example.test');

  final reloaded = SoloProvider();
  await reloaded.loadContacts();
  expect(reloaded.contacts.first.email, 'claire@example.test');
});

test('deadmanThresholdMin defaults to 15 and can be changed', () {
  final s = SoloProvider();
  expect(s.deadmanThresholdMin, 15);
  s.setDeadmanThreshold(20);
  expect(s.deadmanThresholdMin, 20);
});
```

**Also update every existing `addContact(...)` call in this test file** to pass `email: '...@example.test'` — the constructor requires it now, so the three pre-existing persistence tests (add/reload, remove/reload, 3-contact cap) will not compile otherwise. Read the file first to find each call site.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/providers/solo_provider_test.dart`
Expected: FAIL — compile error, `email` parameter doesn't exist yet

- [ ] **Step 3: Write the implementation**

In `lib/providers/solo_provider.dart`, replace the `TrustedContact` class:
```dart
class TrustedContact {
  final String id;
  final String name;
  final String phone;
  final String email;
  final String relation;
  bool isNotified;

  TrustedContact({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.relation,
    this.isNotified = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    'email': email,
    'relation': relation,
  };

  // Les contacts enregistrés avant ce lot n'ont pas d'e-mail en stockage —
  // '' plutôt qu'un champ nullable, pour que le reste du code n'ait qu'un
  // seul cas à traiter (« vide » = à compléter), pas deux (null vs vide).
  factory TrustedContact.fromJson(Map<String, dynamic> j) => TrustedContact(
    id:       j['id'] as String,
    name:     j['name'] as String,
    phone:    j['phone'] as String,
    email:    j['email'] as String? ?? '',
    relation: j['relation'] as String,
  );
}
```

Update `addContact`:
```dart
  Future<void> addContact({
    required String name,
    required String phone,
    required String email,
    required String relation,
  }) async {
    if (_contacts.length >= 3) return; // max 3 contacts
    _contacts.add(TrustedContact(
      id:       _uuid.v4(),
      name:     name,
      phone:    phone,
      email:    email,
      relation: relation,
    ));
    await _saveContacts();
    notifyListeners();
  }
```

Add the deadman setting, next to the existing `immobilityThresholdMin`:
```dart
  int _deadmanThresholdMin = 15;   // alerte si silence total > N min
  int get deadmanThresholdMin => _deadmanThresholdMin;

  void setDeadmanThreshold(int minutes) {
    _deadmanThresholdMin = minutes;
    notifyListeners();
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/providers/solo_provider_test.dart`
Expected: PASS (all tests, including the 3 pre-existing ones updated with the new parameter)

- [ ] **Step 5: Commit**

```bash
git add lib/providers/solo_provider.dart test/providers/solo_provider_test.dart
git commit -m "feat: e-mail du contact de confiance et seuil homme-mort reglable"
```

---

### Task 10: `SoloScreen` — contact e-mail field and deadman slider **[GUI — use impeccable skill]**

**Files:**
- Modify: `lib/screens/solo/solo_screen.dart`

**Interfaces:**
- Consumes: `TrustedContact.email`, `SoloProvider.deadmanThresholdMin`/`setDeadmanThreshold` (Task 9).

- [ ] **Step 1: There is no automated widget-test harness for this screen** (consistent with every prior GUI task touching it). Verify with `flutter analyze` and, if convenient, `flutter run`.

- [ ] **Step 2: Write the implementation**

Read the current `lib/screens/solo/solo_screen.dart` in full first (it changed since this lot's spec was written — Task 13 of the prior plan added the SMS-share button to `_statusCard`; don't touch that block).

In `_showAddContactDialog`, add an e-mail field alongside the existing name/phone/relation fields. Add a new controller `_emailCtrl` next to `_nameCtrl`/`_phoneCtrl`/`_relationCtrl` (declare, dispose, clear it the same way as the other three — mirror each of their three call sites exactly). Insert into the dialog's `Column`, after the phone `TextField` and before the relation one:
```dart
            const SizedBox(height: 8),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'E-mail'),
              style: const TextStyle(color: Colors.white),
            ),
```
Update the dialog's "Ajouter" button condition and call to require the e-mail:
```dart
            onPressed: () async {
              if (_nameCtrl.text.isNotEmpty && _phoneCtrl.text.isNotEmpty && _emailCtrl.text.contains('@')) {
                await solo.addContact(
                  name:     _nameCtrl.text,
                  phone:    _phoneCtrl.text,
                  email:    _emailCtrl.text.trim(),
                  relation: _relationCtrl.text.isNotEmpty ? _relationCtrl.text : 'Contact',
                );
                _nameCtrl.clear();
                _phoneCtrl.clear();
                _emailCtrl.clear();
                _relationCtrl.clear();
                Navigator.pop(ctx);
              }
            },
```

Add a deadman slider in `build`, right after the existing `_immobilitySlider(solo)` call and its `SizedBox(height: 24)`, following the exact same structural pattern as `_immobilitySlider` (a bordered `Container` with a title row, a `Slider`, and an explanatory caption):
```dart
              _sectionTitle('ALERTE SILENCE TOTAL'),
              const SizedBox(height: 8),
              _deadmanSlider(solo),
              const SizedBox(height: 24),
```
And the widget method, placed right after `_immobilitySlider`:
```dart
  Widget _deadmanSlider(SoloProvider solo) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A3E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Alerte si aucune position reçue depuis', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              Text('${solo.deadmanThresholdMin} min',
                style: const TextStyle(color: AppColors.orange, fontWeight: FontWeight.w700,
                  fontFamily: 'Rajdhani', fontSize: 18)),
            ],
          ),
          Slider(
            value: solo.deadmanThresholdMin.toDouble(),
            min: 10, max: 30, divisions: 4,
            activeColor: AppColors.orange,
            onChanged: (v) => solo.setDeadmanThreshold(v.round()),
          ),
          const Text('Couvre le téléphone détruit, déchargé ou hors réseau — le serveur alerte même si l\'application ne répond plus.',
            style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
        ],
      ),
    );
  }
```

- [ ] **Step 3: Apply the impeccable skill**

Invoke the `impeccable` skill on the two additions (e-mail field in the dialog, deadman slider in the screen) to confirm they read as a natural continuation of the existing dialog/slider patterns, not a bolted-on addition.

- [ ] **Step 4: Verify**

Run: `flutter analyze lib/screens/solo/solo_screen.dart`
Expected: no new errors.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/solo/solo_screen.dart
git commit -m "feat: champ e-mail du contact et reglage du delai homme-mort"
```

---

### Task 11: `SettingsProvider` — pilot e-mail, newsletter opt-in, fall detection settings

**Files:**
- Modify: `lib/providers/settings_provider.dart`
- Modify: `test/providers/settings_provider_test.dart`

**Interfaces:**
- Produces: `SettingsProvider` gains, all following the file's existing `SharedPreferences` key/getter/setter pattern: `pilotEmail` (String, default `''`), `pilotNewsletterOptIn` (bool, default `false`), `fallDetectionEnabled` (bool, default `true`), `fallCountdownSeconds` (int, default `30`, valid range 15-120), `alertChannelPhone` (bool, default `true`), `alertChannelServer` (bool, default `true`).

- [ ] **Step 1: Write the failing test**

Read the current `test/providers/settings_provider_test.dart` first to match its exact style (likely one `load()`-then-assert-defaults test, plus one set-then-reload test per setting group — mirror whatever pattern is already there). Add:
```dart
test('pilot email and newsletter opt-in persist', () async {
  SharedPreferences.setMockInitialValues({});
  final s = SettingsProvider();
  await s.load();
  expect(s.pilotEmail, '');
  expect(s.pilotNewsletterOptIn, false);

  await s.setPilotEmail('marc@example.test');
  await s.setPilotNewsletterOptIn(true);

  final reloaded = SettingsProvider();
  await reloaded.load();
  expect(reloaded.pilotEmail, 'marc@example.test');
  expect(reloaded.pilotNewsletterOptIn, true);
});

test('fall detection settings default and persist', () async {
  SharedPreferences.setMockInitialValues({});
  final s = SettingsProvider();
  await s.load();
  expect(s.fallDetectionEnabled, true);
  expect(s.fallCountdownSeconds, 30);
  expect(s.alertChannelPhone, true);
  expect(s.alertChannelServer, true);

  await s.setFallDetectionEnabled(false);
  await s.setFallCountdownSeconds(60);
  await s.setAlertChannelPhone(false);
  await s.setAlertChannelServer(false);

  final reloaded = SettingsProvider();
  await reloaded.load();
  expect(reloaded.fallDetectionEnabled, false);
  expect(reloaded.fallCountdownSeconds, 60);
  expect(reloaded.alertChannelPhone, false);
  expect(reloaded.alertChannelServer, false);
});

test('fall countdown seconds is clamped to 15-120', () async {
  SharedPreferences.setMockInitialValues({});
  final s = SettingsProvider();
  await s.load();
  await s.setFallCountdownSeconds(5);
  expect(s.fallCountdownSeconds, 15);
  await s.setFallCountdownSeconds(999);
  expect(s.fallCountdownSeconds, 120);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/providers/settings_provider_test.dart`
Expected: FAIL — the new getters/setters don't exist

- [ ] **Step 3: Write the implementation**

In `lib/providers/settings_provider.dart`, add new keys alongside the existing `static const _k...` block:
```dart
  static const _kPilotEmail          = 'pilot_email';
  static const _kPilotNewsletter     = 'pilot_newsletter_opt_in';
  static const _kFallEnabled         = 'fall_detection_enabled';
  static const _kFallCountdown       = 'fall_countdown_seconds';
  static const _kAlertChannelPhone   = 'alert_channel_phone';
  static const _kAlertChannelServer  = 'alert_channel_server';
```

Add fields/getters alongside the existing ones:
```dart
  String _pilotEmail          = '';
  bool   _pilotNewsletterOptIn = false;
  bool   _fallDetectionEnabled = true;
  int    _fallCountdownSeconds = 30;
  bool   _alertChannelPhone    = true;
  bool   _alertChannelServer   = true;

  String get pilotEmail           => _pilotEmail;
  bool   get pilotNewsletterOptIn => _pilotNewsletterOptIn;
  bool   get fallDetectionEnabled => _fallDetectionEnabled;
  int    get fallCountdownSeconds => _fallCountdownSeconds;
  bool   get alertChannelPhone    => _alertChannelPhone;
  bool   get alertChannelServer   => _alertChannelServer;
```

In `load()`, add alongside the existing reads (before the trailing `notifyListeners();`):
```dart
    _pilotEmail           = prefs.getString(_kPilotEmail) ?? '';
    _pilotNewsletterOptIn = prefs.getBool(_kPilotNewsletter) ?? false;
    _fallDetectionEnabled = prefs.getBool(_kFallEnabled) ?? true;
    _fallCountdownSeconds = (prefs.getInt(_kFallCountdown) ?? 30).clamp(15, 120);
    _alertChannelPhone    = prefs.getBool(_kAlertChannelPhone) ?? true;
    _alertChannelServer   = prefs.getBool(_kAlertChannelServer) ?? true;
```

Add setters, following the file's existing pattern exactly (each reads `SharedPreferences.getInstance()`, writes, calls `notifyListeners()`):
```dart
  Future<void> setPilotEmail(String v) async {
    _pilotEmail = v.trim();
    (await SharedPreferences.getInstance()).setString(_kPilotEmail, _pilotEmail);
    notifyListeners();
  }

  Future<void> setPilotNewsletterOptIn(bool v) async {
    _pilotNewsletterOptIn = v;
    (await SharedPreferences.getInstance()).setBool(_kPilotNewsletter, v);
    notifyListeners();
  }

  Future<void> setFallDetectionEnabled(bool v) async {
    _fallDetectionEnabled = v;
    (await SharedPreferences.getInstance()).setBool(_kFallEnabled, v);
    notifyListeners();
  }

  Future<void> setFallCountdownSeconds(int v) async {
    _fallCountdownSeconds = v.clamp(15, 120);
    (await SharedPreferences.getInstance()).setInt(_kFallCountdown, _fallCountdownSeconds);
    notifyListeners();
  }

  Future<void> setAlertChannelPhone(bool v) async {
    _alertChannelPhone = v;
    (await SharedPreferences.getInstance()).setBool(_kAlertChannelPhone, v);
    notifyListeners();
  }

  Future<void> setAlertChannelServer(bool v) async {
    _alertChannelServer = v;
    (await SharedPreferences.getInstance()).setBool(_kAlertChannelServer, v);
    notifyListeners();
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/providers/settings_provider_test.dart`
Expected: PASS (all tests, new and pre-existing)

- [ ] **Step 5: Commit**

```bash
git add lib/providers/settings_provider.dart test/providers/settings_provider_test.dart
git commit -m "feat: reglages e-mail pilote, newsletter et detection de chute"
```

---

### Task 12: `TrackerApiClient` — pilot/contact e-mails and `sendAlert`

**Files:**
- Modify: `lib/services/tracker_api_client.dart`
- Modify: `test/services/tracker_api_client_test.dart`

**Interfaces:**
- Produces: `createSoloSession` gains required `pilotEmail` (String) and `contactEmails` (List\<String\>) parameters, and an optional `deadmanAfterSec` (int?, sent only if non-null). New method `Future<bool> sendAlert({required String sessionId, required String deviceKey, required String memberId, required String kind})` → `POST /api/sessions/:id/alert`.

- [ ] **Step 1: Write the failing test**

Add to `test/services/tracker_api_client_test.dart`. First, update the existing `createSoloSession` tests (there are three: success, network failure, non-2xx — find them, they currently call `api.createSoloSession(name: 'Marc', immobileAfterSec: 1800)`) to pass the two new required parameters:
```dart
final result = await api.createSoloSession(
  name: 'Marc', immobileAfterSec: 1800,
  pilotEmail: 'marc@example.test', contactEmails: ['claire@example.test'],
);
```
(apply this same parameter addition to all three existing `createSoloSession` call sites in this file — the method signature is now required to include them)

Then add a test confirming the body actually carries the new fields:
```dart
test('createSoloSession sends pilotEmail, contactEmails, and deadmanAfterSec', () async {
  Map<String, dynamic>? capturedBody;
  final client = MockClient((req) async {
    capturedBody = jsonDecode(req.body) as Map<String, dynamic>;
    return http.Response(
      '{"sessionId":"s1","ownerKey":"ok","deviceKey":"dk","memberId":"m1","watchToken":"tok"}',
      201,
    );
  });
  final api = TrackerApiClient(client: client, baseUrl: 'https://example.test');
  await api.createSoloSession(
    name: 'Marc', immobileAfterSec: 1800, deadmanAfterSec: 600,
    pilotEmail: 'marc@example.test', contactEmails: ['claire@example.test', 'jean@example.test'],
  );
  expect(capturedBody!['pilotEmail'], 'marc@example.test');
  expect(capturedBody!['contactEmails'], ['claire@example.test', 'jean@example.test']);
  expect(capturedBody!['deadmanAfterSec'], 600);
});
```
(this test needs `import 'dart:convert';` — check the file's existing imports first, it likely already has it since the client itself uses `jsonEncode`/`jsonDecode`)

Then add tests for `sendAlert`:
```dart
group('sendAlert', () {
  test('returns true on success', () async {
    final client = MockClient((req) async {
      expect(req.url.path, '/api/sessions/s1/alert');
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      expect(body['kind'], 'fall');
      return http.Response('{}', 200);
    });
    final api = TrackerApiClient(client: client, baseUrl: 'https://example.test');
    final ok = await api.sendAlert(sessionId: 's1', deviceKey: 'dk', memberId: 'm1', kind: 'fall');
    expect(ok, isTrue);
  });

  test('returns false on network failure without throwing', () async {
    final client = MockClient((_) async => throw Exception('offline'));
    final api = TrackerApiClient(client: client, baseUrl: 'https://example.test');
    final ok = await api.sendAlert(sessionId: 's1', deviceKey: 'dk', memberId: 'm1', kind: 'sos');
    expect(ok, isFalse);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/tracker_api_client_test.dart`
Expected: FAIL — compile errors on the new required parameters, `sendAlert` doesn't exist

- [ ] **Step 3: Write the implementation**

In `lib/services/tracker_api_client.dart`, replace `createSoloSession` and `_createSession`:
```dart
  Future<SessionCreated?> createSoloSession({
    required String name,
    required int immobileAfterSec,
    required String pilotEmail,
    required List<String> contactEmails,
    int? deadmanAfterSec,
  }) {
    final body = <String, dynamic>{
      'kind': 'solo', 'name': name, 'immobileAfterSec': immobileAfterSec,
      'pilotEmail': pilotEmail, 'contactEmails': contactEmails,
    };
    if (deadmanAfterSec != null) body['deadmanAfterSec'] = deadmanAfterSec;
    return _createSession(body);
  }
```
(`_createSession`, `createGroupSession`, and everything else in the class are unchanged)

Add `sendAlert` near `endSession` (same file):
```dart
  Future<bool> sendAlert({
    required String sessionId,
    required String deviceKey,
    required String memberId,
    required String kind,
  }) async {
    try {
      final res = await _client.post(
        _uri('/api/sessions/$sessionId/alert'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'deviceKey': deviceKey, 'memberId': memberId, 'kind': kind}),
      );
      return res.statusCode ~/ 100 == 2;
    } catch (_) {
      return false;
    }
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/tracker_api_client_test.dart`
Expected: PASS (all tests, new and pre-existing)

- [ ] **Step 5: Commit**

```bash
git add lib/services/tracker_api_client.dart test/services/tracker_api_client_test.dart
git commit -m "feat: client HTTP — e-mails a la creation de session et endpoint d alerte"
```

---

### Task 13: `SoloProvider.activate()` sends pilot/contact e-mails and deadman

**Files:**
- Modify: `lib/providers/solo_provider.dart`
- Modify: `test/providers/solo_provider_test.dart`

**Interfaces:**
- Consumes: `TrackerApiClient.createSoloSession`'s new parameters (Task 12), `TrustedContact.email` (Task 9).
- Produces: `SoloProvider.activate(List<String> contactIds, {required String pilotEmail})` — `pilotEmail` becomes a required parameter (Task 16's `main.dart`/screen wiring supplies it from `SettingsProvider.pilotEmail`). `activate` fails (`false`, no state change) if `pilotEmail` is empty or any selected contact's `email` is empty — mirrors the existing "fail cleanly, no partial state" pattern from `activate`'s hub-failure path.

- [ ] **Step 1: Write the failing test**

Add to `test/providers/solo_provider_test.dart`. First, update the file's existing `activate()`-related tests (the two from the prior lot: "creates a real hub session..." and "fails cleanly when hub unreachable") to pass a `pilotEmail` argument — find each `s.activate([...])` call and change it to `s.activate([...], pilotEmail: 'marc@example.test')`, and give the contacts they create an `email:` (Task 9 already made this required).

Then add:
```dart
test('activate() sends the pilot email and every selected contact email to the hub', () async {
  SharedPreferences.setMockInitialValues({});
  Map<String, dynamic>? capturedBody;
  final client = MockClient((req) async {
    capturedBody = jsonDecode(req.body) as Map<String, dynamic>;
    return http.Response(
      '{"sessionId":"s1","ownerKey":"ok","deviceKey":"dk","memberId":"m1","watchToken":"tok"}',
      201,
    );
  });
  final s = SoloProvider(trackerClient: TrackerApiClient(client: client, baseUrl: 'https://example.test'));
  await s.loadContacts();
  await s.addContact(name: 'Claire', phone: '0600000000', email: 'claire@example.test', relation: 'Sœur');
  await s.addContact(name: 'Jean', phone: '0600000001', email: 'jean@example.test', relation: 'Ami');

  final ok = await s.activate([s.contacts.first.id], pilotEmail: 'marc@example.test');

  expect(ok, isTrue);
  expect(capturedBody!['pilotEmail'], 'marc@example.test');
  expect(capturedBody!['contactEmails'], ['claire@example.test']); // seul le contact sélectionné, pas Jean
  expect(capturedBody!['deadmanAfterSec'], 15 * 60); // valeur par défaut de deadmanThresholdMin
});

test('activate() fails without contacting the hub if the pilot email is empty', () async {
  SharedPreferences.setMockInitialValues({});
  var hubCalled = false;
  final client = MockClient((req) async { hubCalled = true; return http.Response('', 500); });
  final s = SoloProvider(trackerClient: TrackerApiClient(client: client, baseUrl: 'https://example.test'));
  await s.loadContacts();
  await s.addContact(name: 'Claire', phone: '0600000000', email: 'claire@example.test', relation: 'Sœur');

  final ok = await s.activate([s.contacts.first.id], pilotEmail: '');

  expect(ok, isFalse);
  expect(hubCalled, isFalse);
  expect(s.soloActive, isFalse);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/providers/solo_provider_test.dart`
Expected: FAIL — `activate` doesn't accept `pilotEmail`, doesn't send it

- [ ] **Step 3: Write the implementation**

In `lib/providers/solo_provider.dart`, replace `activate`:
```dart
  Future<bool> activate(List<String> contactIds, {required String pilotEmail}) async {
    if (_contacts.isEmpty) return false;
    if (pilotEmail.isEmpty) return false;

    final selected = _contacts.where((c) => contactIds.contains(c.id)).toList();
    if (selected.isEmpty || selected.any((c) => c.email.isEmpty)) return false;

    final created = await _tracker.createSoloSession(
      name: 'Pilote',
      immobileAfterSec: _immobilityThresholdMin * 60,
      deadmanAfterSec: _deadmanThresholdMin * 60,
      pilotEmail: pilotEmail,
      contactEmails: selected.map((c) => c.email).toList(),
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
```

Update the single call site in `lib/screens/solo/solo_screen.dart` (the `_activateBtn` method's `onPressed`):
```dart
                    final ok = await solo.activate(
                      _selectedContactIds.toList(),
                      pilotEmail: context.read<SettingsProvider>().pilotEmail,
                    );
```
(this needs `import '../../providers/settings_provider.dart';` added to `solo_screen.dart` if not already present — check first)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/providers/solo_provider_test.dart`
Expected: PASS (all tests, new and pre-existing)

Run: `flutter analyze lib/screens/solo/solo_screen.dart`
Expected: no new errors.

- [ ] **Step 5: Commit**

```bash
git add lib/providers/solo_provider.dart lib/screens/solo/solo_screen.dart test/providers/solo_provider_test.dart
git commit -m "feat: activate() envoie l e-mail pilote et les e-mails des contacts selectionnes"
```

---

### Task 14: `AlertChannelUnlock` — the subscription lock

**Files:**
- Create: `lib/services/alert_channel_unlock.dart`
- Test: `test/services/alert_channel_unlock_test.dart`

**Interfaces:**
- Produces: `class AlertChannelUnlock { bool isUnlocked(String channel); }` with a single implementation, `AlertChannelUnlock()`, whose `isUnlocked` always returns `false`. This is the entire subscription system for this lot (spec §7.4 / addendum §15.4) — flipping a channel on later means changing this one method's body, nothing else.

- [ ] **Step 1: Write the failing test**

`test/services/alert_channel_unlock_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_offroad/services/alert_channel_unlock.dart';

void main() {
  test('sms gateway and voice call are always locked', () {
    final unlock = AlertChannelUnlock();
    expect(unlock.isUnlocked('sms_gateway'), isFalse);
    expect(unlock.isUnlocked('voice_call'), isFalse);
  });

  test('an unknown channel name is also locked, not an error', () {
    final unlock = AlertChannelUnlock();
    expect(unlock.isUnlocked('anything'), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/alert_channel_unlock_test.dart`
Expected: FAIL with "Cannot find module" / file doesn't exist

- [ ] **Step 3: Write the implementation**

`lib/services/alert_channel_unlock.dart`:
```dart
// ── Verrou d'abonnement ───────────────────────────────────────
//
// Une seule question : ce canal est-il déverrouillé ? Répond toujours non
// tant qu'aucun système d'abonnement n'existe. Brancher l'abonnement plus
// tard consistera à changer cette réponse, pas à restructurer la chaîne
// d'alerte qui l'appelle.
class AlertChannelUnlock {
  bool isUnlocked(String channel) => false;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/alert_channel_unlock_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/alert_channel_unlock.dart test/services/alert_channel_unlock_test.dart
git commit -m "feat: verrou d abonnement pour la passerelle SMS et l appel vocal"
```

---

### Task 15: `FallThresholds` — the calibrated shock threshold

**Files:**
- Create: `lib/services/fall_thresholds.dart`
- Test: `test/services/fall_thresholds_test.dart`

**Interfaces:**
- Consumes: `VibrationCalibration` (`lib/services/vibration_calibration.dart`, existing from Lot 1).
- Produces: `double shockThresholdMs2(VibrationCalibration calibration)` — pure function, m/s² units (matches `sensors_plus`'s `accelerometerEventStream` SI units). Used by Task 16's `FallDetector`.

- [ ] **Step 1: Write the failing test**

`test/services/fall_thresholds_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_offroad/services/fall_thresholds.dart';
import 'package:moto_offroad/services/vibration_calibration.dart';

void main() {
  test('uncalibrated falls back to exactly 4g', () {
    const cal = VibrationCalibration();
    expect(shockThresholdMs2(cal), closeTo(4.0 * 9.81, 0.001));
  });

  test('a calibration at the default idle level matches the 4g fallback', () {
    final cal = VibrationCalibration(
      stillLevel: VibrationCalibration.defaultThreshold * 0.3,
      idleLevel: VibrationCalibration.defaultThreshold,
    );
    expect(shockThresholdMs2(cal), closeTo(4.0 * 9.81, 0.01));
  });

  test('a noisier bike (higher idle level) raises the threshold, bounded at 3x', () {
    final cal = VibrationCalibration(
      stillLevel: VibrationCalibration.defaultThreshold * 0.3,
      idleLevel: VibrationCalibration.defaultThreshold * 100, // extrême, pour tester la borne
    );
    expect(shockThresholdMs2(cal), closeTo(4.0 * 9.81 * 3.0, 0.01));
  });

  test('a quieter bike (lower idle level) lowers the threshold, bounded at 0.5x', () {
    final cal = VibrationCalibration(
      stillLevel: 0.001,
      idleLevel: VibrationCalibration.defaultThreshold * 0.01, // extrême, pour tester la borne
    );
    expect(shockThresholdMs2(cal), closeTo(4.0 * 9.81 * 0.5, 0.01));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/fall_thresholds_test.dart`
Expected: FAIL with "Cannot find module"

- [ ] **Step 3: Write the implementation**

`lib/services/fall_thresholds.dart`:
```dart
import 'vibration_calibration.dart';

// ── Seuil de choc pour la détection de chute ─────────────────
//
// 4g est le repli du spec quand rien n'est calibré. Une fois calibré, le
// seuil est mis à l'échelle du niveau de vibration au ralenti propre à la
// moto et au montage du téléphone : un ralenti plus bruyant exige un choc
// plus franc pour ne pas confondre les cahots du terrain avec une chute,
// et inversement. L'échelle est bornée [0.5, 3] pour qu'une calibration
// aberrante ne rende jamais la détection absurdement permissive ou
// hypersensible.
const double _fallbackG = 4.0;
const double _gravity = 9.81;

double shockThresholdMs2(VibrationCalibration calibration) {
  if (!calibration.isCalibrated) return _fallbackG * _gravity;
  final scale = (calibration.idleLevel! / VibrationCalibration.defaultThreshold).clamp(0.5, 3.0);
  return _fallbackG * _gravity * scale;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/fall_thresholds_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/fall_thresholds.dart test/services/fall_thresholds_test.dart
git commit -m "feat: seuil de choc calibre pour la detection de chute"
```

---

### Task 16: `FallDetector` — the three-stage state machine

**Files:**
- Create: `lib/services/fall_detector.dart`
- Test: `test/services/fall_detector_test.dart`

**Interfaces:**
- Consumes: `GpsSnapshot` (`lib/services/location_service.dart`).
- Produces: `class FallDetector` with constructor `FallDetector({required Stream<List<double>> accelerometer, required Stream<GpsSnapshot> positions, required double Function() shockThreshold, Duration stopWindow = const Duration(seconds: 20), double stopSpeedKmh = 3.0, double tiltMaxDeg = 5.0})`, `void start({required void Function() onFallDetected})`, `void stop()`. `accelerometer` emits `[x, y, z]` in m/s² (the caller adapts `sensors_plus`'s `AccelerometerEvent` to this shape — kept as a plain list here so this class has no Flutter-plugin dependency and is fully unit-testable with synthetic streams).

- [ ] **Step 1: Write the failing test**

`test/services/fall_detector_test.dart`:
```dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_offroad/services/fall_detector.dart';
import 'package:moto_offroad/services/location_service.dart';

GpsSnapshot _snap(double speedKmh) => GpsSnapshot(
  position: const LatLng(45, 5), accuracyMeters: 5, altitudeMeters: 100,
  speedKmh: speedKmh, headingDeg: 0, timestamp: DateTime.now(),
);

void main() {
  test('a shock followed by full stillness and no tilt for the whole window fires the callback', () async {
    final accel = StreamController<List<double>>();
    final positions = StreamController<GpsSnapshot>();
    var fired = false;
    final detector = FallDetector(
      accelerometer: accel.stream, positions: positions.stream,
      shockThreshold: () => 10.0,
      stopWindow: const Duration(milliseconds: 60),
      stopSpeedKmh: 3.0, tiltMaxDeg: 5.0,
    );
    detector.start(onFallDetected: () => fired = true);

    accel.add([0, 0, 9.8]);       // repos, sous le seuil
    await Future.delayed(const Duration(milliseconds: 5));
    accel.add([15, 0, 0]);        // choc : magnitude 15 > seuil 10
    await Future.delayed(const Duration(milliseconds: 5));
    positions.add(_snap(1.0));    // arrêt : sous 3 km/h
    accel.add([0, 0, 9.8]);       // même orientation que l'origine du choc

    await Future.delayed(const Duration(milliseconds: 80)); // laisse la fenêtre de 60ms s'écouler

    expect(fired, isTrue);
    detector.stop();
    await accel.close();
    await positions.close();
  });

  test('movement during the window cancels the detection', () async {
    final accel = StreamController<List<double>>();
    final positions = StreamController<GpsSnapshot>();
    var fired = false;
    final detector = FallDetector(
      accelerometer: accel.stream, positions: positions.stream,
      shockThreshold: () => 10.0,
      stopWindow: const Duration(milliseconds: 60),
    );
    detector.start(onFallDetected: () => fired = true);

    accel.add([15, 0, 0]); // choc
    await Future.delayed(const Duration(milliseconds: 10));
    positions.add(_snap(20.0)); // le pilote roule encore : pas une chute
    await Future.delayed(const Duration(milliseconds: 80));

    expect(fired, isFalse);
    detector.stop();
    await accel.close();
    await positions.close();
  });

  test('a tilt change during the window cancels the detection', () async {
    final accel = StreamController<List<double>>();
    final positions = StreamController<GpsSnapshot>();
    var fired = false;
    final detector = FallDetector(
      accelerometer: accel.stream, positions: positions.stream,
      shockThreshold: () => 10.0,
      stopWindow: const Duration(milliseconds: 60),
      tiltMaxDeg: 5.0,
    );
    detector.start(onFallDetected: () => fired = true);

    accel.add([0, 0, 9.8]);   // origine du choc : vertical
    await Future.delayed(const Duration(milliseconds: 5));
    accel.add([15, 0, 0]);    // choc (magnitude 15, la direction sert d'origine de tilt)
    await Future.delayed(const Duration(milliseconds: 10));
    positions.add(_snap(1.0)); // immobile
    accel.add([0, 15, 0]);     // orientation totalement différente : > 5° de l'origine
    await Future.delayed(const Duration(milliseconds: 80));

    expect(fired, isFalse);
    detector.stop();
    await accel.close();
    await positions.close();
  });

  test('a sub-threshold jolt never starts watching', () async {
    final accel = StreamController<List<double>>();
    final positions = StreamController<GpsSnapshot>();
    var fired = false;
    final detector = FallDetector(
      accelerometer: accel.stream, positions: positions.stream,
      shockThreshold: () => 10.0,
      stopWindow: const Duration(milliseconds: 30),
    );
    detector.start(onFallDetected: () => fired = true);

    accel.add([3, 0, 0]); // magnitude 3, sous le seuil de 10
    await Future.delayed(const Duration(milliseconds: 60));

    expect(fired, isFalse);
    detector.stop();
    await accel.close();
    await positions.close();
  });

  test('stop() prevents a callback from firing after a shock already in progress', () async {
    final accel = StreamController<List<double>>();
    final positions = StreamController<GpsSnapshot>();
    var fired = false;
    final detector = FallDetector(
      accelerometer: accel.stream, positions: positions.stream,
      shockThreshold: () => 10.0,
      stopWindow: const Duration(milliseconds: 30),
    );
    detector.start(onFallDetected: () => fired = true);

    accel.add([15, 0, 0]); // choc, la fenêtre de 30ms démarre
    await Future.delayed(const Duration(milliseconds: 5));
    detector.stop();
    await Future.delayed(const Duration(milliseconds: 60)); // largement au-delà de la fenêtre

    expect(fired, isFalse);
    await accel.close();
    await positions.close();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/fall_detector_test.dart`
Expected: FAIL with "Cannot find module"

- [ ] **Step 3: Write the implementation**

`lib/services/fall_detector.dart`:
```dart
import 'dart:async';
import 'dart:math';
import 'location_service.dart';

// ── Détection de chute en trois temps ────────────────────────
//
// Choc, puis 20 secondes où la vitesse reste sous le seuil ET l'inclinaison
// ne varie pas — les deux doivent tenir sur toute la fenêtre, pas
// seulement à un instant donné. Un saut produit un choc mais le pilote
// repart (la vitesse remonte) ; une chute sans gravité fait bouger le
// téléphone pendant qu'on se relève (l'inclinaison varie). Les deux sont
// ainsi écartées sans confondre avec une vraie chute.
class FallDetector {
  FallDetector({
    required Stream<List<double>> accelerometer,
    required Stream<GpsSnapshot> positions,
    required this.shockThreshold,
    this.stopWindow = const Duration(seconds: 20),
    this.stopSpeedKmh = 3.0,
    this.tiltMaxDeg = 5.0,
  })  : _accelerometer = accelerometer,
        _positions = positions;

  final Stream<List<double>> _accelerometer;
  final Stream<GpsSnapshot> _positions;
  final double Function() shockThreshold;
  final Duration stopWindow;
  final double stopSpeedKmh;
  final double tiltMaxDeg;

  StreamSubscription<List<double>>? _accelSub;
  StreamSubscription<GpsSnapshot>? _positionSub;
  Timer? _windowTimer;
  List<double>? _originVector;
  List<double>? _lastSample;
  void Function()? _onFallDetected;

  void start({required void Function() onFallDetected}) {
    stop();
    _onFallDetected = onFallDetected;

    _accelSub = _accelerometer.listen((sample) {
      final magnitude = _magnitude(sample);
      final previousSample = _lastSample;
      _lastSample = sample;

      if (_originVector == null) {
        // Pas en observation : un choc démarre la fenêtre. L'orientation de
        // référence est celle d'AVANT le choc (le dernier échantillon connu),
        // pas le choc lui-même — le choc est justement le moment où
        // l'orientation change brutalement, donc s'en servir comme référence
        // ferait toujours passer l'instant suivant pour une inclinaison.
        if (magnitude >= shockThreshold()) {
          _originVector = previousSample ?? sample;
          _windowTimer?.cancel();
          _windowTimer = Timer(stopWindow, () {
            _onFallDetected?.call();
            _resetWatch();
          });
        }
        return;
      }

      // En observation : toute inclinaison hors tolérance annule.
      if (_angleBetweenDeg(_originVector!, sample) > tiltMaxDeg) {
        _resetWatch();
      }
    });

    _positionSub = _positions.listen((snap) {
      if (_originVector == null) return; // pas en observation, rien à vérifier
      if (snap.speedKmh >= stopSpeedKmh) {
        _resetWatch();
      }
    });
  }

  void _resetWatch() {
    _windowTimer?.cancel();
    _windowTimer = null;
    _originVector = null;
  }

  void stop() {
    _accelSub?.cancel();
    _positionSub?.cancel();
    _accelSub = null;
    _positionSub = null;
    _onFallDetected = null;
    _resetWatch();
  }

  static double _magnitude(List<double> v) => sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);

  static double _angleBetweenDeg(List<double> a, List<double> b) {
    final dot = a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
    final magA = _magnitude(a);
    final magB = _magnitude(b);
    if (magA == 0 || magB == 0) return 0;
    final cosAngle = (dot / (magA * magB)).clamp(-1.0, 1.0);
    return acos(cosAngle) * 180 / pi;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/fall_detector_test.dart`
Expected: PASS (all 5 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/services/fall_detector.dart test/services/fall_detector_test.dart
git commit -m "feat: machine a etats de detection de chute en trois temps"
```

---

### Task 17: `FallAlertService` — the two-channel alert orchestrator

**Files:**
- Create: `lib/services/fall_alert_service.dart`
- Test: `test/services/fall_alert_service_test.dart`

**Interfaces:**
- Consumes: `CallBridge.sendSms` (`lib/services/call_bridge.dart`, already used by the auto-reply feature), `TrackerApiClient.sendAlert` (Task 12), `GpsSnapshot` (`lib/services/location_service.dart`).
- Produces: `class FallAlertService` with constructor taking function-typed dependencies (matching this codebase's established `AutoReplyService` injection style — see `lib/services/auto_reply_service.dart`), and `Future<void> sendFallAlert({required String kind})` (`kind` is `'fall'` or `'sos'`, passed straight through to the server).

- [ ] **Step 1: Write the failing test**

`test/services/fall_alert_service_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:moto_offroad/providers/solo_provider.dart';
import 'package:moto_offroad/services/fall_alert_service.dart';
import 'package:moto_offroad/services/location_service.dart';

GpsSnapshot _snap() => GpsSnapshot(
  position: const LatLng(45, 5), accuracyMeters: 5, altitudeMeters: 100,
  speedKmh: 0, headingDeg: 0, timestamp: DateTime.now(),
);

void main() {
  test('sends an SMS to every trusted contact when the phone channel is enabled', () async {
    final sentSms = <String>[];
    final service = FallAlertService(
      sendSms: (phone, text) async { sentSms.add(phone); return true; },
      sendServerAlert: ({required kind}) async => true,
      phoneChannelEnabled: () => true,
      serverChannelEnabled: () => false,
      trustedContacts: () => [
        TrustedContact(id: '1', name: 'Claire', phone: '0600000000', email: 'c@x.test', relation: 'Sœur'),
        TrustedContact(id: '2', name: 'Jean', phone: '0600000001', email: 'j@x.test', relation: 'Ami'),
      ],
      positionProvider: () async => _snap(),
    );

    await service.sendFallAlert(kind: 'fall');

    expect(sentSms, ['0600000000', '0600000001']);
  });

  test('calls the server alert when the server channel is enabled', () async {
    var serverCalled = false;
    String? capturedKind;
    final service = FallAlertService(
      sendSms: (_, __) async => true,
      sendServerAlert: ({required kind}) async { serverCalled = true; capturedKind = kind; return true; },
      phoneChannelEnabled: () => false,
      serverChannelEnabled: () => true,
      trustedContacts: () => [],
      positionProvider: () async => _snap(),
    );

    await service.sendFallAlert(kind: 'sos');

    expect(serverCalled, isTrue);
    expect(capturedKind, 'sos');
  });

  test('neither channel fires when both are disabled', () async {
    var smsCalled = false;
    var serverCalled = false;
    final service = FallAlertService(
      sendSms: (_, __) async { smsCalled = true; return true; },
      sendServerAlert: ({required kind}) async { serverCalled = true; return true; },
      phoneChannelEnabled: () => false,
      serverChannelEnabled: () => false,
      trustedContacts: () => [
        TrustedContact(id: '1', name: 'Claire', phone: '0600000000', email: 'c@x.test', relation: 'Sœur'),
      ],
      positionProvider: () async => _snap(),
    );

    await service.sendFallAlert(kind: 'fall');

    expect(smsCalled, isFalse);
    expect(serverCalled, isFalse);
  });

  test('the SMS text includes the position link', () async {
    String? capturedText;
    final service = FallAlertService(
      sendSms: (phone, text) async { capturedText = text; return true; },
      sendServerAlert: ({required kind}) async => true,
      phoneChannelEnabled: () => true,
      serverChannelEnabled: () => false,
      trustedContacts: () => [
        TrustedContact(id: '1', name: 'Claire', phone: '0600000000', email: 'c@x.test', relation: 'Sœur'),
      ],
      positionProvider: () async => _snap(),
    );

    await service.sendFallAlert(kind: 'fall');

    expect(capturedText, contains('maps.google.com'));
  });

  test('a missing position still sends the SMS, without a broken link', () async {
    String? capturedText;
    final service = FallAlertService(
      sendSms: (phone, text) async { capturedText = text; return true; },
      sendServerAlert: ({required kind}) async => true,
      phoneChannelEnabled: () => true,
      serverChannelEnabled: () => false,
      trustedContacts: () => [
        TrustedContact(id: '1', name: 'Claire', phone: '0600000000', email: 'c@x.test', relation: 'Sœur'),
      ],
      positionProvider: () async => null,
    );

    await service.sendFallAlert(kind: 'fall');

    expect(capturedText, isNotNull);
    expect(capturedText, isNot(contains('maps.google.com')));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/fall_alert_service_test.dart`
Expected: FAIL with "Cannot find module"

- [ ] **Step 3: Write the implementation**

`lib/services/fall_alert_service.dart`:
```dart
import '../providers/solo_provider.dart';
import 'location_service.dart';

typedef SendSmsFn = Future<bool> Function(String phone, String text);
typedef SendServerAlertFn = Future<bool> Function({required String kind});

// ── Orchestration de la chaîne d'alerte à deux canaux ────────
//
// Dépendances injectées en fonctions, comme AutoReplyService : le service
// lit l'état courant des réglages à chaque appel plutôt que de garder une
// référence figée aux providers.
class FallAlertService {
  FallAlertService({
    required this.sendSms,
    required this.sendServerAlert,
    required this.phoneChannelEnabled,
    required this.serverChannelEnabled,
    required this.trustedContacts,
    required this.positionProvider,
  });

  final SendSmsFn sendSms;
  final SendServerAlertFn sendServerAlert;
  final bool Function() phoneChannelEnabled;
  final bool Function() serverChannelEnabled;
  final List<TrustedContact> Function() trustedContacts;
  final Future<GpsSnapshot?> Function() positionProvider;

  Future<void> sendFallAlert({required String kind}) async {
    final snap = await positionProvider();

    if (phoneChannelEnabled()) {
      final text = _smsText(kind, snap);
      for (final contact in trustedContacts()) {
        await sendSms(contact.phone, text);
      }
    }

    if (serverChannelEnabled()) {
      await sendServerAlert(kind: kind);
    }
  }

  String _smsText(String kind, GpsSnapshot? snap) {
    final label = kind == 'sos' ? 'SOS' : 'une chute possible';
    final positionLine = snap != null
        ? 'Position : ${snap.googleMapsUrl}'
        : 'Position indisponible';
    return 'ALERTE — $label détectée sur MOTO OFFROAD 4X4.\n$positionLine';
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/fall_alert_service_test.dart`
Expected: PASS (all 5 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/services/fall_alert_service.dart test/services/fall_alert_service_test.dart
git commit -m "feat: orchestrateur d alerte a deux canaux (telephone/serveur)"
```

---

### Task 18: Router — full-screen countdown route

**Files:**
- Modify: `lib/app/router.dart`

**Interfaces:**
- Produces: `AppRoutes.fallCountdown` (a new route string), and an exported `GlobalKey<NavigatorState> rootNavigatorKey` — needed because Task 20 triggers this screen from a background service, not from a widget's own `context`, so it needs a stable, app-wide way to push a route.

- [ ] **Step 1: There is no automated test for router wiring** — this mirrors how the existing routes in this file (`AppRoutes.sos`, `.solo`, etc.) have no dedicated test either; they're exercised indirectly by the app compiling and running. Verify with `flutter analyze`.

- [ ] **Step 2: Write the implementation**

Read the current `lib/app/router.dart` in full first. Add near the top, before `class AppRoutes`:
```dart
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
```

Add the import for the new screen (Task 19 creates it):
```dart
import '../screens/sos/fall_countdown_screen.dart';
```

Add to `class AppRoutes`, alongside the existing route constants:
```dart
  static const String fallCountdown = '/fall-countdown';
```

Add `navigatorKey: rootNavigatorKey,` to the `GoRouter(...)` constructor call (alongside its existing `initialLocation:`/`debugLogDiagnostics:` arguments).

Add a new `GoRoute` alongside the other modal routes (`AppRoutes.sos`, `.solo`, `.sendPosition` — find that block, add this in the same style):
```dart
    GoRoute(
      path: AppRoutes.fallCountdown,
      pageBuilder: (_, __) => const MaterialPage(
        fullscreenDialog: true, child: FallCountdownScreen()),
    ),
```

- [ ] **Step 3: Verify**

Run: `flutter analyze lib/app/router.dart`
Expected: an error naming `FallCountdownScreen` as undefined — expected until Task 19 lands; note this in your report as the same kind of expected-and-explained gap as earlier tasks in this project (e.g. Task 15 of the prior plan), not a defect. Do not attempt to stub the screen here — Task 19 is immediately next.

- [ ] **Step 4: Commit**

```bash
git add lib/app/router.dart
git commit -m "feat: route et cle de navigation pour le compte a rebours de chute"
```

---

### Task 19: `FallCountdownScreen` **[GUI — use impeccable skill]**

**Files:**
- Create: `lib/screens/sos/fall_countdown_screen.dart`

**Interfaces:**
- Consumes: `SettingsProvider.fallCountdownSeconds` (Task 11), `FallAlertService` (Task 17, supplied via `Provider` — see Task 20 for how it's registered in `main.dart`).
- Produces: a full-screen, un-dismissable-by-back-button countdown. Tapping "ANNULER" cancels and pops. Reaching zero calls `FallAlertService.sendFallAlert(kind: 'fall')` and shows a brief confirmation before popping.

- [ ] **Step 1: There is no automated widget test for this screen** (this codebase has no widget-test harness for any full-screen modal — `SosScreen`, `SoloScreen` have none either). Verify with `flutter analyze` and, ideally, `flutter run` to trigger it manually (see the post-plan checklist at the end of this document for the real-device fall simulation).

- [ ] **Step 2: Write the implementation**

`lib/screens/sos/fall_countdown_screen.dart`:
```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../app/theme.dart';
import '../../providers/settings_provider.dart';
import '../../services/fall_alert_service.dart';

class FallCountdownScreen extends StatefulWidget {
  const FallCountdownScreen({super.key});

  @override
  State<FallCountdownScreen> createState() => _FallCountdownScreenState();
}

class _FallCountdownScreenState extends State<FallCountdownScreen> {
  Timer? _tick;
  Timer? _alarm;
  late int _remaining;
  bool _cancelled = false;
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    _remaining = context.read<SettingsProvider>().fallCountdownSeconds;
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() => _remaining--);
      if (_remaining <= 0) {
        t.cancel();
        _trigger();
      }
    });
    _alarm = Timer.periodic(const Duration(seconds: 1), (_) {
      HapticFeedback.vibrate();
      SystemSound.play(SystemSoundType.alert);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _alarm?.cancel();
    super.dispose();
  }

  Future<void> _trigger() async {
    _alarm?.cancel();
    final service = context.read<FallAlertService>();
    await service.sendFallAlert(kind: 'fall');
    if (!mounted) return;
    setState(() => _sent = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) Navigator.of(context).pop();
  }

  void _cancel() {
    _tick?.cancel();
    _alarm?.cancel();
    setState(() => _cancelled = true);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // seule l'annulation explicite ferme cet écran
      child: Scaffold(
        backgroundColor: const Color(0xFF1A0000),
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_sent) ..._confirmation() else ..._countdown(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _countdown() => [
        const Icon(Icons.warning_amber_rounded, color: AppColors.red, size: 64),
        const SizedBox(height: 24),
        const Text('CHUTE DÉTECTÉE',
          style: TextStyle(fontFamily: 'Rajdhani', fontSize: 24, fontWeight: FontWeight.w700,
            color: Colors.white, letterSpacing: 1.5)),
        const SizedBox(height: 8),
        const Text('Appuyez pour annuler si vous allez bien',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
        const SizedBox(height: 40),
        Text('$_remaining',
          style: const TextStyle(fontSize: 96, fontWeight: FontWeight.bold, color: AppColors.red)),
        const SizedBox(height: 48),
        SizedBox(
          width: 220, height: 64,
          child: ElevatedButton(
            onPressed: _cancel,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('ANNULER', style: TextStyle(
              fontFamily: 'Rajdhani', fontSize: 22, fontWeight: FontWeight.w700)),
          ),
        ),
      ];

  List<Widget> _confirmation() => const [
        Icon(Icons.check_circle, color: AppColors.statusGreen, size: 64),
        SizedBox(height: 24),
        Text('Alerte envoyée', style: TextStyle(
          fontFamily: 'Rajdhani', fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
      ];
}
```

- [ ] **Step 3: Apply the impeccable skill**

Invoke the `impeccable` skill on this screen: this is the single highest-urgency moment in the whole app — confirm the countdown number is legible at arm's length with gloves on and a possibly-cracked screen, the cancel button is large and impossible to miss, and the confirmation state doesn't read as an afterthought.

- [ ] **Step 4: Verify**

Run: `flutter analyze lib/screens/sos/fall_countdown_screen.dart lib/app/router.dart`
Expected: no errors (Task 18's forward-reference is now resolved).

- [ ] **Step 5: Commit**

```bash
git add lib/screens/sos/fall_countdown_screen.dart
git commit -m "feat: ecran plein ecran de compte a rebours avant l alerte de chute"
```

---

### Task 20: Wire `FallDetector`/`FallAlertService` lifecycle in `main.dart`

**Files:**
- Modify: `lib/main.dart`

**Interfaces:**
- Consumes: `FallDetector` (Task 16), `FallAlertService` (Task 17), `AlertChannelUnlock` (Task 14 — registered but not yet consulted for a decision in this lot, since no channel is ever unlockable; wiring it into the Provider tree now means Task 22's settings screen can read it without another `main.dart` change later), `SettingsProvider.fallDetectionEnabled` (Task 11), `RecordingProvider.isRecording` / `SoloProvider.soloActive` (existing — same gating rule already used by `AutoReplyService`: "runs only while recording or Solo is active").

- [ ] **Step 1: There is no isolated test for this wiring step**, matching Tasks 14/18/20 of the prior plan for the same reason — it is exercised by the existing `smoke_test.dart`, and its constituent parts (`FallDetector`, `FallAlertService`) are already unit-tested individually.

- [ ] **Step 2: Write the implementation**

Read the current `lib/main.dart` in full first (it has grown across the prior lot's tasks — `_AutoReplyHost`, `_SoloUplinkHost` are both already there; this task adds a third host of the same shape, and one new `Provider` registration).

Add imports:
```dart
import 'package:sensors_plus/sensors_plus.dart';
import 'services/alert_channel_unlock.dart';
import 'services/fall_alert_service.dart';
import 'services/fall_detector.dart';
import 'services/fall_thresholds.dart';
import 'services/vibration_calibration.dart';
import 'app/router.dart' show rootNavigatorKey, AppRoutes;
```
(check whether `router.dart`'s exports are already imported some other way in this file — if `app/router.dart` is already imported for `appRouter`, add `rootNavigatorKey` to that existing import's shown-names instead of a second import line for the same file)

Register `AlertChannelUnlock` as a plain `Provider` (not a `ChangeNotifierProvider` — it never changes) in the `MultiProvider` list, alongside the existing providers:
```dart
        Provider<AlertChannelUnlock>(create: (_) => AlertChannelUnlock()),
```

Register `FallAlertService`, which needs `CallBridge`, `TrackerApiClient`, `SettingsProvider`, and `SoloProvider` — build it with a `ProxyProvider` reading the already-registered `SettingsProvider`/`SoloProvider`:
```dart
        ChangeNotifierProxyProvider2<SettingsProvider, SoloProvider, FallAlertService>(
          create: (_) => FallAlertService(
            sendSms: CallBridge().sendSms,
            sendServerAlert: ({required kind}) async {
              final solo = _fallSoloRef;
              if (solo == null || solo.sessionId == null || solo.deviceKey == null || solo.memberId == null) {
                return false;
              }
              return TrackerApiClient().sendAlert(
                sessionId: solo.sessionId!, deviceKey: solo.deviceKey!, memberId: solo.memberId!, kind: kind,
              );
            },
            phoneChannelEnabled: () => _fallSettingsRef?.alertChannelPhone ?? true,
            serverChannelEnabled: () => _fallSettingsRef?.alertChannelServer ?? true,
            trustedContacts: () => _fallSoloRef?.contacts ?? [],
            positionProvider: () => LocationService().getCurrentPosition(),
          ),
          update: (_, settings, solo, previous) {
            _fallSettingsRef = settings;
            _fallSoloRef = solo;
            return previous!;
          },
        ),
```

This needs two module-level (top of `main.dart`, outside any class) mutable references so `FallAlertService`'s captured closures can read the *current* provider instances without `main.dart` reaching for `BuildContext` inside a non-widget callback:
```dart
SettingsProvider? _fallSettingsRef;
SoloProvider? _fallSoloRef;
```
(this mirrors the existing codebase's own preference for function-based injection over holding a `BuildContext` — `ChangeNotifierProxyProvider2`'s `update` callback is the idiomatic Provider way to keep such references current without a rebuild loop, since `FallAlertService` itself never changes identity, only what it reads)

Add `import 'services/location_service.dart';` if not already present, and `import 'services/tracker_api_client.dart';`, `import 'services/call_bridge.dart';` — check the file's existing imports first for each; several are likely already there from the prior lot's tasks.

Add a new host widget below `_SoloUplinkHost` (same file), following its exact shape:
```dart
// ── Cycle de vie de la détection de chute ────────────────────
// Même règle de garde que l'auto-réponse aux appels : actif seulement
// pendant un enregistrement ou en mode Solo, jamais téléphone posé sur
// une table.
class _FallDetectionHost extends StatefulWidget {
  const _FallDetectionHost({required this.child});
  final Widget child;

  @override
  State<_FallDetectionHost> createState() => _FallDetectionHostState();
}

class _FallDetectionHostState extends State<_FallDetectionHost> {
  FallDetector? _detector;
  bool _running = false;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final recording = context.watch<RecordingProvider>();
    final solo = context.watch<SoloProvider>();

    final shouldRun = settings.fallDetectionEnabled && (recording.isRecording || solo.soloActive);

    if (shouldRun && !_running) {
      _running = true;
      _detector = FallDetector(
        accelerometer: accelerometerEventStream().map((e) => [e.x, e.y, e.z]),
        positions: LocationService().stream,
        shockThreshold: () => shockThresholdMs2(_lastCalibration ?? const VibrationCalibration()),
      );
      VibrationCalibration.load().then((cal) => _lastCalibration = cal);
      _detector!.start(onFallDetected: () {
        rootNavigatorKey.currentState?.pushNamed(AppRoutes.fallCountdown);
      });
    } else if (!shouldRun && _running) {
      _running = false;
      _detector?.stop();
      _detector = null;
    }

    return widget.child;
  }

  VibrationCalibration? _lastCalibration;

  @override
  void dispose() {
    _detector?.stop();
    super.dispose();
  }
}
```

Note: `rootNavigatorKey.currentState?.pushNamed(...)` requires the routes to be registered by name on the `Navigator`, which they are not here (this app uses `go_router`, not named `Navigator` routes) — use `rootNavigatorKey.currentContext` with `go_router`'s own push instead:
```dart
      _detector!.start(onFallDetected: () {
        final ctx = rootNavigatorKey.currentContext;
        if (ctx != null) GoRouter.of(ctx).push(AppRoutes.fallCountdown);
      });
```
(add `import 'package:go_router/go_router.dart';` if not already present in this file)

Wrap `_SoloUplinkHost`'s child with the new host, in `MotoOffroadApp.build` (find the existing nesting — `_AutoReplyHost` wraps `_SoloUplinkHost` wraps `MaterialApp.router`):
```dart
      child: _AutoReplyHost(
        child: _SoloUplinkHost(
          child: _FallDetectionHost(
            child: MaterialApp.router(
              title: 'Moto Offroad 4x4',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.dark,
              routerConfig: appRouter,
            ),
          ),
        ),
      ),
```

- [ ] **Step 3: Verify**

Run: `flutter test test/smoke_test.dart`
Expected: PASS

Run: `flutter analyze`
Expected: no new errors versus the pre-lot baseline (the known pre-existing `weather_service.dart` errors from the gitignored `api_keys.dart` are unrelated and expected).

- [ ] **Step 4: Commit**

```bash
git add lib/main.dart
git commit -m "feat: demarrage/arret de la detection de chute avec l enregistrement ou le mode Solo"
```

---

### Task 21: Settings screen — pilot e-mail, newsletter, fall detection **[GUI — use impeccable skill]**

**Files:**
- Modify: `lib/screens/settings/settings_screen.dart`

**Interfaces:**
- Consumes: `SettingsProvider` (Task 11 additions), `AlertChannelUnlock` (Task 14, via `context.read`).

- [ ] **Step 1: There is no automated test for this screen** (no widget-test harness in this codebase, consistent with every prior settings-screen change). Verify with `flutter analyze` and `flutter run`.

- [ ] **Step 2: Write the implementation**

Read the current `lib/screens/settings/settings_screen.dart` in full first — it's organized as a sequence of `GlassPanel(child: _xSection())` calls in `build`; this task adds two more sections following that exact pattern, plus one field addition to whichever section already holds the rider's name (`_riderSection()`, per the file's existing structure).

In `_riderSection()` (or wherever the rider name `TextField` lives — confirm from the read), add a pilot e-mail field right after it:
```dart
          const SizedBox(height: 12),
          TextField(
            controller: _pilotEmailCtrl,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'E-mail (obligatoire pour le mode Solo)',
              prefixIcon: Icon(Icons.email_outlined, color: AppColors.textMuted),
            ),
            onChanged: (v) => context.read<SettingsProvider>().setPilotEmail(v),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: context.watch<SettingsProvider>().pilotNewsletterOptIn,
            onChanged: (v) => context.read<SettingsProvider>().setPilotNewsletterOptIn(v ?? false),
            title: const Text('Recevoir les nouvelles de MOTO OFFROAD 4X4',
              style: TextStyle(color: Colors.white, fontSize: 13)),
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: AppColors.orange,
            contentPadding: EdgeInsets.zero,
          ),
```
Add `late final TextEditingController _pilotEmailCtrl;` alongside the existing `_nameCtrl` field, initialize it in `initState` the same way (`TextEditingController(text: context.read<SettingsProvider>().pilotEmail)`), and dispose it in `dispose()` alongside `_nameCtrl.dispose()`.

Add a new section method, called from `build` right after the existing recording-settings section (`GlassPanel(child: _recordingSection(context))`):
```dart
            const SizedBox(height: 16),
            GlassPanel(child: _fallDetectionSection(context)),
```
```dart
  Widget _fallDetectionSection(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final unlock = context.read<AlertChannelUnlock>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('DÉTECTION DE CHUTE', style: TextStyle(
          fontFamily: 'Rajdhani', fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
        const SizedBox(height: 8),
        SwitchListTile(
          value: settings.fallDetectionEnabled,
          onChanged: (v) => settings.setFallDetectionEnabled(v),
          title: const Text('Activer la détection de chute', style: TextStyle(color: Colors.white, fontSize: 14)),
          activeColor: AppColors.orange,
          contentPadding: EdgeInsets.zero,
        ),
        if (settings.fallDetectionEnabled) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Compte à rebours avant alerte', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              Text('${settings.fallCountdownSeconds} s', style: const TextStyle(
                color: AppColors.orange, fontWeight: FontWeight.w700, fontFamily: 'Rajdhani', fontSize: 16)),
            ],
          ),
          Slider(
            value: settings.fallCountdownSeconds.toDouble(),
            min: 15, max: 120, divisions: 21,
            activeColor: AppColors.orange,
            onChanged: (v) => settings.setFallCountdownSeconds(v.round()),
          ),
          const SizedBox(height: 8),
          const Text('CANAUX D\'ALERTE', style: TextStyle(
            fontFamily: 'Rajdhani', fontSize: 12, color: AppColors.textMuted, letterSpacing: 1.5)),
          SwitchListTile(
            value: settings.alertChannelPhone,
            onChanged: (v) => settings.setAlertChannelPhone(v),
            title: const Text('SMS depuis le téléphone', style: TextStyle(color: Colors.white, fontSize: 14)),
            activeColor: AppColors.statusGreen,
            contentPadding: EdgeInsets.zero,
          ),
          SwitchListTile(
            value: settings.alertChannelServer,
            onChanged: (v) => settings.setAlertChannelServer(v),
            title: const Text('E-mail depuis le serveur', style: TextStyle(color: Colors.white, fontSize: 14)),
            activeColor: AppColors.statusGreen,
            contentPadding: EdgeInsets.zero,
          ),
          IgnorePointer(
            child: Opacity(
              opacity: 0.4,
              child: SwitchListTile(
                value: unlock.isUnlocked('sms_gateway'),
                onChanged: null,
                title: const Text('SMS via passerelle — Abonnement bientôt', style: TextStyle(color: Colors.white, fontSize: 14)),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          IgnorePointer(
            child: Opacity(
              opacity: 0.4,
              child: SwitchListTile(
                value: unlock.isUnlocked('voice_call'),
                onChanged: null,
                title: const Text('Appel vocal automatique — Abonnement bientôt', style: TextStyle(color: Colors.white, fontSize: 14)),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ],
    );
  }
```

- [ ] **Step 3: Apply the impeccable skill**

Invoke the `impeccable` skill on the new section against the rest of the settings screen — confirm the locked options read as clearly disabled (not confusingly clickable), and the section fits the existing `GlassPanel` rhythm.

- [ ] **Step 4: Verify**

Run: `flutter analyze lib/screens/settings/settings_screen.dart`
Expected: no new errors.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/settings/settings_screen.dart
git commit -m "feat: reglages e-mail pilote, newsletter et detection de chute dans l ecran Reglages"
```

---

## Post-plan checklist (not a task — a reminder for whoever merges)

- Run the full Flutter suite (`flutter test`) and `flutter analyze` once after Task 21, and the full server suite via Docker after Task 8 — every task above only runs its own test file.
- Real-device verification `flutter test` cannot do: trigger an actual fall pattern (drop the phone onto a soft surface from standing height, or simulate with a firm tap while stationary) with the app recording or in Solo mode, confirm the countdown appears, the alarm is audible, cancelling works, and letting it expire sends both a real SMS and (if a Solo session is active) a real e-mail.
- Brevo: verify the sender address, send one real test alert end-to-end after deploying Task 8, and confirm the reply-to actually reaches the pilot's inbox.
- The server repo (Part 1) and the app repo are deployed independently, exactly as documented at the end of the prior plan — pushing one never touches the other.
- `crypto: ^3.0.0` in `pubspec.yaml` has been unused since the prior lot (a deferred minor from that plan's Task 12); still not addressed by this plan — a good small follow-up whenever someone next touches `pubspec.yaml`.
