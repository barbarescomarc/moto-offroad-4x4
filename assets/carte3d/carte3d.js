// Reconnaissance 3D — MapLibre GL JS dans une vue web.
// Le relief en volume n'existe que dans la version web du moteur : MapLibre
// Native (iOS/Android) ne l'implémente pas. Cet écran sert à préparer et à
// observer un terrain, jamais à rouler — l'enregistrement, le guidage et le
// SOS restent du côté Flutter, sur la carte 2D.

const geo = (couche, format) =>
  'https://data.geopf.fr/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0' +
  '&LAYER=' + couche + '&STYLE=normal&FORMAT=image/' + format +
  '&TILEMATRIXSET=PM&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}';

const SOURCES = {
  photo:  { type: 'raster', tiles: [geo('ORTHOIMAGERY.ORTHOPHOTOS', 'jpeg')],
            tileSize: 256, maxzoom: 19, attribution: 'IGN' },
  topo:   { type: 'raster', tiles: [geo('GEOGRAPHICALGRIDSYSTEMS.PLANIGNV2', 'png')],
            tileSize: 256, maxzoom: 18, attribution: 'IGN' },
  releve: { type: 'raster-dem',
            tiles: ['https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png'],
            encoding: 'terrarium', tileSize: 256, maxzoom: 15 },
};

const CHEMINS = [
  { id: 'ttx-piste', filtre: ['==', ['get', 'class'], 'track'],
    peinture: { 'line-color': '#ff6a00',
                'line-width': ['interpolate', ['linear'], ['zoom'], 11, 1.4, 16, 5] } },
  { id: 'ttx-sentier', filtre: ['==', ['get', 'class'], 'path'],
    peinture: { 'line-color': '#ffd24a', 'line-dasharray': [2, 1.6],
                'line-width': ['interpolate', ['linear'], ['zoom'], 11, 1, 16, 3.4] } },
  { id: 'ttx-route', filtre: ['in', ['get', 'class'], ['literal', ['minor', 'service']]],
    peinture: { 'line-color': '#ffffff', 'line-opacity': 0.85,
                'line-width': ['interpolate', ['linear'], ['zoom'], 11, 0.7, 16, 2.6] } },
];

// L'app transmet la position regardée sur la carte 2D en appelant `allerA`
// une fois la page chargée. Un fragment d'URL ne convenait pas :
// `loadFlutterAsset` attend une clé de ressource, pas une adresse — la page
// ne se chargeait alors pas du tout, et l'écran restait sur sa roue (constaté
// sur appareil le 2026-09-12).
const depart = { lon: 1.44, lat: 43.60, zoom: 12.5 };
let fond = 'photo';
let exageration = 1.5;
let liberty = null;
let map;

async function styleCourant() {
  liberty ??= await (await fetch('https://tiles.openfreemap.org/styles/liberty')).json();
  const style = {
    version: 8, glyphs: liberty.glyphs, sprite: liberty.sprite,
    sources: { ...SOURCES, openmaptiles: liberty.sources.openmaptiles },
    sky: { 'sky-color': '#8fb4dd', 'horizon-color': '#dfe8f2', 'fog-color': '#e8eef5',
           'sky-horizon-blend': 0.6, 'horizon-fog-blend': 0.6, 'fog-ground-blend': 0.2 },
    layers: [{ id: 'ciel', type: 'background',
               paint: { 'background-color': fond === 'topo' ? '#e9eef2' : '#9fb8d6' } }],
  };
  if (fond !== 'relief') style.layers.push({ id: 'fond', type: 'raster', source: fond });
  style.layers.push({ id: 'ombrage', type: 'hillshade', source: 'releve',
    paint: { 'hillshade-exaggeration': fond === 'relief' ? 0.75 : (fond === 'topo' ? 0.4 : 0.15),
             'hillshade-shadow-color': '#4a4033' } });
  for (const c of CHEMINS) {
    style.layers.push({ id: c.id, type: 'line', source: 'openmaptiles',
      'source-layer': 'transportation', filter: c.filtre, minzoom: 10,
      layout: { 'line-cap': 'round', 'line-join': 'round' }, paint: c.peinture });
  }
  for (const l of liberty.layers.filter((l) => l.type === 'symbol')) style.layers.push(l);
  return style;
}

const bouton = (id) => document.getElementById(id);
const bascule = (el) => el.classList.toggle('actif');

function appliquerVisibilite() {
  const chemins = bouton('c-chemins').classList.contains('actif');
  const noms = bouton('c-noms').classList.contains('actif');
  for (const c of CHEMINS) {
    if (map.getLayer(c.id)) map.setLayoutProperty(c.id, 'visibility', chemins ? 'visible' : 'none');
  }
  for (const l of map.getStyle().layers) {
    if (l.type === 'symbol') map.setLayoutProperty(l.id, 'visibility', noms ? 'visible' : 'none');
  }
}

const appliquerRelief = () =>
  map.setTerrain({ source: 'releve', exaggeration: exageration });

(async () => {
  map = new maplibregl.Map({
    container: 'map', style: await styleCourant(),
    center: [depart.lon, depart.lat], zoom: depart.zoom,
    pitch: 70, bearing: 0, maxPitch: 85, attributionControl: false,
  });
  map.addControl(new maplibregl.AttributionControl({ compact: true }), 'bottom-right');
  map.on('style.load', () => { appliquerRelief(); appliquerVisibilite(); });

  for (const [clef, id] of Object.entries({ photo: 'f-photo', topo: 'f-topo', relief: 'f-relief' })) {
    bouton(id).onclick = async () => {
      fond = clef;
      map.setStyle(await styleCourant());
      for (const autre of ['f-photo', 'f-topo', 'f-relief']) {
        bouton(autre).classList.toggle('actif', autre === id);
      }
    };
  }
  bouton('c-chemins').onclick = (e) => { bascule(e.target); appliquerVisibilite(); };
  bouton('c-noms').onclick = (e) => { bascule(e.target); appliquerVisibilite(); };
  // Appelée par l'application dès que la page est prête.
  window.allerA = (lon, lat, zoom, fondDemande) => {
    if (fondDemande === 'topo' || fondDemande === 'photo') {
      bouton(fondDemande === 'topo' ? 'f-topo' : 'f-photo').click();
    }
    map.jumpTo({ center: [lon, lat], zoom: zoom, pitch: 70 });
    return 'ok';
  };

  bouton('c-relief').onclick = (e) => {
    exageration = exageration >= 2.4 ? 1.5 : exageration + 0.45;
    e.target.classList.toggle('actif', exageration > 1.5);
    appliquerRelief();
  };
})();
