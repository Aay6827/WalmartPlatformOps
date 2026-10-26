// Checkout load test. Open-model load: requests arrive at a fixed rate whether or not the service keeps up,
// so a slow service cannot hide by slowing the test down (the closed-loop drill script did exactly that).
//
//   BASE_URL   where checkout listens                       (default http://localhost:31000)
//   BASE_RPS   steady background rate, requests/s           (default 10)
//   PEAK_RPS   rate at the top of the ramp, requests/s      (default 120)
//   WARM / RAMP / HOLD / COOL   stage lengths               (defaults 30s / 60s / 120s / 30s)
//
// Pass/fail thresholds are the checkout SLOs from docs/slo.md.
import http from 'k6/http';
import { check } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:31000';
const BASE_RPS = Number(__ENV.BASE_RPS || 10);
const PEAK_RPS = Number(__ENV.PEAK_RPS || 120);
const WARM = __ENV.WARM || '30s';
const RAMP = __ENV.RAMP || '60s';
const HOLD = __ENV.HOLD || '120s';
const COOL = __ENV.COOL || '30s';

const SKUS = ['WMT-1001', 'WMT-1002', 'WMT-1003', 'WMT-1004', 'WMT-1005', 'WMT-1006', 'WMT-1007'];

// Only 201 counts as success, so http_req_failed is the real availability SLI for this test
// (every order here should be accepted; stock is sized so it never runs out).
http.setResponseCallback(http.expectedStatuses(201));

export const options = {
  scenarios: {
    checkout: {
      executor: 'ramping-arrival-rate',
      startRate: BASE_RPS,
      timeUnit: '1s',
      preAllocatedVUs: 50,
      maxVUs: 500,
      stages: [
        { target: BASE_RPS, duration: WARM },
        { target: PEAK_RPS, duration: RAMP },
        { target: PEAK_RPS, duration: HOLD },
        { target: BASE_RPS, duration: COOL },
      ],
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.005'],      // availability SLO: 99.5%
    http_req_duration: ['p(95)<500'],     // latency SLO: 95% under 500 ms
    dropped_iterations: ['count<1'],      // k6 itself kept up, so the numbers are trustworthy
  },
  summaryTrendStats: ['avg', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

export function setup() {
  // Readiness is expected to answer 200; without this it would be counted as a failure against the 201-only default.
  const res = http.get(`${BASE_URL}/health/ready`, { responseCallback: http.expectedStatuses(200) });
  if (res.status !== 200) {
    throw new Error(`checkout is not ready at ${BASE_URL} (HTTP ${res.status}). ` +
      'Is the cluster up, and is BASE_URL reachable from where k6 runs?');
  }
}

export default function () {
  const sku = SKUS[Math.floor(Math.random() * SKUS.length)];
  const payload = JSON.stringify({
    customer_id: `load-${__VU}`,
    items: [{ sku: sku, quantity: 1 }],
  });
  const res = http.post(`${BASE_URL}/checkout`, payload, {
    headers: { 'Content-Type': 'application/json' },
    tags: { name: 'POST /checkout' },
  });
  check(res, {
    'order confirmed': (r) => r.status === 201 && r.body.indexOf('CONFIRMED') !== -1,
  });
}