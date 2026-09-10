# Lot B — catalogue de traces partagées : plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** permettre à un rider de publier une de ses sorties dans un catalogue public, et aux autres de la trouver par distance et de la télécharger dans leurs propres sorties, avec compteur, signalement et modération a posteriori.

**Architecture:** le serveur Node/Express existant reçoit un routeur `/api/traces` ; les fiches vont en SQLite, les fichiers GPX sur le disque du volume de données. L'application gagne un second volet dans l'onglet Sorties (liste triée par distance depuis un point de référence) et un écran de publication avec recadrage. Le client HTTP existant se met enfin à porter le jeton de compte, ce qui solde la dette d'identité du lot A.

**Tech Stack:** Node 18 + Express 4 + better-sqlite3 + `fast-xml-parser` (nouvelle dépendance, JavaScript pur) côté serveur, tests `node:test` dans Docker. Flutter 3.44 / Dart 3.12 + provider + http + sqflite + flutter_map côté application, tests `flutter test`.

**Spec:** `docs/superpowers/specs/2026-09-09-lotB-partage-traces-design.md`

## Global Constraints

- Deux dépôts : serveur `~/Claude/Projects/APP OFFROAD MOTO 4X4/moto-tracker-server`, application `~/Claude/Projects/APP OFFROAD MOTO 4X4/moto_offroad`. Chaque tâche dit dans lequel elle travaille. Un commit ne mélange jamais les deux.
- **Les tests serveur tournent dans Docker**, jamais directement sur ce Mac : `better-sqlite3` est un addon natif et les outils de compilation du poste sont hors service. Commande de référence, depuis le dépôt serveur :
  `docker run --rm -v "$PWD":/app -w /app node:20 sh -c "npm install && npm test"`
- Tests application : `flutter test` depuis le dépôt de l'app. `flutter analyze` doit rester propre, à l'exception connue de `lib/config/firebase_options.dart` (gitignoré, obsolète, sans rapport).
- Code et commentaires en français, accents compris, comme le reste des deux dépôts. Messages de commit en français, sans accent (convention des dépôts).
- Valeurs exactes reprises de la spec, à ne pas réinventer : engin `moto` / `4x4` / `mixte` ; difficulté `facile` / `moyen` / `difficile` ; motif de signalement `terrain_prive` / `dangereux` / `doublon` / `inapproprie` / `autre` ; rayon par défaut 50 km, maximum 300 km ; GPX 5 Mo et 50 000 points maximum ; 10 publications par compte et par jour ; corps JSON de la seule route de publication porté à 6 Mo.
- Une trace masquée n'apparaît jamais dans `GET /api/traces` ni dans `GET /api/traces/:id`, y compris pour son auteur.
- `account_id` n'est jamais renvoyé à un client, quelle que soit la route publique.
- Les aides de test (`buildApp`, `listen`, `creerCompte`, `_ApiFactice`, `resume`…) ne sont pas partagées entre fichiers de test : chaque fichier recopie celles dont il a besoin. C'est la convention des deux dépôts, et elle garde chaque fichier lisible seul.
- Chaque commit termine par les deux lignes d'attribution utilisées dans ce projet :
  `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>` puis
  `Claude-Session: https://claude.ai/code/session_01DucWhoeRSQ1DZWn8jT3fdg`

---

# Partie 1 — Serveur

### Task 1: Extraire l'authentification de compte dans son propre module

**Files:**
- Create: `src/accounts/auth.js`
- Modify: `src/routes/account.js` (retirer `authenticate`, `requireVerified`, `hashToken` de ce fichier et les importer)
- Test: `test/auth.test.js`

**Interfaces:**
- Consumes: rien.
- Produces: `authenticate(db, now)` → middleware Express qui pose `req.account` (`{ id, email, display_name, verified_at }`) et `req.sessionTokenHash`, répond `401 { error: 'authentification requise' }` sinon ; `requireVerified(req, res, next)` qui répond `403 { error: 'adresse non verifiee' }` si `req.account.verified_at` est nul ; `hashToken(token)` → SHA-256 hexadécimal ; `SESSION_TTL_MS`.

- [ ] **Step 1: Écrire le test qui échoue**

`test/auth.test.js` :

```js
const test = require('node:test');
const assert = require('node:assert/strict');
const { authenticate, requireVerified, hashToken } = require('../src/accounts/auth');
const { openDb } = require('../src/db');

function reponseFactice() {
  return {
    code: null, corps: null,
    status(c) { this.code = c; return this; },
    json(b) { this.corps = b; return this; },
  };
}

test('authenticate refuse une requete sans en-tete', () => {
  const db = openDb(':memory:');
  const res = reponseFactice();
  let suivantAppele = false;
  authenticate(db, () => 1000)({ get: () => '' }, res, () => { suivantAppele = true; });
  assert.equal(suivantAppele, false);
  assert.equal(res.code, 401);
});

test('requireVerified laisse passer un compte verifie', () => {
  const res = reponseFactice();
  let suivantAppele = false;
  requireVerified({ account: { verified_at: 42 } }, res, () => { suivantAppele = true; });
  assert.equal(suivantAppele, true);
});

test('hashToken rend une empreinte hexadecimale stable', () => {
  assert.equal(hashToken('a'), hashToken('a'));
  assert.match(hashToken('a'), /^[0-9a-f]{64}$/);
});
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

Depuis le dépôt serveur :
`docker run --rm -v "$PWD":/app -w /app node:20 sh -c "npm install && npm test"`
Attendu : ÉCHEC, `Cannot find module '../src/accounts/auth'`.

- [ ] **Step 3: Créer le module**

Déplacer sans les modifier, depuis `src/routes/account.js` vers `src/accounts/auth.js` : `hashToken`, `SESSION_TTL_MS`, `authenticate`, `requireVerified`, avec leurs commentaires. Terminer par :

```js
module.exports = { authenticate, requireVerified, hashToken, SESSION_TTL_MS };
```

Dans `src/routes/account.js`, remplacer les définitions par :

```js
const { authenticate, requireVerified, hashToken, SESSION_TTL_MS } = require('../accounts/auth');
```

et conserver ces symboles dans le `module.exports` existant du fichier, pour ne casser aucun test déjà écrit.

- [ ] **Step 4: Lancer toute la suite**

`docker run --rm -v "$PWD":/app -w /app node:20 sh -c "npm install && npm test"`
Attendu : SUCCÈS, y compris les tests de compte déjà présents (`test/account.test.js`), sans aucune modification de ceux-ci.

- [ ] **Step 5: Commit**

```bash
git add src/accounts/auth.js src/routes/account.js test/auth.test.js
git commit -m "refactor(comptes): l authentification sort du routeur de compte"
```

---

### Task 2: Schéma des traces partagées

**Files:**
- Modify: `src/db.js` (constante `SCHEMA`)
- Test: `test/db.test.js`

**Interfaces:**
- Consumes: rien.
- Produces: tables `shared_trace`, `trace_report`, `trace_download` et leurs index, créées par `openDb(path)`.

- [ ] **Step 1: Écrire le test qui échoue**

Ajouter à `test/db.test.js` :

```js
test('le schema cree les tables du partage de traces', () => {
  const db = openDb(':memory:');
  const tables = db.prepare("SELECT name FROM sqlite_master WHERE type='table'").all().map((r) => r.name);
  assert.ok(tables.includes('shared_trace'));
  assert.ok(tables.includes('trace_report'));
  assert.ok(tables.includes('trace_download'));
});

test('un engin hors liste est refuse', () => {
  const db = openDb(':memory:');
  db.prepare("INSERT INTO account (id, email, password_hash, created_at) VALUES ('c1','a@b.test','x',1)").run();
  const inserer = (engin) => db.prepare(`
    INSERT INTO shared_trace (id, account_id, author_name, name, description, vehicle, difficulty,
      start_lat, start_lng, distance_m, point_count, gpx_bytes, gpx_sha256, published_at, updated_at)
    VALUES ('t1','c1','Marco','Boucle','Desc',?,'moyen',43.6,1.44,12000,300,4096,'abc',1,1)`).run(engin);
  assert.throws(() => inserer('quad'));
  inserer('moto');
});

test('un meme rider ne compte qu une fois dans trace_download', () => {
  const db = openDb(':memory:');
  db.prepare("INSERT INTO account (id, email, password_hash, created_at) VALUES ('c1','a@b.test','x',1)").run();
  db.prepare(`INSERT INTO shared_trace (id, account_id, author_name, name, description, vehicle, difficulty,
      start_lat, start_lng, distance_m, point_count, gpx_bytes, gpx_sha256, published_at, updated_at)
    VALUES ('t1','c1','Marco','Boucle','Desc','moto','moyen',43.6,1.44,12000,300,4096,'abc',1,1)`).run();
  const inserer = db.prepare('INSERT OR IGNORE INTO trace_download (trace_id, account_id, downloaded_at) VALUES (?,?,?)');
  assert.equal(inserer.run('t1', 'c1', 1).changes, 1);
  assert.equal(inserer.run('t1', 'c1', 2).changes, 0);
});
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

`docker run --rm -v "$PWD":/app -w /app node:20 sh -c "npm install && npm test"`
Attendu : ÉCHEC, `no such table: shared_trace`.

- [ ] **Step 3: Ajouter les tables au schéma**

Coller les trois `CREATE TABLE` et les quatre `CREATE INDEX` de la section 4 de la spec à la fin de la constante `SCHEMA` de `src/db.js`, **sans rien modifier** aux tables existantes. Aucune migration à ajouter dans `migrate()` : `CREATE TABLE IF NOT EXISTS` suffit pour des tables neuves.

- [ ] **Step 4: Lancer les tests**

`docker run --rm -v "$PWD":/app -w /app node:20 sh -c "npm install && npm test"`
Attendu : SUCCÈS.

- [ ] **Step 5: Commit**

```bash
git add src/db.js test/db.test.js
git commit -m "feat(traces): schema des traces partagees, signalements et telechargements"
```

---

### Task 3: Lecteur de GPX côté serveur

**Files:**
- Create: `src/traces/gpx.js`
- Modify: `package.json` (dépendance `fast-xml-parser`)
- Test: `test/traces_gpx.test.js`

**Interfaces:**
- Consumes: rien.
- Produces: `parseGpx(xml)` → `{ points, startLat, startLng, distanceM, elevationGainM, durationS, pointCount }` où `points` est un tableau de `{ lat, lng, ele, time }` (`ele` et `time` valant `null` si absents) ; lève `GpxInvalide` (classe exportée, propriété `code` valant `'illisible'`, `'vide'` ou `'trop_de_points'`). `MAX_POINTS = 50000`.

- [ ] **Step 1: Écrire le test qui échoue**

`test/traces_gpx.test.js` :

```js
const test = require('node:test');
const assert = require('node:assert/strict');
const { parseGpx, GpxInvalide } = require('../src/traces/gpx');

const GPX = `<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1"><trk><name>Boucle</name><trkseg>
<trkpt lat="43.6000" lon="1.4400"><ele>150</ele><time>2026-09-01T08:00:00Z</time></trkpt>
<trkpt lat="43.6090" lon="1.4400"><ele>180</ele><time>2026-09-01T08:10:00Z</time></trkpt>
<trkpt lat="43.6180" lon="1.4400"><ele>160</ele><time>2026-09-01T08:20:00Z</time></trkpt>
</trkseg></trk></gpx>`;

test('parseGpx rend le point de depart et les statistiques', () => {
  const t = parseGpx(GPX);
  assert.equal(t.pointCount, 3);
  assert.equal(t.startLat, 43.6);
  assert.equal(t.startLng, 1.44);
  // deux fois ~1 km a cette latitude, a 5 % pres
  assert.ok(t.distanceM > 1900 && t.distanceM < 2100, `distance inattendue: ${t.distanceM}`);
  assert.equal(t.elevationGainM, 30); // seules les montees comptent
  assert.equal(t.durationS, 1200);
});

test('parseGpx refuse un fichier illisible', () => {
  assert.throws(() => parseGpx('ceci n est pas du xml <<<'), (e) => e instanceof GpxInvalide && e.code === 'illisible');
});

test('parseGpx refuse une trace de moins de deux points', () => {
  const seul = GPX.replace(/<trkpt lat="43.6090".*?<\/trkpt>/s, '').replace(/<trkpt lat="43.6180".*?<\/trkpt>/s, '');
  assert.throws(() => parseGpx(seul), (e) => e instanceof GpxInvalide && e.code === 'vide');
});

test('parseGpx tolere l absence d altitude et d horodatage', () => {
  const nu = `<gpx><trk><trkseg>
    <trkpt lat="43.60" lon="1.44"></trkpt><trkpt lat="43.61" lon="1.44"></trkpt>
  </trkseg></trk></gpx>`;
  const t = parseGpx(nu);
  assert.equal(t.elevationGainM, null);
  assert.equal(t.durationS, null);
  assert.equal(t.pointCount, 2);
});
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

`docker run --rm -v "$PWD":/app -w /app node:20 sh -c "npm install && npm test"`
Attendu : ÉCHEC, `Cannot find module '../src/traces/gpx'`.

- [ ] **Step 3: Écrire le lecteur**

Ajouter `"fast-xml-parser": "^4.4.1"` aux dépendances de `package.json`, puis créer `src/traces/gpx.js` :

```js
const { XMLParser } = require('fast-xml-parser');

const MAX_POINTS = 50000;
const RAYON_TERRE_M = 6371000;

// Le client envoie le fichier, le serveur en tire les statistiques : un
// client bricole peut mentir sur sa distance ou sa position de depart pour
// remonter en tete de liste, pas sur le contenu du fichier qu'il depose.
class GpxInvalide extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'GpxInvalide';
    this.code = code;
  }
}

const parseur = new XMLParser({ ignoreAttributes: false, attributeNamePrefix: '@' });

function enTableau(valeur) {
  if (valeur === undefined || valeur === null) return [];
  return Array.isArray(valeur) ? valeur : [valeur];
}

function distanceM(a, b) {
  const rad = Math.PI / 180;
  const dLat = (b.lat - a.lat) * rad;
  const dLng = (b.lng - a.lng) * rad;
  const h = Math.sin(dLat / 2) ** 2
    + Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin(dLng / 2) ** 2;
  return 2 * RAYON_TERRE_M * Math.asin(Math.sqrt(h));
}

function parseGpx(xml) {
  let arbre;
  try {
    arbre = parseur.parse(xml);
  } catch (err) {
    throw new GpxInvalide('illisible', 'fichier GPX illisible');
  }
  if (!arbre || !arbre.gpx) throw new GpxInvalide('illisible', 'racine gpx absente');

  // Seules les traces roulees sont publiees : les <rte> et les <wpt> isoles
  // sont ignores, pas convertis.
  const points = [];
  for (const trk of enTableau(arbre.gpx.trk)) {
    for (const seg of enTableau(trk.trkseg)) {
      for (const pt of enTableau(seg.trkpt)) {
        const lat = Number(pt['@lat']);
        const lng = Number(pt['@lon']);
        if (!Number.isFinite(lat) || !Number.isFinite(lng)) continue;
        if (lat < -90 || lat > 90 || lng < -180 || lng > 180) continue;
        const ele = pt.ele === undefined ? null : Number(pt.ele);
        const time = pt.time === undefined ? null : new Date(pt.time).getTime();
        points.push({
          lat, lng,
          ele: Number.isFinite(ele) ? ele : null,
          time: Number.isFinite(time) ? time : null,
        });
        if (points.length > MAX_POINTS) throw new GpxInvalide('trop_de_points', 'trace trop longue');
      }
    }
  }
  if (points.length < 2) throw new GpxInvalide('vide', 'moins de deux points');

  let distance = 0;
  for (let i = 1; i < points.length; i++) distance += distanceM(points[i - 1], points[i]);

  const avecEle = points.filter((p) => p.ele !== null);
  let denivele = null;
  if (avecEle.length >= 2) {
    denivele = 0;
    for (let i = 1; i < avecEle.length; i++) {
      const ecart = avecEle[i].ele - avecEle[i - 1].ele;
      if (ecart > 0) denivele += ecart;
    }
  }

  const avecTemps = points.filter((p) => p.time !== null);
  const duree = avecTemps.length >= 2
    ? Math.round((avecTemps[avecTemps.length - 1].time - avecTemps[0].time) / 1000)
    : null;

  return {
    points,
    startLat: points[0].lat,
    startLng: points[0].lng,
    distanceM: distance,
    elevationGainM: denivele,
    durationS: duree,
    pointCount: points.length,
  };
}

module.exports = { parseGpx, GpxInvalide, MAX_POINTS, distanceM };
```

- [ ] **Step 4: Lancer les tests**

`docker run --rm -v "$PWD":/app -w /app node:20 sh -c "npm install && npm test"`
Attendu : SUCCÈS, les quatre tests du fichier compris.

- [ ] **Step 5: Commit**

```bash
git add package.json package-lock.json src/traces/gpx.js test/traces_gpx.test.js
git commit -m "feat(traces): lecture du GPX et calcul des statistiques cote serveur"
```

---

### Task 4: Stockage des fichiers GPX sur le disque

**Files:**
- Create: `src/traces/store.js`
- Test: `test/traces_store.test.js`

**Interfaces:**
- Consumes: rien.
- Produces: `createTraceStore(dir)` → `{ write(id, xml), read(id), remove(id), exists(id), list(), pathOf(id), dir }`. `write` est atomique (écriture `.tmp` puis renommage) et rend le nombre d'octets écrits. `read` rend `null` si le fichier n'existe pas. `remove` est silencieux sur un fichier absent. `list()` rend les identifiants présents sur le disque.

- [ ] **Step 1: Écrire le test qui échoue**

`test/traces_store.test.js` :

```js
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { createTraceStore } = require('../src/traces/store');

