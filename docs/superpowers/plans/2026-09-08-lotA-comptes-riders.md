# Lot A — Comptes riders : plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Doter MOTO OFFROAD 4X4 d'un compte rider obligatoire à la première ouverture — e-mail vérifié, session conservée ensuite — sur lequel s'appuieront le partage de traces, la console d'administration et la validation des points d'intérêt.

**Architecture:** Le socle vit dans le serveur existant `moto-tracker-server` (Express + better-sqlite3 + nodemailer), qui gagne trois tables et un routeur `/api/account`. L'application Flutter gagne un client HTTP, un provider, quatre écrans et une redirection GoRouter qui garde l'accès à la carte. Deux chemins temporaires accompagnent la bascule : un délai de grâce de 30 jours pour les installations existantes, et un tutoriel de première ouverture en six étapes.

**Tech Stack:** Node 18+, Express 4, better-sqlite3, nodemailer, `node:test` · Flutter 3.44.3, provider, go_router, http, shared_preferences, flutter_secure_storage (nouvelle dépendance)

**Spec:** `docs/superpowers/specs/2026-09-08-comptes-riders-design.md`

## Contrainte de dépôts

Ce plan touche **deux dépôts git distincts** :

| Chemin | Dépôt | Tâches |
|---|---|---|
| `../moto-tracker-server` | `barbarescomarc/moto-tracker-server` | 1 à 10 |
| `.` (`moto_offroad`) | `barbarescomarc/moto-offroad-4x4` | 11 à 18 |

Les chemins de fichiers des tâches 1 à 10 sont relatifs à `moto-tracker-server`, ceux des tâches 11 à 18 à `moto_offroad`. Chaque tâche commite dans son propre dépôt. **Le serveur doit être déployé avant que l'application ne soit publiée** : l'inverse mettrait les riders devant un mur d'inscription sans serveur pour y répondre.

## Global Constraints

- Aucun jeton n'est stocké en clair : le serveur ne garde que son empreinte SHA-256.
- Hachage des mots de passe par `scrypt` de `node:crypto` — **aucune dépendance serveur nouvelle**.
- Mot de passe : **10 caractères minimum**, sans règle de composition arbitraire.
- `POST /login` et `POST /password/forgot` répondent de façon **identique** que le compte existe ou non.
- **Aucune adresse e-mail dans les journaux du serveur.**
- Durées : jeton de vérification **24 heures**, jeton de réinitialisation **1 heure**, session **180 jours** prolongés à chaque échange réussi.
- Le jeton de session délivré avant vérification **n'ouvre que les routes de compte**.
- L'application **ne se re-verrouille jamais en cours de sortie** : carte, GPS, SOS et détection de chute restent accessibles même serveur injoignable ou jeton révoqué.
- Une seule dépendance nouvelle côté application : `flutter_secure_storage`.
- Le code du délai de grâce est **temporaire** : isolé, commenté avec sa condition de retrait.
- Commentaires et libellés en français, avec les accents.

---

# Partie I — Serveur (`moto-tracker-server`)

### Task 1: Schéma des comptes et migration additive

**Files:**
- Modify: `src/db.js`
- Test: `test/db.test.js`

**Interfaces:**
- Consomme : `openDb(path)` existant.
- Produit : les tables `account`, `account_token`, `account_session`, et les colonnes `account_id` sur `session`, `member`, `subscriber`.

**Pourquoi les colonnes `account_id` n'ont pas de clé étrangère :** une contrainte `REFERENCES account(id) ON DELETE CASCADE` détruirait les sorties et les positions d'un rider qui supprime son compte. Or une sortie de groupe appartient aussi aux autres participants. Le lien est donc une colonne simple, et l'effacement RGPD la remet explicitement à NULL (tâche 7).

- [ ] **Step 1: Écrire le test qui échoue**

Ajouter à `test/db.test.js` :

```js
test('le schema cree les tables de comptes', () => {
  const db = openDb(':memory:');
  const tables = db.prepare("SELECT name FROM sqlite_master WHERE type='table'").all().map((r) => r.name);
  assert.ok(tables.includes('account'));
  assert.ok(tables.includes('account_token'));
  assert.ok(tables.includes('account_session'));
});

test('les colonnes account_id sont ajoutees aux tables existantes', () => {
  const db = openDb(':memory:');
  for (const table of ['session', 'member', 'subscriber']) {
    const columns = db.prepare(`PRAGMA table_info(${table})`).all().map((c) => c.name);
    assert.ok(columns.includes('account_id'), `${table} devrait porter account_id`);
  }
});

test('la migration ajoute account_id a une base deja peuplee', () => {
  const db = openDb(':memory:');
  db.prepare('INSERT INTO subscriber (email, subscribed_at, source, unsubscribe_token) VALUES (?,?,?,?)')
    .run('rider@example.test', Date.now(), 'pilot', 'jeton');
  const row = db.prepare('SELECT account_id FROM subscriber WHERE email = ?').get('rider@example.test');
  assert.equal(row.account_id, null);
});
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

Run: `npm test`
Expected: FAIL — `assert.ok(tables.includes('account'))` échoue.

- [ ] **Step 3: Implémenter**

Dans `src/db.js`, ajouter à la fin de la constante `SCHEMA` :

```sql
CREATE TABLE IF NOT EXISTS account (
  id            TEXT PRIMARY KEY,
  email         TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  display_name  TEXT,
  created_at    INTEGER NOT NULL,
  verified_at   INTEGER,
  deleted_at    INTEGER
);

CREATE TABLE IF NOT EXISTS account_token (
  token_hash TEXT PRIMARY KEY,
  account_id TEXT NOT NULL REFERENCES account(id) ON DELETE CASCADE,
  purpose    TEXT NOT NULL CHECK (purpose IN ('verify','reset')),
  expires_at INTEGER NOT NULL,
  used_at    INTEGER
);

CREATE TABLE IF NOT EXISTS account_session (
  token_hash   TEXT PRIMARY KEY,
  account_id   TEXT NOT NULL REFERENCES account(id) ON DELETE CASCADE,
  created_at   INTEGER NOT NULL,
  last_seen_at INTEGER NOT NULL,
  expires_at   INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_account_token_account ON account_token(account_id);
CREATE INDEX IF NOT EXISTS idx_account_session_account ON account_session(account_id);
```

Puis étendre `migrate` :

```js
function migrate(db) {
  addColumn(db, 'session', 'pilot_email', 'TEXT');
  // Colonnes de rattachement au compte rider. Volontairement sans clé
  // étrangère : une cascade détruirait les sorties et les positions d'un
  // rider qui supprime son compte, alors qu'une sortie de groupe appartient
  // aussi aux autres participants. L'effacement les remet à NULL.
  addColumn(db, 'session', 'account_id', 'TEXT');
  addColumn(db, 'member', 'account_id', 'TEXT');
  addColumn(db, 'subscriber', 'account_id', 'TEXT');
}

function addColumn(db, table, column, type) {
  const columns = db.prepare(`PRAGMA table_info(${table})`).all().map((c) => c.name);
  if (!columns.includes(column)) {
    db.exec(`ALTER TABLE ${table} ADD COLUMN ${column} ${type}`);
  }
}
```

- [ ] **Step 4: Lancer les tests**

Run: `npm test`
Expected: PASS, y compris les tests existants.

- [ ] **Step 5: Commit**

```bash
git add src/db.js test/db.test.js
git commit -m "feat(db): tables de comptes riders et colonnes de rattachement"
```

---

### Task 2: Hachage des mots de passe et empreintes de jetons

**Files:**
- Create: `src/accounts/password.js`
- Modify: `src/secrets.js`
- Test: `test/password.test.js`

**Interfaces:**
- Produit : `hashPassword(plain) -> string`, `verifyPassword(plain, stored) -> boolean`, `DUMMY_HASH` (constante), et dans `secrets.js` : `hashToken(token) -> string` (SHA-256 hexadécimal).

`DUMMY_HASH` sert à la tâche 5 : quand l'e-mail est inconnu, `login` vérifie quand même un mot de passe contre cette empreinte factice, pour que le temps de réponse ne trahisse pas l'absence de compte.

- [ ] **Step 1: Écrire le test qui échoue**

Créer `test/password.test.js` :

```js
const test = require('node:test');
const assert = require('node:assert/strict');
const { hashPassword, verifyPassword, DUMMY_HASH } = require('../src/accounts/password');
const { hashToken } = require('../src/secrets');

test('un mot de passe hache se verifie', () => {
  const stored = hashPassword('correct horse battery');
  assert.ok(verifyPassword('correct horse battery', stored));
});

test('un mauvais mot de passe est refuse', () => {
  const stored = hashPassword('correct horse battery');
  assert.equal(verifyPassword('mauvais mot de passe', stored), false);
});

test('deux hachages du meme mot de passe different par leur sel', () => {
  assert.notEqual(hashPassword('identique'), hashPassword('identique'));
});

test('le hachage factice est verifiable sans jamais reussir', () => {
  assert.equal(verifyPassword('nimporte quoi', DUMMY_HASH), false);
});

test('un stockage corrompu est refuse sans lever', () => {
  assert.equal(verifyPassword('peu importe', 'nawak'), false);
});

test('hashToken est stable et ne rend jamais le jeton', () => {
  assert.equal(hashToken('abc'), hashToken('abc'));
  assert.notEqual(hashToken('abc'), 'abc');
  assert.equal(hashToken('abc').length, 64);
});
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

Run: `node --test test/password.test.js`
Expected: FAIL — `Cannot find module '../src/accounts/password'`.

- [ ] **Step 3: Implémenter**

Créer `src/accounts/password.js` :

```js
const crypto = require('node:crypto');

// Paramètres scrypt : coût mémoire 16 Mo, largement au-dessus du seuil
// recommandé pour un mot de passe utilisateur, et tenable sur le serveur.
const N = 16384;
const R = 8;
const P = 1;
const KEY_LENGTH = 64;
const SALT_LENGTH = 16;

function derive(plain, salt) {
  return crypto.scryptSync(plain, salt, KEY_LENGTH, { N, r: R, p: P, maxmem: 64 * 1024 * 1024 });
}

function hashPassword(plain) {
  const salt = crypto.randomBytes(SALT_LENGTH);
  const key = derive(plain, salt);
  return `scrypt$${N}$${R}$${P}$${salt.toString('base64')}$${key.toString('base64')}`;
}

function verifyPassword(plain, stored) {
  try {
    const [scheme, n, r, p, saltB64, keyB64] = String(stored).split('$');
    if (scheme !== 'scrypt') return false;
    const salt = Buffer.from(saltB64, 'base64');
    const expected = Buffer.from(keyB64, 'base64');
    const actual = crypto.scryptSync(plain, salt, expected.length, {
      N: Number(n), r: Number(r), p: Number(p), maxmem: 64 * 1024 * 1024,
    });
    return crypto.timingSafeEqual(actual, expected);
  } catch (_) {
    // Un stockage illisible n'est pas une raison de planter la route de
    // connexion : c'est un refus, comme un mauvais mot de passe.
    return false;
  }
}

// Empreinte d'un mot de passe qui n'est celui de personne. Vérifiée quand
// l'adresse est inconnue, pour que la durée de la réponse ne dise pas si le
// compte existe.
const DUMMY_HASH = hashPassword(crypto.randomBytes(32).toString('base64'));

module.exports = { hashPassword, verifyPassword, DUMMY_HASH };
```

Ajouter à `src/secrets.js` :

```js
function hashToken(token) {
  return crypto.createHash('sha256').update(String(token)).digest('hex');
}
```

et l'exporter : `module.exports = { randomToken, randomJoinCode, hashToken };`

- [ ] **Step 4: Lancer les tests**

Run: `npm test`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/accounts/password.js src/secrets.js test/password.test.js
git commit -m "feat(comptes): hachage scrypt des mots de passe et empreinte des jetons"
```

---

### Task 3: E-mails de compte

**Files:**
- Modify: `src/mailer.js`
- Test: `test/mailer.test.js`

**Interfaces:**
- Produit : `createMailer(transport)` renvoie désormais `{ sendAlertEmail, sendVerifyEmail, sendResetEmail }`.
- `sendVerifyEmail({ to, verifyUrl })`, `sendResetEmail({ to, resetUrl })` — toutes deux `async`, ne lèvent jamais.

- [ ] **Step 1: Écrire le test qui échoue**

Ajouter à `test/mailer.test.js` :

```js
test('l e-mail de verification porte le lien et ne leve pas si le transport echoue', async () => {
  const envoyes = [];
  const transport = { sendMail: async (msg) => { envoyes.push(msg); } };
  const mailer = createMailer(transport);

  await mailer.sendVerifyEmail({ to: 'rider@example.test', verifyUrl: 'https://exemple.test/a/verify/JETON' });

  assert.equal(envoyes.length, 1);
  assert.equal(envoyes[0].to, 'rider@example.test');
  assert.ok(envoyes[0].text.includes('https://exemple.test/a/verify/JETON'));

  const cassé = createMailer({ sendMail: async () => { throw new Error('smtp down'); } });
  await cassé.sendVerifyEmail({ to: 'rider@example.test', verifyUrl: 'https://exemple.test/x' });
});

test('l e-mail de reinitialisation porte le lien', async () => {
  const envoyes = [];
  const mailer = createMailer({ sendMail: async (msg) => { envoyes.push(msg); } });
  await mailer.sendResetEmail({ to: 'rider@example.test', resetUrl: 'https://exemple.test/r/JETON' });
  assert.ok(envoyes[0].text.includes('https://exemple.test/r/JETON'));
});
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

Run: `node --test test/mailer.test.js`
Expected: FAIL — `mailer.sendVerifyEmail is not a function`.

- [ ] **Step 3: Implémenter**

Dans `src/mailer.js`, à l'intérieur de `createMailer(transport)`, avant le `return` :

```js
  async function sendTransactional({ to, subject, text }) {
    try {
      await transport.sendMail({ from: process.env.MAIL_FROM, to, subject, text });
    } catch (err) {
      // Pas d'adresse dans le journal : le message dit seulement quel type
      // d'envoi a échoué.
      console.error('mailer: envoi transactionnel echoue', subject, err.message);
    }
  }

  async function sendVerifyEmail({ to, verifyUrl }) {
    await sendTransactional({
      to,
      subject: 'Confirme ton adresse — MOTO OFFROAD 4X4',
      text:
        `Bienvenue !\n\n` +
        `Confirme ton adresse pour accéder à l'application :\n${verifyUrl}\n\n` +
        `Ce lien est valable 24 heures.\n` +
        `Si tu n'es pas à l'origine de cette inscription, ignore ce message.`,
    });
  }

  async function sendResetEmail({ to, resetUrl }) {
    await sendTransactional({
      to,
      subject: 'Réinitialiser ton mot de passe — MOTO OFFROAD 4X4',
      text:
        `Pour choisir un nouveau mot de passe :\n${resetUrl}\n\n` +
        `Ce lien est valable 1 heure et ne peut servir qu'une fois.\n` +
        `Si tu n'as rien demandé, ignore ce message : ton mot de passe reste inchangé.`,
    });
  }
