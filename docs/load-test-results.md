# Checkout load test results

Run on 2026-10-26 08:51 against the local kind cluster. **PASS - every threshold held.**

- Load: 10 req/s -> 120 req/s (open model, `ramping-arrival-rate`), warm 30s, ramp 60s, hold 120s, cool 30s. Every request is `POST /checkout` and must return 201.
- Pass/fail thresholds are the checkout SLOs: failed requests < 0.5%, p95 < 500 ms, and no dropped iterations (k6 itself kept up).
- Autoscaler: 2 to 6 replicas, CPU target 70% of the 100m request. Observed: first scale-up decision at t=111 s; peak 5 replicas, first reached at t=152 s; back to 2 replicas at t=384 s.
- Runner: Docker image grafana/k6:latest. Docker Desktop: 8 CPUs, 7.6 GiB RAM. k6, kind, Prometheus, Grafana and the services all share this one machine, so absolute numbers are indicative only.

## Autoscaler timeline

k6 ended at t=252 s.

| t (s) | replicas | desired | CPU vs request (target 70%) |
|---|---|---|---|
| 0 | 2 | 2 | 3% |
| 10 | 2 | 2 | 3% |
| 20 | 2 | 2 | 3% |
| 30 | 2 | 2 | 6% |
| 40 | 2 | 2 | 6% |
| 51 | 2 | 2 | 16% |
| 61 | 2 | 2 | 18% |
| 71 | 2 | 2 | 18% |
| 81 | 2 | 2 | 40% |
| 91 | 2 | 2 | 61% |
| 101 | 2 | 2 | 61% |
| 111 | 2 | 3 | 100% |
| 121 | 3 | 4 | 139% |
| 131 | 3 | 4 | 139% |
| 141 | 4 | 5 | 162% |
| 152 | 5 | 5 | 114% |
| 162 | 5 | 5 | 114% |
| 172 | 5 | 5 | 88% |
| 182 | 5 | 5 | 70% |
| 192 | 5 | 5 | 70% |
| 202 | 5 | 5 | 67% |
| 212 | 5 | 5 | 71% |
| 222 | 5 | 5 | 71% |
| 232 | 5 | 5 | 69% |
| 242 | 5 | 5 | 67% |
| 252 | 5 | 5 | 67% |
| 263 | 5 | 5 | 51% |
| 273 | 5 | 5 | 29% |
| 283 | 5 | 5 | 29% |
| 293 | 5 | 5 | 17% |
| 303 | 5 | 4 | 3% |
| 313 | 5 | 4 | 3% |
| 323 | 4 | 4 | 3% |
| 333 | 4 | 3 | 3% |
| 343 | 4 | 3 | 3% |
| 353 | 3 | 3 | 3% |
| 363 | 3 | 2 | 3% |
| 374 | 3 | 2 | 3% |
| 384 | 2 | 2 | 3% |

## k6 summary

```text


  â–ˆ THRESHOLDS 

    dropped_iterations
    âœ“ 'count<1' count=0

    http_req_duration
    âœ“ 'p(95)<500' p(95)=7.26ms

    http_req_failed
    âœ“ 'rate<0.005' rate=0.00%


  â–ˆ TOTAL RESULTS 

    checks_total.......: 20549   85.623326/s
    checks_succeeded...: 100.00% 20549 out of 20549
    checks_failed......: 0.00%   0 out of 20549

    âœ“ order confirmed

    HTTP
    http_req_duration..............: avg=5.17ms med=4.76ms p(90)=6.45ms p(95)=7.26ms p(99)=10.49ms max=93.22ms
      { expected_response:true }...: avg=5.17ms med=4.76ms p(90)=6.45ms p(95)=7.26ms p(99)=10.49ms max=93.22ms
    http_req_failed................: 0.00%  0 out of 20550
    http_reqs......................: 20550  85.627492/s

    EXECUTION
    dropped_iterations.............: 0      0/s
    iteration_duration.............: avg=5.39ms med=4.97ms p(90)=6.75ms p(95)=7.61ms p(99)=11.07ms max=95.41ms
    iterations.....................: 20549  85.623326/s
    vus............................: 0      min=0          max=2 
    vus_max........................: 50     min=50         max=50

    NETWORK
    data_received..................: 4.7 MB 20 kB/s
    data_sent......................: 4.3 MB 18 kB/s

--- k6 log (stderr) ---
Unable to find image 'grafana/k6:latest' locally
latest: Pulling from grafana/k6
2b28f25602d4: Pulling fs layer
4f4fb700ef54: Pulling fs layer
699240e0b337: Pulling fs layer
55afa1ecc21d: Pulling fs layer
4f4fb700ef54: Already exists
4f4fb700ef54: Pull complete
2b28f25602d4: Download complete
55afa1ecc21d: Download complete
44136fa355b3: Already exists
55afa1ecc21d: Pull complete
2b28f25602d4: Pull complete
935631f8a8f2: Download complete
699240e0b337: Download complete
699240e0b337: Pull complete
Digest: sha256:3e4186aea62e11a45560bfc51e19eeafe82fc07ce069c78aff44b7ff893d9a5e
Status: Downloaded newer image for grafana/k6:latest
```