function dossierTemporaire() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'traces-'));
}

test('write puis read rendent le meme contenu', () => {
  const store = createTraceStore(dossierTemporaire());
  const octets = store.write('t1', '<gpx/>');
  assert.equal(octets, Buffer.byteLength('<gpx/>'));
  assert.equal(store.read('t1'), '<gpx/>');
  assert.equal(store.exists('t1'), true);
});

test('read rend null pour une trace absente', () => {
  const store = createTraceStore(dossierTemporaire());
  assert.equal(store.read('inconnue'), null);
});

test('write ne laisse aucun fichier temporaire derriere lui', () => {
  const dir = dossierTemporaire();
  const store = createTraceStore(dir);
  store.write('t1', '<gpx/>');
  assert.deepEqual(fs.readdirSync(dir).filter((f) => f.endsWith('.tmp')), []);
});

test('remove efface, et ne se plaint pas d une trace absente', () => {
  const store = createTraceStore(dossierTemporaire());
  store.write('t1', '<gpx/>');
  store.remove('t1');
  assert.equal(store.exists('t1'), false);
  store.remove('t1');
});

test('un identifiant qui remonte l arborescence est refuse', () => {
  const store = createTraceStore(dossierTemporaire());
  assert.throws(() => store.write('../evasion', '<gpx/>'));
});

test('list rend les identifiants presents', () => {
  const store = createTraceStore(dossierTemporaire());
  store.write('t1', '<gpx/>');
  store.write('t2', '<gpx/>');
  assert.deepEqual(store.list().sort(), ['t1', 't2']);
});
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

`docker run --rm -v "$PWD":/app -w /app node:20 sh -c "npm install && npm test"`
Attendu : ÉCHEC, `Cannot find module '../src/traces/store'`.

- [ ] **Step 3: Écrire le stockage**

`src/traces/store.js` :

```js
const fs = require('node:fs');
const path = require('node:path');

// Les identifiants viennent de nous (jetons aleatoires), mais une route qui
// se tromperait de variable ne doit pas pouvoir ecrire hors du dossier.
const ID_VALIDE = /^[A-Za-z0-9_-]{1,64}$/;

function createTraceStore(dir) {
  fs.mkdirSync(dir, { recursive: true });

  function pathOf(id) {
    if (!ID_VALIDE.test(id)) throw new Error(`identifiant de trace invalide: ${id}`);
    return path.join(dir, `${id}.gpx`);
  }

  return {
    dir,
    pathOf,

    // Ecrire a cote puis renommer : une publication interrompue ne laisse
    // pas un fichier tronque derriere une ligne valide en base.
    write(id, xml) {
      const cible = pathOf(id);
      const temporaire = `${cible}.tmp`;
      fs.writeFileSync(temporaire, xml, 'utf8');
      fs.renameSync(temporaire, cible);
      return Buffer.byteLength(xml, 'utf8');
    },

    read(id) {
      try {
        return fs.readFileSync(pathOf(id), 'utf8');
      } catch (err) {
        if (err.code === 'ENOENT') return null;
        throw err;
      }
    },

    exists(id) {
      return fs.existsSync(pathOf(id));
    },

    remove(id) {
      try {
        fs.rmSync(pathOf(id));
      } catch (err) {
        if (err.code !== 'ENOENT') throw err;
      }
    },

    list() {
      return fs.readdirSync(dir)
        .filter((f) => f.endsWith('.gpx'))
        .map((f) => f.slice(0, -4));
    },
  };
}

module.exports = { createTraceStore };
```

- [ ] **Step 4: Lancer les tests**

`docker run --rm -v "$PWD":/app -w /app node:20 sh -c "npm install && npm test"`
Attendu : SUCCÈS.

- [ ] **Step 5: Commit**

```bash
git add src/traces/store.js test/traces_store.test.js
git commit -m "feat(traces): stockage atomique des fichiers GPX sur le disque"
```

---

### Task 5: Publier une trace

**Files:**
- Create: `src/routes/traces.js`
- Test: `test/traces_publish.test.js`

**Interfaces:**
- Consumes: `authenticate`, `requireVerified` (Task 1) ; `parseGpx`, `GpxInvalide`, `MAX_POINTS` (Task 3) ; `createTraceStore` (Task 4).
- Produces: `createTracesRouter(db, { store, now = () => Date.now() })` → routeur Express monté sur `/api/traces`, avec pour l'instant la seule route `POST /`. Réponse `201 { id }`. Helper exporté `nouvelIdentifiant()` (16 octets aléatoires en base64url).

- [ ] **Step 1: Écrire le test qui échoue**

`test/traces_publish.test.js` :

```js
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const express = require('express');
const { openDb } = require('../src/db');
const { hashToken } = require('../src/accounts/auth');
const { createTraceStore } = require('../src/traces/store');
const { createTracesRouter } = require('../src/routes/traces');

const GPX = `<?xml version="1.0"?><gpx><trk><trkseg>
<trkpt lat="43.6000" lon="1.4400"><ele>150</ele><time>2026-09-01T08:00:00Z</time></trkpt>
<trkpt lat="43.6090" lon="1.4400"><ele>180</ele><time>2026-09-01T08:10:00Z</time></trkpt>
</trkseg></trk></gpx>`;

const FICHE = {
  name: 'Boucle du Sidobre',
  description: 'Pistes forestieres, deux gues',
  authorName: 'Marco31',
  vehicle: 'moto',
  difficulty: 'moyen',
  gpx: GPX,
};

function creerCompte(db, { id = 'c1', email = 'rider@exemple.test', verifie = true } = {}) {
  db.prepare('INSERT INTO account (id, email, password_hash, display_name, created_at, verified_at) VALUES (?,?,?,?,?,?)')
    .run(id, email, 'x', 'Marc', 1, verifie ? 1 : null);
  const jeton = `jeton-${id}`;
  db.prepare('INSERT INTO account_session (token_hash, account_id, created_at, last_seen_at, expires_at) VALUES (?,?,?,?,?)')
    .run(hashToken(jeton), id, 1, 1, 9e15);
  return jeton;
}

function buildApp({ now = () => 1_000_000 } = {}) {
  const db = openDb(':memory:');
  const store = createTraceStore(fs.mkdtempSync(path.join(os.tmpdir(), 'traces-')));
  const app = express();
  app.use('/api/traces', createTracesRouter(db, { store, now }));
  return { app, db, store };
}

async function listen(app) {
  const server = app.listen(0);
  await new Promise((r) => server.once('listening', r));
  return { server, base: `http://127.0.0.1:${server.address().port}` };
}

function publier(base, corps, jeton) {
  const headers = { 'content-type': 'application/json' };
  if (jeton) headers.authorization = `Bearer ${jeton}`;
  return fetch(`${base}/api/traces`, { method: 'POST', headers, body: JSON.stringify(corps) });
}

test('une publication valide cree la fiche, le fichier, et les statistiques du serveur', async () => {
  const { app, db, store } = buildApp();
  const jeton = creerCompte(db);
  const { server, base } = await listen(app);

  // La fiche annonce des statistiques fantaisistes : le serveur ne doit pas les croire.
  const res = await publier(base, { ...FICHE, distanceM: 999999, startLat: 0, startLng: 0 }, jeton);
  assert.equal(res.status, 201);
  const { id } = await res.json();

  const ligne = db.prepare('SELECT * FROM shared_trace WHERE id = ?').get(id);
  assert.equal(ligne.account_id, 'c1');
  assert.equal(ligne.author_name, 'Marco31');
  assert.equal(ligne.vehicle, 'moto');
  assert.equal(ligne.start_lat, 43.6);
  assert.ok(ligne.distance_m > 900 && ligne.distance_m < 1100);
  assert.equal(ligne.point_count, 2);
  assert.equal(ligne.download_count, 0);
  assert.equal(ligne.hidden_at, null);
  assert.equal(store.read(id), GPX);
  server.close();
});

test('publier sans jeton est refuse', async () => {
  const { app } = buildApp();
  const { server, base } = await listen(app);
  assert.equal((await publier(base, FICHE)).status, 401);
  server.close();
});

test('un compte non verifie ne peut pas publier', async () => {
  const { app, db } = buildApp();
  const jeton = creerCompte(db, { verifie: false });
  const { server, base } = await listen(app);
  assert.equal((await publier(base, FICHE, jeton)).status, 403);
  server.close();
});

test('une fiche incomplete ou un engin inconnu sont refuses', async () => {
  const { app, db } = buildApp();
  const jeton = creerCompte(db);
  const { server, base } = await listen(app);
  assert.equal((await publier(base, { ...FICHE, description: '  ' }, jeton)).status, 400);
  assert.equal((await publier(base, { ...FICHE, vehicle: 'quad' }, jeton)).status, 400);
  assert.equal((await publier(base, { ...FICHE, difficulty: 'extreme' }, jeton)).status, 400);
  server.close();
});

test('un GPX illisible est refuse et ne laisse pas de fichier', async () => {
  const { app, db, store } = buildApp();
  const jeton = creerCompte(db);
  const { server, base } = await listen(app);
  assert.equal((await publier(base, { ...FICHE, gpx: 'pas du xml <<<' }, jeton)).status, 400);
  assert.deepEqual(store.list(), []);
  server.close();
});

test('la onzieme publication du jour est refusee', async () => {
  const { app, db } = buildApp();
  const jeton = creerCompte(db);
  const { server, base } = await listen(app);
  for (let i = 0; i < 10; i++) {
    assert.equal((await publier(base, FICHE, jeton)).status, 201);
  }
  const res = await publier(base, FICHE, jeton);
  assert.equal(res.status, 429);
  server.close();
});
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

`docker run --rm -v "$PWD":/app -w /app node:20 sh -c "npm install && npm test"`
Attendu : ÉCHEC, `Cannot find module '../src/routes/traces'`.

- [ ] **Step 3: Écrire le routeur**

`src/routes/traces.js` :