```

et changer le retour : `return { sendAlertEmail, sendVerifyEmail, sendResetEmail };`

- [ ] **Step 4: Lancer les tests**

Run: `npm test`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/mailer.js test/mailer.test.js
git commit -m "feat(comptes): e-mails de verification et de reinitialisation"
```

---

### Task 4: Inscription, vérification de l'adresse et rattachement de l'existant

**Files:**
- Create: `src/routes/account.js`
- Test: `test/account.test.js`

**Interfaces:**
- Consomme : `hashPassword`, `DUMMY_HASH` (tâche 2), `randomToken`, `hashToken` (tâche 2), `mailer.sendVerifyEmail` (tâche 3).
- Produit : `createAccountRouter(db, { mailer, baseUrl, now })` et `createAccountPagesRouter(db, { now })`, tous deux exportés par `src/routes/account.js`.
- Routes de cette tâche : `POST /register`, `POST /verify/resend`, `POST /email`, et la page `GET /a/verify/:token`.

**Un écart assumé à l'anti-énumération :** `POST /register` répond 409 quand l'adresse est déjà prise. La règle du chapitre 6.1 de la spec vise `login` et `password/forgot` ; l'appliquer aussi à l'inscription empêcherait un rider de comprendre pourquoi son compte ne se crée pas. Le compromis est délibéré.

**Rattachement :** à l'inscription, les lignes `subscriber` et `session` portant la même adresse reçoivent le nouvel `account_id`. `alert_contact` n'est jamais rattaché — ce sont les proches du rider, pas des utilisateurs. `member` ne peut pas l'être : la table ne contient aucune adresse.

- [ ] **Step 1: Écrire le test qui échoue**

Créer `test/account.test.js` :

```js
const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const { openDb } = require('../src/db');
const { createAccountRouter, createAccountPagesRouter } = require('../src/routes/account');

function buildApp({ now = () => Date.now() } = {}) {
  const db = openDb(':memory:');
  const envoyes = [];
  const mailer = {
    sendVerifyEmail: async (m) => { envoyes.push({ type: 'verify', ...m }); },
    sendResetEmail:  async (m) => { envoyes.push({ type: 'reset',  ...m }); },
  };
  const app = express();
  app.use(express.json());
  app.use('/api/account', createAccountRouter(db, { mailer, baseUrl: 'https://exemple.test', now }));
  app.use('/', createAccountPagesRouter(db, { now }));
  return { app, db, envoyes };
}

async function listen(app) {
  const server = app.listen(0);
  await new Promise((r) => server.once('listening', r));
  return { server, base: `http://127.0.0.1:${server.address().port}` };
}

function post(base, path, body, token) {
  const headers = { 'content-type': 'application/json' };
  if (token) headers.authorization = `Bearer ${token}`;
  return fetch(`${base}${path}`, { method: 'POST', headers, body: JSON.stringify(body) });
}

test('l inscription cree un compte non verifie et envoie le lien', async () => {
  const { app, db, envoyes } = buildApp();
  const { server, base } = await listen(app);
  const res = await post(base, '/api/account/register', {
    email: '  Rider@Example.TEST ', password: 'dix caracteres', displayName: 'Marc',
  });
  assert.equal(res.status, 201);
  const body = await res.json();
  assert.ok(body.token);
  assert.equal(body.verified, false);

  const row = db.prepare('SELECT * FROM account').get();
  assert.equal(row.email, 'rider@example.test'); // découpé et mis en minuscules
  assert.equal(row.verified_at, null);
  assert.equal(envoyes.length, 1);
  assert.ok(envoyes[0].verifyUrl.startsWith('https://exemple.test/a/verify/'));
  server.close();
});

test('un mot de passe trop court est refuse', async () => {
  const { app } = buildApp();
  const { server, base } = await listen(app);
  const res = await post(base, '/api/account/register', { email: 'a@b.test', password: 'court' });
  assert.equal(res.status, 400);
  server.close();
});

test('une adresse deja inscrite est refusee', async () => {
  const { app } = buildApp();
  const { server, base } = await listen(app);
  const body = { email: 'rider@example.test', password: 'dix caracteres' };
  await post(base, '/api/account/register', body);
  const res = await post(base, '/api/account/register', body);
  assert.equal(res.status, 409);
  server.close();
});

test('le lien de verification marque le compte verifie et ne sert qu une fois', async () => {
  const { app, db, envoyes } = buildApp();
  const { server, base } = await listen(app);
  await post(base, '/api/account/register', { email: 'rider@example.test', password: 'dix caracteres' });
  const url = envoyes[0].verifyUrl.replace('https://exemple.test', base);

  const premiere = await fetch(url);
  assert.equal(premiere.status, 200);
  assert.ok(db.prepare('SELECT verified_at FROM account').get().verified_at);

  const seconde = await fetch(url);
  assert.equal(seconde.status, 410);
  server.close();
});

test('un lien de verification expire est refuse', async () => {
  let maintenant = 1_000_000;
  const { app, envoyes } = buildApp({ now: () => maintenant });
  const { server, base } = await listen(app);
  await post(base, '/api/account/register', { email: 'rider@example.test', password: 'dix caracteres' });
  maintenant += 25 * 3600 * 1000;
  const res = await fetch(envoyes[0].verifyUrl.replace('https://exemple.test', base));
  assert.equal(res.status, 410);
  server.close();
});

test('l inscription rattache l abonne newsletter et la session solo de meme adresse', async () => {
  const { app, db } = buildApp();
  const { server, base } = await listen(app);
  db.prepare('INSERT INTO subscriber (email, subscribed_at, source, unsubscribe_token) VALUES (?,?,?,?)')
    .run('rider@example.test', Date.now(), 'pilot', 'jeton-desabo');
  db.prepare(`INSERT INTO session (id, kind, owner_key, pilot_email, created_at, expires_at)
              VALUES ('s1','solo','k','rider@example.test',?,?)`).run(Date.now(), Date.now() + 3600_000);
  db.prepare('INSERT INTO alert_contact (session_id, email) VALUES (?, ?)').run('s1', 'rider@example.test');

  await post(base, '/api/account/register', { email: 'rider@example.test', password: 'dix caracteres' });

  const accountId = db.prepare('SELECT id FROM account').get().id;
  assert.equal(db.prepare('SELECT account_id FROM subscriber').get().account_id, accountId);
  assert.equal(db.prepare('SELECT account_id FROM session').get().account_id, accountId);
  // Les proches ne sont jamais rattachés : la table n'a même pas la colonne.
  const colonnes = db.prepare('PRAGMA table_info(alert_contact)').all().map((c) => c.name);
  assert.equal(colonnes.includes('account_id'), false);
  server.close();
});

test('l adresse d un compte non verifie peut etre corrigee', async () => {
  const { app, db, envoyes } = buildApp();
  const { server, base } = await listen(app);
  const inscription = await post(base, '/api/account/register', { email: 'faute@example.test', password: 'dix caracteres' });
  const { token } = await inscription.json();

  const res = await post(base, '/api/account/email', { email: 'correct@example.test' }, token);
  assert.equal(res.status, 200);
  assert.equal(db.prepare('SELECT email FROM account').get().email, 'correct@example.test');
  assert.equal(envoyes.length, 2);
  assert.equal(envoyes[1].to, 'correct@example.test');
  server.close();
});
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

Run: `node --test test/account.test.js`
Expected: FAIL — `Cannot find module '../src/routes/account'`.

- [ ] **Step 3: Implémenter**

Créer `src/routes/account.js` :

```js
const crypto = require('node:crypto');
const express = require('express');
const { randomToken, hashToken } = require('../secrets');
const { hashPassword, verifyPassword, DUMMY_HASH } = require('../accounts/password');

const MIN_PASSWORD_LENGTH = 10;
const VERIFY_TTL_MS = 24 * 3600 * 1000;
const RESET_TTL_MS = 3600 * 1000;
const SESSION_TTL_MS = 180 * 24 * 3600 * 1000;

function normalizeEmail(email) {
  return typeof email === 'string' ? email.trim().toLowerCase() : '';
}

function isValidEmail(email) {
  return email.length > 2 && email.includes('@');
}

function page(message) {
  return `<!doctype html><html lang="fr"><meta charset="utf-8">` +
    `<body style="font-family:sans-serif;text-align:center;padding:40px">` +
    `<h2>${message}</h2></body></html>`;
}

function issueToken(db, accountId, purpose, now, ttl) {
  const token = randomToken(32);
  db.prepare('INSERT INTO account_token (token_hash, account_id, purpose, expires_at) VALUES (?,?,?,?)')
    .run(hashToken(token), accountId, purpose, now() + ttl);
  return token;
}

function openSession(db, accountId, now) {
  const token = randomToken(32);
  const at = now();
  db.prepare('INSERT INTO account_session (token_hash, account_id, created_at, last_seen_at, expires_at) VALUES (?,?,?,?,?)')
    .run(hashToken(token), accountId, at, at, at + SESSION_TTL_MS);
  return token;
}

function attachExisting(db, accountId, email) {
  db.prepare('UPDATE subscriber SET account_id = ? WHERE email = ? AND account_id IS NULL').run(accountId, email);
  db.prepare('UPDATE session SET account_id = ? WHERE pilot_email = ? AND account_id IS NULL').run(accountId, email);
}

function createAccountRouter(db, { mailer, baseUrl = 'https://motooffroad.duckdns.org', now = () => Date.now() } = {}) {
  const router = express.Router();

  router.post('/register', async (req, res) => {
    const email = normalizeEmail(req.body?.email);
    const password = req.body?.password;
    const displayName = typeof req.body?.displayName === 'string' ? req.body.displayName.trim() : null;

    if (!isValidEmail(email)) return res.status(400).json({ error: 'adresse invalide' });
    if (typeof password !== 'string' || password.length < MIN_PASSWORD_LENGTH) {
      return res.status(400).json({ error: `mot de passe de ${MIN_PASSWORD_LENGTH} caracteres minimum` });
    }
    if (db.prepare('SELECT 1 FROM account WHERE email = ?').get(email)) {
      return res.status(409).json({ error: 'adresse deja inscrite' });
    }

    const id = crypto.randomUUID();
    db.prepare('INSERT INTO account (id, email, password_hash, display_name, created_at) VALUES (?,?,?,?,?)')
      .run(id, email, hashPassword(password), displayName, now());
    attachExisting(db, id, email);

    const verify = issueToken(db, id, 'verify', now, VERIFY_TTL_MS);
    await mailer?.sendVerifyEmail({ to: email, verifyUrl: `${baseUrl}/a/verify/${verify}` });

    res.status(201).json({ token: openSession(db, id, now), verified: false, displayName });
  });

  return router;
}

function createAccountPagesRouter(db, { now = () => Date.now() } = {}) {
  const router = express.Router();

  router.get('/a/verify/:token', (req, res) => {
    const row = db.prepare(`SELECT * FROM account_token WHERE token_hash = ? AND purpose = 'verify'`)
      .get(hashToken(req.params.token));
    if (!row || row.used_at || row.expires_at < now()) {
      return res.status(410).send(page('Ce lien n’est plus valable. Demande un nouvel envoi depuis l’application.'));
    }
    db.prepare('UPDATE account_token SET used_at = ? WHERE token_hash = ?').run(now(), row.token_hash);
    db.prepare('UPDATE account SET verified_at = ? WHERE id = ? AND verified_at IS NULL').run(now(), row.account_id);
    res.status(200).send(page('Adresse confirmée. Tu peux revenir dans l’application.'));
  });

  return router;
}

module.exports = { createAccountRouter, createAccountPagesRouter, MIN_PASSWORD_LENGTH, SESSION_TTL_MS, RESET_TTL_MS, VERIFY_TTL_MS };
```

Les routes `POST /verify/resend` et `POST /email` ont besoin de l'authentification de la tâche 5. Les ajouter maintenant en fin de tâche 5 ; **le test `l adresse d un compte non verifie peut etre corrigee` reste rouge jusque-là**, c'est attendu et signalé dans le commit.

- [ ] **Step 4: Lancer les tests**

Run: `node --test test/account.test.js`
Expected: tous PASS sauf `l adresse d un compte non verifie peut etre corrigee` et `le lien de verification marque le compte verifie` — non, ce dernier doit passer. Seul le test de correction d'adresse échoue, faute de `POST /email`.

- [ ] **Step 5: Commit**

```bash
git add src/routes/account.js test/account.test.js
git commit -m "feat(comptes): inscription, verification d'adresse et rattachement de l'existant"
```

---

### Task 5: Authentification, connexion, profil et déconnexion

