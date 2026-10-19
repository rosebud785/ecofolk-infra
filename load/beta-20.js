// beta-20.js — k6 scenario for the 20-user beta (#16).
//
// WHY
//   Small Cloud SQL tiers allow few connections (db-f1-micro: 25), while Cloud
//   Run scales out per request. ef#400's cold-start number measures one user;
//   this measures twenty at once, to find where the connection ceiling bites.
//
// WHAT IT DOES
//   20 VUs for 10 minutes. Each iteration reads a map tile and a place; if
//   EF_LOAD_TOKEN is set it also creates a sit. With no token the write path
//   is skipped entirely (read-only run), never sent unauthenticated.
//   Thresholds: p95 under 800 ms, errors under 1%.
//
// RUNNING IT
//   Always check the target first; the guard refuses prod, private or
//   loopback hosts, and anything that isn't https:
//
//     bash scripts/check-load-target.sh "$EF_BASE_URL" && \
//       k6 run -e EF_BASE_URL="$EF_BASE_URL" load/beta-20.js
//
//   Add -e EF_LOAD_TOKEN=... for the write path (on-site only; never commit a
//   token or put one in a workflow file).
//
// ENV
//   EF_BASE_URL    required at run time, e.g. https://qa.example.com
//   EF_LOAD_TOKEN  optional bearer token; enables the create-a-sit write path
//   EF_TILE_PATH   tile path template, default /tiles/{z}/{x}/{y}.pbf
//   EF_PLACE_PATH  place path template, default /places/{id}
//   EF_SIT_PATH    create-a-sit path, default /sits
//   EF_PLACE_IDS   comma-separated place ids to read and sit at, default 1
//   The path defaults are placeholders: confirm them against the deployed API
//   (ef#408) before the first run.

import http from 'k6/http';
import { check, group, sleep } from 'k6';

const BASE_URL = (__ENV.EF_BASE_URL || '').replace(/\/+$/, '');
const TOKEN = __ENV.EF_LOAD_TOKEN || '';
const TILE_PATH = __ENV.EF_TILE_PATH || '/tiles/{z}/{x}/{y}.pbf';
const PLACE_PATH = __ENV.EF_PLACE_PATH || '/places/{id}';
const SIT_PATH = __ENV.EF_SIT_PATH || '/sits';
const PLACE_IDS = (__ENV.EF_PLACE_IDS || '1').split(',').map((s) => s.trim()).filter(Boolean);

// A 4x4 block of zoom-12 tiles over Montréal, so VUs spread across tiles
// instead of all hitting one cached response.
const TILE_Z = 12;
const TILE_X0 = 1209;
const TILE_Y0 = 1464;
const TILE_SPAN = 4;

export const options = {
  scenarios: {
    beta_20: {
      executor: 'constant-vus',
      vus: 20,
      duration: '10m',
    },
  },
  // Refused at connect time, after DNS: covers a public name that resolves to
  // a private or loopback address, which check-load-target.sh can't see.
  blacklistIPs: [
    '10.0.0.0/8',
    '172.16.0.0/12',
    '192.168.0.0/16',
    '127.0.0.0/8',
    '0.0.0.0/8',
    '169.254.0.0/16',
    '::1/128',
    'fc00::/7',
    'fe80::/10',
  ],
  thresholds: {
    http_req_duration: ['p(95)<800'],
    http_req_failed: ['rate<0.01'],
    checks: ['rate>0.99'],
  },
};

function pick(list) {
  return list[Math.floor(Math.random() * list.length)];
}

function fill(template, values) {
  return template.replace(/\{(\w+)\}/g, (_, k) => encodeURIComponent(String(values[k])));
}

// Runs once before the VUs start (not during `k6 inspect`). A second line of
// defence for a direct `k6 run`; scripts/check-load-target.sh is the guard.
export function setup() {
  if (!BASE_URL) {
    throw new Error('EF_BASE_URL is required, e.g. -e EF_BASE_URL=https://qa.example.com');
  }
  if (!/^https:\/\//i.test(BASE_URL) || /prod/i.test(BASE_URL)) {
    throw new Error('refusing EF_BASE_URL: run scripts/check-load-target.sh on it first');
  }
  if (PLACE_IDS.length === 0) {
    throw new Error('EF_PLACE_IDS is empty');
  }
  console.log(TOKEN ? 'write path: ON (EF_LOAD_TOKEN set)' : 'write path: SKIPPED (EF_LOAD_TOKEN not set)');
}

export default function () {
  group('read: map tile', () => {
    const url = BASE_URL + fill(TILE_PATH, {
      z: TILE_Z,
      x: TILE_X0 + Math.floor(Math.random() * TILE_SPAN),
      y: TILE_Y0 + Math.floor(Math.random() * TILE_SPAN),
    });
    const res = http.get(url, { tags: { name: 'tile' } });
    check(res, { 'tile 200': (r) => r.status === 200 });
  });

  const placeId = pick(PLACE_IDS);

  group('read: place', () => {
    const url = BASE_URL + fill(PLACE_PATH, { id: placeId });
    const res = http.get(url, { tags: { name: 'place' } });
    check(res, { 'place 200': (r) => r.status === 200 });
  });

  if (TOKEN) {
    group('write: create sit', () => {
      const res = http.post(
        BASE_URL + SIT_PATH,
        JSON.stringify({ place_id: placeId, source: 'k6-beta-20' }),
        {
          headers: {
            Authorization: `Bearer ${TOKEN}`,
            'Content-Type': 'application/json',
          },
          tags: { name: 'create_sit' },
        },
      );
      check(res, { 'sit 2xx': (r) => r.status >= 200 && r.status < 300 });
    });
  }

  // Think time: a beta user browsing, not a tight loop.
  sleep(1 + Math.random() * 2);
}