```js
const crypto = require('node:crypto');
const express = require('express');
const { authenticate, requireVerified } = require('../accounts/auth');
const { parseGpx, GpxInvalide } = require('../traces/gpx');
const { createRateLimiter } = require('../rate_limit');

const ENGINS = new Set(['moto', '4x4', 'mixte']);
const DIFFICULTES = new Set(['facile', 'moyen', 'difficile']);
const TAILLE_MAX_OCTETS = 5 * 1024 * 1024;
const PUBLICATIONS_PAR_JOUR = 10;
const JOUR_MS = 24 * 3600 * 1000;

function nouvelIdentifiant() {
  return crypto.randomBytes(16).toString('base64url');
}

function texte(valeur, maximum) {
  if (typeof valeur !== 'string') return null;
  const propre = valeur.trim();
  if (propre.length === 0 || propre.length > maximum) return null;
  return propre;
}

function createTracesRouter(db, { store, now = () => Date.now() } = {}) {
  const router = express.Router();
  const auth = authenticate(db, now);

  // Le corps porte un fichier entier : la limite globale du serveur (100 ko
  // par defaut d'express.json) ne convient qu'ici, et nulle part ailleurs.
  const corpsVolumineux = express.json({ limit: '6mb' });
  const limiteurPublication = createRateLimiter({ windowMs: 15 * 60 * 1000, max: 30, now });

  router.post('/', corpsVolumineux, limiteurPublication, auth, requireVerified, (req, res) => {
    const nom = texte(req.body?.name, 120);
    const description = texte(req.body?.description, 4000);
    const auteur = texte(req.body?.authorName, 60);
    const engin = req.body?.vehicle;
    const difficulte = req.body?.difficulty;
    const gpx = typeof req.body?.gpx === 'string' ? req.body.gpx : null;

    if (!nom || !description || !auteur || !gpx) {
      return res.status(400).json({ error: 'fiche incomplete' });
    }
    if (!ENGINS.has(engin) || !DIFFICULTES.has(difficulte)) {
      return res.status(400).json({ error: 'engin ou difficulte inconnu' });
    }
    if (Buffer.byteLength(gpx, 'utf8') > TAILLE_MAX_OCTETS) {
      return res.status(413).json({ error: 'fichier trop volumineux' });
    }

    const at = now();
    const depuis = at - JOUR_MS;
    const publiees = db.prepare('SELECT COUNT(*) AS n FROM shared_trace WHERE account_id = ? AND published_at > ?')
      .get(req.account.id, depuis).n;
    if (publiees >= PUBLICATIONS_PAR_JOUR) {
      return res.status(429).json({ error: 'quota de publications atteint' });
    }

    let trace;
    try {
      trace = parseGpx(gpx);
    } catch (err) {
      if (err instanceof GpxInvalide) {
        const code = err.code === 'trop_de_points' ? 413 : 400;
        return res.status(code).json({ error: `gpx invalide: ${err.code}` });
      }
      throw err;
    }

    const id = nouvelIdentifiant();
    // Le fichier d'abord : une ligne sans fichier serait une fiche
    // intelechargeable, un fichier sans ligne n'est qu'un orphelin que la
    // sauvegarde balaie.
    const octets = store.write(id, gpx);
    const empreinte = crypto.createHash('sha256').update(gpx, 'utf8').digest('hex');
    const enregistreeLe = trace.points.find((p) => p.time !== null)?.time ?? null;

    db.prepare(`INSERT INTO shared_trace (
        id, account_id, author_name, name, description, vehicle, difficulty,
        start_lat, start_lng, distance_m, elevation_gain_m, duration_s, point_count,
        gpx_bytes, gpx_sha256, recorded_at, published_at, updated_at
      ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`).run(
      id, req.account.id, auteur, nom, description, engin, difficulte,
      trace.startLat, trace.startLng, trace.distanceM, trace.elevationGainM, trace.durationS,
      trace.pointCount, octets, empreinte, enregistreeLe, at, at,
    );

    res.status(201).json({ id });
  });

  return router;
}

module.exports = { createTracesRouter, nouvelIdentifiant, ENGINS, DIFFICULTES };
```

- [ ] **Step 4: Lancer les tests**

`docker run --rm -v "$PWD":/app -w /app node:20 sh -c "npm install && npm test"`
Attendu : SUCCÈS, les six tests de publication compris.

- [ ] **Step 5: Commit**

```bash
git add src/routes/traces.js test/traces_publish.test.js
git commit -m "feat(traces): publication d une trace, quota et statistiques calculees"
```

---

### Task 6: Lister les traces, triées par distance

**Files:**
- Modify: `src/routes/traces.js`
- Test: `test/traces_list.test.js`

**Interfaces:**
- Consumes: `createTracesRouter` (Task 5), `distanceM` (Task 3).
- Produces: `GET /api/traces?lat&lng&rayon&engin&difficulte&q&limite&depuis` → `200 { traces: [...], total }`. Chaque entrée : `{ id, name, authorName, vehicle, difficulty, distanceM, elevationGainM, durationS, recordedAt, publishedAt, downloadCount, startLat, startLng, distanceFromRefM }`. Jamais `account_id`.

- [ ] **Step 1: Écrire le test qui échoue**

`test/traces_list.test.js` — reprendre `creerCompte`, `buildApp`, `listen` de `test/traces_publish.test.js` (les recopier dans ce fichier : chaque test est autonome), puis :

```js
function insererTrace(db, { id, lat, lng, engin = 'moto', difficulte = 'moyen', nom = 'Boucle', cache = null, compte = 'c1' }) {
  db.prepare(`INSERT INTO shared_trace (id, account_id, author_name, name, description, vehicle, difficulty,
      start_lat, start_lng, distance_m, point_count, gpx_bytes, gpx_sha256, published_at, updated_at, hidden_at)
    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`)
    .run(id, compte, 'Marco31', nom, 'Desc', engin, difficulte, lat, lng, 12000, 300, 4096, 'abc', 1000, 1000, cache);
}

function lister(base, requete, jeton) {
  return fetch(`${base}/api/traces?${new URLSearchParams(requete)}`, {
    headers: { authorization: `Bearer ${jeton}` },
  });
}

test('la liste est triee par distance croissante au point de reference', async () => {
  const { app, db } = buildApp();
  const jeton = creerCompte(db);
  insererTrace(db, { id: 'loin',   lat: 44.20, lng: 1.44 }); // ~67 km
  insererTrace(db, { id: 'proche', lat: 43.70, lng: 1.44 }); // ~11 km
  const { server, base } = await listen(app);

  const res = await lister(base, { lat: '43.6', lng: '1.44', rayon: '100' }, jeton);
  assert.equal(res.status, 200);
  const { traces } = await res.json();
  assert.deepEqual(traces.map((t) => t.id), ['proche', 'loin']);
  assert.ok(traces[0].distanceFromRefM < traces[1].distanceFromRefM);
  assert.equal(traces[0].account_id, undefined);
  assert.equal(traces[0].accountId, undefined);
  server.close();
});

test('le rayon exclut ce qui est au dela', async () => {
  const { app, db } = buildApp();
  const jeton = creerCompte(db);
  insererTrace(db, { id: 'loin',   lat: 44.20, lng: 1.44 });
  insererTrace(db, { id: 'proche', lat: 43.70, lng: 1.44 });
  const { server, base } = await listen(app);
  const { traces } = await (await lister(base, { lat: '43.6', lng: '1.44', rayon: '25' }, jeton)).json();
  assert.deepEqual(traces.map((t) => t.id), ['proche']);
  server.close();
});

test('les filtres engin, difficulte et nom s appliquent', async () => {
  const { app, db } = buildApp();
  const jeton = creerCompte(db);
  insererTrace(db, { id: 'm', lat: 43.61, lng: 1.44, engin: 'moto', difficulte: 'facile', nom: 'Sidobre' });
  insererTrace(db, { id: 'q', lat: 43.62, lng: 1.44, engin: '4x4',  difficulte: 'difficile', nom: 'Montagne Noire' });
  const { server, base } = await listen(app);

  let r = await (await lister(base, { lat: '43.6', lng: '1.44', engin: '4x4' }, jeton)).json();
  assert.deepEqual(r.traces.map((t) => t.id), ['q']);
  r = await (await lister(base, { lat: '43.6', lng: '1.44', difficulte: 'facile' }, jeton)).json();
  assert.deepEqual(r.traces.map((t) => t.id), ['m']);
  r = await (await lister(base, { lat: '43.6', lng: '1.44', q: 'sidob' }, jeton)).json();
  assert.deepEqual(r.traces.map((t) => t.id), ['m']);
  server.close();
});

test('une trace masquee n apparait pas, meme pour son auteur', async () => {
  const { app, db } = buildApp();
  const jeton = creerCompte(db);
  insererTrace(db, { id: 'cachee', lat: 43.61, lng: 1.44, cache: 5000, compte: 'c1' });
  const { server, base } = await listen(app);
  const { traces } = await (await lister(base, { lat: '43.6', lng: '1.44' }, jeton)).json();
  assert.deepEqual(traces, []);
  server.close();
});

test('lat et lng sont obligatoires, le rayon est plafonne', async () => {
  const { app, db } = buildApp();
  const jeton = creerCompte(db);
  const { server, base } = await listen(app);
  assert.equal((await lister(base, { rayon: '50' }, jeton)).status, 400);
  assert.equal((await lister(base, { lat: '43.6', lng: '1.44', rayon: '5000' }, jeton)).status, 400);
  server.close();
});
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

`docker run --rm -v "$PWD":/app -w /app node:20 sh -c "npm install && npm test"`
Attendu : ÉCHEC, la liste renvoie 404 (route absente).

- [ ] **Step 3: Ajouter la route**

Dans `src/routes/traces.js`, ajouter en tête du fichier `const { parseGpx, GpxInvalide, distanceM } = require('../traces/gpx');`, les constantes, puis la route :

```js
const RAYON_DEFAUT_KM = 50;
const RAYON_MAX_KM = 300;
const LIMITE_DEFAUT = 50;
const LIMITE_MAX = 200;
const DEGRE_LAT_M = 111320;

function ligneVersFiche(ligne, distanceRef) {
  return {
    id: ligne.id,
    name: ligne.name,
    authorName: ligne.author_name,
    vehicle: ligne.vehicle,
    difficulty: ligne.difficulty,
    distanceM: ligne.distance_m,
    elevationGainM: ligne.elevation_gain_m,
    durationS: ligne.duration_s,
    pointCount: ligne.point_count,
    recordedAt: ligne.recorded_at,
    publishedAt: ligne.published_at,
    downloadCount: ligne.download_count,
    startLat: ligne.start_lat,
    startLng: ligne.start_lng,
    distanceFromRefM: distanceRef,
  };
}
```

```js
  router.get('/', auth, (req, res) => {
    const lat = Number(req.query.lat);
    const lng = Number(req.query.lng);
    if (!Number.isFinite(lat) || !Number.isFinite(lng) || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      return res.status(400).json({ error: 'point de reference manquant' });
    }
    const rayonKm = req.query.rayon === undefined ? RAYON_DEFAUT_KM : Number(req.query.rayon);
    if (!Number.isFinite(rayonKm) || rayonKm <= 0 || rayonKm > RAYON_MAX_KM) {
      return res.status(400).json({ error: 'rayon invalide' });
    }
    const limite = Math.min(Number(req.query.limite) || LIMITE_DEFAUT, LIMITE_MAX);
    const depuis = Math.max(Number(req.query.depuis) || 0, 0);

    // Rectangle englobant d'abord, en SQL sur l'index : c'est lui qui evite
    // de charger la France entiere pour en garder trois lignes. La distance
    // reelle et le tri se font ensuite, sur ce petit lot.
    const rayonM = rayonKm * 1000;
    const dLat = rayonM / DEGRE_LAT_M;
    const cos = Math.max(Math.cos(lat * Math.PI / 180), 0.01);
    const dLng = rayonM / (DEGRE_LAT_M * cos);

    const conditions = ['hidden_at IS NULL', 'start_lat BETWEEN ? AND ?', 'start_lng BETWEEN ? AND ?'];
    const params = [lat - dLat, lat + dLat, lng - dLng, lng + dLng];
    if (ENGINS.has(req.query.engin)) { conditions.push('vehicle = ?'); params.push(req.query.engin); }
    if (DIFFICULTES.has(req.query.difficulte)) { conditions.push('difficulty = ?'); params.push(req.query.difficulte); }
    const recherche = texte(req.query.q, 80);
    if (recherche) {
      conditions.push('(name LIKE ? OR author_name LIKE ?)');
      params.push(`%${recherche}%`, `%${recherche}%`);
    }

    const lignes = db.prepare(`SELECT * FROM shared_trace WHERE ${conditions.join(' AND ')}`).all(...params);
    const dans = lignes
      .map((l) => ({ l, d: distanceM({ lat, lng }, { lat: l.start_lat, lng: l.start_lng }) }))
      .filter((e) => e.d <= rayonM)
      .sort((a, b) => a.d - b.d);

    res.status(200).json({
      total: dans.length,
      traces: dans.slice(depuis, depuis + limite).map((e) => ligneVersFiche(e.l, Math.round(e.d))),
    });
  });
```

- [ ] **Step 4: Lancer les tests**

`docker run --rm -v "$PWD":/app -w /app node:20 sh -c "npm install && npm test"`
Attendu : SUCCÈS.

- [ ] **Step 5: Commit**

```bash
git add src/routes/traces.js test/traces_list.test.js
git commit -m "feat(traces): liste triee par distance, avec rayon et filtres"
```

---

### Task 7: Fiche d'une trace, et mes publications

**Files:**
- Modify: `src/routes/traces.js`
- Test: `test/traces_detail.test.js`

**Interfaces:**
- Consumes: Task 6.
- Produces: `GET /api/traces/mine` → `200 { traces: [...] }` avec les publications du rider connecté, masquées comprises, chacune portant `hidden: true|false` et `hiddenReason`. `GET /api/traces/:id` → `200 { ...fiche, preview: [[lat,lng], …] }`, `404` si absente ou masquée. L'aperçu est échantillonné à 300 points maximum.

**Attention à l'ordre de déclaration :** `/mine` doit être déclarée **avant** `/:id`, sans quoi Express traite « mine » comme un identifiant.

- [ ] **Step 1: Écrire le test qui échoue**

`test/traces_detail.test.js` — mêmes aides que la tâche 6, plus une publication réelle pour disposer d'un fichier :

```js
test('la fiche rend les statistiques et un apercu du trace', async () => {
  const { app, db } = buildApp();
  const jeton = creerCompte(db);
  const { server, base } = await listen(app);
  const { id } = await (await publier(base, FICHE, jeton)).json();

  const res = await fetch(`${base}/api/traces/${id}`, { headers: { authorization: `Bearer ${jeton}` } });
  assert.equal(res.status, 200);
  const fiche = await res.json();
  assert.equal(fiche.name, 'Boucle du Sidobre');
  assert.equal(fiche.authorName, 'Marco31');
  assert.equal(fiche.preview.length, 2);
  assert.deepEqual(fiche.preview[0], [43.6, 1.44]);
  assert.equal(fiche.accountId, undefined);
  server.close();
});

test('une trace masquee rend 404, meme a son auteur', async () => {
  const { app, db } = buildApp();
  const jeton = creerCompte(db);
  const { server, base } = await listen(app);
  const { id } = await (await publier(base, FICHE, jeton)).json();
  db.prepare('UPDATE shared_trace SET hidden_at = 5000 WHERE id = ?').run(id);

  const res = await fetch(`${base}/api/traces/${id}`, { headers: { authorization: `Bearer ${jeton}` } });
  assert.equal(res.status, 404);
  server.close();
});

test('mine rend mes publications, masquees comprises et signalees comme telles', async () => {
  const { app, db } = buildApp();
  const jeton = creerCompte(db);
  const autre = creerCompte(db, { id: 'c2', email: 'autre@exemple.test' });
  const { server, base } = await listen(app);
  const { id } = await (await publier(base, FICHE, jeton)).json();
  db.prepare('UPDATE shared_trace SET hidden_at = 5000, hidden_reason = ? WHERE id = ?').run('terrain prive', id);

  const mien = await (await fetch(`${base}/api/traces/mine`, { headers: { authorization: `Bearer ${jeton}` } })).json();
  assert.equal(mien.traces.length, 1);
  assert.equal(mien.traces[0].hidden, true);
  assert.equal(mien.traces[0].hiddenReason, 'terrain prive');

  const sien = await (await fetch(`${base}/api/traces/mine`, { headers: { authorization: `Bearer ${autre}` } })).json();
  assert.deepEqual(sien.traces, []);
  server.close();
});
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

`docker run --rm -v "$PWD":/app -w /app node:20 sh -c "npm install && npm test"`
Attendu : ÉCHEC, 404 sur les trois routes.

- [ ] **Step 3: Ajouter les routes**

Dans `src/routes/traces.js`, **avant** toute route `/:id` :

```js
  router.get('/mine', auth, (req, res) => {
    const lignes = db.prepare('SELECT * FROM shared_trace WHERE account_id = ? ORDER BY published_at DESC')
      .all(req.account.id);
    res.status(200).json({
      traces: lignes.map((l) => ({
        ...ligneVersFiche(l, null),
        hidden: l.hidden_at !== null,
        hiddenReason: l.hidden_reason,
      })),
    });
  });

  router.get('/:id', auth, (req, res) => {
    const ligne = db.prepare('SELECT * FROM shared_trace WHERE id = ? AND hidden_at IS NULL').get(req.params.id);
    if (!ligne) return res.status(404).json({ error: 'trace introuvable' });

    const gpx = store.read(ligne.id);
    let apercu = [];
    if (gpx) {
      try {
        const { points } = parseGpx(gpx);
        // Un apercu de carte n'a pas besoin de 40 000 points : un sur n
        // suffit a dessiner la meme forme pour une fraction du transfert.
        const pas = Math.max(1, Math.ceil(points.length / 300));
        apercu = points.filter((_, i) => i % pas === 0).map((p) => [p.lat, p.lng]);
      } catch (err) {
        console.error(`apercu illisible pour la trace ${ligne.id}:`, err.message);
      }
    }
    res.status(200).json({ ...ligneVersFiche(ligne, null), description: ligne.description, preview: apercu });
  });
```

Ajouter aussi `description: ligne.description` au retour de `ligneVersFiche` n'est pas souhaitable — la liste n'a pas à transporter 4 000 caractères par entrée. La description est donc ajoutée seulement ici, comme ci-dessus.

- [ ] **Step 4: Lancer les tests**

`docker run --rm -v "$PWD":/app -w /app node:20 sh -c "npm install && npm test"`
Attendu : SUCCÈS.

- [ ] **Step 5: Commit**

```bash
git add src/routes/traces.js test/traces_detail.test.js
git commit -m "feat(traces): fiche detaillee avec apercu, et liste de mes publications"
```

---

### Task 8: Télécharger, et compter les téléchargements

**Files:**
- Modify: `src/routes/traces.js`
- Test: `test/traces_download.test.js`

**Interfaces:**
- Consumes: Task 7.
- Produces: `GET /api/traces/:id/gpx` → `200` avec `Content-Type: application/gpx+xml` et le fichier ; incrémente `download_count` au premier téléchargement d'un rider donné ; ne compte jamais l'auteur ; `404` si masquée ou absente ; `410` si la ligne existe mais que le fichier a disparu du disque.

- [ ] **Step 1: Écrire le test qui échoue**

`test/traces_download.test.js` :

```js
function telecharger(base, id, jeton) {
  return fetch(`${base}/api/traces/${id}/gpx`, { headers: { authorization: `Bearer ${jeton}` } });
}

test('le compteur ne monte qu une fois par rider', async () => {
  const { app, db } = buildApp();
  const auteur = creerCompte(db);
  const lecteur = creerCompte(db, { id: 'c2', email: 'lecteur@exemple.test' });
  const troisieme = creerCompte(db, { id: 'c3', email: 'tiers@exemple.test' });
  const { server, base } = await listen(app);
  const { id } = await (await publier(base, FICHE, auteur)).json();

  const res = await telecharger(base, id, lecteur);
  assert.equal(res.status, 200);
  assert.match(res.headers.get('content-type'), /gpx/);
  assert.equal(await res.text(), GPX);

  await telecharger(base, id, lecteur);
  assert.equal(db.prepare('SELECT download_count AS n FROM shared_trace WHERE id = ?').get(id).n, 1);

  await telecharger(base, id, troisieme);
  assert.equal(db.prepare('SELECT download_count AS n FROM shared_trace WHERE id = ?').get(id).n, 2);
  server.close();
});

test('telecharger sa propre trace ne compte pas', async () => {
  const { app, db } = buildApp();
  const auteur = creerCompte(db);
  const { server, base } = await listen(app);
  const { id } = await (await publier(base, FICHE, auteur)).json();
  assert.equal((await telecharger(base, id, auteur)).status, 200);
  assert.equal(db.prepare('SELECT download_count AS n FROM shared_trace WHERE id = ?').get(id).n, 0);
  server.close();
});

test('une trace masquee ne se telecharge plus', async () => {
  const { app, db } = buildApp();
  const auteur = creerCompte(db);
  const lecteur = creerCompte(db, { id: 'c2', email: 'lecteur@exemple.test' });
  const { server, base } = await listen(app);
  const { id } = await (await publier(base, FICHE, auteur)).json();
  db.prepare('UPDATE shared_trace SET hidden_at = 1 WHERE id = ?').run(id);
  assert.equal((await telecharger(base, id, lecteur)).status, 404);
  server.close();
});

test('une fiche dont le fichier a disparu rend 410', async () => {
  const { app, db, store } = buildApp();
  const auteur = creerCompte(db);
  const lecteur = creerCompte(db, { id: 'c2', email: 'lecteur@exemple.test' });
  const { server, base } = await listen(app);
  const { id } = await (await publier(base, FICHE, auteur)).json();
  store.remove(id);
  assert.equal((await telecharger(base, id, lecteur)).status, 410);
  server.close();
});
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

`docker run --rm -v "$PWD":/app -w /app node:20 sh -c "npm install && npm test"`
Attendu : ÉCHEC, 404 sur la route de téléchargement.

- [ ] **Step 3: Ajouter la route**

```js
  router.get('/:id/gpx', auth, (req, res) => {
    const ligne = db.prepare('SELECT * FROM shared_trace WHERE id = ? AND hidden_at IS NULL').get(req.params.id);
    if (!ligne) return res.status(404).json({ error: 'trace introuvable' });

    const gpx = store.read(ligne.id);
    if (gpx === null) {
      console.error(`fichier absent pour la trace ${ligne.id}`);
      return res.status(410).json({ error: 'fichier indisponible' });
    }

    // Le compteur compte des riders, pas des reclics : la cle primaire de
    // trace_download fait le dedoublonnage, et l'auteur ne se compte pas.
    if (ligne.account_id !== req.account.id) {
      const insertion = db.prepare('INSERT OR IGNORE INTO trace_download (trace_id, account_id, downloaded_at) VALUES (?,?,?)')
        .run(ligne.id, req.account.id, now());
      if (insertion.changes === 1) {
        db.prepare('UPDATE shared_trace SET download_count = download_count + 1 WHERE id = ?').run(ligne.id);
      }
    }

    res.status(200)
      .set('Content-Type', 'application/gpx+xml; charset=utf-8')
      .set('Content-Disposition', `attachment; filename="${ligne.id}.gpx"`)
      .send(gpx);
  });
```

- [ ] **Step 4: Lancer les tests**

`docker run --rm -v "$PWD":/app -w /app node:20 sh -c "npm install && npm test"`
Attendu : SUCCÈS.

- [ ] **Step 5: Commit**

```bash
git add src/routes/traces.js test/traces_download.test.js
git commit -m "feat(traces): telechargement du GPX et compteur dedoublonne par rider"
```

---

### Task 9: Modifier sa fiche, dépublier

**Files:**
- Modify: `src/routes/traces.js`
- Test: `test/traces_owner.test.js`

**Interfaces:**
- Consumes: Task 8.
- Produces: `PATCH /api/traces/:id` (champs `name`, `description`, `authorName`, `vehicle`, `difficulty`, tous facultatifs) → `200 { ok: true }` ; `DELETE /api/traces/:id` → `204`, supprime la ligne et le fichier. Les deux répondent `404` si la trace n'appartient pas au demandeur — jamais `403`, qui révélerait l'existence de la trace.

- [ ] **Step 1: Écrire le test qui échoue**

```js
test('l auteur modifie sa fiche, le GPX ne bouge pas', async () => {
  const { app, db, store } = buildApp();
  const auteur = creerCompte(db);
  const { server, base } = await listen(app);
  const { id } = await (await publier(base, FICHE, auteur)).json();
  const avant = store.read(id);

  const res = await fetch(`${base}/api/traces/${id}`, {
    method: 'PATCH',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${auteur}` },
    body: JSON.stringify({ description: 'Deux gues, praticable en ete seulement', difficulty: 'difficile' }),
  });
  assert.equal(res.status, 200);
  const ligne = db.prepare('SELECT * FROM shared_trace WHERE id = ?').get(id);
  assert.equal(ligne.difficulty, 'difficile');
  assert.equal(ligne.name, 'Boucle du Sidobre'); // inchange
  assert.equal(store.read(id), avant);
  server.close();
});

test('un autre rider ne peut ni modifier ni supprimer, et l ignore', async () => {
  const { app, db } = buildApp();
  const auteur = creerCompte(db);
  const intrus = creerCompte(db, { id: 'c2', email: 'intrus@exemple.test' });
  const { server, base } = await listen(app);
  const { id } = await (await publier(base, FICHE, auteur)).json();

  const patch = await fetch(`${base}/api/traces/${id}`, {
    method: 'PATCH',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${intrus}` },
    body: JSON.stringify({ name: 'detournee' }),
  });
  assert.equal(patch.status, 404);
  const suppr = await fetch(`${base}/api/traces/${id}`, { method: 'DELETE', headers: { authorization: `Bearer ${intrus}` } });
  assert.equal(suppr.status, 404);
  assert.ok(db.prepare('SELECT 1 FROM shared_trace WHERE id = ?').get(id));
  server.close();
});