**Files:**
- Modify: `src/routes/account.js`
- Test: `test/account.test.js`

**Interfaces:**
- Produit : `authenticate(db, now)` et `requireVerified` exportés par `src/routes/account.js`. `authenticate` pose `req.account` (`{ id, email, display_name, verified_at }`) et `req.sessionTokenHash`.
- Routes ajoutées : `POST /login`, `POST /logout`, `GET /me`, `POST /verify/resend`, `POST /email`.

`requireVerified` est écrit ici et **consommé par les lots B et suivants** : c'est lui qui empêche le jeton non vérifié de devenir un contournement.

- [ ] **Step 1: Écrire le test qui échoue**

Ajouter à `test/account.test.js` :

```js
test('la connexion rend un jeton utilisable sur /me', async () => {
  const { app } = buildApp();
  const { server, base } = await listen(app);
  await post(base, '/api/account/register', { email: 'rider@example.test', password: 'dix caracteres' });
  const res = await post(base, '/api/account/login', { email: 'RIDER@example.test', password: 'dix caracteres' });
  assert.equal(res.status, 200);
  const { token } = await res.json();

  const moi = await fetch(`${base}/api/account/me`, { headers: { authorization: `Bearer ${token}` } });
  assert.equal(moi.status, 200);
  const profil = await moi.json();
  assert.equal(profil.email, 'rider@example.test');
  assert.equal(profil.verified, false);
  server.close();
});

test('une adresse inconnue et un mauvais mot de passe rendent la meme reponse', async () => {
  const { app } = buildApp();
  const { server, base } = await listen(app);
  await post(base, '/api/account/register', { email: 'rider@example.test', password: 'dix caracteres' });

  const inconnue = await post(base, '/api/account/login', { email: 'personne@example.test', password: 'dix caracteres' });
  const mauvais = await post(base, '/api/account/login', { email: 'rider@example.test', password: 'faux mot de passe' });

  assert.equal(inconnue.status, mauvais.status);
  assert.deepEqual(await inconnue.json(), await mauvais.json());
  server.close();
});

test('la deconnexion revoque le jeton', async () => {
  const { app } = buildApp();
  const { server, base } = await listen(app);
  const { token } = await (await post(base, '/api/account/register', { email: 'rider@example.test', password: 'dix caracteres' })).json();
  await post(base, '/api/account/logout', {}, token);
  const moi = await fetch(`${base}/api/account/me`, { headers: { authorization: `Bearer ${token}` } });
  assert.equal(moi.status, 401);
  server.close();
});

test('une session expiree est refusee', async () => {
  let maintenant = 1_000_000;
  const { app } = buildApp({ now: () => maintenant });
  const { server, base } = await listen(app);
  const { token } = await (await post(base, '/api/account/register', { email: 'rider@example.test', password: 'dix caracteres' })).json();
  maintenant += 181 * 24 * 3600 * 1000;
  const moi = await fetch(`${base}/api/account/me`, { headers: { authorization: `Bearer ${token}` } });
  assert.equal(moi.status, 401);
  server.close();
});
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

Run: `node --test test/account.test.js`
Expected: FAIL — 404 sur `/api/account/login`.

- [ ] **Step 3: Implémenter**

Dans `src/routes/account.js`, ajouter avant `createAccountRouter` :

```js
function authenticate(db, now) {
  return (req, res, next) => {
    const header = req.get('authorization') || '';
    const token = header.startsWith('Bearer ') ? header.slice(7) : null;
    if (!token) return res.status(401).json({ error: 'authentification requise' });

    const session = db.prepare('SELECT * FROM account_session WHERE token_hash = ?').get(hashToken(token));
    if (!session || session.expires_at < now()) return res.status(401).json({ error: 'authentification requise' });

    const account = db.prepare('SELECT id, email, display_name, verified_at FROM account WHERE id = ? AND deleted_at IS NULL')
      .get(session.account_id);
    if (!account) return res.status(401).json({ error: 'authentification requise' });

    const at = now();
    db.prepare('UPDATE account_session SET last_seen_at = ?, expires_at = ? WHERE token_hash = ?')
      .run(at, at + SESSION_TTL_MS, session.token_hash);

    req.account = account;
    req.sessionTokenHash = session.token_hash;
    next();
  };
}

// Garde destinée aux lots suivants : un jeton délivré avant vérification
// n'ouvre que les routes de compte, jamais une fonction du produit.
function requireVerified(req, res, next) {
  if (!req.account?.verified_at) return res.status(403).json({ error: 'adresse non verifiee' });
  next();
}
```

et dans `createAccountRouter`, après `/register` :

```js
  const auth = authenticate(db, now);

  router.post('/login', (req, res) => {
    const email = normalizeEmail(req.body?.email);
    const password = typeof req.body?.password === 'string' ? req.body.password : '';
    const account = db.prepare('SELECT * FROM account WHERE email = ? AND deleted_at IS NULL').get(email);

    // Adresse inconnue : on vérifie quand même un mot de passe, contre une
    // empreinte qui n'est celle de personne. Sans cela le temps de réponse
    // dirait qui est inscrit.
    const ok = verifyPassword(password, account?.password_hash ?? DUMMY_HASH);
    if (!account || !ok) return res.status(401).json({ error: 'identifiants invalides' });

    res.status(200).json({
      token: openSession(db, account.id, now),
      verified: Boolean(account.verified_at),
      displayName: account.display_name,
    });
  });

  router.post('/logout', auth, (req, res) => {
    db.prepare('DELETE FROM account_session WHERE token_hash = ?').run(req.sessionTokenHash);
    res.status(200).json({});
  });

  router.get('/me', auth, (req, res) => {
    res.status(200).json({
      email: req.account.email,
      displayName: req.account.display_name,
      verified: Boolean(req.account.verified_at),
    });
  });

  router.post('/verify/resend', auth, async (req, res) => {
    if (req.account.verified_at) return res.status(200).json({ alreadyVerified: true });
    const verify = issueToken(db, req.account.id, 'verify', now, VERIFY_TTL_MS);
    await mailer?.sendVerifyEmail({ to: req.account.email, verifyUrl: `${baseUrl}/a/verify/${verify}` });
    res.status(200).json({});
  });

  router.post('/email', auth, async (req, res) => {
    if (req.account.verified_at) return res.status(409).json({ error: 'adresse deja verifiee' });
    const email = normalizeEmail(req.body?.email);
    if (!isValidEmail(email)) return res.status(400).json({ error: 'adresse invalide' });
    if (db.prepare('SELECT 1 FROM account WHERE email = ? AND id <> ?').get(email, req.account.id)) {
      return res.status(409).json({ error: 'adresse deja inscrite' });
    }

    db.prepare('UPDATE account SET email = ? WHERE id = ?').run(email, req.account.id);
    db.prepare(`DELETE FROM account_token WHERE account_id = ? AND purpose = 'verify'`).run(req.account.id);
    attachExisting(db, req.account.id, email);

    const verify = issueToken(db, req.account.id, 'verify', now, VERIFY_TTL_MS);
    await mailer?.sendVerifyEmail({ to: email, verifyUrl: `${baseUrl}/a/verify/${verify}` });
    res.status(200).json({});
  });
```

Compléter l'export : `module.exports = { createAccountRouter, createAccountPagesRouter, authenticate, requireVerified, MIN_PASSWORD_LENGTH, SESSION_TTL_MS, RESET_TTL_MS, VERIFY_TTL_MS };`

- [ ] **Step 4: Lancer les tests**

Run: `npm test`
Expected: PASS, y compris le test de correction d'adresse resté rouge à la tâche 4.

- [ ] **Step 5: Commit**

```bash
git add src/routes/account.js test/account.test.js
git commit -m "feat(comptes): connexion, profil, deconnexion et garde de verification"
```

---

### Task 6: Mot de passe oublié et réinitialisation

**Files:**
- Modify: `src/routes/account.js`
- Test: `test/account.test.js`

**Interfaces:**
- Routes ajoutées : `POST /password/forgot`, `POST /password/reset`, et la page `GET /r/:token`.
- Consomme : `issueToken`, `hashPassword`, `mailer.sendResetEmail` (tâche 3).

- [ ] **Step 1: Écrire le test qui échoue**

Ajouter à `test/account.test.js` :

```js
test('l oubli repond pareil pour une adresse connue et inconnue', async () => {
  const { app, envoyes } = buildApp();
  const { server, base } = await listen(app);
  await post(base, '/api/account/register', { email: 'rider@example.test', password: 'dix caracteres' });
  envoyes.length = 0;

  const connue   = await post(base, '/api/account/password/forgot', { email: 'rider@example.test' });
  const inconnue = await post(base, '/api/account/password/forgot', { email: 'personne@example.test' });

  assert.equal(connue.status, inconnue.status);
  assert.deepEqual(await connue.json(), await inconnue.json());
  // Un seul e-mail part réellement : celui du compte qui existe.
  assert.equal(envoyes.filter((e) => e.type === 'reset').length, 1);
  server.close();
});

test('la reinitialisation change le mot de passe et revoque toutes les sessions', async () => {
  const { app, envoyes } = buildApp();
  const { server, base } = await listen(app);
  const { token: ancienJeton } = await (await post(base, '/api/account/register', { email: 'rider@example.test', password: 'dix caracteres' })).json();
  await post(base, '/api/account/password/forgot', { email: 'rider@example.test' });
  const lien = envoyes.find((e) => e.type === 'reset').resetUrl;
  const jetonReset = lien.split('/').pop();

  const res = await post(base, '/api/account/password/reset', { token: jetonReset, password: 'nouveau mot de passe' });
  assert.equal(res.status, 200);

  const ancienne = await fetch(`${base}/api/account/me`, { headers: { authorization: `Bearer ${ancienJeton}` } });
  assert.equal(ancienne.status, 401);

  const reconnexion = await post(base, '/api/account/login', { email: 'rider@example.test', password: 'nouveau mot de passe' });
  assert.equal(reconnexion.status, 200);
  server.close();
});

test('un jeton de reinitialisation ne sert qu une fois', async () => {
  const { app, envoyes } = buildApp();
  const { server, base } = await listen(app);
  await post(base, '/api/account/register', { email: 'rider@example.test', password: 'dix caracteres' });
  await post(base, '/api/account/password/forgot', { email: 'rider@example.test' });
  const jetonReset = envoyes.find((e) => e.type === 'reset').resetUrl.split('/').pop();

  await post(base, '/api/account/password/reset', { token: jetonReset, password: 'nouveau mot de passe' });
  const seconde = await post(base, '/api/account/password/reset', { token: jetonReset, password: 'encore un autre' });
  assert.equal(seconde.status, 410);
  server.close();
});

test('la page de reinitialisation affiche un formulaire', async () => {
  const { app, envoyes } = buildApp();
  const { server, base } = await listen(app);
  await post(base, '/api/account/register', { email: 'rider@example.test', password: 'dix caracteres' });
  await post(base, '/api/account/password/forgot', { email: 'rider@example.test' });
  const lien = envoyes.find((e) => e.type === 'reset').resetUrl.replace('https://exemple.test', base);
  const res = await fetch(lien);
  assert.equal(res.status, 200);
  assert.ok((await res.text()).includes('<form'));
  server.close();
});
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

Run: `node --test test/account.test.js`
Expected: FAIL — 404 sur `/api/account/password/forgot`.

- [ ] **Step 3: Implémenter**

Dans `createAccountRouter` :

```js
  router.post('/password/forgot', async (req, res) => {
    const email = normalizeEmail(req.body?.email);
    const account = db.prepare('SELECT id, email FROM account WHERE email = ? AND deleted_at IS NULL').get(email);
    if (account) {
      const reset = issueToken(db, account.id, 'reset', now, RESET_TTL_MS);
      await mailer?.sendResetEmail({ to: account.email, resetUrl: `${baseUrl}/r/${reset}` });
    }
    // Réponse identique dans les deux cas : le serveur ne dit pas qui est inscrit.
    res.status(202).json({});
  });

  router.post('/password/reset', (req, res) => {
    const { token, password } = req.body ?? {};
    if (typeof password !== 'string' || password.length < MIN_PASSWORD_LENGTH) {
      return res.status(400).json({ error: `mot de passe de ${MIN_PASSWORD_LENGTH} caracteres minimum` });
    }
    const row = db.prepare(`SELECT * FROM account_token WHERE token_hash = ? AND purpose = 'reset'`)
      .get(hashToken(String(token ?? '')));
    if (!row || row.used_at || row.expires_at < now()) return res.status(410).json({ error: 'lien expire' });

    db.prepare('UPDATE account_token SET used_at = ? WHERE token_hash = ?').run(now(), row.token_hash);
    db.prepare('UPDATE account SET password_hash = ? WHERE id = ?').run(hashPassword(password), row.account_id);
    // Changer son mot de passe est le geste de quelqu'un dont le compte a
    // fuité : tous les appareils sont déconnectés.
    db.prepare('DELETE FROM account_session WHERE account_id = ?').run(row.account_id);
    res.status(200).json({});
  });
```

et dans `createAccountPagesRouter` :

```js
  router.use(express.urlencoded({ extended: false }));

  router.get('/r/:token', (req, res) => {
    const safe = String(req.params.token).replace(/[^A-Za-z0-9_-]/g, '');
    res.status(200).send(
      `<!doctype html><html lang="fr"><meta charset="utf-8">` +
      `<body style="font-family:sans-serif;max-width:420px;margin:40px auto;padding:0 16px">` +
      `<h2>Nouveau mot de passe</h2>` +
      `<form method="post" action="/api/account/password/reset">` +
      `<input type="hidden" name="token" value="${safe}">` +
      `<input type="password" name="password" minlength="10" required ` +
      `placeholder="10 caractères minimum" style="width:100%;padding:10px;font-size:16px">` +
      `<button type="submit" style="margin-top:12px;padding:10px 18px;font-size:16px">Valider</button>` +
      `</form></body></html>`
    );
  });
```

