# Checkout load test results

Run on 2026-10-26 20:15 against the local kind cluster. **FAIL - at least one threshold was crossed.**

- Load: 10 req/s -> 300 req/s (open model, `ramping-arrival-rate`), warm 30s, ramp 60s, hold 120s, cool 30s. Every request is `POST /checkout` and must return 201.
- Pass/fail thresholds are the checkout SLOs: failed requests < 0.5%, p95 < 500 ms, and no dropped iterations (k6 itself kept up).
- Autoscaler: 2 to 6 replicas, CPU target 70% of the 100m request. Observed: first scale-up decision at t=61 s; peak 6 replicas, first reached at t=92 s; back to 2 replicas at t=438 s.
- Runner: Docker image grafana/k6:latest. Docker Desktop: 8 CPUs, 7.6 GiB RAM. k6, kind, Prometheus, Grafana and the services all share this one machine, so absolute numbers are indicative only.

## Autoscaler timeline

k6 ended at t=244 s.

| t (s) | replicas | desired | CPU vs request (target 70%) |
|---|---|---|---|
| 0 | 2 | 2 | 5% |
| 10 | 2 | 2 | 4% |
| 20 | 2 | 2 | 4% |
| 31 | 2 | 2 | 21% |
| 41 | 2 | 2 | 21% |
| 51 | 2 | 2 | 41% |
| 61 | 2 | 4 | 135% |
| 71 | 2 | 4 | 135% |
| 81 | 4 | 6 | 247% |
| 92 | 6 | 6 | 354% |
| 102 | 6 | 6 | 354% |
| 112 | 6 | 6 | 263% |
| 122 | 6 | 6 | 213% |
| 133 | 6 | 6 | 213% |
| 143 | 6 | 6 | 213% |
| 153 | 6 | 6 | 217% |
| 163 | 6 | 6 | 217% |
| 173 | 6 | 6 | 208% |
| 183 | 6 | 6 | 203% |
| 194 | 6 | 6 | 203% |
| 204 | 6 | 6 | 208% |
| 214 | 6 | 6 | 205% |
| 224 | 6 | 6 | 205% |
| 234 | 6 | 6 | 209% |
| 244 | 6 | 6 | 211% |
| 255 | 6 | 6 | 211% |
| 265 | 6 | 6 | 123% |
| 275 | 6 | 6 | 11% |
| 285 | 6 | 6 | 11% |
| 295 | 6 | 6 | 4% |
| 305 | 6 | 6 | 4% |
| 316 | 6 | 6 | 4% |
| 326 | 6 | 5 | 4% |
| 336 | 5 | 5 | 4% |
| 357 | 5 | 5 | 4% |
| 367 | 5 | 4 | 4% |
| 377 | 4 | 4 | 3% |
| 388 | 4 | 3 | 3% |
| 398 | 4 | 3 | 3% |
| 408 | 3 | 3 | 5% |
| 418 | 3 | 2 | 5% |
| 428 | 3 | 2 | 5% |
| 438 | 2 | 2 | 4% |

## k6 summary

```text


  █ THRESHOLDS 

    dropped_iterations
    ✗ 'count<1' count=16098

    http_req_duration
    ✗ 'p(95)<500' p(95)=5.46s

    http_req_failed
    ✗ 'rate<0.005' rate=6.61%


  █ TOTAL RESULTS 

    checks_total.......: 34151  142.284999/s
    checks_succeeded...: 93.38% 31892 out of 34151
    checks_failed......: 6.61%  2259 out of 34151

    ✗ order confirmed
      ↳  93% — ✓ 31892 / ✗ 2259

    HTTP
    http_req_duration..............: avg=2.18s med=1.71s p(90)=5.17s p(95)=5.46s p(99)=5.89s max=6.45s
      { expected_response:true }...: avg=2.14s med=1.58s p(90)=5.18s p(95)=5.46s p(99)=5.89s max=6.45s
    http_req_failed................: 6.61%  2259 out of 34152
    http_reqs......................: 34152  142.289165/s

    EXECUTION
    dropped_iterations.............: 16098  67.069893/s
    iteration_duration.............: avg=2.18s med=1.71s p(90)=5.17s p(95)=5.46s p(99)=5.89s max=6.45s
    iterations.....................: 34151  142.284999/s
    vus............................: 0      min=0             max=500
    vus_max........................: 500    min=50            max=500

    NETWORK
    data_received..................: 7.7 MB 32 kB/s
    data_sent......................: 7.2 MB 30 kB/s

--- k6 log (stderr) ---
time="2026-10-26T14:46:52Z" level=warning msg="Insufficient VUs, reached 500 active VUs and cannot initialize more" executor=ramping-arrival-rate scenario=checkout
time="2026-10-26T14:49:28Z" level=error msg="thresholds on metrics 'dropped_iterations, http_req_duration, http_req_failed' have been crossed"
```