test('depublier efface la ligne et le fichier', async () => {
  const { app, db, store } = buildApp();
  const auteur = creerCompte(db);
  const { server, base } = await listen(app);
  const { id } = await (await publier(base, FICHE, auteur)).json();

  const res = await fetch(`${base}/api/traces/${id}`, { method: 'DELETE', headers: { authorization: `Bearer ${auteur}` } });
  assert.equal(res.status, 204);
  assert.equal(db.prepare('SELECT 1 FROM shared_trace WHERE id = ?').get(id), undefined);
  assert.equal(store.exists(id), false);
  server.close();
});
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

`docker run --rm -v "$PWD":/app -w /app node:20 sh -c "npm install && npm test"`
Attendu : ÉCHEC, 404 sur PATCH et DELETE.

- [ ] **Step 3: Ajouter les routes**

```js
  router.patch('/:id', express.json(), auth, (req, res) => {
    const ligne = db.prepare('SELECT * FROM shared_trace WHERE id = ? AND account_id = ?')
      .get(req.params.id, req.account.id);
    // 404 et non 403 : repondre « interdit » confirmerait l'existence de la
    // trace a qui n'a pas a le savoir.
    if (!ligne) return res.status(404).json({ error: 'trace introuvable' });

    const champs = {};
    if (req.body?.name !== undefined) {
      const v = texte(req.body.name, 120);
      if (!v) return res.status(400).json({ error: 'nom invalide' });
      champs.name = v;
    }
    if (req.body?.description !== undefined) {
      const v = texte(req.body.description, 4000);
      if (!v) return res.status(400).json({ error: 'description invalide' });
      champs.description = v;
    }
    if (req.body?.authorName !== undefined) {
      const v = texte(req.body.authorName, 60);
      if (!v) return res.status(400).json({ error: 'auteur invalide' });
      champs.author_name = v;
    }
    if (req.body?.vehicle !== undefined) {
      if (!ENGINS.has(req.body.vehicle)) return res.status(400).json({ error: 'engin inconnu' });
      champs.vehicle = req.body.vehicle;
    }
    if (req.body?.difficulty !== undefined) {
      if (!DIFFICULTES.has(req.body.difficulty)) return res.status(400).json({ error: 'difficulte inconnue' });
      champs.difficulty = req.body.difficulty;
    }
    const cles = Object.keys(champs);
    if (cles.length === 0) return res.status(400).json({ error: 'rien a modifier' });

    db.prepare(`UPDATE shared_trace SET ${cles.map((c) => `${c} = ?`).join(', ')}, updated_at = ? WHERE id = ?`)
      .run(...cles.map((c) => champs[c]), now(), ligne.id);
    res.status(200).json({ ok: true });
  });

  router.delete('/:id', auth, (req, res) => {
    const ligne = db.prepare('SELECT * FROM shared_trace WHERE id = ? AND account_id = ?')
      .get(req.params.id, req.account.id);
    if (!ligne) return res.status(404).json({ error: 'trace introuvable' });
    db.prepare('DELETE FROM shared_trace WHERE id = ?').run(ligne.id);
    store.remove(ligne.id);
    res.status(204).end();
  });
```

- [ ] **Step 4: Lancer les tests**

`docker run --rm -v "$PWD":/app -w /app node:20 sh -c "npm install && npm test"`
Attendu : SUCCÈS.

- [ ] **Step 5: Commit**

```bash
git add src/routes/traces.js test/traces_owner.test.js
git commit -m "feat(traces): l auteur modifie sa fiche et depublie sa trace"
```

---

### Task 10: Signaler une trace

**Files:**
- Modify: `src/routes/traces.js`
- Test: `test/traces_report.test.js`

**Interfaces:**
- Consumes: Task 9.
- Produces: `POST /api/traces/:id/report` corps `{ reason, detail? }` → `201 { ok: true }` ; `400` si le motif n'est pas dans `terrain_prive`, `dangereux`, `doublon`, `inapproprie`, `autre` ; `409` si ce rider a déjà signalé cette trace ; `404` si la trace est absente ou masquée. Un signalement ne masque rien.

- [ ] **Step 1: Écrire le test qui échoue**

```js
function signaler(base, id, corps, jeton) {
  return fetch(`${base}/api/traces/${id}/report`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${jeton}` },
    body: JSON.stringify(corps),
  });
}

test('un signalement est enregistre sans masquer la trace', async () => {
  const { app, db } = buildApp();
  const auteur = creerCompte(db);
  const temoin = creerCompte(db, { id: 'c2', email: 'temoin@exemple.test' });
  const { server, base } = await listen(app);
  const { id } = await (await publier(base, FICHE, auteur)).json();

  assert.equal((await signaler(base, id, { reason: 'terrain_prive', detail: 'le proprietaire a rale' }, temoin)).status, 201);
  const ligne = db.prepare('SELECT * FROM trace_report WHERE trace_id = ?').get(id);
  assert.equal(ligne.account_id, 'c2');
  assert.equal(ligne.reason, 'terrain_prive');
  assert.equal(ligne.handled_at, null);
  assert.equal(db.prepare('SELECT hidden_at FROM shared_trace WHERE id = ?').get(id).hidden_at, null);
  server.close();
});

test('un motif inconnu est refuse', async () => {
  const { app, db } = buildApp();
  const auteur = creerCompte(db);
  const temoin = creerCompte(db, { id: 'c2', email: 'temoin@exemple.test' });
  const { server, base } = await listen(app);
  const { id } = await (await publier(base, FICHE, auteur)).json();
  assert.equal((await signaler(base, id, { reason: 'je n aime pas' }, temoin)).status, 400);
  server.close();
});

test('le meme rider ne signale pas deux fois', async () => {
  const { app, db } = buildApp();
  const auteur = creerCompte(db);
  const temoin = creerCompte(db, { id: 'c2', email: 'temoin@exemple.test' });
  const { server, base } = await listen(app);
  const { id } = await (await publier(base, FICHE, auteur)).json();
  assert.equal((await signaler(base, id, { reason: 'dangereux' }, temoin)).status, 201);
  assert.equal((await signaler(base, id, { reason: 'doublon' }, temoin)).status, 409);
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM trace_report WHERE trace_id = ?').get(id).n, 1);
  server.close();
});
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

`docker run --rm -v "$PWD":/app -w /app node:20 sh -c "npm install && npm test"`
Attendu : ÉCHEC, 404 sur la route de signalement.

- [ ] **Step 3: Ajouter la route**

Ajouter la constante en tête de fichier :

```js
const MOTIFS = new Set(['terrain_prive', 'dangereux', 'doublon', 'inapproprie', 'autre']);
```

```js
  router.post('/:id/report', express.json(), limiteurPublication, auth, (req, res) => {
    const ligne = db.prepare('SELECT id FROM shared_trace WHERE id = ? AND hidden_at IS NULL').get(req.params.id);
    if (!ligne) return res.status(404).json({ error: 'trace introuvable' });
    if (!MOTIFS.has(req.body?.reason)) return res.status(400).json({ error: 'motif inconnu' });

    const detail = req.body?.detail === undefined ? null : texte(req.body.detail, 1000);
    const insertion = db.prepare(
      'INSERT OR IGNORE INTO trace_report (trace_id, account_id, reason, detail, created_at) VALUES (?,?,?,?,?)'
    ).run(ligne.id, req.account.id, req.body.reason, detail, now());
    if (insertion.changes === 0) return res.status(409).json({ error: 'deja signalee' });

    res.status(201).json({ ok: true });
  });
```

- [ ] **Step 4: Lancer les tests**

`docker run --rm -v "$PWD":/app -w /app node:20 sh -c "npm install && npm test"`
Attendu : SUCCÈS.

- [ ] **Step 5: Commit**

```bash
git add src/routes/traces.js test/traces_report.test.js
git commit -m "feat(traces): signalement d une trace par un rider"
```

---

### Task 11: Routes d'administration (masquer, démasquer, supprimer)

**Files:**
- Create: `src/routes/admin_traces.js`
- Test: `test/admin_traces.test.js`

**Interfaces:**
- Consumes: `createTraceStore` (Task 4), schéma (Task 2).
- Produces: `createAdminTracesRouter(db, { store, now })` monté sur `/api/admin`, protégé par `?key=` comparé à `process.env.ADMIN_EXPORT_KEY`, avec `GET /traces`, `GET /reports`, `POST /traces/:id/hide`, `POST /traces/:id/unhide`, `DELETE /traces/:id`. C'est ce routeur que l'interface web du lot C consommera.

- [ ] **Step 1: Écrire le test qui échoue**

`test/admin_traces.test.js` :

```js
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const express = require('express');
const { openDb } = require('../src/db');
const { createTraceStore } = require('../src/traces/store');
const { createAdminTracesRouter } = require('../src/routes/admin_traces');

const CLE = 'cle-de-test';

function buildApp() {
  process.env.ADMIN_EXPORT_KEY = CLE;
  const db = openDb(':memory:');
  const store = createTraceStore(fs.mkdtempSync(path.join(os.tmpdir(), 'traces-')));
  const app = express();
  app.use('/api/admin', createAdminTracesRouter(db, { store, now: () => 5000 }));
  return { app, db, store };
}

async function listen(app) {
  const server = app.listen(0);
  await new Promise((r) => server.once('listening', r));
  return { server, base: `http://127.0.0.1:${server.address().port}` };
}

function insererTrace(db, store, id = 't1') {
  db.prepare("INSERT OR IGNORE INTO account (id, email, password_hash, created_at) VALUES ('c1','rider@exemple.test','x',1)").run();
  db.prepare(`INSERT INTO shared_trace (id, account_id, author_name, name, description, vehicle, difficulty,
      start_lat, start_lng, distance_m, point_count, gpx_bytes, gpx_sha256, published_at, updated_at)
    VALUES (?, 'c1','Marco31','Boucle','Desc','moto','moyen',43.6,1.44,12000,300,4096,'abc',1000,1000)`).run(id);
  store.write(id, '<gpx/>');
  return id;
}

test('sans la bonne cle, tout est refuse', async () => {
  const { app } = buildApp();
  const { server, base } = await listen(app);
  assert.equal((await fetch(`${base}/api/admin/traces`)).status, 403);
  assert.equal((await fetch(`${base}/api/admin/traces?key=mauvaise`)).status, 403);
  server.close();
});

test('la liste admin montre les traces masquees, l e-mail de l auteur et le nombre de signalements', async () => {
  const { app, db, store } = buildApp();
  const id = insererTrace(db, store);
  db.prepare('UPDATE shared_trace SET hidden_at = 1 WHERE id = ?').run(id);
  db.prepare("INSERT INTO trace_report (trace_id, account_id, reason, created_at) VALUES (?, 'c1', 'dangereux', 1)").run(id);
  const { server, base } = await listen(app);

  const { traces } = await (await fetch(`${base}/api/admin/traces?key=${CLE}`)).json();
  assert.equal(traces.length, 1);
  assert.equal(traces[0].hidden, true);
  assert.equal(traces[0].authorEmail, 'rider@exemple.test');
  assert.equal(traces[0].reportCount, 1);
  server.close();
});