Le routeur de l'API doit accepter ce formulaire : ajouter `router.use(express.urlencoded({ extended: false }));` en tête de `createAccountRouter`, comme le fait déjà `createNewsletterRouter`.

- [ ] **Step 4: Lancer les tests**

Run: `npm test`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/routes/account.js test/account.test.js
git commit -m "feat(comptes): mot de passe oublie, reinitialisation et revocation des sessions"
```

---

### Task 7: Effacement RGPD

**Files:**
- Modify: `src/routes/account.js`
- Test: `test/account.test.js`

**Interfaces:**
- Route ajoutée : `DELETE /me`.

L'effacement supprime le compte, ses jetons et ses sessions, et **remet `account_id` à NULL** sur les lignes rattachées plutôt que de les détruire : une sortie de groupe appartient aussi aux autres participants.

- [ ] **Step 1: Écrire le test qui échoue**

```js
test('la suppression efface le compte et delie sans detruire les sorties', async () => {
  const { app, db } = buildApp();
  const { server, base } = await listen(app);
  const { token } = await (await post(base, '/api/account/register', { email: 'rider@example.test', password: 'dix caracteres' })).json();
  const accountId = db.prepare('SELECT id FROM account').get().id;
  db.prepare(`INSERT INTO session (id, kind, owner_key, created_at, expires_at, account_id)
              VALUES ('s1','group','k',?,?,?)`).run(Date.now(), Date.now() + 3600_000, accountId);

  const res = await fetch(`${base}/api/account/me`, { method: 'DELETE', headers: { authorization: `Bearer ${token}` } });
  assert.equal(res.status, 200);

  assert.equal(db.prepare('SELECT COUNT(*) c FROM account').get().c, 0);
  assert.equal(db.prepare('SELECT COUNT(*) c FROM account_session').get().c, 0);
  assert.equal(db.prepare('SELECT COUNT(*) c FROM account_token').get().c, 0);
  const sortie = db.prepare("SELECT * FROM session WHERE id = 's1'").get();
  assert.ok(sortie, 'la sortie ne doit pas etre detruite');
  assert.equal(sortie.account_id, null);

  const apres = await fetch(`${base}/api/account/me`, { headers: { authorization: `Bearer ${token}` } });
  assert.equal(apres.status, 401);
  server.close();
});

test('la suppression retire aussi l abonnement newsletter', async () => {
  const { app, db } = buildApp();
  const { server, base } = await listen(app);
  db.prepare('INSERT INTO subscriber (email, subscribed_at, source, unsubscribe_token) VALUES (?,?,?,?)')
    .run('rider@example.test', Date.now(), 'pilot', 'jeton-desabo');
  const { token } = await (await post(base, '/api/account/register', { email: 'rider@example.test', password: 'dix caracteres' })).json();
  await fetch(`${base}/api/account/me`, { method: 'DELETE', headers: { authorization: `Bearer ${token}` } });
  assert.equal(db.prepare('SELECT COUNT(*) c FROM subscriber').get().c, 0);
  server.close();
});
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

Run: `node --test test/account.test.js`
Expected: FAIL — 404 sur `DELETE /api/account/me`.

- [ ] **Step 3: Implémenter**

```js
  router.delete('/me', auth, (req, res) => {
    const id = req.account.id;
    const effacer = db.transaction(() => {
      // Délier sans détruire : une sortie de groupe appartient aussi aux
      // autres participants, et ses positions à eux tous.
      db.prepare('UPDATE session SET account_id = NULL WHERE account_id = ?').run(id);
      db.prepare('UPDATE member SET account_id = NULL WHERE account_id = ?').run(id);
      // L'abonnement, lui, est une donnée personnelle : il part avec le compte.
      db.prepare('DELETE FROM subscriber WHERE account_id = ?').run(id);
      db.prepare('DELETE FROM account_session WHERE account_id = ?').run(id);
      db.prepare('DELETE FROM account_token WHERE account_id = ?').run(id);
      db.prepare('DELETE FROM account WHERE id = ?').run(id);
    });
    effacer();
    res.status(200).json({});
  });
```

- [ ] **Step 4: Lancer les tests**

Run: `npm test`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/routes/account.js test/account.test.js
git commit -m "feat(comptes): effacement RGPD effectif du compte"
```

---

### Task 8: Limitation de débit

**Files:**
- Create: `src/rate_limit.js`
- Modify: `src/routes/account.js`
- Test: `test/rate_limit.test.js`

**Interfaces:**
- Produit : `createRateLimiter({ windowMs, max, now })` — un middleware Express, compteur en mémoire par adresse IP et par chemin.

Le serveur tourne en un seul processus (voir `docker-compose.yml`) : un compteur en mémoire suffit et évite une dépendance. Il est remis à zéro au redémarrage, ce qui est acceptable pour une protection contre le bourrinage.

- [ ] **Step 1: Écrire le test qui échoue**

Créer `test/rate_limit.test.js` :

```js
const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const { createRateLimiter } = require('../src/rate_limit');

async function listen(app) {
  const server = app.listen(0);
  await new Promise((r) => server.once('listening', r));
  return { server, base: `http://127.0.0.1:${server.address().port}` };
}

test('au-dela du quota la reponse est 429, puis la fenetre se relache', async () => {
  let maintenant = 0;
  const app = express();
  app.use(createRateLimiter({ windowMs: 60_000, max: 2, now: () => maintenant }));
  app.get('/x', (_req, res) => res.status(200).json({}));
  const { server, base } = await listen(app);

  assert.equal((await fetch(`${base}/x`)).status, 200);
  assert.equal((await fetch(`${base}/x`)).status, 200);
  assert.equal((await fetch(`${base}/x`)).status, 429);

  maintenant += 60_001;
  assert.equal((await fetch(`${base}/x`)).status, 200);
  server.close();
});

test('deux chemins ont des compteurs distincts', async () => {
  let maintenant = 0;
  const app = express();
  app.use(createRateLimiter({ windowMs: 60_000, max: 1, now: () => maintenant }));
  app.get('/a', (_req, res) => res.status(200).json({}));
  app.get('/b', (_req, res) => res.status(200).json({}));
  const { server, base } = await listen(app);

  assert.equal((await fetch(`${base}/a`)).status, 200);
  assert.equal((await fetch(`${base}/b`)).status, 200);
  server.close();
});
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

Run: `node --test test/rate_limit.test.js`
Expected: FAIL — `Cannot find module '../src/rate_limit'`.

- [ ] **Step 3: Implémenter**

Créer `src/rate_limit.js` :

```js
// Compteur en mémoire, par adresse IP et par chemin, sur fenêtre fixe.
// Le serveur tourne en un seul processus : pas de dépendance externe à
// ajouter pour cela. Le compteur repart de zéro au redémarrage, ce qui est
// sans conséquence pour une protection contre le bourrinage.
function createRateLimiter({ windowMs, max, now = () => Date.now() }) {
  const compteurs = new Map();

  return (req, res, next) => {
    const cle = `${req.ip}|${req.path}`;
    const at = now();
    const entree = compteurs.get(cle);

    if (!entree || at - entree.debut >= windowMs) {
      compteurs.set(cle, { debut: at, nombre: 1 });
      return next();
    }
    if (entree.nombre >= max) {
      res.set('Retry-After', String(Math.ceil((entree.debut + windowMs - at) / 1000)));
      return res.status(429).json({ error: 'trop de tentatives' });
    }
    entree.nombre += 1;
    next();
  };
}

module.exports = { createRateLimiter };
```

Dans `src/routes/account.js`, en tête de `createAccountRouter` :

```js
  const { createRateLimiter } = require('../rate_limit');
  // Sans cela le formulaire de connexion invite au bourrinage, et le renvoi
  // d'e-mail devient un canon à messages gratuit sur le quota Brevo,
  // expédiés sous le nom du produit.
  const limiteur = createRateLimiter({ windowMs: 15 * 60 * 1000, max: 10, now });
  router.post('/register', limiteur);
  router.post('/login', limiteur);
  router.post('/password/forgot', limiteur);
  router.post('/verify/resend', limiteur);
```

Ces quatre lignes doivent précéder les définitions de routes correspondantes.

- [ ] **Step 4: Lancer les tests**

Run: `npm test`
Expected: PASS. Si un test de la tâche 4 ou 5 dépasse 10 requêtes sur une même route, augmenter `max` du test concerné en injectant une horloge, pas en affaiblissant la valeur de production.

- [ ] **Step 5: Commit**

```bash
git add src/rate_limit.js src/routes/account.js test/rate_limit.test.js
git commit -m "feat(comptes): limitation de debit sur les routes sensibles"
```

---

### Task 9: Sauvegarde quotidienne et garde du balayage

**Files:**
- Create: `src/backup.js`
- Modify: `src/sweep.js`
- Test: `test/backup.test.js`, `test/sweep.test.js`

**Interfaces:**
- Produit : `backupDatabase(db, dir, now)` et `startBackups(db, dir)`.
- Modifie : `purgeExpired(db, now)` purge en plus les jetons de compte périmés, **sans jamais toucher aux comptes**.

- [ ] **Step 1: Écrire le test qui échoue**

Créer `test/backup.test.js` :

```js
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const Database = require('better-sqlite3');
const { openDb } = require('../src/db');
const { backupDatabase } = require('../src/backup');

test('la sauvegarde produit un fichier relisible et fait tourner les anciens', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'moto-backup-'));
  const dbPath = path.join(dir, 'source.db');
  const db = openDb(dbPath);
  db.prepare('INSERT INTO account (id, email, password_hash, created_at) VALUES (?,?,?,?)')
    .run('a1', 'rider@example.test', 'x', Date.now());

  const fichier = backupDatabase(db, dir, () => Date.parse('2026-09-08T03:00:00Z'));
  assert.ok(fs.existsSync(fichier));

  const relu = new Database(fichier, { readonly: true });
  assert.equal(relu.prepare('SELECT COUNT(*) c FROM account').get().c, 1);
  relu.close();

  for (let jour = 1; jour <= 20; jour++) {
    backupDatabase(db, dir, () => Date.parse('2026-09-08T03:00:00Z') + jour * 86_400_000);
  }
  const restants = fs.readdirSync(dir).filter((f) => f.startsWith('tracker-'));
  assert.equal(restants.length, 14);
  db.close();
});
```

Ajouter à `test/sweep.test.js` :

```js
test('le balayage ne supprime jamais un compte, seulement les jetons perimes', () => {
  const db = openDb(':memory:');
  const maintenant = Date.now();
  db.prepare('INSERT INTO account (id, email, password_hash, created_at) VALUES (?,?,?,?)')
    .run('a1', 'rider@example.test', 'x', maintenant);
  db.prepare('INSERT INTO account_token (token_hash, account_id, purpose, expires_at) VALUES (?,?,?,?)')
    .run('perime', 'a1', 'verify', maintenant - 1000);
  db.prepare('INSERT INTO account_token (token_hash, account_id, purpose, expires_at) VALUES (?,?,?,?)')
    .run('valide', 'a1', 'verify', maintenant + 3600_000);
  db.prepare('INSERT INTO account_session (token_hash, account_id, created_at, last_seen_at, expires_at) VALUES (?,?,?,?,?)')
    .run('vieille', 'a1', maintenant, maintenant, maintenant - 1000);

  purgeExpired(db, maintenant);

  assert.equal(db.prepare('SELECT COUNT(*) c FROM account').get().c, 1);
  assert.equal(db.prepare('SELECT COUNT(*) c FROM account_token').get().c, 1);
  assert.equal(db.prepare('SELECT COUNT(*) c FROM account_session').get().c, 0);
});
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `node --test test/backup.test.js test/sweep.test.js`
Expected: FAIL — module `../src/backup` introuvable, et les jetons périmés survivent au balayage.

- [ ] **Step 3: Implémenter**

Créer `src/backup.js` :

```js
const fs = require('node:fs');
const path = require('node:path');

const KEEP = 14;

// Jusqu'ici cette base n'hébergeait que du jetable. Depuis les comptes, elle
// détient des données irremplaçables : elle se sauvegarde.
function backupDatabase(db, dir, now = () => Date.now()) {
  fs.mkdirSync(dir, { recursive: true });
  const horodatage = new Date(now()).toISOString().slice(0, 10);
  const cible = path.join(dir, `tracker-${horodatage}.db`);
  if (fs.existsSync(cible)) fs.rmSync(cible);
  db.prepare('VACUUM INTO ?').run(cible);

  const anciennes = fs.readdirSync(dir).filter((f) => f.startsWith('tracker-') && f.endsWith('.db')).sort();
  for (const f of anciennes.slice(0, Math.max(0, anciennes.length - KEEP))) {
    fs.rmSync(path.join(dir, f));
  }
  return cible;
}

function startBackups(db, dir) {
  const timer = setInterval(() => {
    try {
      backupDatabase(db, dir);
    } catch (err) {
      console.error('backup: sauvegarde echouee', err.message);
    }
  }, 24 * 3600 * 1000);
  return { stop: () => clearInterval(timer) };
}

module.exports = { backupDatabase, startBackups };
```

Dans `src/sweep.js`, à la fin de `purgeExpired` :

```js
  // Jetons et sessions périmés seulement. Les comptes ne sont jamais balayés.
  db.prepare('DELETE FROM account_token WHERE expires_at < ? OR used_at IS NOT NULL').run(now);
  db.prepare('DELETE FROM account_session WHERE expires_at < ?').run(now);
```

- [ ] **Step 4: Lancer les tests**

Run: `npm test`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/backup.js src/sweep.js test/backup.test.js test/sweep.test.js
git commit -m "feat(exploitation): sauvegarde quotidienne et garde du balayage sur les comptes"
```

---

### Task 10: Branchement et déploiement

