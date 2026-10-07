// LnP core lifecycle under load: apply → verify → officer inbox search → VERIFY_DOCUMENTS transition. One iteration = one lifecycle.
// Config (env): BASE=https://<domain>  TENANT=BASETENANT  CT=BUSINESS_LICENSE  SEED=seed.json  SECRETS=secrets.json  VUS, DURATION
// seed.json: {schemaDefinitionId, fileStoreId, individuals:[{id, mobile, name}]}   (seed.sh)
// secrets.json: {citizen, verifier, otpBypass}  tokens + the tenant's OTP bypass code (mint-tokens.sh; mode 600, never logged)
import http from 'k6/http';
import { check, fail } from 'k6';
import { SharedArray } from 'k6/data';
import { Trend, Counter } from 'k6/metrics';

const BASE = __ENV.BASE, TENANT = __ENV.TENANT || 'BASETENANT', CT = __ENV.CT || 'BUSINESS_LICENSE';
const seed = JSON.parse(open(__ENV.SEED || './seed.json'));
const secrets = JSON.parse(open(__ENV.SECRETS || './secrets.json'));
const people = new SharedArray('individuals', () => seed.individuals);
const lifecycle = new Trend('lifecycle_duration', true), lifecycles = new Counter('lifecycles');

export const options = {
  scenarios: { core: { executor: 'constant-vus', vus: Number(__ENV.VUS || 1), duration: __ENV.DURATION || '1m', gracefulStop: '30s' } },
  thresholds: { http_req_failed: ['rate<0.01'], 'http_req_duration{name:apply}': ['p(95)<2000'], 'http_req_duration{name:search}': ['p(95)<2000'],
                'http_req_duration{name:transition}': ['p(95)<2000'] },
  summaryTrendStats: ['avg', 'p(50)', 'p(95)', 'p(99)', 'max'],
};
const hdr = (tok) => ({ headers: { Authorization: `Bearer ${tok}`, 'X-Tenant-ID': TENANT, 'X-User-Id': 'lnp-load', 'X-Client-ID': 'lnp-load', 'Content-Type': 'application/json' } });
const tagged = (tok, name) => Object.assign(hdr(tok), { tags: { name } });

export default function () {
  const t0 = Date.now();
  const p = people[(__VU * 100003 + __ITER) % people.length];
  const stamp = `${__VU}-${__ITER}-${Date.now() % 100000}`;
  const body = {
    applicantIds: [p.id], holderSameAsApplicant: true, holder: { holderType: 'INDIVIDUAL' },
    addresses: [{ addressType: 'PHYSICAL', addressLines: ['1 Load Street'], city: 'Testville', stateOrProvince: 'TS', postalCode: '500001', country: 'IN' }],
    documents: [{ documentType: 'ID_CARD_OR_PASSPORT', fileStoreId: seed.fileStoreId }],
    declaration: { declarationAccepted: true, consentToDataSharing: true }, channel: 'CITIZEN_PORTAL', schemaDefinitionId: seed.schemaDefinitionId,
    mobileNumber: p.mobile, partyDetails: { [p.id]: { name: p.name, mobileNumber: p.mobile, role: 'APPLICANT' } },
    certificateDetail: { businessName: `Load Diner ${stamp}`, ownershipType: 'SOLE_PROPRIETOR', businessRegistrationDate: '2024-01-15', numberOfEmployees: 3, annualTurnover: 1200000 },
  };
  // 1. apply (citizen)
  const a = http.post(`${BASE}/license/certificate-types/${CT}/certificates`, JSON.stringify(body), tagged(secrets.citizen, 'apply'));
  if (!check(a, { 'apply 201/200': (r) => r.status === 201 || r.status === 200 })) { fail(`apply ${a.status}: ${a.body && a.body.slice(0, 160)}`); }
  const app = a.json(); const id = app.id; const ref = app.pendingVerification && app.pendingVerification.otp && app.pendingVerification.otp.referenceId;
  // 1b. verify (citizen) — the OTP step, with the tenant's bypass code; part of "create" but reported on its own
  if (ref) {
    const v = http.post(`${BASE}/license/certificates/${id}/_verify`, JSON.stringify({ otp: { referenceId: ref, code: secrets.otpBypass } }), tagged(secrets.citizen, 'verify'));
    check(v, { 'verify 200': (r) => r.status === 200 }) || fail(`verify ${v.status}: ${v.body && v.body.slice(0, 160)}`);
  }
  // 2. officer inbox search (verifier)
  const s = http.post(`${BASE}/license/certificates/search`, JSON.stringify({ status: 'IN_PROGRESS', page: 0, size: 20 }), tagged(secrets.verifier, 'search'));
  check(s, { 'search 200': (r) => r.status === 200, 'search has rows': (r) => { const j = r.json(); const rows = j.certificates || j.results || j; return Array.isArray(rows) && rows.length > 0; } }) || fail(`search ${s.status}`);
  // 3. transition VERIFY_DOCUMENTS (verifier)
  const t = http.post(`${BASE}/license/certificate-types/${CT}/certificates/${id}`, JSON.stringify({ processCode: CT, action: 'VERIFY_DOCUMENTS', comment: 'Documents verified (load).' }), tagged(secrets.verifier, 'transition'));
  check(t, { 'transition 200': (r) => r.status === 200 }) || fail(`transition ${t.status}: ${t.body && t.body.slice(0, 160)}`);
  lifecycle.add(Date.now() - t0); lifecycles.add(1);
}