test('masquer puis demasquer, sans toucher au compteur ni au fichier', async () => {
  const { app, db, store } = buildApp();
  const id = insererTrace(db, store);
  db.prepare('UPDATE shared_trace SET download_count = 7 WHERE id = ?').run(id);
  const { server, base } = await listen(app);

  const masque = await fetch(`${base}/api/admin/traces/${id}/hide?key=${CLE}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ reason: 'terrain prive signale par le proprietaire' }),
  });
  assert.equal(masque.status, 200);
  let ligne = db.prepare('SELECT * FROM shared_trace WHERE id = ?').get(id);
  assert.equal(ligne.hidden_at, 5000);
  assert.equal(ligne.hidden_reason, 'terrain prive signale par le proprietaire');
  assert.equal(store.exists(id), true);

  assert.equal((await fetch(`${base}/api/admin/traces/${id}/unhide?key=${CLE}`, { method: 'POST' })).status, 200);
  ligne = db.prepare('SELECT * FROM shared_trace WHERE id = ?').get(id);
  assert.equal(ligne.hidden_at, null);
  assert.equal(ligne.hidden_reason, null);
  assert.equal(ligne.download_count, 7);
  server.close();
});

test('supprimer efface la ligne, le fichier et les signalements', async () => {
  const { app, db, store } = buildApp();
  const id = insererTrace(db, store);
  db.prepare("INSERT INTO trace_report (trace_id, account_id, reason, created_at) VALUES (?, 'c1', 'dangereux', 1)").run(id);
  const { server, base } = await listen(app);

  assert.equal((await fetch(`${base}/api/admin/traces/${id}?key=${CLE}`, { method: 'DELETE' })).status, 204);
  assert.equal(db.prepare('SELECT 1 FROM shared_trace WHERE id = ?').get(id), undefined);
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM trace_report').get().n, 0);
  assert.equal(store.exists(id), false);
  server.close();
});

test('la file des signalements rend les plus recents non traites', async () => {
  const { app, db, store } = buildApp();
  const id = insererTrace(db, store);
  db.prepare("INSERT INTO trace_report (trace_id, account_id, reason, detail, created_at) VALUES (?, 'c1', 'dangereux', 'gue infranchissable', 2000)").run(id);
  const { server, base } = await listen(app);

  const { reports } = await (await fetch(`${base}/api/admin/reports?key=${CLE}`)).json();
  assert.equal(reports.length, 1);
  assert.equal(reports[0].traceId, id);
  assert.equal(reports[0].traceName, 'Boucle');
  assert.equal(reports[0].reason, 'dangereux');
  server.close();
});
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

`docker run --rm -v "$PWD":/app -w /app node:20 sh -c "npm install && npm test"`
Attendu : ÉCHEC, `Cannot find module '../src/routes/admin_traces'`.

- [ ] **Step 3: Écrire le routeur**

`src/routes/admin_traces.js` :

```js
const express = require('express');

// Meme mecanisme que l'export de la lettre d'information : une cle unique
// dans la requete. Le lot C la remplacera par de vrais comptes
// administrateurs, en gardant ces routes.
function cleValide(req) {
  const attendue = process.env.ADMIN_EXPORT_KEY;
  return Boolean(attendue) && req.query.key === attendue;
}

function createAdminTracesRouter(db, { store, now = () => Date.now() } = {}) {
  const router = express.Router();
  router.use(express.json());
  router.use((req, res, next) => {
    if (!cleValide(req)) return res.status(403).json({ error: 'invalid key' });
    next();
  });

  router.get('/traces', (_req, res) => {
    const lignes = db.prepare(`
      SELECT t.*, a.email AS author_email,
             (SELECT COUNT(*) FROM trace_report r WHERE r.trace_id = t.id) AS report_count
      FROM shared_trace t LEFT JOIN account a ON a.id = t.account_id
      ORDER BY t.published_at DESC`).all();
    res.status(200).json({
      traces: lignes.map((l) => ({
        id: l.id,
        name: l.name,
        authorName: l.author_name,
        authorEmail: l.author_email,
        vehicle: l.vehicle,
        difficulty: l.difficulty,
        distanceM: l.distance_m,
        startLat: l.start_lat,
        startLng: l.start_lng,
        publishedAt: l.published_at,
        downloadCount: l.download_count,
        reportCount: l.report_count,
        hidden: l.hidden_at !== null,
        hiddenReason: l.hidden_reason,
      })),
    });
  });

  router.get('/reports', (_req, res) => {
    const lignes = db.prepare(`
      SELECT r.*, t.name AS trace_name FROM trace_report r
      JOIN shared_trace t ON t.id = r.trace_id
      WHERE r.handled_at IS NULL ORDER BY r.created_at DESC`).all();
    res.status(200).json({
      reports: lignes.map((r) => ({
        id: r.id,
        traceId: r.trace_id,
        traceName: r.trace_name,
        reason: r.reason,
        detail: r.detail,
        createdAt: r.created_at,
      })),
    });
  });

  router.post('/traces/:id/hide', (req, res) => {
    const motif = typeof req.body?.reason === 'string' ? req.body.reason.trim() : null;
    const r = db.prepare('UPDATE shared_trace SET hidden_at = ?, hidden_reason = ? WHERE id = ?')
      .run(now(), motif || null, req.params.id);
    if (r.changes === 0) return res.status(404).json({ error: 'trace introuvable' });
    db.prepare('UPDATE trace_report SET handled_at = ? WHERE trace_id = ? AND handled_at IS NULL')
      .run(now(), req.params.id);
    res.status(200).json({ ok: true });
  });

  router.post('/traces/:id/unhide', (req, res) => {
    const r = db.prepare('UPDATE shared_trace SET hidden_at = NULL, hidden_reason = NULL WHERE id = ?')
      .run(req.params.id);
    if (r.changes === 0) return res.status(404).json({ error: 'trace introuvable' });
    res.status(200).json({ ok: true });
  });

  router.delete('/traces/:id', (req, res) => {
    const r = db.prepare('DELETE FROM shared_trace WHERE id = ?').run(req.params.id);
    if (r.changes === 0) return res.status(404).json({ error: 'trace introuvable' });
    store.remove(req.params.id);
    res.status(204).end();
  });

  return router;
}

module.exports = { createAdminTracesRouter };
```

- [ ] **Step 4: Lancer les tests**

`docker run --rm -v "$PWD":/app -w /app node:20 sh -c "npm install && npm test"`
Attendu : SUCCÈS. Les signalements disparaissent avec la trace grâce au `ON DELETE CASCADE` de la tâche 2, à condition que `foreign_keys = ON` soit posé — il l'est déjà dans `openDb`.

- [ ] **Step 5: Commit**

```bash
git add src/routes/admin_traces.js test/admin_traces.test.js
git commit -m "feat(traces): routes d administration, masquage reversible et suppression"
```

---

### Task 12: Sauvegarder aussi les fichiers GPX

**Files:**
- Modify: `src/backup.js`
- Test: `test/backup.test.js`

**Interfaces:**
- Consumes: `createTraceStore` (Task 4).
- Produces: `backupTraces(store, backupDir)` → `{ copies, supprimes }`. Copie dans `<backupDir>/traces/` les fichiers absents, retire ceux dont la trace n'existe plus dans le magasin. `startBackups(db, dir, now, { store })` l'appelle dans le même cycle, et son échec n'interrompt ni la sauvegarde de la base ni le démarrage.

- [ ] **Step 1: Écrire le test qui échoue**

Ajouter à `test/backup.test.js` :

```js
const { backupTraces } = require('../src/backup');
const { createTraceStore } = require('../src/traces/store');

test('backupTraces copie les fichiers manquants et retire les disparus', () => {
  const source = fs.mkdtempSync(path.join(os.tmpdir(), 'traces-'));
  const cible = fs.mkdtempSync(path.join(os.tmpdir(), 'sauv-'));
  const store = createTraceStore(source);
  store.write('t1', '<gpx>un</gpx>');
  store.write('t2', '<gpx>deux</gpx>');

  let bilan = backupTraces(store, cible);
  assert.equal(bilan.copies, 2);
  assert.equal(fs.readFileSync(path.join(cible, 'traces', 't1.gpx'), 'utf8'), '<gpx>un</gpx>');

  // Deuxieme passage : rien a recopier, les fichiers sont immuables.
  bilan = backupTraces(store, cible);
  assert.equal(bilan.copies, 0);

  store.remove('t2');
  bilan = backupTraces(store, cible);
  assert.equal(bilan.supprimes, 1);
  assert.equal(fs.existsSync(path.join(cible, 'traces', 't2.gpx')), false);
});

test('un echec de sauvegarde des traces n empeche pas celle de la base', () => {
  const db = openDb(':memory:');
  const cible = fs.mkdtempSync(path.join(os.tmpdir(), 'sauv-'));
  const storeCasse = { list: () => { throw new Error('disque en panne'); } };
  const { stop } = startBackups(db, cible, () => Date.now(), { store: storeCasse });
  stop();
  assert.ok(fs.readdirSync(cible).some((f) => f.startsWith('tracker-') && f.endsWith('.db')));
});
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

`docker run --rm -v "$PWD":/app -w /app node:20 sh -c "npm install && npm test"`
Attendu : ÉCHEC, `backupTraces is not a function`.

- [ ] **Step 3: Écrire la sauvegarde des fichiers**

Dans `src/backup.js` :

```js
// Le GPX d'une trace ne change jamais apres sa publication : la sauvegarde
// se limite donc a copier ce qui manque, au lieu de recopier chaque jour un
// dossier qui ne fait que grossir. Sans elle, restaurer la base rendrait
// toutes les fiches intelechargeables.
function backupTraces(store, backupDir) {
  const cible = path.join(backupDir, 'traces');
  fs.mkdirSync(cible, { recursive: true });

  const presents = new Set(store.list());
  let copies = 0;
  for (const id of presents) {
    const destination = path.join(cible, `${id}.gpx`);
    if (fs.existsSync(destination)) continue;
    const temporaire = `${destination}.tmp`;
    fs.copyFileSync(store.pathOf(id), temporaire);
    fs.renameSync(temporaire, destination);
    copies += 1;
  }

  let supprimes = 0;
  for (const f of fs.readdirSync(cible)) {
    if (!f.endsWith('.gpx')) continue;
    if (presents.has(f.slice(0, -4))) continue;
    fs.rmSync(path.join(cible, f));
    supprimes += 1;
  }
  return { copies, supprimes };
}
```

Modifier `startBackups(db, dir, now = () => Date.now(), { store } = {})` pour qu'après chaque `backupDatabase` réussi ou non, il tente :

```js
    if (store) {
      try {
        backupTraces(store, dir);
      } catch (err) {
        console.error('backup: sauvegarde des traces echouee', err.message);
      }
    }
```

à l'appel immédiat comme dans l'intervalle. Ajouter `backupTraces` à `module.exports`.

- [ ] **Step 4: Lancer les tests**

`docker run --rm -v "$PWD":/app -w /app node:20 sh -c "npm install && npm test"`
Attendu : SUCCÈS, y compris les tests de sauvegarde déjà présents.

- [ ] **Step 5: Commit**

```bash
git add src/backup.js test/backup.test.js
git commit -m "feat(exploitation): la sauvegarde quotidienne emporte les fichiers GPX"
```

---

### Task 13: Montage, rattachement au compte, et déploiement

**Files:**
- Modify: `src/server.js`, `src/routes/sessions.js`, `.env.example`, `docker-compose.yml`
- Test: `test/server.test.js`, `test/sessions.test.js`

**Interfaces:**
- Consumes: tâches 1 à 12.
- Produces: le serveur monte `/api/traces` et `/api/admin`, avec `TRACES_DIR` (défaut `/app/data/traces`). `POST /api/sessions` et `POST /api/sessions/join/:joinCode` renseignent `session.account_id` et `member.account_id` **quand** un en-tête `Authorization: Bearer` valide accompagne la requête, et fonctionnent exactement comme avant sans lui.

- [ ] **Step 1: Écrire le test qui échoue**

Ajouter à `test/sessions.test.js` :

```js
test('une session creee avec un jeton de compte est rattachee au compte', async () => {
  const { app, db } = buildApp();
  const jeton = creerCompte(db); // meme aide que dans test/traces_publish.test.js
  const { server, base } = await listen(app);

  const res = await fetch(`${base}/api/sessions`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${jeton}` },
    body: JSON.stringify({ kind: 'solo', name: 'Marc', immobileAfterSec: 300 }),
  });
  assert.equal(res.status, 201);
  const { sessionId } = await res.json();
  assert.equal(db.prepare('SELECT account_id FROM session WHERE id = ?').get(sessionId).account_id, 'c1');
  assert.equal(db.prepare('SELECT account_id FROM member WHERE session_id = ?').get(sessionId).account_id, 'c1');
  server.close();
});

test('une session creee sans jeton reste possible et non rattachee', async () => {
  const { app, db } = buildApp();
  const { server, base } = await listen(app);
  const res = await fetch(`${base}/api/sessions`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ kind: 'solo', name: 'Marc', immobileAfterSec: 300 }),
  });
  assert.equal(res.status, 201);
  const { sessionId } = await res.json();
  assert.equal(db.prepare('SELECT account_id FROM session WHERE id = ?').get(sessionId).account_id, null);
  server.close();
});
```

Ajouter à `test/server.test.js` :

```js
test('les routes de traces et d administration sont montees', async () => {
  const app = createApp(openDb(':memory:'), { tracesDir: fs.mkdtempSync(path.join(os.tmpdir(), 'traces-')) });
  const { server, base } = await listen(app);
  // 401 et non 404 : la route existe, c'est l'authentification qui manque.
  assert.equal((await fetch(`${base}/api/traces?lat=43.6&lng=1.44`)).status, 401);
  assert.equal((await fetch(`${base}/api/admin/traces`)).status, 403);
  server.close();
});
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

`docker run --rm -v "$PWD":/app -w /app node:20 sh -c "npm install && npm test"`
Attendu : ÉCHEC — 404 sur les deux routes, et `account_id` nul malgré le jeton.

- [ ] **Step 3: Monter et rattacher**

Dans `src/server.js`, `createApp(db, { mailer, tracesDir } = {})` :

```js
const { createTraceStore } = require('./traces/store');
const { createTracesRouter } = require('./routes/traces');
const { createAdminTracesRouter } = require('./routes/admin_traces');
```

```js
  const store = createTraceStore(tracesDir || process.env.TRACES_DIR || '/app/data/traces');
  app.use('/api/traces', createTracesRouter(db, { store }));
  app.use('/api/admin', createAdminTracesRouter(db, { store }));
```

en plaçant ces deux lignes **avant** `app.use(express.static(...))`, et en passant `store` à `startBackups` dans le bloc `require.main === module` :

```js
  startBackups(db, process.env.BACKUP_DIR || '/app/data/backups', () => Date.now(), { store });
```

`createApp` construit déjà le magasin ; exposer `app._traceStore = store;` à côté de `app._handleAlert` évite de le reconstruire ailleurs.

Dans `src/routes/sessions.js`, ajouter un rattachement facultatif. Il ne s'agit pas d'une authentification : une alerte de chute ne doit jamais échouer parce qu'une session de compte a expiré.

```js
const { hashToken } = require('../accounts/auth');

// Rattachement au compte, jamais une authentification : un jeton absent,
// expire ou inconnu laisse simplement la colonne a NULL.
function compteEventuel(db, req, now) {
  const header = req.get('authorization') || '';
  if (!header.startsWith('Bearer ')) return null;
  const ligne = db.prepare('SELECT account_id, expires_at FROM account_session WHERE token_hash = ?')
    .get(hashToken(header.slice(7)));
  if (!ligne || ligne.expires_at < now()) return null;
  return ligne.account_id;
}
```

et renseigner `account_id` dans les `INSERT` de `session` et de `member` des routes `POST /` et `POST /join/:joinCode`.

Ajouter `TRACES_DIR=/app/data/traces` à `.env.example`. Vérifier dans `docker-compose.yml` que le volume monté sur `/app/data` couvre bien ce chemin — c'est le cas si la base y vit déjà ; aucun volume supplémentaire à créer.

- [ ] **Step 4: Lancer toute la suite**

`docker run --rm -v "$PWD":/app -w /app node:20 sh -c "npm install && npm test"`
Attendu : SUCCÈS sur l'ensemble des fichiers de test, anciens compris.

- [ ] **Step 5: Commit**

```bash
git add src/server.js src/routes/sessions.js .env.example test/server.test.js test/sessions.test.js
git commit -m "feat(traces): montage des routes et rattachement des sorties au compte"
```

---

### Task 13B: Consentement aux conditions de publication

**Files:**
- Modify: `src/db.js` (deux colonnes sur `shared_trace`), `src/routes/traces.js` (publication)
- Test: `test/traces_publish.test.js`

**Interfaces:**
- Consumes: la route de publication (Task 5), le schéma (Task 2).
- Produces: colonnes `licence_version TEXT` et `licence_accepted_at INTEGER` sur `shared_trace` ; `POST /api/traces` exige un champ `licenceVersion` égal à la version courante (`LICENCE_VERSION`, exportée par `src/routes/traces.js`, valeur `'1.0'`) et refuse en `400 { error: 'conditions de publication non acceptees' }` sinon.

**Pourquoi.** Le pilote cède des droits d'exploitation sur ce qu'il publie et accepte que sa trace reste au catalogue après la suppression de son compte (`docs/legal/conditions-publication-traces.md`). Un consentement qui n'est pas enregistré ne se prouve pas : chaque publication doit porter la version des conditions acceptées et l'horodatage. Une case cochée dans l'application, sans trace côté serveur, ne vaut rien le jour où quelqu'un conteste.

- [ ] **Step 1: Écrire le test qui échoue**

Ajouter à `test/traces_publish.test.js` :

```js
test('une publication enregistre la version des conditions acceptees', async () => {
  const { app, db } = buildApp();
  const jeton = creerCompte(db);
  const { server, base } = await listen(app);
  try {
    const res = await publier(base, { ...FICHE, licenceVersion: '1.0' }, jeton);
    assert.equal(res.status, 201);
    const { id } = await res.json();
    const ligne = db.prepare('SELECT * FROM shared_trace WHERE id = ?').get(id);
    assert.equal(ligne.licence_version, '1.0');
    assert.equal(ligne.licence_accepted_at, 1_000_000); // le `now` fige de buildApp
  } finally {
    server.close();
  }
});

test('publier sans accepter les conditions est refuse', async () => {
  const { app, db, store } = buildApp();
  const jeton = creerCompte(db);
  const { server, base } = await listen(app);
  try {
    const sans = await publier(base, FICHE, jeton);
    assert.equal(sans.status, 400);
    const perimee = await publier(base, { ...FICHE, licenceVersion: '0.9' }, jeton);
    assert.equal(perimee.status, 400);
    // Rien ne doit avoir ete ecrit, ni en base ni sur le disque.
    assert.equal(db.prepare('SELECT COUNT(*) AS n FROM shared_trace').get().n, 0);
    assert.deepEqual(store.list(), []);
  } finally {
    server.close();
  }
});
```

Les publications des autres tests de ce fichier doivent recevoir `licenceVersion: '1.0'` — le plus simple est de l'ajouter à la constante `FICHE`.

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

`docker run --rm -v "$PWD":/app -w /app node:20 sh -c "npm install && npm test"`
Attendu : ÉCHEC — la colonne n'existe pas, et la publication sans consentement passe.

- [ ] **Step 3: Implémenter**

Dans `src/db.js`, ajouter à `CREATE TABLE shared_trace` :

```sql
  licence_version    TEXT,
  licence_accepted_at INTEGER,
```

Dans `src/routes/traces.js` :

```js
// Version des conditions de publication en vigueur. Chaque publication
// enregistre celle que le pilote a acceptee : un consentement non horodate
// ne se prouve pas le jour ou quelqu un le conteste.
const LICENCE_VERSION = '1.0';
```

et, dans la route de publication, refuser avant tout traitement :

```js
    if (req.body?.licenceVersion !== LICENCE_VERSION) {
      return res.status(400).json({ error: 'conditions de publication non acceptees' });
    }
```

en plaçant ce refus **avant** l'écriture du fichier, puis renseigner les deux colonnes dans l'`INSERT`. Exporter `LICENCE_VERSION`.

- [ ] **Step 4: Lancer les tests**

`docker run --rm -v "$PWD":/app -w /app node:20 sh -c "npm install && npm test"`
Attendu : SUCCÈS, toute la suite comprise.

- [ ] **Step 5: Commit**

```bash
git add src/db.js src/routes/traces.js test/traces_publish.test.js
git commit -m "feat(traces): consentement aux conditions de publication enregistre"
```

---

# Partie 2 — Application

Toutes les tâches suivantes se font dans `~/Claude/Projects/APP OFFROAD MOTO 4X4/moto_offroad`. Commande de test : `flutter test`.

### Task 14: Le client de suivi porte enfin le jeton de compte

**Files:**
- Modify: `lib/services/tracker_api_client.dart`, `lib/main.dart`
- Test: `test/services/tracker_api_client_test.dart`

**Interfaces:**
- Consumes: Task 13 côté serveur.
- Produces: `TrackerApiClient({http.Client? client, String? baseUrl, Future<String?> Function()? readToken})`. Toutes les requêtes ajoutent `Authorization: Bearer <jeton>` quand `readToken` rend une valeur non nulle, et partent sans lui sinon. Une exception levée par `readToken` est avalée : la requête part sans jeton.

- [ ] **Step 1: Écrire le test qui échoue**

Ajouter à `test/services/tracker_api_client_test.dart` :