**Files:**
- Modify: `src/server.js`
- Modify: `docker-compose.yml`
- Test: `test/server.test.js`

**Interfaces:**
- Consomme : `createAccountRouter`, `createAccountPagesRouter` (tâches 4 à 8), `startBackups` (tâche 9).

- [ ] **Step 1: Écrire le test qui échoue**

Ajouter à `test/server.test.js` :

```js
test('l application expose les routes de compte', async () => {
  const db = openDb(':memory:');
  const app = createApp(db);
  const server = app.listen(0);
  await new Promise((r) => server.once('listening', r));
  const base = `http://127.0.0.1:${server.address().port}`;

  const res = await fetch(`${base}/api/account/register`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email: 'rider@example.test', password: 'dix caracteres' }),
  });
  assert.equal(res.status, 201);
  server.close();
});
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

Run: `node --test test/server.test.js`
Expected: FAIL — 404.

- [ ] **Step 3: Implémenter**

Dans `src/server.js` :

```js
const { createAccountRouter, createAccountPagesRouter } = require('./routes/account');
```

puis, dans `createApp`, avant le montage de `createWatchRouter` :

```js
  const publicBaseUrl = process.env.PUBLIC_BASE_URL || 'https://motooffroad.duckdns.org';
  app.use('/api/account', createAccountRouter(db, { mailer, baseUrl: publicBaseUrl }));
  app.use('/', createAccountPagesRouter(db));
```

Dans le bloc `require.main === module`, après `startSweeps` :

```js
  const { startBackups } = require('./backup');
  startBackups(db, process.env.BACKUP_DIR || '/app/data/backups');
```

Dans `docker-compose.yml`, ajouter aux variables d'environnement :

```yaml
      PUBLIC_BASE_URL: https://motooffroad.duckdns.org
      BACKUP_DIR: /app/data/backups
```

Le volume `./data:/app/data` existe déjà : les sauvegardes atterrissent donc sur le disque de l'hôte, hors du conteneur.

- [ ] **Step 4: Lancer la suite complète**

Run: `npm test`
Expected: PASS, tous fichiers confondus.

- [ ] **Step 5: Commit et déploiement**

```bash
git add src/server.js docker-compose.yml test/server.test.js
git commit -m "feat(comptes): montage des routes de compte et sauvegarde au demarrage"
./deploy.sh "Comptes riders : socle serveur"
```

- [ ] **Step 6: Vérifier sur le serveur**

```bash
curl -s https://motooffroad.duckdns.org/healthz
curl -s -X POST https://motooffroad.duckdns.org/api/account/register \
  -H 'content-type: application/json' \
  -d '{"email":"verification@example.test","password":"dix caracteres"}'
ssh drone31 "ls -l /root/moto-tracker/data/"
```

Attendu : `{"ok":true}`, une réponse 201 portant un jeton, et le répertoire `data` présent. Supprimer ensuite le compte de vérification avec le jeton reçu (`DELETE /api/account/me`).

---

# Partie II — Application (`moto_offroad`)

### Task 11: Stockage sécurisé du jeton

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/services/account_storage.dart`
- Test: `test/services/account_storage_test.dart`

**Interfaces:**
- Produit : `AccountStorage` avec `Future<String?> readToken()`, `Future<void> writeToken(String)`, `Future<void> clear()`. Constructeur `AccountStorage({FlutterSecureStorage? storage})` pour l'injection en test.

`shared_preferences` conviendrait techniquement, mais un jeton d'identité y est lisible sur un appareil déverrouillé par la racine et part dans la sauvegarde automatique Android : il serait restauré sur un autre téléphone.

- [ ] **Step 1: Écrire le test qui échoue**

Créer `test/services/account_storage_test.dart` :

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:moto_offroad/services/account_storage.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('un jeton ecrit est relu', () async {
    final storage = AccountStorage();
    await storage.writeToken('jeton-abc');
    expect(await storage.readToken(), 'jeton-abc');
  });

  test('sans jeton la lecture rend null', () async {
    expect(await AccountStorage().readToken(), isNull);
  });

  test('l effacement retire le jeton', () async {
    final storage = AccountStorage();
    await storage.writeToken('jeton-abc');
    await storage.clear();
    expect(await storage.readToken(), isNull);
  });
}
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

Run: `flutter test test/services/account_storage_test.dart`
Expected: FAIL — paquet et fichier introuvables.

- [ ] **Step 3: Implémenter**

Dans `pubspec.yaml`, section `# ── Stockage ─────`, ajouter :

```yaml
  flutter_secure_storage: ^9.2.2  # Jeton de session : Trousseau iOS, Keystore Android
```

Puis `flutter pub get`.

Créer `lib/services/account_storage.dart` :

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Conserve le jeton de session hors des préférences : un jeton d'identité
/// dans `shared_preferences` est lisible sur un appareil déverrouillé par la
/// racine, et part dans la sauvegarde automatique Android — il serait
/// restauré sur un autre téléphone.
class AccountStorage {
  AccountStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _kToken = 'account_session_token';

  final FlutterSecureStorage _storage;

  Future<String?> readToken() => _storage.read(key: _kToken);

  Future<void> writeToken(String token) => _storage.write(key: _kToken, value: token);

  Future<void> clear() => _storage.delete(key: _kToken);
}
```

- [ ] **Step 4: Lancer le test**

Run: `flutter test test/services/account_storage_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/services/account_storage.dart test/services/account_storage_test.dart
git commit -m "feat(compte): stockage securise du jeton de session"
```

---

### Task 12: Client HTTP du compte

**Files:**
- Create: `lib/services/account_api_client.dart`
- Test: `test/services/account_api_client_test.dart`

**Interfaces:**
- Produit :
  - `class AccountSession { final String token; final bool verified; final String? displayName; }`
  - `class AccountProfile { final String email; final bool verified; final String? displayName; }`
  - `enum AccountError { reseau, identifiants, adresseDejaPrise, motDePasseTropCourt, adresseInvalide, tropDeTentatives, inconnue }`
  - `class AccountResult<T> { final T? value; final AccountError? error; bool get ok; }`
  - `AccountApiClient({http.Client? client, String? baseUrl})` avec `register`, `login`, `logout`, `me`, `resendVerification`, `changeEmail`, `forgotPassword`, `deleteAccount`.

Le client suit `TrackerApiClient` : `http.Client` injectable, `baseUrl` par défaut `https://motooffroad.duckdns.org`. Il ne renvoie **pas** `null` en cas d'échec comme `TrackerApiClient`, parce que l'écran d'inscription doit distinguer « pas de réseau » de « adresse déjà prise » — c'est la différence entre réessayer et corriger.

- [ ] **Step 1: Écrire le test qui échoue**

Créer `test/services/account_api_client_test.dart` :

```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moto_offroad/services/account_api_client.dart';

AccountApiClient clientQuiRepond(int code, Map<String, dynamic> body, {void Function(http.Request)? onRequest}) {
  return AccountApiClient(
    baseUrl: 'https://exemple.test',
    client: MockClient((req) async {
      onRequest?.call(req);
      return http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json'});
    }),
  );
}

void main() {
  test('une inscription reussie rend le jeton et l etat non verifie', () async {
    final api = clientQuiRepond(201, {'token': 'jeton-abc', 'verified': false, 'displayName': 'Marc'});
    final res = await api.register(email: 'rider@example.test', password: 'dix caracteres', displayName: 'Marc');
    expect(res.ok, isTrue);
    expect(res.value!.token, 'jeton-abc');
    expect(res.value!.verified, isFalse);
  });

  test('une adresse deja prise est distinguee', () async {
    final api = clientQuiRepond(409, {'error': 'adresse deja inscrite'});
    final res = await api.register(email: 'rider@example.test', password: 'dix caracteres');
    expect(res.error, AccountError.adresseDejaPrise);
  });

  test('un mot de passe trop court est distingue', () async {
    final api = clientQuiRepond(400, {'error': 'mot de passe de 10 caracteres minimum'});
    final res = await api.register(email: 'rider@example.test', password: 'court');
    expect(res.error, AccountError.motDePasseTropCourt);
  });

  test('une panne reseau est distinguee d un refus', () async {
    final api = AccountApiClient(
      baseUrl: 'https://exemple.test',
      client: MockClient((_) async => throw const SocketExceptionStub()),
    );
    final res = await api.login(email: 'rider@example.test', password: 'dix caracteres');
    expect(res.error, AccountError.reseau);
  });

  test('le jeton est envoye en Bearer sur les routes authentifiees', () async {
    late http.Request vue;
    final api = clientQuiRepond(200, {'email': 'rider@example.test', 'verified': true}, onRequest: (r) => vue = r);
    await api.me(token: 'jeton-abc');
    expect(vue.headers['authorization'], 'Bearer jeton-abc');
  });

  test('un 429 devient tropDeTentatives', () async {
    final api = clientQuiRepond(429, {'error': 'trop de tentatives'});
    final res = await api.login(email: 'rider@example.test', password: 'dix caracteres');
    expect(res.error, AccountError.tropDeTentatives);
  });
}

class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

Run: `flutter test test/services/account_api_client_test.dart`
Expected: FAIL — fichier introuvable.

- [ ] **Step 3: Implémenter**

Créer `lib/services/account_api_client.dart` :

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class AccountSession {
  final String token;
  final bool verified;
  final String? displayName;
  const AccountSession({required this.token, required this.verified, this.displayName});
}

class AccountProfile {
  final String email;
  final bool verified;
  final String? displayName;
  const AccountProfile({required this.email, required this.verified, this.displayName});
}

/// Une panne de réseau et un refus du serveur n'appellent pas la même
/// conduite : l'une se réessaie, l'autre se corrige. L'écran doit pouvoir
/// les distinguer.
enum AccountError { reseau, identifiants, adresseDejaPrise, motDePasseTropCourt, adresseInvalide, tropDeTentatives, inconnue }

class AccountResult<T> {
  final T? value;
  final AccountError? error;
  const AccountResult.success(this.value) : error = null;
  const AccountResult.failure(this.error) : value = null;
  bool get ok => error == null;
}

class AccountApiClient {
  AccountApiClient({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? 'https://motooffroad.duckdns.org';

  final http.Client _client;
  final String _baseUrl;

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  Map<String, String> _headers([String? token]) => {
        'content-type': 'application/json',
        if (token != null) 'authorization': 'Bearer $token',
      };

  AccountError _errorFor(int status, String body) {
    switch (status) {
      case 401:
        return AccountError.identifiants;
      case 409:
        return AccountError.adresseDejaPrise;
      case 429:
        return AccountError.tropDeTentatives;
      case 400:
        return body.contains('mot de passe')
            ? AccountError.motDePasseTropCourt
            : AccountError.adresseInvalide;
      default:
        return AccountError.inconnue;
    }
  }

  Future<AccountResult<AccountSession>> _sessionCall(String path, Map<String, dynamic> body) async {
    try {
      final res = await _client.post(_uri(path), headers: _headers(), body: jsonEncode(body));
      if (res.statusCode ~/ 100 != 2) {
        return AccountResult.failure(_errorFor(res.statusCode, res.body));
      }
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      return AccountResult.success(AccountSession(
        token: j['token'] as String,
        verified: j['verified'] as bool? ?? false,
        displayName: j['displayName'] as String?,
      ));
    } catch (_) {
      return const AccountResult.failure(AccountError.reseau);
    }
  }

  Future<AccountResult<AccountSession>> register({
    required String email,
    required String password,
    String? displayName,
  }) =>
      _sessionCall('/api/account/register', {
        'email': email,
        'password': password,
        if (displayName != null && displayName.isNotEmpty) 'displayName': displayName,
      });

  Future<AccountResult<AccountSession>> login({required String email, required String password}) =>
      _sessionCall('/api/account/login', {'email': email, 'password': password});

  Future<AccountResult<AccountProfile>> me({required String token}) async {
    try {
      final res = await _client.get(_uri('/api/account/me'), headers: _headers(token));
      if (res.statusCode ~/ 100 != 2) {
        return AccountResult.failure(_errorFor(res.statusCode, res.body));
      }
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      return AccountResult.success(AccountProfile(
        email: j['email'] as String,
        verified: j['verified'] as bool? ?? false,
        displayName: j['displayName'] as String?,
      ));
    } catch (_) {
      return const AccountResult.failure(AccountError.reseau);
    }
  }

  Future<AccountResult<void>> _voidCall(String path, {String? token, Map<String, dynamic>? body, String method = 'POST'}) async {
    try {
      final uri = _uri(path);
      final res = method == 'DELETE'
          ? await _client.delete(uri, headers: _headers(token))
          : await _client.post(uri, headers: _headers(token), body: jsonEncode(body ?? {}));
      if (res.statusCode ~/ 100 != 2) {
        return AccountResult.failure(_errorFor(res.statusCode, res.body));
      }
      return const AccountResult.success(null);
    } catch (_) {
      return const AccountResult.failure(AccountError.reseau);
    }
  }

  Future<AccountResult<void>> logout({required String token}) =>
      _voidCall('/api/account/logout', token: token);

  Future<AccountResult<void>> resendVerification({required String token}) =>
      _voidCall('/api/account/verify/resend', token: token);

  Future<AccountResult<void>> changeEmail({required String token, required String email}) =>
      _voidCall('/api/account/email', token: token, body: {'email': email});

  Future<AccountResult<void>> forgotPassword({required String email}) =>
      _voidCall('/api/account/password/forgot', body: {'email': email});

  Future<AccountResult<void>> deleteAccount({required String token}) =>
      _voidCall('/api/account/me', token: token, method: 'DELETE');
}
```

- [ ] **Step 4: Lancer le test**

Run: `flutter test test/services/account_api_client_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/account_api_client.dart test/services/account_api_client_test.dart
git commit -m "feat(compte): client HTTP des routes de compte"
```

---

### Task 13: Provider du compte