```dart
test('le jeton de compte accompagne la requete quand il existe', () async {
  late http.Request capturee;
  final client = MockClient((req) async {
    capturee = req;
    return http.Response('{"sessionId":"s1","ownerKey":"o","deviceKey":"d","memberId":"m"}', 201);
  });
  final api = TrackerApiClient(client: client, readToken: () async => 'jeton-abc');

  await api.createSoloSession(name: 'Marc', immobileAfterSec: 300, pilotEmail: 'a@b.test');

  expect(capturee.headers['authorization'], 'Bearer jeton-abc');
});

test('sans jeton, la requete part quand meme', () async {
  late http.Request capturee;
  final client = MockClient((req) async {
    capturee = req;
    return http.Response('{"sessionId":"s1","ownerKey":"o","deviceKey":"d","memberId":"m"}', 201);
  });
  final api = TrackerApiClient(client: client, readToken: () async => null);

  final res = await api.createSoloSession(name: 'Marc', immobileAfterSec: 300, pilotEmail: 'a@b.test');

  expect(res, isNotNull);
  expect(capturee.headers.containsKey('authorization'), isFalse);
});

test('une panne du stockage securise ne bloque pas l envoi', () async {
  final client = MockClient((_) async =>
      http.Response('{"sessionId":"s1","ownerKey":"o","deviceKey":"d","memberId":"m"}', 201));
  final api = TrackerApiClient(client: client, readToken: () async => throw Exception('keystore casse'));

  // Une alerte de chute ne doit jamais echouer parce que le compte est en panne.
  expect(await api.createSoloSession(name: 'Marc', immobileAfterSec: 300, pilotEmail: 'a@b.test'), isNotNull);
});
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

`flutter test test/services/tracker_api_client_test.dart`
Attendu : ÉCHEC à la compilation, `No named parameter with the name 'readToken'`.

- [ ] **Step 3: Ajouter le porteur de jeton**

Dans `lib/services/tracker_api_client.dart` :

```dart
  TrackerApiClient({http.Client? client, String? baseUrl, Future<String?> Function()? readToken})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? 'https://motooffroad.duckdns.org',
        _readToken = readToken;

  final Future<String?> Function()? _readToken;

  // Rattachement, pas authentification : le serveur accepte ces routes sans
  // jeton, et une panne du stockage securise ne doit jamais empecher une
  // alerte de partir.
  Future<Map<String, String>> _headers() async {
    final headers = {'Content-Type': 'application/json'};
    if (_readToken == null) return headers;
    try {
      final token = await _readToken();
      if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
    } catch (_) {}
    return headers;
  }
```

Remplacer chaque en-tête littéral `{'Content-Type': 'application/json'}` des méthodes du fichier par `await _headers()`.

Dans `lib/main.dart`, à la construction du `TrackerApiClient`, passer `readToken: () => AccountStorage().readToken()`.

- [ ] **Step 4: Lancer les tests**

`flutter test test/services/tracker_api_client_test.dart && flutter test`
Attendu : SUCCÈS, tous les tests existants du client compris.

- [ ] **Step 5: Commit**

```bash
git add lib/services/tracker_api_client.dart lib/main.dart test/services/tracker_api_client_test.dart
git commit -m "fix(compte): le client de suivi porte le jeton, account_id cesse d etre mort"
```

---

### Task 15: La base locale retient l'origine d'une trace téléchargée

**Files:**
- Modify: `lib/services/ride_database.dart`, `lib/models/ride.dart`, `lib/services/ride_repository.dart`
- Test: `test/services/ride_repository_test.dart`

**Interfaces:**
- Consumes: rien.
- Produces: `Ride.sharedTraceId` (`String?`), colonne `shared_trace_id` sur `rides`, `RideDatabase.schemaVersion == 2` avec migration 1 → 2. `Ride.copyWith` accepte `sharedTraceId`.

- [ ] **Step 1: Écrire le test qui échoue**

Ajouter à `test/services/ride_repository_test.dart` :

Ce fichier ouvre déjà sa base dans un `setUp` (`databaseFactoryFfi.openDatabase(inMemoryDatabasePath, …)`) et expose `db` et `repo` : les deux premiers tests s'en servent tels quels, le troisième ouvre sa propre base en version 1 pour éprouver la migration.

```dart
test('une sortie telechargee retient l identifiant de la trace partagee', () async {
  await repo.insertRide(Ride(
    id: 'r1', name: 'Boucle du Sidobre', startedAt: DateTime(2026, 9, 1),
    source: RideSource.imported, status: RideStatus.finished,
    stats: RideStats.empty, sharedTraceId: 'abc123',
  ));

  final relue = await repo.findRide('r1');
  expect(relue!.sharedTraceId, 'abc123');
});

test('une sortie enregistree n a pas d origine partagee', () async {
  await repo.insertRide(Ride(
    id: 'r2', name: 'Sortie du dimanche', startedAt: DateTime(2026, 9, 1),
    source: RideSource.recorded, status: RideStatus.finished, stats: RideStats.empty,
  ));

  expect((await repo.findRide('r2'))!.sharedTraceId, isNull);
});

test('la migration v1 vers v2 ajoute la colonne sans perdre les sorties', () async {
  final ancienne = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(version: 1, onCreate: RideDatabase.onCreate),
  );
  await ancienne.insert('rides', {
    'id': 'ancienne', 'name': 'Avant migration', 'started_at': 1, 'source': 'recorded',
    'status': 'finished', 'distance_m': 0, 'total_time_s': 0, 'moving_time_s': 0,
    'avg_speed_kmh': 0, 'max_speed_kmh': 0,
  });
  await RideDatabase.onUpgrade(ancienne, 1, 2);

  final rows = await ancienne.query('rides');
  expect(rows.length, 1);
  expect(rows.first['shared_trace_id'], isNull);
});
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

`flutter test test/services/ride_repository_test.dart`
Attendu : ÉCHEC, `No named parameter with the name 'sharedTraceId'`.

- [ ] **Step 3: Ajouter le champ et la migration**

Dans `lib/models/ride.dart`, ajouter à `Ride` le champ `final String? sharedTraceId;`, le paramètre nommé `this.sharedTraceId` du constructeur, et dans `copyWith` : `String? sharedTraceId,` puis `sharedTraceId: sharedTraceId ?? this.sharedTraceId,`.

Dans `lib/services/ride_database.dart` :

```dart
  static const int schemaVersion = 2;
```

Ajouter `shared_trace_id TEXT` à la fin du `CREATE TABLE rides` de `onCreate`, et écrire la migration :

```dart
  // ── Migrations ───────────────────────────────────────────
  // v2 : origine d'une sortie telechargee depuis le catalogue partage.
  // Elle empeche de republier la trace d'un autre, et sert a afficher
  // « telechargee depuis le partage » sur la fiche locale.
  static Future<void> onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE rides ADD COLUMN shared_trace_id TEXT');
    }
  }
```

Dans `lib/services/ride_repository.dart`, ajouter `'shared_trace_id': r.sharedTraceId,` à `_toRow` et `sharedTraceId: row['shared_trace_id'] as String?,` à `_toRide`.

- [ ] **Step 4: Lancer les tests**

`flutter test test/services/ride_repository_test.dart && flutter test`
Attendu : SUCCÈS.

- [ ] **Step 5: Commit**

```bash
git add lib/models/ride.dart lib/services/ride_database.dart lib/services/ride_repository.dart test/services/ride_repository_test.dart
git commit -m "feat(sorties): la base locale retient l origine d une trace telechargee"
```

---

### Task 16: Modèles et client HTTP du catalogue

**Files:**
- Create: `lib/models/shared_trace.dart`, `lib/services/shared_traces_api_client.dart`
- Test: `test/services/shared_traces_api_client_test.dart`

**Interfaces:**
- Consumes: routes serveur des tâches 5 à 10.
- Produces:
  - `enum TraceVehicle { moto, quatreQuatre, mixte }` et `enum TraceDifficulty { facile, moyen, difficile }`, chacun avec `String get wire` (`moto` / `4x4` / `mixte`, et les trois noms tels quels) et `static X fromWire(String)`.
  - `SharedTraceSummary` : `id, name, authorName, vehicle, difficulty, distanceM, elevationGainM, durationS, recordedAt, publishedAt, downloadCount, startLat, startLng, distanceFromRefM, hidden, hiddenReason`, avec `fromJson`.
  - `SharedTraceDetail extends SharedTraceSummary` : ajoute `description` et `preview` (`List<LatLng>`), avec `fromJson`.
  - `SharedTracesApiClient({http.Client? client, String? baseUrl, required Future<String?> Function() readToken})` et ses méthodes : `publish({name, description, authorName, vehicle, difficulty, gpx})` → `String id` ; `list({lat, lng, radiusKm, vehicle, difficulty, query, offset})` → `List<SharedTraceSummary>` ; `detail(id)` → `SharedTraceDetail` ; `downloadGpx(id)` → `String` ; `mine()` → `List<SharedTraceSummary>` ; `update(id, {name, description, authorName, vehicle, difficulty})` ; `unpublish(id)` ; `report(id, {reason, detail})`.
  - `SharedTracesException(this.statusCode, this.message)` levée sur toute réponse hors 2xx, avec `message` déjà traduit pour l'affichage (« ta session a expiré », « quota de publications atteint », « fichier trop volumineux »…).

- [ ] **Step 1: Écrire le test qui échoue**

`test/services/shared_traces_api_client_test.dart` :

```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moto_offroad/models/shared_trace.dart';
import 'package:moto_offroad/services/shared_traces_api_client.dart';

SharedTracesApiClient clientAvec(MockClient mock, {String? jeton = 'jeton'}) =>
    SharedTracesApiClient(client: mock, baseUrl: 'https://exemple.test', readToken: () async => jeton);

test('publish envoie la fiche et rend l identifiant', () async {
  late http.Request capturee;
  final api = clientAvec(MockClient((req) async {
    capturee = req;
    return http.Response('{"id":"t42"}', 201);
  }));

  final id = await api.publish(
    name: 'Boucle', description: 'Pistes', authorName: 'Marco31',
    vehicle: TraceVehicle.quatreQuatre, difficulty: TraceDifficulty.facile, gpx: '<gpx/>',
  );

  expect(id, 't42');
  expect(capturee.headers['authorization'], 'Bearer jeton');
  final corps = jsonDecode(capturee.body) as Map<String, dynamic>;
  expect(corps['vehicle'], '4x4');
  expect(corps['difficulty'], 'facile');
  expect(corps['gpx'], '<gpx/>');
});

test('list transmet le point de reference, le rayon et les filtres', () async {
  late Uri appelee;
  final api = clientAvec(MockClient((req) async {
    appelee = req.url;
    return http.Response(jsonEncode({'total': 1, 'traces': [{
      'id': 't1', 'name': 'Boucle', 'authorName': 'Marco31', 'vehicle': 'moto',
      'difficulty': 'moyen', 'distanceM': 12000.0, 'elevationGainM': 300.0, 'durationS': 3600,
      'recordedAt': 1000, 'publishedAt': 2000, 'downloadCount': 3,
      'startLat': 43.6, 'startLng': 1.44, 'distanceFromRefM': 11000,
    }]}), 200);
  }));

  final traces = await api.list(lat: 43.6, lng: 1.44, radiusKm: 25, vehicle: TraceVehicle.moto);

  expect(appelee.queryParameters['lat'], '43.6');
  expect(appelee.queryParameters['rayon'], '25');
  expect(appelee.queryParameters['engin'], 'moto');
  expect(traces.single.name, 'Boucle');
  expect(traces.single.downloadCount, 3);
  expect(traces.single.vehicle, TraceVehicle.moto);
});

test('detail rend la description et l apercu', () async {
  final api = clientAvec(MockClient((_) async => http.Response(jsonEncode({
    'id': 't1', 'name': 'Boucle', 'authorName': 'Marco31', 'vehicle': 'mixte',
    'difficulty': 'difficile', 'distanceM': 12000.0, 'downloadCount': 0,
    'startLat': 43.6, 'startLng': 1.44, 'publishedAt': 2000,
    'description': 'Deux gues', 'preview': [[43.6, 1.44], [43.61, 1.45]],
  }), 200)));

  final fiche = await api.detail('t1');

  expect(fiche.description, 'Deux gues');
  expect(fiche.preview.length, 2);
  expect(fiche.preview.first.latitude, 43.6);
});

test('downloadGpx rend le fichier tel quel', () async {
  final api = clientAvec(MockClient((_) async => http.Response('<gpx>ici</gpx>', 200)));
  expect(await api.downloadGpx('t1'), '<gpx>ici</gpx>');
});

test('une erreur du serveur est traduite pour l affichage', () async {
  final api = clientAvec(MockClient((_) async => http.Response('{"error":"quota de publications atteint"}', 429)));

  expect(
    () => api.publish(name: 'B', description: 'D', authorName: 'M',
        vehicle: TraceVehicle.moto, difficulty: TraceDifficulty.moyen, gpx: '<gpx/>'),
    throwsA(isA<SharedTracesException>()
        .having((e) => e.statusCode, 'statusCode', 429)
        .having((e) => e.message, 'message', contains('publications'))),
  );
});

test('sans jeton, l appel echoue avant de partir', () async {
  final api = clientAvec(MockClient((_) async => http.Response('', 200)), jeton: null);
  expect(() => api.mine(), throwsA(isA<SharedTracesException>().having((e) => e.statusCode, 'statusCode', 401)));
});
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

`flutter test test/services/shared_traces_api_client_test.dart`
Attendu : ÉCHEC, fichiers introuvables.

- [ ] **Step 3: Écrire les modèles et le client**

`lib/models/shared_trace.dart` — les deux énumérations avec leur correspondance vers les valeurs du serveur (`4x4` n'est pas un identifiant Dart valide, d'où `quatreQuatre`), `SharedTraceSummary` et `SharedTraceDetail` avec leurs `fromJson`, et un libellé français pour l'affichage (`String get libelle` : « Moto », « 4x4 », « Moto et 4x4 » ; « Facile », « Moyen », « Difficile »).

`lib/services/shared_traces_api_client.dart` — un client sur le modèle de `AccountApiClient` (le lire d'abord pour reprendre sa gestion d'erreurs et son style) : `_headers()` qui refuse tôt si le jeton est absent, une méthode privée `_traduire(int code, String corps)` qui rend le message affichable :

| Code | Message |
|---|---|
| 401 | `Ta session a expiré, reconnecte-toi.` |
| 403 | `Vérifie ton adresse e-mail avant de publier.` |
| 404 | `Cette trace n'est plus disponible.` |
| 409 | `Tu as déjà signalé cette trace.` |
| 410 | `Le fichier de cette trace est introuvable.` |
| 413 | `Cette trace est trop lourde pour être publiée.` |
| 429 | `Quota de publications atteint, réessaie demain.` |
| autre | `Le serveur n'a pas répondu correctement (code).` |

- [ ] **Step 4: Lancer les tests**

`flutter test test/services/shared_traces_api_client_test.dart`
Attendu : SUCCÈS, les six tests.

- [ ] **Step 5: Commit**

```bash
git add lib/models/shared_trace.dart lib/services/shared_traces_api_client.dart test/services/shared_traces_api_client_test.dart
git commit -m "feat(partage): modeles et client HTTP du catalogue de traces"
```

---

### Task 17: Recadrage d'une trace avant publication

**Files:**
- Create: `lib/services/trace_crop_service.dart`
- Test: `test/services/trace_crop_service_test.dart`

**Interfaces:**
- Consumes: `RidePoint`, `Ride` (`lib/models/ride.dart`), `GpxService.exportToGpx`, `RideExportService.toTraceModel`.
- Produces: `TraceCropService.cropToGpx(Ride ride, List<RidePoint> points, {required int startIndex, required int endIndex, required String name, String? description})` → `String` (GPX du seul intervalle retenu, bornes comprises) ; `TraceCropService.distanceOf(List<RidePoint> points, int startIndex, int endIndex)` → mètres, pour l'affichage en direct sous les curseurs. Lève `ArgumentError` si `endIndex <= startIndex` ou si les bornes sortent de la liste.

- [ ] **Step 1: Écrire le test qui échoue**

`test/services/trace_crop_service_test.dart` :

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:moto_offroad/models/ride.dart';
import 'package:moto_offroad/services/trace_crop_service.dart';

List<RidePoint> pointsFactices(int n) => List.generate(n, (i) => RidePoint(
      rideId: 'r1', seq: i, segment: 0,
      lat: 43.60 + i * 0.001, lng: 1.44, altitude: 150 + i.toDouble(), speedKmh: 30,
      timestamp: DateTime(2026, 9, 1, 8, i),
    ));

final ride = Ride(
  id: 'r1', name: 'Sortie du dimanche', startedAt: DateTime(2026, 9, 1, 8),
  source: RideSource.recorded, status: RideStatus.finished, stats: RideStats.empty,
);

test('le GPX publie ne contient que l intervalle retenu', () {
  final gpx = TraceCropService.cropToGpx(ride, pointsFactices(10),
      startIndex: 3, endIndex: 6, name: 'Boucle publiee');

  expect('lat="'.allMatches(gpx).length, 4); // 3, 4, 5 et 6
  expect(gpx.contains('43.603'), isTrue);
  expect(gpx.contains('43.600'), isFalse); // le depart devant chez soi a saute
  expect(gpx.contains('43.609'), isFalse);
  expect(gpx.contains('Boucle publiee'), isTrue);
});

test('recadrer ne touche pas les points d origine', () {
  final points = pointsFactices(10);
  TraceCropService.cropToGpx(ride, points, startIndex: 2, endIndex: 5, name: 'B');
  expect(points.length, 10);
  expect(points.first.lat, 43.60);
});

test('des bornes incoherentes sont refusees', () {
  final points = pointsFactices(10);
  expect(() => TraceCropService.cropToGpx(ride, points, startIndex: 5, endIndex: 5, name: 'B'),
      throwsArgumentError);
  expect(() => TraceCropService.cropToGpx(ride, points, startIndex: -1, endIndex: 4, name: 'B'),
      throwsArgumentError);
  expect(() => TraceCropService.cropToGpx(ride, points, startIndex: 0, endIndex: 10, name: 'B'),
      throwsArgumentError);
});