**Files:**
- Create: `lib/providers/account_provider.dart`
- Modify: `lib/main.dart`
- Test: `test/providers/account_provider_test.dart`

**Interfaces:**
- Produit : `AccountProvider({AccountApiClient? api, AccountStorage? storage})` avec
  `AccountStatus get status` (`enum AccountStatus { chargement, deconnecte, nonVerifie, connecte }`),
  `String? get email`, `AccountError? get lastError`,
  `Future<void> restore()`, `Future<bool> register(...)`, `Future<bool> login(...)`,
  `Future<bool> refreshVerification()`, `Future<void> logout()`, `Future<bool> deleteAccount()`,
  `Future<bool> resendVerification()`, `Future<bool> changeEmail(String)`.

**Règle de robustesse :** si `refreshVerification()` échoue faute de réseau, le statut **ne change pas**. Une panne réseau ne déconnecte jamais un rider — c'est ce qui empêche l'application de se re-verrouiller en pleine sortie.

- [ ] **Step 1: Écrire le test qui échoue**

Créer `test/providers/account_provider_test.dart` :

```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moto_offroad/providers/account_provider.dart';
import 'package:moto_offroad/services/account_api_client.dart';
import 'package:moto_offroad/services/account_storage.dart';

AccountProvider provider(http.Client client) => AccountProvider(
      api: AccountApiClient(baseUrl: 'https://exemple.test', client: client),
      storage: AccountStorage(),
    );

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('sans jeton stocke le rider est deconnecte', () async {
    final p = provider(MockClient((_) async => http.Response('{}', 200)));
    await p.restore();
    expect(p.status, AccountStatus.deconnecte);
  });

  test('une inscription laisse le rider non verifie', () async {
    final p = provider(MockClient((_) async =>
        http.Response(jsonEncode({'token': 'jeton', 'verified': false}), 201)));
    final ok = await p.register(email: 'rider@example.test', password: 'dix caracteres');
    expect(ok, isTrue);
    expect(p.status, AccountStatus.nonVerifie);
    expect(await AccountStorage().readToken(), 'jeton');
  });

  test('la verification confirmee fait passer a connecte', () async {
    final p = provider(MockClient((req) async {
      if (req.url.path.endsWith('/register')) {
        return http.Response(jsonEncode({'token': 'jeton', 'verified': false}), 201);
      }
      return http.Response(jsonEncode({'email': 'rider@example.test', 'verified': true}), 200);
    }));
    await p.register(email: 'rider@example.test', password: 'dix caracteres');
    expect(await p.refreshVerification(), isTrue);
    expect(p.status, AccountStatus.connecte);
  });

  test('une panne reseau ne deconnecte jamais un rider connecte', () async {
    var enPanne = false;
    final p = provider(MockClient((req) async {
      if (enPanne) throw Exception('reseau coupe');
      if (req.url.path.endsWith('/register')) {
        return http.Response(jsonEncode({'token': 'jeton', 'verified': true}), 201);
      }
      return http.Response(jsonEncode({'email': 'rider@example.test', 'verified': true}), 200);
    }));
    await p.register(email: 'rider@example.test', password: 'dix caracteres');
    expect(p.status, AccountStatus.connecte);

    enPanne = true;
    await p.refreshVerification();
    expect(p.status, AccountStatus.connecte, reason: 'le reseau absent ne verrouille pas l application');
  });

  test('la deconnexion efface le jeton', () async {
    final p = provider(MockClient((_) async =>
        http.Response(jsonEncode({'token': 'jeton', 'verified': true}), 201)));
    await p.register(email: 'rider@example.test', password: 'dix caracteres');
    await p.logout();
    expect(p.status, AccountStatus.deconnecte);
    expect(await AccountStorage().readToken(), isNull);
  });
}
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

Run: `flutter test test/providers/account_provider_test.dart`
Expected: FAIL — fichier introuvable.

- [ ] **Step 3: Implémenter**

Créer `lib/providers/account_provider.dart` :

```dart
import 'package:flutter/foundation.dart';
import '../services/account_api_client.dart';
import '../services/account_storage.dart';

enum AccountStatus { chargement, deconnecte, nonVerifie, connecte }

class AccountProvider extends ChangeNotifier {
  AccountProvider({AccountApiClient? api, AccountStorage? storage})
      : _api = api ?? AccountApiClient(),
        _storage = storage ?? AccountStorage();

  final AccountApiClient _api;
  final AccountStorage _storage;

  AccountStatus _status = AccountStatus.chargement;
  String? _token;
  String? _email;
  String? _displayName;
  AccountError? _lastError;

  AccountStatus get status => _status;
  String? get email => _email;
  String? get displayName => _displayName;
  AccountError? get lastError => _lastError;
  String? get token => _token;

  void _set(AccountStatus status) {
    _status = status;
    notifyListeners();
  }

  Future<void> restore() async {
    _token = await _storage.readToken();
    if (_token == null) {
      _set(AccountStatus.deconnecte);
      return;
    }
    final profil = await _api.me(token: _token!);
    if (profil.ok) {
      _email = profil.value!.email;
      _displayName = profil.value!.displayName;
      _set(profil.value!.verified ? AccountStatus.connecte : AccountStatus.nonVerifie);
      return;
    }
    if (profil.error == AccountError.identifiants) {
      // Jeton révoqué : le rider devra se reconnecter.
      await _storage.clear();
      _token = null;
      _set(AccountStatus.deconnecte);
      return;
    }
    // Serveur injoignable : on garde le jeton et on suppose la session
    // valide. Une panne de réseau ne verrouille jamais l'application.
    _set(AccountStatus.connecte);
  }

  Future<bool> _apply(AccountResult<AccountSession> res, String email) async {
    _lastError = res.error;
    if (!res.ok) {
      notifyListeners();
      return false;
    }
    _token = res.value!.token;
    _email = email;
    _displayName = res.value!.displayName;
    await _storage.writeToken(_token!);
    _set(res.value!.verified ? AccountStatus.connecte : AccountStatus.nonVerifie);
    return true;
  }

  Future<bool> register({required String email, required String password, String? displayName}) async =>
      _apply(await _api.register(email: email, password: password, displayName: displayName), email);

  Future<bool> login({required String email, required String password}) async =>
      _apply(await _api.login(email: email, password: password), email);

  Future<bool> refreshVerification() async {
    if (_token == null) return false;
    final profil = await _api.me(token: _token!);
    if (!profil.ok) {
      _lastError = profil.error;
      // Statut inchangé : ni le réseau absent ni une erreur serveur ne
      // doivent dégrader l'état d'un rider déjà connecté.
      notifyListeners();
      return false;
    }
    _email = profil.value!.email;
    if (profil.value!.verified) {
      _set(AccountStatus.connecte);
      return true;
    }
    _set(AccountStatus.nonVerifie);
    return false;
  }

  Future<bool> resendVerification() async {
    if (_token == null) return false;
    return (await _api.resendVerification(token: _token!)).ok;
  }

  Future<bool> changeEmail(String email) async {
    if (_token == null) return false;
    final res = await _api.changeEmail(token: _token!, email: email);
    _lastError = res.error;
    if (res.ok) _email = email;
    notifyListeners();
    return res.ok;
  }

  Future<bool> forgotPassword(String email) async => (await _api.forgotPassword(email: email)).ok;

  Future<void> logout() async {
    if (_token != null) await _api.logout(token: _token!);
    await _storage.clear();
    _token = null;
    _email = null;
    _displayName = null;
    _set(AccountStatus.deconnecte);
  }

  Future<bool> deleteAccount() async {
    if (_token == null) return false;
    final res = await _api.deleteAccount(token: _token!);
    if (!res.ok) {
      _lastError = res.error;
      notifyListeners();
      return false;
    }
    await _storage.clear();
    _token = null;
    _email = null;
    _set(AccountStatus.deconnecte);
    return true;
  }
}
```

Dans `lib/main.dart`, ajouter l'import et le provider à la liste existante :

```dart
import 'providers/account_provider.dart';
```

```dart
        ChangeNotifierProvider(create: (_) => AccountProvider()..restore()),
```

- [ ] **Step 4: Lancer les tests**

Run: `flutter test test/providers/account_provider_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/providers/account_provider.dart lib/main.dart test/providers/account_provider_test.dart
git commit -m "feat(compte): provider d'etat du compte rider"
```

---

### Task 14: Porte d'entrée — la règle de redirection

**Files:**
- Create: `lib/app/account_gate.dart`
- Test: `test/app/account_gate_test.dart`

**Interfaces:**
- Produit : `String? accountRedirect({required AccountStatus status, required String location, required bool graceActive})`.

La décision est isolée dans une fonction pure plutôt que noyée dans le `redirect` de GoRouter : c'est la règle la plus lourde de conséquences du lot, elle doit être testable sans monter d'interface.

- [ ] **Step 1: Écrire le test qui échoue**

Créer `test/app/account_gate_test.dart` :

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_offroad/app/account_gate.dart';
import 'package:moto_offroad/providers/account_provider.dart';

void main() {
  String? gate(AccountStatus s, String loc, {bool grace = false}) =>
      accountRedirect(status: s, location: loc, graceActive: grace);

  test('pendant le chargement rien ne bouge', () {
    expect(gate(AccountStatus.chargement, '/'), isNull);
  });

  test('un rider deconnecte est renvoye a l accueil du compte', () {
    expect(gate(AccountStatus.deconnecte, '/'), '/bienvenue');
  });

  test('un rider deconnecte peut atteindre les ecrans de compte', () {
    expect(gate(AccountStatus.deconnecte, '/bienvenue'), isNull);
    expect(gate(AccountStatus.deconnecte, '/inscription'), isNull);
    expect(gate(AccountStatus.deconnecte, '/connexion'), isNull);
  });

  test('un compte non verifie est retenu sur l ecran d attente', () {
    expect(gate(AccountStatus.nonVerifie, '/'), '/verification');
    expect(gate(AccountStatus.nonVerifie, '/verification'), isNull);
  });

  test('un rider connecte ne voit plus les ecrans de compte', () {
    expect(gate(AccountStatus.connecte, '/bienvenue'), '/');
    expect(gate(AccountStatus.connecte, '/verification'), '/');
    expect(gate(AccountStatus.connecte, '/'), isNull);
  });

  test('le delai de grace laisse passer un rider sans compte', () {
    expect(gate(AccountStatus.deconnecte, '/', grace: true), isNull);
    expect(gate(AccountStatus.deconnecte, '/rides', grace: true), isNull);
  });

  test('le delai de grace ne s applique pas a un compte non verifie', () {
    expect(gate(AccountStatus.nonVerifie, '/', grace: true), '/verification');
  });
}
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

Run: `flutter test test/app/account_gate_test.dart`
Expected: FAIL — fichier introuvable.

- [ ] **Step 3: Implémenter**

Créer `lib/app/account_gate.dart` :

```dart
import '../providers/account_provider.dart';

/// Chemins accessibles sans compte : les écrans du compte lui-même.
const Set<String> accountRoutes = {'/bienvenue', '/inscription', '/connexion', '/mot-de-passe-oublie'};
const String verificationRoute = '/verification';

/// Règle d'accès à l'application. Fonction pure : c'est la décision la plus
/// lourde de conséquences du lot, elle se teste sans monter d'interface.
///
/// [graceActive] n'est vrai que pour une installation antérieure aux comptes,
/// et seulement pendant ses trente premiers jours — voir `GraceWindow`.
String? accountRedirect({
  required AccountStatus status,
  required String location,
  required bool graceActive,
}) {
  final surEcranDeCompte = accountRoutes.contains(location);

  switch (status) {
    case AccountStatus.chargement:
      return null;

    case AccountStatus.deconnecte:
      if (surEcranDeCompte) return null;
      if (graceActive) return null;
      return '/bienvenue';

    case AccountStatus.nonVerifie:
      // Le délai de grâce ne s'applique pas ici : un compte a été créé, son
      // adresse doit être confirmée.
      return location == verificationRoute ? null : verificationRoute;

    case AccountStatus.connecte:
      if (surEcranDeCompte || location == verificationRoute) return '/';
      return null;
  }
}
```

- [ ] **Step 4: Lancer le test**

Run: `flutter test test/app/account_gate_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/app/account_gate.dart test/app/account_gate_test.dart
git commit -m "feat(compte): regle de redirection de la porte d'entree"
```

---

### Task 15: Délai de grâce des installations existantes

**Files:**
- Create: `lib/services/grace_window.dart`
- Test: `test/services/grace_window_test.dart`

**Interfaces:**
- Produit : `GraceWindow` avec `Future<void> evaluate({required bool hasLegacyData, DateTime? now})`, `bool get active`, `DateTime? get deadline`.

**Code temporaire.** Cette classe et ses appels doivent disparaître quand les installations d'avant les comptes auront quitté le parc. Le commentaire de tête porte cette condition de retrait.

- [ ] **Step 1: Écrire le test qui échoue**

Créer `test/services/grace_window_test.dart` :

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moto_offroad/services/grace_window.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('une installation neuve n a aucun delai', () async {
    final g = GraceWindow();
    await g.evaluate(hasLegacyData: false);
    expect(g.active, isFalse);
    expect(g.deadline, isNull);
  });

  test('une installation anterieure recoit trente jours', () async {
    final depart = DateTime(2026, 9, 8);
    final g = GraceWindow();
    await g.evaluate(hasLegacyData: true, now: depart);
    expect(g.active, isTrue);
    expect(g.deadline, DateTime(2026, 10, 8));
  });

  test('l echeance est conservee entre deux lancements', () async {
    final depart = DateTime(2026, 9, 8);
    await GraceWindow().evaluate(hasLegacyData: true, now: depart);

    final second = GraceWindow();
    await second.evaluate(hasLegacyData: true, now: depart.add(const Duration(days: 5)));
    expect(second.deadline, DateTime(2026, 10, 8), reason: 'l echeance ne se repousse pas a chaque lancement');
    expect(second.active, isTrue);
  });

  test('passe l echeance le delai est clos', () async {
    final depart = DateTime(2026, 9, 8);
    await GraceWindow().evaluate(hasLegacyData: true, now: depart);

    final apres = GraceWindow();
    await apres.evaluate(hasLegacyData: true, now: depart.add(const Duration(days: 31)));
    expect(apres.active, isFalse);
  });

  test('une installation neuve ne recoit pas de delai meme si le telephone en a deja eu un', () async {
    SharedPreferences.setMockInitialValues({});
    final g = GraceWindow();
    await g.evaluate(hasLegacyData: false, now: DateTime(2026, 9, 8));
    expect(g.active, isFalse);
  });
}
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

Run: `flutter test test/services/grace_window_test.dart`
Expected: FAIL — fichier introuvable.

- [ ] **Step 3: Implémenter**

Créer `lib/services/grace_window.dart` :

```dart
import 'package:shared_preferences/shared_preferences.dart';

/// CODE TEMPORAIRE — à supprimer quand les installations antérieures aux
/// comptes auront quitté le parc (versions < 1.7.0). Retirer alors cette
/// classe, son appel dans `main.dart` et le paramètre `graceActive` de
/// `accountRedirect`.
///
/// Un rider qui utilise l'application depuis des semaines ne doit pas trouver
/// un mur d'inscription au départ d'une sortie, sans avertissement. La version
/// qui introduit les comptes reconnaît son installation à ses données locales
/// et lui laisse trente jours.
class GraceWindow {
  static const String _kDeadline = 'account_grace_deadline_ms';
  static const Duration duration = Duration(days: 30);

  DateTime? _deadline;

  DateTime? get deadline => _deadline;

  bool get active {
    final echeance = _deadline;
    return echeance != null && DateTime.now().isBefore(echeance);
  }

  Future<void> evaluate({required bool hasLegacyData, DateTime? now}) async {
    final maintenant = now ?? DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    final stocke = prefs.getInt(_kDeadline);

    if (stocke != null) {
      _deadline = DateTime.fromMillisecondsSinceEpoch(stocke);
    } else if (hasLegacyData) {
      _deadline = maintenant.add(duration);
      await prefs.setInt(_kDeadline, _deadline!.millisecondsSinceEpoch);
    } else {
      _deadline = null;
      return;
    }

    if (!maintenant.isBefore(_deadline!)) _deadline = null;
  }
}

/// Instance unique, évaluée une fois dans `main.dart` et lue par le
/// `redirect` du routeur. Elle disparaît avec le reste du code temporaire.
final GraceWindow graceWindow = GraceWindow();
```

Le test s'appuie sur `DateTime.now()` dans `active` ; pour que les cas horodatés restent déterministes, `evaluate` clôt lui-même le délai quand `now` l'a dépassé, et `active` ne fait que confirmer.

- [ ] **Step 4: Lancer le test**

Run: `flutter test test/services/grace_window_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/grace_window.dart test/services/grace_window_test.dart
git commit -m "feat(compte): delai de grace de trente jours pour les installations existantes"
```

---

### Task 16: Écrans du compte et branchement du routeur

**Files:**
- Create: `lib/screens/account/welcome_screen.dart`, `lib/screens/account/register_screen.dart`, `lib/screens/account/login_screen.dart`, `lib/screens/account/verify_screen.dart`, `lib/screens/account/forgot_password_screen.dart`
- Modify: `lib/app/router.dart`, `lib/main.dart`
- Test: `test/screens/account_screens_test.dart`

**Interfaces:**
- Consomme : `AccountProvider` (tâche 13), `accountRedirect` (tâche 14), `GraceWindow` (tâche 15).
- Produit : les routes `AppRoutes.welcome = '/bienvenue'`, `register = '/inscription'`, `login = '/connexion'`, `verify = '/verification'`, `forgotPassword = '/mot-de-passe-oublie'`.

**Détection des données antérieures**, dans `main.dart` : présence de la base des sorties (`RideDatabase`) ou d'une préférence connue (`rider_name`, `skill_level`).

- [ ] **Step 1: Écrire le test qui échoue**

Créer `test/screens/account_screens_test.dart` :

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';
import 'package:moto_offroad/providers/account_provider.dart';
import 'package:moto_offroad/services/account_api_client.dart';
import 'package:moto_offroad/screens/account/register_screen.dart';
import 'package:moto_offroad/screens/account/verify_screen.dart';

Widget monter(Widget enfant, AccountProvider p) => ChangeNotifierProvider.value(
      value: p,
      child: MaterialApp(home: enfant),
    );

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('l inscription refuse un mot de passe trop court sans appeler le serveur', (tester) async {
    var appels = 0;
    final p = AccountProvider(
      api: AccountApiClient(baseUrl: 'https://exemple.test', client: MockClient((_) async {
        appels++;
        return http.Response('{}', 201);
      })),
    );
    await tester.pumpWidget(monter(const RegisterScreen(), p));

    await tester.enterText(find.byKey(const Key('champ-email')), 'rider@example.test');
    await tester.enterText(find.byKey(const Key('champ-mot-de-passe')), 'court');
    await tester.tap(find.byKey(const Key('bouton-inscription')));
    await tester.pump();

    expect(find.textContaining('10 caractères'), findsOneWidget);
    expect(appels, 0);
  });

  testWidgets('l ecran d attente propose de renvoyer et de corriger l adresse', (tester) async {
    final p = AccountProvider(
      api: AccountApiClient(baseUrl: 'https://exemple.test', client: MockClient((_) async =>
          http.Response(jsonEncode({'email': 'rider@example.test', 'verified': false}), 200))),
    );
    await tester.pumpWidget(monter(const VerifyScreen(), p));
    await tester.pump();

    expect(find.byKey(const Key('bouton-jai-confirme')), findsOneWidget);
    expect(find.byKey(const Key('bouton-renvoyer')), findsOneWidget);
    expect(find.byKey(const Key('bouton-corriger-adresse')), findsOneWidget);
  });

  testWidgets('une panne reseau affiche un message explicite', (tester) async {
    final p = AccountProvider(
      api: AccountApiClient(baseUrl: 'https://exemple.test',
          client: MockClient((_) async => throw Exception('reseau coupe'))),
    );
    await tester.pumpWidget(monter(const RegisterScreen(), p));

    await tester.enterText(find.byKey(const Key('champ-email')), 'rider@example.test');
    await tester.enterText(find.byKey(const Key('champ-mot-de-passe')), 'dix caracteres');
    await tester.tap(find.byKey(const Key('bouton-inscription')));
    await tester.pumpAndSettle();

    expect(find.textContaining('connexion internet'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

Run: `flutter test test/screens/account_screens_test.dart`
Expected: FAIL — écrans introuvables.

- [ ] **Step 3: Implémenter**

Créer les quatre écrans. `register_screen.dart` (les autres suivent le même moule ; `welcome_screen.dart` n'a que deux boutons vers `/inscription` et `/connexion`) :

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/account_provider.dart';
import '../../services/account_api_client.dart';

const int kMinPasswordLength = 10;

String messagePour(AccountError erreur) {
  switch (erreur) {
    case AccountError.reseau:
      return 'Une connexion internet est nécessaire pour créer ton compte. Réessaie.';
    case AccountError.adresseDejaPrise:
      return 'Cette adresse est déjà inscrite. Connecte-toi.';
    case AccountError.motDePasseTropCourt:
      return 'Mot de passe de $kMinPasswordLength caractères minimum.';
    case AccountError.adresseInvalide:
      return 'Cette adresse ne semble pas valide.';
    case AccountError.identifiants:
      return 'Adresse ou mot de passe incorrect.';
    case AccountError.tropDeTentatives:
      return 'Trop de tentatives. Patiente quelques minutes.';
    case AccountError.inconnue:
      return 'Une erreur est survenue. Réessaie.';
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _email = TextEditingController();
  final _motDePasse = TextEditingController();
  final _prenom = TextEditingController();
  String? _erreur;
  bool _enCours = false;

  @override
  void dispose() {
    _email.dispose();
    _motDePasse.dispose();
    _prenom.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    if (_motDePasse.text.length < kMinPasswordLength) {
      setState(() => _erreur = 'Mot de passe de $kMinPasswordLength caractères minimum.');
      return;
    }
    setState(() { _erreur = null; _enCours = true; });

    final compte = context.read<AccountProvider>();
    final ok = await compte.register(
      email: _email.text.trim(),
      password: _motDePasse.text,
      displayName: _prenom.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _enCours = false;
      _erreur = ok ? null : messagePour(compte.lastError ?? AccountError.inconnue);
    });
    if (ok) context.go('/verification');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Créer un compte')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(key: const Key('champ-email'), controller: _email,
            keyboardType: TextInputType.emailAddress, autocorrect: false,
            decoration: const InputDecoration(labelText: 'Adresse e-mail')),
          const SizedBox(height: 12),
          TextField(key: const Key('champ-mot-de-passe'), controller: _motDePasse, obscureText: true,
            decoration: const InputDecoration(labelText: 'Mot de passe ($kMinPasswordLength caractères minimum)')),
          const SizedBox(height: 12),
          TextField(key: const Key('champ-prenom'), controller: _prenom,
            decoration: const InputDecoration(labelText: 'Prénom')),
          if (_erreur != null) ...[
            const SizedBox(height: 16),
            Text(_erreur!, style: const TextStyle(color: Colors.redAccent)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('bouton-inscription'),
            onPressed: _enCours ? null : _valider,
            child: Text(_enCours ? 'Création…' : 'Créer mon compte'),
          ),
        ],
      ),
    );
  }
}
```

`forgot_password_screen.dart` est le plus simple : un champ d'adresse, un bouton, et **toujours le même message de retour** — « Si un compte existe pour cette adresse, le lien vient de partir. » Afficher « adresse inconnue » ici annulerait l'anti-énumération que le serveur applique dans `POST /password/forgot`.

`verify_screen.dart` porte les trois issues et l'interrogation périodique :

```dart
class _VerifyScreenState extends State<VerifyScreen> {
  Timer? _sondage;

  @override
  void initState() {
    super.initState();
    // Le rider peut confirmer depuis son ordinateur : l'application s'en
    // aperçoit seule, il n'a rien à toucher.
    _sondage = Timer.periodic(const Duration(seconds: 5), (_) async {
      final ok = await context.read<AccountProvider>().refreshVerification();
      if (ok && mounted) context.go('/');
    });
  }

  @override
  void dispose() {
    _sondage?.cancel();
    super.dispose();
  }
  // … boutons Key('bouton-jai-confirme'), Key('bouton-renvoyer'),
  //   Key('bouton-corriger-adresse')
}
```

Dans `lib/app/router.dart` : ajouter les cinq constantes à `AppRoutes`, les `GoRoute` correspondantes **hors** du `ShellRoute` (ces écrans n'ont pas la barre de navigation), et le `redirect` :

```dart
  refreshListenable: accountGateListenable,
  redirect: (context, state) => accountRedirect(
    status: context.read<AccountProvider>().status,
    location: state.matchedLocation,
    graceActive: graceWindow.active,
  ),
```

où `accountGateListenable` est le `AccountProvider` lui-même et `graceWindow` l'instance évaluée dans `main.dart`.

Dans `lib/main.dart`, avant `runApp` :

```dart
  // CODE TEMPORAIRE (voir GraceWindow) : reconnaît une installation
  // antérieure aux comptes à ses données locales.
  final prefs = await SharedPreferences.getInstance();
  final aDesDonneesAnterieures =
      prefs.containsKey('rider_name') || prefs.containsKey('skill_level') || await RideDatabase.exists();
  await graceWindow.evaluate(hasLegacyData: aDesDonneesAnterieures);
```

- [ ] **Step 4: Lancer les tests**

Run: `flutter test`
Expected: PASS, y compris `smoke_test.dart` — s'il monte l'application entière, il faut lui fournir un `AccountProvider` déjà connecté.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/account lib/app/router.dart lib/main.dart test/screens/account_screens_test.dart
git commit -m "feat(compte): ecrans d'inscription, de connexion et d'attente de verification"
```

---

### Task 17: Tutoriel de première ouverture

**Files:**
- Create: `lib/services/tutorial_steps.dart`, `lib/services/tutorial_controller.dart`, `lib/widgets/tutorial_overlay.dart`
- Modify: `lib/screens/map/map_screen.dart`
- Test: `test/services/tutorial_controller_test.dart`, `test/widgets/tutorial_overlay_test.dart`

**Interfaces:**
- Produit :
  - `class TutorialStep { final String title; final String body; final GlobalKey? target; }`
  - `List<TutorialStep> buildTutorialSteps(TutorialTargets targets)`
  - `class TutorialTargets { final GlobalKey modeSwitch, sos, recording, actions, layers; }`
  - `class TutorialController extends ChangeNotifier` : `bool get visible`, `int get index`, `int get total`, `TutorialStep get current`, `Future<void> startIfNeeded()`, `void next()`, `void previous()`, `Future<void> skip()`, `Future<void> replay()`.
  - `class TutorialOverlay extends StatelessWidget`.

Transposition du tutoriel de `dashboard.html` (projet DRONE 31) : voile, projecteur sur l'élément réel, carte « ÉTAPE n / 6 », pastilles, *Passer / Préc. / Suivant / Terminer*. Aucune dépendance nouvelle : `Stack` et `CustomPaint` suffisent.

- [ ] **Step 1: Écrire les tests qui échouent**

Créer `test/services/tutorial_controller_test.dart` :

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moto_offroad/services/tutorial_controller.dart';
import 'package:moto_offroad/services/tutorial_steps.dart';

TutorialTargets cibles() => TutorialTargets(
      modeSwitch: GlobalKey(), sos: GlobalKey(), recording: GlobalKey(),
      actions: GlobalKey(), layers: GlobalKey(),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('le tutoriel compte six etapes', () {
    expect(buildTutorialSteps(cibles()).length, 6);
  });

  test('la premiere etape n a pas de cible', () {
    expect(buildTutorialSteps(cibles()).first.target, isNull);
  });

  test('il se declenche la premiere fois et pas la seconde', () async {
    final premier = TutorialController(targets: cibles());
    await premier.startIfNeeded();
    expect(premier.visible, isTrue);
    await premier.skip();
    expect(premier.visible, isFalse);

    final second = TutorialController(targets: cibles());
    await second.startIfNeeded();
    expect(second.visible, isFalse, reason: 'un tutoriel deja vu ne revient pas');
  });

  test('la navigation avance, recule et se termine', () async {
    final c = TutorialController(targets: cibles());
    await c.startIfNeeded();
    expect(c.index, 0);
    c.next();
    expect(c.index, 1);
    c.previous();
    expect(c.index, 0);
    for (var i = 0; i < 10; i++) {
      c.next();
    }
    expect(c.visible, isFalse, reason: 'passe la derniere etape le tutoriel se ferme');
  });

  test('il est rejouable depuis les reglages', () async {
    final c = TutorialController(targets: cibles());
    await c.startIfNeeded();
    await c.skip();
    await c.replay();
    expect(c.visible, isTrue);
    expect(c.index, 0);
  });
}
```

Créer `test/widgets/tutorial_overlay_test.dart` :

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moto_offroad/services/tutorial_controller.dart';
import 'package:moto_offroad/services/tutorial_steps.dart';
import 'package:moto_offroad/widgets/tutorial_overlay.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('la carte affiche le numero d etape et avance au clic', (tester) async {
    final c = TutorialController(targets: TutorialTargets(
      modeSwitch: GlobalKey(), sos: GlobalKey(), recording: GlobalKey(),
      actions: GlobalKey(), layers: GlobalKey(),
    ));
    await c.startIfNeeded();

    await tester.pumpWidget(MaterialApp(home: Stack(children: [TutorialOverlay(controller: c)])));
    expect(find.text('ÉTAPE 1 / 6'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tuto-suivant')));
    await tester.pump();
    expect(find.text('ÉTAPE 2 / 6'), findsOneWidget);
  });

  testWidgets('le bouton passer ferme le tutoriel', (tester) async {
    final c = TutorialController(targets: TutorialTargets(
      modeSwitch: GlobalKey(), sos: GlobalKey(), recording: GlobalKey(),
      actions: GlobalKey(), layers: GlobalKey(),
    ));
    await c.startIfNeeded();
    await tester.pumpWidget(MaterialApp(home: Stack(children: [TutorialOverlay(controller: c)])));

    await tester.tap(find.byKey(const Key('tuto-passer')));
    await tester.pumpAndSettle();
    expect(find.text('ÉTAPE 1 / 6'), findsNothing);
  });
}
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `flutter test test/services/tutorial_controller_test.dart test/widgets/tutorial_overlay_test.dart`
Expected: FAIL — fichiers introuvables.