test('la distance de l intervalle est plus courte que celle de la trace entiere', () {
  final points = pointsFactices(10);
  final totale = TraceCropService.distanceOf(points, 0, 9);
  final partielle = TraceCropService.distanceOf(points, 3, 6);
  expect(partielle, lessThan(totale));
  expect(partielle, greaterThan(0));
});
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

`flutter test test/services/trace_crop_service_test.dart`
Attendu : ÉCHEC, `lib/services/trace_crop_service.dart` introuvable.

- [ ] **Step 3: Écrire le service**

```dart
import 'package:latlong2/latlong.dart';
import '../models/ride.dart';
import '../models/trace.dart';
import 'gpx_service.dart';

// Une sortie enregistree commence presque toujours devant chez son auteur.
// Le recadrage produit une copie publiee amputee de ce debut, sans jamais
// toucher a la sortie d'origine, qui reste entiere dans les Sorties.
class TraceCropService {
  static const _distance = Distance();

  static List<RidePoint> _intervalle(List<RidePoint> points, int startIndex, int endIndex) {
    if (startIndex < 0 || endIndex >= points.length || endIndex <= startIndex) {
      throw ArgumentError('bornes de recadrage invalides: $startIndex..$endIndex sur ${points.length} points');
    }
    return points.sublist(startIndex, endIndex + 1);
  }

  static String cropToGpx(
    Ride ride,
    List<RidePoint> points, {
    required int startIndex,
    required int endIndex,
    required String name,
    String? description,
  }) {
    final retenus = _intervalle(points, startIndex, endIndex);
    final trace = TraceModel(
      id: ride.id,
      name: name,
      description: description,
      date: retenus.first.timestamp,
      source: ride.source.name,
      points: retenus
          .map((p) => TracePoint(
                position: p.position,
                elevation: p.altitude,
                time: p.timestamp,
                speed: p.speedKmh,
              ))
          .toList(),
    );
    return GpxService().exportToGpx(trace);
  }

  static double distanceOf(List<RidePoint> points, int startIndex, int endIndex) {
    final retenus = _intervalle(points, startIndex, endIndex);
    double total = 0;
    for (int i = 1; i < retenus.length; i++) {
      total += _distance(retenus[i - 1].position, retenus[i].position);
    }
    return total;
  }
}
```

- [ ] **Step 4: Lancer les tests**

`flutter test test/services/trace_crop_service_test.dart`
Attendu : SUCCÈS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/trace_crop_service.dart test/services/trace_crop_service_test.dart
git commit -m "feat(partage): recadrage d une trace avant publication"
```

---

### Task 18: Provider du catalogue

**Files:**
- Create: `lib/providers/shared_traces_provider.dart`
- Test: `test/providers/shared_traces_provider_test.dart`

**Interfaces:**
- Consumes: `SharedTracesApiClient`, `SharedTraceSummary` (Task 16).
- Produces: `SharedTracesProvider extends ChangeNotifier` avec `List<SharedTraceSummary> get traces`, `bool get isLoading`, `String? get error`, `LatLng? get reference`, `String? get referenceLabel`, `double get radiusKm`, `TraceVehicle? get vehicle`, `TraceDifficulty? get difficulty`, `String get query` ; et les méthodes `setReference(LatLng point, {String? label})`, `setRadius(double km)`, `setVehicle(TraceVehicle?)`, `setDifficulty(TraceDifficulty?)`, `setQuery(String)`, `refresh()`, `loadMore()`. Chaque `set*` relance `refresh()`. `refresh()` sans référence ne lance aucune requête et pose `error = 'Position inconnue'`.

- [ ] **Step 1: Écrire le test qui échoue**

```dart
class _ApiFactice extends SharedTracesApiClient {
  _ApiFactice() : super(client: MockClient((_) async => http.Response('', 200)),
                        readToken: () async => 'jeton');
  final List<Map<String, Object?>> appels = [];
  List<SharedTraceSummary> reponse = [];
  Object? erreur;

  @override
  Future<List<SharedTraceSummary>> list({required double lat, required double lng,
      double radiusKm = 50, TraceVehicle? vehicle, TraceDifficulty? difficulty,
      String? query, int offset = 0}) async {
    appels.add({'lat': lat, 'rayon': radiusKm, 'engin': vehicle, 'depuis': offset});
    if (erreur != null) throw erreur!;
    return reponse;
  }
}

test('sans point de reference, aucune requete ne part', () async {
  final api = _ApiFactice();
  final provider = SharedTracesProvider(api);
  await provider.refresh();
  expect(api.appels, isEmpty);
  expect(provider.error, isNotNull);
});

test('poser la reference declenche le chargement', () async {
  final api = _ApiFactice()..reponse = [resume('t1')];
  final provider = SharedTracesProvider(api);
  await provider.setReference(const LatLng(43.6, 1.44), label: 'Ma position');
  expect(api.appels.single['lat'], 43.6);
  expect(provider.traces.single.id, 't1');
  expect(provider.referenceLabel, 'Ma position');
});

test('changer le rayon relance la recherche depuis le debut', () async {
  final api = _ApiFactice()..reponse = [resume('t1')];
  final provider = SharedTracesProvider(api);
  await provider.setReference(const LatLng(43.6, 1.44));
  await provider.setRadius(25);
  expect(api.appels.last['rayon'], 25);
  expect(api.appels.last['depuis'], 0);
});

test('loadMore ajoute a la suite sans effacer', () async {
  final api = _ApiFactice()..reponse = [resume('t1')];
  final provider = SharedTracesProvider(api);
  await provider.setReference(const LatLng(43.6, 1.44));
  api.reponse = [resume('t2')];
  await provider.loadMore();
  expect(provider.traces.map((t) => t.id), ['t1', 't2']);
  expect(api.appels.last['depuis'], 1);
});

test('une panne reseau laisse un message et vide le chargement', () async {
  final api = _ApiFactice()..erreur = const SharedTracesException(503, 'Le serveur ne repond pas');
  final provider = SharedTracesProvider(api);
  await provider.setReference(const LatLng(43.6, 1.44));
  expect(provider.isLoading, isFalse);
  expect(provider.error, contains('serveur'));
});
```

Écrire l'aide `SharedTraceSummary resume(String id)` en tête du fichier de test.

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

`flutter test test/providers/shared_traces_provider_test.dart`
Attendu : ÉCHEC, provider introuvable.

- [ ] **Step 3: Écrire le provider**

Suivre la forme de `lib/providers/fuel_poi_provider.dart` (déjà un provider de liste distante avec état de chargement et message d'erreur) : champs privés, `notifyListeners()` après chaque changement d'état, `try/catch` autour de l'appel réseau qui pose `_error = e is SharedTracesException ? e.message : 'Réseau indisponible'` et remet `_isLoading = false` dans un `finally`.

- [ ] **Step 4: Lancer les tests**

`flutter test test/providers/shared_traces_provider_test.dart`
Attendu : SUCCÈS.

- [ ] **Step 5: Commit**

```bash
git add lib/providers/shared_traces_provider.dart test/providers/shared_traces_provider_test.dart
git commit -m "feat(partage): provider du catalogue, reference, rayon et filtres"
```

---

### Task 19: Le volet « Partagées » dans l'onglet Sorties

**Files:**
- Create: `lib/screens/rides/shared_traces_panel.dart`
- Modify: `lib/screens/rides/rides_screen.dart`, `lib/main.dart` (déclaration du provider)
- Test: `test/screens/shared_traces_panel_test.dart`

**Interfaces:**
- Consumes: `SharedTracesProvider` (Task 18).
- Produces: `SharedTracesPanel` (widget sans état propre au-delà des contrôleurs de saisie), affiché par `RidesScreen` sous un `SegmentedButton` « Mes sorties » / « Partagées ». La liste locale existante devient `MyRidesPanel` dans le même fichier `rides_screen.dart`, sans changement de comportement.

- [ ] **Step 1: Écrire le test qui échoue**

```dart
testWidgets('l onglet Sorties propose les deux volets et bascule', (tester) async {
  await tester.pumpWidget(appDeTest()); // aide locale : MaterialApp + providers factices
  expect(find.text('Mes sorties'), findsOneWidget);
  expect(find.text('Partagées'), findsOneWidget);

  await tester.tap(find.text('Partagées'));
  await tester.pumpAndSettle();
  expect(find.byType(SharedTracesPanel), findsOneWidget);
});

testWidgets('le volet partage affiche les traces avec leur distance et leur compteur', (tester) async {
  final provider = SharedTracesProvider(_ApiFactice()..reponse = [
    resume('t1', nom: 'Boucle du Sidobre', distanceFromRefM: 11000, downloadCount: 7),
  ]);
  await provider.setReference(const LatLng(43.6, 1.44));
  await tester.pumpWidget(panneauDeTest(provider));
  await tester.pumpAndSettle();

  expect(find.text('Boucle du Sidobre'), findsOneWidget);
  expect(find.textContaining('11 km'), findsOneWidget);
  expect(find.textContaining('7'), findsWidgets);
});

testWidgets('changer le rayon relance la recherche', (tester) async {
  final api = _ApiFactice()..reponse = [];
  final provider = SharedTracesProvider(api);
  await provider.setReference(const LatLng(43.6, 1.44));
  await tester.pumpWidget(panneauDeTest(provider));
  await tester.pumpAndSettle();

  await tester.tap(find.text('50 km'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('25 km').last);
  await tester.pumpAndSettle();

  expect(api.appels.last['rayon'], 25);
});

testWidgets('sans resultat, le volet le dit au lieu de rester vide', (tester) async {
  final provider = SharedTracesProvider(_ApiFactice()..reponse = []);
  await provider.setReference(const LatLng(43.6, 1.44));
  await tester.pumpWidget(panneauDeTest(provider));
  await tester.pumpAndSettle();
  expect(find.textContaining('Aucune trace'), findsOneWidget);
});
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

`flutter test test/screens/shared_traces_panel_test.dart`
Attendu : ÉCHEC, `SharedTracesPanel` introuvable.

- [ ] **Step 3: Écrire le volet**

Dans `rides_screen.dart` : extraire le corps actuel dans un widget `MyRidesPanel` (même contenu, aucun changement), puis un `SegmentedButton<int>` en haut du `Scaffold` qui bascule entre `MyRidesPanel` et `SharedTracesPanel`.

`SharedTracesPanel` affiche dans l'ordre : une ligne de référence (« Autour de ma position » ou le lieu choisi, avec un bouton pour en choisir un autre), un `DropdownButton` de rayon (10, 25, 50, 100, 200 km), deux `FilterChip` de filtre (engin, difficulté), un champ de recherche, puis la liste. Chaque entrée : nom, auteur, `12,4 km` de longueur, difficulté, engin, `à 11 km`, et le nombre de téléchargements avec l'icône `Icons.download_outlined`. État vide explicite : « Aucune trace partagée dans ce rayon. »

Le point de référence par défaut vient de la dernière position connue (`LocationService`), sans jamais demander une nouvelle permission ici : le mur d'inscription du lot A a déjà réglé cette question, et une demande de permission dans un onglet de liste serait une régression du correctif I7.

Déclarer `SharedTracesProvider` dans `lib/main.dart` à côté des autres, en lui passant un `SharedTracesApiClient(readToken: () => AccountStorage().readToken())`.

- [ ] **Step 4: Lancer les tests**

`flutter test test/screens/shared_traces_panel_test.dart && flutter test`
Attendu : SUCCÈS, y compris les tests existants de l'écran Sorties.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/rides/shared_traces_panel.dart lib/screens/rides/rides_screen.dart lib/main.dart test/screens/shared_traces_panel_test.dart
git commit -m "feat(partage): volet Partagees dans l onglet Sorties"
```

---

### Task 20: Fiche d'une trace partagée et téléchargement

**Files:**
- Create: `lib/screens/rides/shared_trace_detail_screen.dart`, `lib/services/shared_trace_importer.dart`
- Modify: `lib/app/router.dart`
- Test: `test/services/shared_trace_importer_test.dart`, `test/screens/shared_trace_detail_screen_test.dart`

**Interfaces:**
- Consumes: `SharedTracesApiClient.detail` et `.downloadGpx` (Task 16), `RideRepository` (Task 15), `GpxService.loadFromString`.
- Produces: `SharedTraceImporter(RideRepository repo)` avec `Future<Ride> import(SharedTraceDetail fiche, String gpx)` — crée une sortie `RideSource.imported`, `RideStatus.finished`, `sharedTraceId` renseigné, points insérés en un seul segment, statistiques calculées par `RideStats.fromPoints`. Route `/traces/:id` vers `SharedTraceDetailScreen`.

- [ ] **Step 1: Écrire le test qui échoue**

Ce fichier de test est neuf : ouvrir la base sur le modèle de `test/services/ride_repository_test.dart`, avec `sqfliteFfiInit()` puis un `setUp` qui pose `db` et `repo` :

```dart
late Database db;
late RideRepository repo;

setUp(() async {
  db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(version: RideDatabase.schemaVersion, onCreate: RideDatabase.onCreate),
  );
  repo = RideRepository(db);
});
tearDown(() async => db.close());

test('l import cree une sortie importee, rattachee a la trace partagee', () async {
  final importer = SharedTraceImporter(repo);

  final ride = await importer.import(ficheFactice(id: 't42', nom: 'Boucle du Sidobre'), gpxFactice());

  expect(ride.source, RideSource.imported);
  expect(ride.status, RideStatus.finished);
  expect(ride.sharedTraceId, 't42');
  expect(ride.name, 'Boucle du Sidobre');
  final points = await repo.pointsOf(ride.id);
  expect(points.length, 3);
  expect(points.every((p) => p.segment == 0), isTrue);
  expect(ride.stats.distanceMeters, greaterThan(0));
});

test('deux imports de la meme trace font deux sorties distinctes', () async {
  final importer = SharedTraceImporter(repo);
  final a = await importer.import(ficheFactice(id: 't42'), gpxFactice());
  final b = await importer.import(ficheFactice(id: 't42'), gpxFactice());
  expect(a.id, isNot(b.id));
  expect((await repo.listRides()).length, 2);
});

test('un GPX illisible remonte une erreur au lieu de creer une sortie vide', () async {
  final importer = SharedTraceImporter(repo);
  await expectLater(() => importer.import(ficheFactice(), 'pas du xml <<<'), throwsA(isA<FormatException>()));
  expect(await repo.listRides(), isEmpty);
});
```

Et pour l'écran :

```dart
testWidgets('la fiche affiche description, auteur, compteur et les deux boutons', (tester) async {
  await tester.pumpWidget(ficheDeTest(ficheFactice(nom: 'Boucle', description: 'Deux gues', downloadCount: 7)));
  await tester.pumpAndSettle();
  expect(find.text('Boucle'), findsOneWidget);
  expect(find.text('Deux gues'), findsOneWidget);
  expect(find.textContaining('7'), findsWidgets);
  expect(find.text('Télécharger'), findsOneWidget);
  expect(find.text('Signaler'), findsOneWidget);
});

testWidgets('apres telechargement, le bouton dit que la trace est dans les sorties', (tester) async {
  await tester.pumpWidget(ficheDeTest(ficheFactice()));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Télécharger'));
  await tester.pumpAndSettle();
  expect(find.textContaining('Dans tes sorties'), findsOneWidget);
});
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

`flutter test test/services/shared_trace_importer_test.dart test/screens/shared_trace_detail_screen_test.dart`
Attendu : ÉCHEC, fichiers introuvables.

- [ ] **Step 3: Écrire l'import et l'écran**