- [ ] **Step 3: Implémenter**

Créer `lib/services/tutorial_steps.dart` :

```dart
import 'package:flutter/widgets.dart';

class TutorialStep {
  final String title;
  final String body;
  final GlobalKey? target;
  const TutorialStep({required this.title, required this.body, this.target});
}

class TutorialTargets {
  const TutorialTargets({
    required this.modeSwitch,
    required this.sos,
    required this.recording,
    required this.actions,
    required this.layers,
  });
  final GlobalKey modeSwitch;
  final GlobalKey sos;
  final GlobalKey recording;
  final GlobalKey actions;
  final GlobalKey layers;
}

/// Six étapes, sur le modèle du tutoriel du tableau de bord de streaming :
/// une par fonction que le rider doit connaître avant sa première sortie.
List<TutorialStep> buildTutorialSteps(TutorialTargets t) => [
      const TutorialStep(
        title: 'Bienvenue sur MOTO OFFROAD',
        body: 'Ce tutoriel te montre les six fonctions essentielles en moins de deux minutes. '
            'Tu pourras le revoir à tout moment depuis les réglages.',
      ),
      TutorialStep(
        title: 'Solo ou Groupe',
        body: 'En Solo, une personne de confiance suit ton trajet en direct et sera prévenue si tu ne donnes plus signe de vie. '
            'En Groupe, tu vois tes coéquipiers sur la carte et tu peux fixer un point de ralliement.',
        target: t.modeSwitch,
      ),
      TutorialStep(
        title: 'SOS et détection de chute',
        body: 'Ce bouton appelle les secours et prévient tes contacts avec ta position. '
            'La détection de chute agit seule : après un choc, un compte à rebours démarre, et sans réaction de ta part l’alerte part.',
        target: t.sos,
      ),
      TutorialStep(
        title: 'Enregistrer ta sortie',
        body: 'Distance, durée, dénivelé et trace complète, même écran éteint. '
            'La sortie se retrouve ensuite dans l’onglet Sorties, et s’exporte en GPX.',
        target: t.recording,
      ),
      TutorialStep(
        title: 'Le menu d’actions',
        body: 'Itinéraire vers une destination, recherche de points d’intérêt — carburant, bivouac, réparateur — et météo du secteur.',
        target: t.actions,
      ),
      TutorialStep(
        title: 'Fonds de carte et hors ligne',
        body: 'Choisis ton fond de carte, et télécharge une zone avant de partir : '
            'sans réseau sur le terrain, seules les tuiles déjà téléchargées s’afficheront.',
        target: t.layers,
      ),
    ];
```

Créer `lib/services/tutorial_controller.dart` :

```dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'tutorial_steps.dart';

class TutorialController extends ChangeNotifier {
  TutorialController({required TutorialTargets targets}) : _steps = buildTutorialSteps(targets);

  static const String _kDone = 'tutorial_done';

  final List<TutorialStep> _steps;
  bool _visible = false;
  int _index = 0;

  bool get visible => _visible;
  int get index => _index;
  int get total => _steps.length;
  TutorialStep get current => _steps[_index];

  Future<void> startIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kDone) ?? false) return;
    _index = 0;
    _visible = true;
    notifyListeners();
  }

  void next() {
    if (_index >= _steps.length - 1) {
      _close();
      return;
    }
    _index++;
    notifyListeners();
  }

  void previous() {
    if (_index == 0) return;
    _index--;
    notifyListeners();
  }

  Future<void> skip() async => _close();

  Future<void> replay() async {
    _index = 0;
    _visible = true;
    notifyListeners();
  }

  Future<void> _close() async {
    _visible = false;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDone, true);
  }
}
```

Créer `lib/widgets/tutorial_overlay.dart` : un `AnimatedBuilder` sur le contrôleur qui, si `visible`, empile

1. un voile `Container(color: Colors.black.withOpacity(0.84))` couvrant l'écran ;
2. un `CustomPaint` qui perce un rectangle arrondi à l'emplacement de la cible, calculé depuis `target.currentContext!.findRenderObject()` — si la cible est absente ou hors écran, aucun trou n'est percé et l'étape reste lisible ;
3. la carte d'explication : `Text('ÉTAPE ${index + 1} / $total')`, le titre, le corps, une rangée de pastilles, et les boutons `Key('tuto-passer')`, `Key('tuto-precedent')`, `Key('tuto-suivant')` — ce dernier affichant « Terminer ✓ » à la dernière étape.

Sur téléphone, la carte est ancrée en bas (`bottom: 16, left: 12, right: 12`) avec `maxHeight: MediaQuery.of(context).size.height - 32` et un défilement interne : la leçon déjà apprise sur le tableau de bord, pour que le pied de la carte reste atteignable.

Dans `lib/screens/map/map_screen.dart` : déclarer les cinq `GlobalKey` en champs d'état, les poser sur `ModeSwitchWidget` (ligne 716), le bouton des calques (ligne 721), `RadialActionMenu` (ligne 769), `SosButton` (ligne 1550) et `RecordingPanel` (ligne 1552), puis ajouter `TutorialOverlay(controller: _tutorial)` en dernier enfant du `Stack` principal, et appeler `_tutorial.startIfNeeded()` dans `initState`.

- [ ] **Step 4: Lancer les tests**

Run: `flutter test`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/tutorial_steps.dart lib/services/tutorial_controller.dart lib/widgets/tutorial_overlay.dart lib/screens/map/map_screen.dart test/services/tutorial_controller_test.dart test/widgets/tutorial_overlay_test.dart
git commit -m "feat(tutoriel): six etapes de premiere ouverture, transposees du tableau de bord"
```

---

### Task 18: Écran « Mon compte », entrées de réglages et livraison

**Files:**
- Create: `lib/screens/account/account_screen.dart`
- Modify: `lib/screens/settings/settings_screen.dart`, `lib/app/router.dart`, `pubspec.yaml`
- Test: `test/screens/account_screen_test.dart`

**Interfaces:**
- Consomme : `AccountProvider` (tâche 13), `TutorialController` (tâche 17).
- Produit : route `AppRoutes.account = '/mon-compte'`.

- [ ] **Step 1: Écrire le test qui échoue**

```dart
testWidgets('la suppression de compte demande confirmation avant d agir', (tester) async {
  var suppressionAppelee = false;
  final p = AccountProvider(
    api: AccountApiClient(baseUrl: 'https://exemple.test', client: MockClient((req) async {
      if (req.method == 'DELETE') suppressionAppelee = true;
      return http.Response('{}', 200);
    })),
  );
  await p.register(email: 'rider@example.test', password: 'dix caracteres');

  await tester.pumpWidget(ChangeNotifierProvider.value(value: p, child: const MaterialApp(home: AccountScreen())));
  await tester.tap(find.byKey(const Key('bouton-supprimer-compte')));
  await tester.pumpAndSettle();

  expect(suppressionAppelee, isFalse, reason: 'aucune suppression sans confirmation');
  expect(find.textContaining('définitive'), findsOneWidget);

  await tester.tap(find.byKey(const Key('bouton-confirmer-suppression')));
  await tester.pumpAndSettle();
  expect(suppressionAppelee, isTrue);
});
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

Run: `flutter test test/screens/account_screen_test.dart`
Expected: FAIL — écran introuvable.

- [ ] **Step 3: Implémenter**

`lib/screens/account/account_screen.dart` affiche l'adresse du rider, son prénom, et trois actions :

- **Se déconnecter** — appelle `AccountProvider.logout()`.
- **Supprimer mon compte** (`Key('bouton-supprimer-compte')`) — ouvre un `AlertDialog` dont le texte annonce que l'opération est **définitive** et le bouton de confirmation porte `Key('bouton-confirmer-suppression')`. Cette suppression est exigée par les règles de l'App Store, et par le RGPD.
- **Revoir le tutoriel** — appelle `TutorialController.replay()` puis revient sur la carte.

Dans `settings_screen.dart`, ajouter une section « Compte » en tête, avec l'adresse du rider et l'accès à `/mon-compte`.

Dans `pubspec.yaml`, porter la version à `1.7.0+22`.

- [ ] **Step 4: Vérification complète**

```bash
flutter analyze
dart format --set-exit-if-changed lib test
flutter test
```

Expected: aucune erreur d'analyse, format inchangé, tous les tests au vert.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(compte): ecran Mon compte, entrees de reglages et version 1.7.0"
```

- [ ] **Step 6: Livraison**

Le serveur doit déjà être déployé (tâche 10). Puis :

```bash
git push origin main
gh workflow run testflight.yml --ref main
```

Le build Android part seul au `push` si la version a changé. Vérifier ensuite sur un appareil réel :

1. Installer par-dessus une version antérieure → la carte s'ouvre, le bandeau du délai de grâce annonce l'échéance, **et le tutoriel se déclenche**.
2. Désinstaller puis réinstaller → le mur d'inscription apparaît, sans délai.
3. Créer un compte avec une adresse erronée → corriger depuis l'écran d'attente, l'e-mail repart à la bonne adresse.
4. Confirmer depuis un ordinateur → l'application ouvre la carte seule, sans geste sur le téléphone.
5. Passer en mode avion en pleine sortie → aucun écran de connexion n'apparaît, carte, GPS et SOS restent accessibles.

---

## Revue du plan

**Couverture de la spec.** Chapitre 4 (modèle de données) → tâche 1. Chapitre 5 (interface HTTP) → tâches 4 à 7. Chapitre 6 (sécurité) → tâches 2, 5, 6, 8. Chapitre 7 (parcours) → tâches 11 à 14 et 16. Chapitre 7.1 (tutoriel) → tâche 17. Chapitre 7.2 (délai de grâce) → tâches 15 et 16. Chapitre 8 (migration) → tâche 4, avec l'absence délibérée de rattachement de `member` et `alert_contact`. Chapitre 9 (exploitation) → tâche 9. Chapitre 10 (tests) → réparti sur toutes les tâches. Chapitre 12 : critères 1 à 3 → tâche 14 ; 4 → tâche 13 ; 5 → tâches 5 et 16 ; 6 → tâches 5 et 6 ; 7 → tâche 7 ; 8 → tâche 9 ; 9 à 11 → tâche 15 ; 12 et 13 → tâches 17 et 18.

**Deux écarts assumés, tous deux argumentés à l'endroit où ils se produisent :**

1. `POST /register` répond 409 sur une adresse déjà prise, alors que `login` et `forgot` ne disent jamais qui est inscrit (tâche 4).
2. Le test de correction d'adresse écrit en tâche 4 reste rouge jusqu'à la tâche 5, qui apporte l'authentification dont il dépend.

**Un point à surveiller à l'exécution :** `test/smoke_test.dart` monte l'application entière. La porte d'entrée de la tâche 14 le fera échouer tant qu'il ne fournit pas un `AccountProvider` déjà connecté. C'est signalé à l'étape 4 de la tâche 16.