`SharedTraceImporter.import` : `GpxService().loadFromString(gpx)` → si `null`, lever `const FormatException('GPX illisible')` **avant** toute écriture en base ; sinon construire les `RidePoint` (`seq` incrémental, `segment: 0`, `timestamp` du GPX ou, à défaut, `fiche.recordedAt` décalé d'une seconde par point pour rester croissant), calculer `RideStats.fromPoints`, insérer la sortie puis les points.

`SharedTraceDetailScreen` : `FutureBuilder` sur `detail(id)`, aperçu `FlutterMap` + `PolylineLayer` sur `fiche.preview` (même construction que le tracé de guidage ajouté le 6 septembre dans `map_screen.dart`), les statistiques, la description, l'auteur, le compteur, puis les deux boutons. Le bouton **Télécharger** enchaîne `downloadGpx` → `SharedTraceImporter.import` → `RidesProvider.refresh()` et devient « Dans tes sorties » une fois fait. Un échec affiche le message de `SharedTracesException` dans une `SnackBar`.

Déclarer la route dans `lib/app/router.dart` sur le modèle des routes existantes.

- [ ] **Step 4: Lancer les tests**

`flutter test test/services/shared_trace_importer_test.dart test/screens/shared_trace_detail_screen_test.dart && flutter test`
Attendu : SUCCÈS.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/rides/shared_trace_detail_screen.dart lib/services/shared_trace_importer.dart lib/app/router.dart test/services/shared_trace_importer_test.dart test/screens/shared_trace_detail_screen_test.dart
git commit -m "feat(partage): fiche d une trace partagee et telechargement dans les sorties"
```

---

### Task 21: Signaler une trace depuis l'application

**Files:**
- Create: `lib/screens/rides/report_trace_sheet.dart`
- Modify: `lib/screens/rides/shared_trace_detail_screen.dart`
- Test: `test/screens/report_trace_sheet_test.dart`

**Interfaces:**
- Consumes: `SharedTracesApiClient.report` (Task 16).
- Produces: `showReportTraceSheet(BuildContext, {required String traceId, required SharedTracesApiClient api})` → `Future<bool>` (vrai si un signalement est parti). Motifs affichés : « Terrain privé », « Dangereux », « Doublon », « Contenu inapproprié », « Autre », correspondant aux valeurs serveur `terrain_prive`, `dangereux`, `doublon`, `inapproprie`, `autre`, plus un champ libre facultatif.

- [ ] **Step 1: Écrire le test qui échoue**

```dart
testWidgets('choisir un motif envoie le signalement au serveur', (tester) async {
  late Map<String, Object?> envoye;
  final api = _ApiFactice()..onReport = (id, reason, detail) { envoye = {'id': id, 'reason': reason}; };
  await tester.pumpWidget(feuilleDeTest(api, 't42'));
  await tester.tap(find.text('Signaler'));
  await tester.pumpAndSettle();

  await tester.tap(find.text('Terrain privé'));
  await tester.tap(find.text('Envoyer'));
  await tester.pumpAndSettle();

  expect(envoye['id'], 't42');
  expect(envoye['reason'], 'terrain_prive');
});

testWidgets('sans motif choisi, le bouton Envoyer reste inactif', (tester) async {
  await tester.pumpWidget(feuilleDeTest(_ApiFactice(), 't42'));
  await tester.tap(find.text('Signaler'));
  await tester.pumpAndSettle();
  final bouton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Envoyer'));
  expect(bouton.onPressed, isNull);
});

testWidgets('un signalement deja envoye affiche le message du serveur', (tester) async {
  final api = _ApiFactice()..erreurReport = const SharedTracesException(409, 'Tu as déjà signalé cette trace.');
  await tester.pumpWidget(feuilleDeTest(api, 't42'));
  await tester.tap(find.text('Signaler'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Dangereux'));
  await tester.tap(find.text('Envoyer'));
  await tester.pumpAndSettle();
  expect(find.textContaining('déjà signalé'), findsOneWidget);
});
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

`flutter test test/screens/report_trace_sheet_test.dart`
Attendu : ÉCHEC, feuille introuvable.

- [ ] **Step 3: Écrire la feuille**

`showModalBottomSheet` avec une liste de `RadioListTile<String>` (valeurs serveur), un `TextField` facultatif, un `FilledButton` « Envoyer » désactivé tant qu'aucun motif n'est choisi. Succès : fermeture et `SnackBar` « Merci, le signalement est parti. » Échec : le message de `SharedTracesException` affiché dans la feuille, qui reste ouverte.

- [ ] **Step 4: Lancer les tests**

`flutter test test/screens/report_trace_sheet_test.dart && flutter test`
Attendu : SUCCÈS.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/rides/report_trace_sheet.dart lib/screens/rides/shared_trace_detail_screen.dart test/screens/report_trace_sheet_test.dart
git commit -m "feat(partage): signalement d une trace depuis l application"
```

---

### Task 22: Écran de publication

**Files:**
- Create: `lib/screens/rides/publish_trace_screen.dart`
- Modify: `lib/screens/rides/ride_detail_screen.dart`, `lib/app/router.dart`
- Test: `test/screens/publish_trace_screen_test.dart`

**Interfaces:**
- Consumes: `TraceCropService` (Task 17), `SharedTracesApiClient.publish` (Task 16), `RidesProvider.pointsOf`.
- Produces: `PublishTraceScreen(rideId)` sur la route `/sorties/:id/publier`. Bouton **Publier** sur `RideDetailScreen`, masqué quand `ride.sharedTraceId != null`. La préférence `SharedPreferences` `partage_avertissement_vu` (booléen) retient si l'avertissement de première publication a déjà été montré.

- [ ] **Step 1: Écrire le test qui échoue**

```dart
testWidgets('une sortie telechargee ne propose pas de la republier', (tester) async {
  await tester.pumpWidget(ficheSortieDeTest(rideFactice(sharedTraceId: 't42')));
  await tester.pumpAndSettle();
  expect(find.text('Publier'), findsNothing);
});

testWidgets('une sortie enregistree propose de la publier', (tester) async {
  await tester.pumpWidget(ficheSortieDeTest(rideFactice()));
  await tester.pumpAndSettle();
  expect(find.text('Publier'), findsOneWidget);
});

testWidgets('l avertissement de premiere publication apparait une seule fois', (tester) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(ecranPublicationDeTest(rideFactice(), pointsFactices(10)));
  await tester.pumpAndSettle();
  expect(find.textContaining('devant chez toi'), findsOneWidget);
  await tester.tap(find.text('Compris'));
  await tester.pumpAndSettle();

  await tester.pumpWidget(ecranPublicationDeTest(rideFactice(), pointsFactices(10)));
  await tester.pumpAndSettle();
  expect(find.textContaining('devant chez toi'), findsNothing);
});

testWidgets('publier envoie la trace recadree et la fiche saisie', (tester) async {
  SharedPreferences.setMockInitialValues({'partage_avertissement_vu': true});
  final api = _ApiFactice();
  await tester.pumpWidget(ecranPublicationDeTest(rideFactice(), pointsFactices(10), api: api));
  await tester.pumpAndSettle();

  await tester.enterText(find.byKey(const Key('champ_description')), 'Pistes forestieres, deux gues');
  await tester.tap(find.text('4x4'));
  await tester.tap(find.text('Difficile'));
  await tester.drag(find.byKey(const Key('curseur_debut')), const Offset(60, 0));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Publier'));
  await tester.pumpAndSettle();

  expect(api.publiees.single['vehicle'], TraceVehicle.quatreQuatre);
  expect(api.publiees.single['difficulty'], TraceDifficulty.difficile);
  expect(api.publiees.single['description'], 'Pistes forestieres, deux gues');
  // Le depart a ete rogne : le premier point d'origine n'est plus dans le GPX.
  expect((api.publiees.single['gpx'] as String).contains('43.600'), isFalse);
});

testWidgets('une description vide bloque la publication', (tester) async {
  SharedPreferences.setMockInitialValues({'partage_avertissement_vu': true});
  final api = _ApiFactice();
  await tester.pumpWidget(ecranPublicationDeTest(rideFactice(), pointsFactices(10), api: api));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Publier'));
  await tester.pumpAndSettle();
  expect(api.publiees, isEmpty);
  expect(find.textContaining('description'), findsWidgets);
});
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

`flutter test test/screens/publish_trace_screen_test.dart`
Attendu : ÉCHEC, écran introuvable.

- [ ] **Step 3: Écrire l'écran**

Structure de haut en bas :

1. L'aperçu de la trace (`FlutterMap` + `PolylineLayer`), sur lequel la portion retenue est dessinée en plein et les extrémités rognées en gris.
2. Deux `Slider` (`Key('curseur_debut')`, `Key('curseur_fin')`) bornés à `0..points.length - 1`, avec sous eux la longueur publiée recalculée par `TraceCropService.distanceOf`. Le curseur de début ne peut pas dépasser celui de fin.
3. Les champs : nom (pré-rempli avec `ride.name`), description (`Key('champ_description')`, obligatoire), auteur (pré-rempli avec le nom du profil pilote lu dans `SettingsProvider`), `SegmentedButton` engin (Moto / 4x4 / Moto et 4x4), `SegmentedButton` difficulté (Facile / Moyen / Difficile).
4. **La case d'acceptation des conditions**, obligatoire, non pré-cochée :
   « J'accepte les conditions de publication » avec un lien qui ouvre le texte
   (`docs/legal/conditions-publication-traces.md`, embarqué en ressource), et
   sous elle, en petit, la phrase qui compte : « Ma trace restera au catalogue
   même si je supprime mon compte. » Le bouton Publier reste inactif tant que
   la case n'est pas cochée, et l'appel envoie `licenceVersion: '1.0'` au
   serveur, qui refuse la publication sans lui (tâche 13B).
5. Le bouton **Publier**, qui valide la description non vide, appelle `TraceCropService.cropToGpx` puis `api.publish`, et revient à l'écran précédent avec une `SnackBar` « Ta trace est publiée. » Un échec affiche le message de `SharedTracesException` sans quitter l'écran, pour ne pas perdre la saisie.

L'avertissement de première publication est un `AlertDialog` affiché au premier `build` si `partage_avertissement_vu` est absent : « Ta trace commence peut-être devant chez toi. Fais glisser le curseur de début pour publier seulement la partie qui t'intéresse. » avec un seul bouton « Compris » qui pose la préférence.

Dans `ride_detail_screen.dart`, ajouter le bouton `Publier` à côté de l'export GPX existant, `if (ride.sharedTraceId == null)`.

- [ ] **Step 4: Lancer les tests**

`flutter test test/screens/publish_trace_screen_test.dart && flutter test`
Attendu : SUCCÈS.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/rides/publish_trace_screen.dart lib/screens/rides/ride_detail_screen.dart lib/app/router.dart test/screens/publish_trace_screen_test.dart
git commit -m "feat(partage): ecran de publication avec recadrage et fiche"
```

---

### Task 23: Mes publications

**Files:**
- Create: `lib/screens/rides/my_publications_screen.dart`
- Modify: `lib/screens/rides/shared_traces_panel.dart`, `lib/app/router.dart`
- Test: `test/screens/my_publications_screen_test.dart`

**Interfaces:**
- Consumes: `SharedTracesApiClient.mine`, `.update`, `.unpublish` (Task 16).
- Produces: `MyPublicationsScreen` sur la route `/traces/mes-publications`, atteignable depuis le volet Partagées. Chaque entrée : nom, nombre de téléchargements, état (publiée ou retirée avec son motif), et deux actions — **Modifier la fiche** et **Dépublier** (avec confirmation).

- [ ] **Step 1: Écrire le test qui échoue**

```dart
testWidgets('mes publications montrent le compteur et l etat retire', (tester) async {
  final api = _ApiFactice()..miennes = [
    resume('t1', nom: 'Boucle', downloadCount: 12),
    resume('t2', nom: 'Crete', hidden: true, hiddenReason: 'terrain prive'),
  ];
  await tester.pumpWidget(mesPublicationsDeTest(api));
  await tester.pumpAndSettle();

  expect(find.text('Boucle'), findsOneWidget);
  expect(find.textContaining('12'), findsWidgets);
  expect(find.textContaining('Retirée du partage'), findsOneWidget);
  expect(find.textContaining('terrain prive'), findsOneWidget);
});

testWidgets('modifier la fiche envoie seulement les champs changes', (tester) async {
  final api = _ApiFactice()..miennes = [resume('t1', nom: 'Boucle')];
  await tester.pumpWidget(mesPublicationsDeTest(api));
  await tester.pumpAndSettle();

  await tester.tap(find.text('Modifier la fiche'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('champ_description')), 'Praticable en ete seulement');
  await tester.tap(find.text('Enregistrer'));
  await tester.pumpAndSettle();

  expect(api.modifiees.single['id'], 't1');
  expect(api.modifiees.single['description'], 'Praticable en ete seulement');
  expect(api.modifiees.single.containsKey('name'), isFalse);
});

testWidgets('depublier demande confirmation avant d appeler le serveur', (tester) async {
  final api = _ApiFactice()..miennes = [resume('t1', nom: 'Boucle')];
  await tester.pumpWidget(mesPublicationsDeTest(api));
  await tester.pumpAndSettle();

  await tester.tap(find.text('Dépublier'));
  await tester.pumpAndSettle();
  expect(api.depubliees, isEmpty); // rien tant que la confirmation n'est pas donnee

  await tester.tap(find.text('Dépublier définitivement'));
  await tester.pumpAndSettle();
  expect(api.depubliees, ['t1']);
});
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

`flutter test test/screens/my_publications_screen_test.dart`
Attendu : ÉCHEC, écran introuvable.

- [ ] **Step 3: Écrire l'écran**

`FutureBuilder` sur `api.mine()`, liste de `Card`. La modification ouvre un `showModalBottomSheet` avec les mêmes champs que la publication moins le recadrage (le GPX ne change jamais après publication) et n'envoie que les champs réellement modifiés. La dépublication ouvre un `AlertDialog` dont le bouton destructeur est libellé « Dépublier définitivement », et rappelle que les riders qui ont déjà téléchargé la trace la gardent.

- [ ] **Step 4: Lancer les tests**

`flutter test test/screens/my_publications_screen_test.dart && flutter test`
Attendu : SUCCÈS.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/rides/my_publications_screen.dart lib/screens/rides/shared_traces_panel.dart lib/app/router.dart test/screens/my_publications_screen_test.dart
git commit -m "feat(partage): ecran de mes publications, modification et depublication"
```

---

### Task 24: Déploiement, vérification sur appareil réel, fusion

**Files:**
- Modify: `pubspec.yaml` (version), `docs/superpowers/plans/2026-09-09-lotB-partage-traces.md` (cases cochées)
- Aucun test nouveau : cette tâche vérifie ce que les tests ne peuvent pas voir.

**Interfaces:**
- Consumes: tâches 1 à 23.
- Produces: le serveur déployé, un build TestFlight et un APK contenant le lot B, et un compte rendu de ce qui a été vérifié sur le téléphone.

- [ ] **Step 1: Suite complète des deux dépôts**

Serveur : `docker run --rm -v "$PWD":/app -w /app node:20 sh -c "npm install && npm test"`
Application : `flutter test && flutter analyze`
Attendu : tout passe ; `flutter analyze` ne signale que `lib/config/firebase_options.dart`, exception connue.

- [ ] **Step 2: Déployer le serveur**

Depuis le dépôt serveur : `bash deploy.sh "lot B — catalogue de traces partagees"`.
Puis vérifier sur le Hetzner que le dossier existe et que les routes répondent :

```sh
ssh drone31 'ls -la /root/moto-tracker/data/traces'
curl -s -o /dev/null -w '%{http_code}\n' 'https://motooffroad.duckdns.org/api/traces?lat=43.6&lng=1.44'   # attendu 401
curl -s -o /dev/null -w '%{http_code}\n' 'https://motooffroad.duckdns.org/api/admin/traces'                # attendu 403
```

- [ ] **Step 3: Publier les applications**

Porter `pubspec.yaml` à la version suivante (`1.9.0+24` si rien n'a bougé depuis `1.8.0+23`), pousser sur `main` — l'APK Android se construit tout seul — puis déclencher manuellement le workflow « Publier sur TestFlight ».

**Rappel des deux gestes manuels obligatoires dans App Store Connect**, sans lesquels le build reste invisible : déclarer « Aucun algorithme de chiffrement » (conformité export), et assigner le build au groupe « Testeurs internes » — en retirant d'abord l'assignation de l'ancien build, faute de quoi la case reste grisée sans message d'erreur.

- [ ] **Step 4: Vérifier sur le téléphone**

À faire réellement, dans cet ordre, sur l'appareil de l'utilisateur :

1. publier une sortie enregistrée, curseur de début déplacé, et vérifier que le début est bien absent du tracé publié ;
2. ouvrir le volet Partagées : la trace apparaît, la distance affichée correspond ;
3. changer le rayon à 10 km puis 200 km et voir la liste changer ;
4. télécharger la trace depuis un second compte, vérifier qu'elle arrive dans les Sorties et qu'elle s'ouvre en guidage ;
5. vérifier que le compteur affiche 1, et qu'un second téléchargement ne le fait pas monter ;
6. signaler la trace, puis la retrouver dans `GET /api/admin/reports` ;
7. la masquer par la ligne de commande admin, vérifier qu'elle disparaît du catalogue **et** qu'elle reste dans les Sorties de celui qui l'a téléchargée ;
8. la démasquer, vérifier qu'elle revient avec son compteur intact.

Tout écart constaté ici est un défaut à corriger avant la fusion, pas une remarque à noter pour plus tard.

- [ ] **Step 5: Fusionner**

Une fois la vérification passée, fusionner la branche dans `main` sur les deux dépôts et pousser. Vérifier après fusion que `flutter test` et la suite serveur passent toujours sur `main` — le lot A avait produit cinq conflits réels malgré une simulation `git merge-tree` qui n'en montrait aucun, tous de simple juxtaposition, avec le piège de l'accolade fermante partagée entre deux ajouts en fin de fichier.

---

## Revue du plan

**Couverture de la spec, section par section :**

| Section de la spec | Tâches |
|---|---|
| 4. Modèle de données | 2 |
| 5. Interface HTTP — publication | 5 |
| 5. Interface HTTP — liste | 6 |
| 5. Interface HTTP — fiche et mes publications | 7 |
| 5. Interface HTTP — téléchargement et compteur | 8 |
| 5. Interface HTTP — modification et dépublication | 9 |
| 5. Interface HTTP — signalement | 10 |
| 5. Interface HTTP — administration | 11 |
| 6. Fichiers et sauvegarde | 4, 12 |
| 7.1 Publier | 17, 22 |
| 7.2 Découvrir | 18, 19 |
| 7.3 Télécharger | 15, 20 |
| Signalement dans l'app | 21 |
| Mes publications | 23 |
| 8. Dette du lot A | 13 (serveur), 14 (application) |
| 9. Sécurité et garde-fous | 1 (extraction), 5 (quotas, taille), 9 (404 plutôt que 403), 11 (clé admin) |
| 10. Exploitation avant le lot C | 11, 24 |
| 11. Tests | chaque tâche, et 24 pour l'appareil réel |
| 13. Critères d'acceptation | 24, étape 4 |
