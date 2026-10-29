# Checkout load test results

Run on 2026-10-29 08:53 against the local kind cluster. **PASS - every threshold held (NOT A CLEAN RUN: checkout and inventory was redeployed during the test).**

- Load: 10 req/s -> 120 req/s (open model, `ramping-arrival-rate`), warm 30s, ramp 60s, hold 120s, cool 30s. Every request is `POST /checkout` and must return 201.
- Pass/fail thresholds are the checkout SLOs: failed requests < 0.5%, p95 < 500 ms, and no dropped iterations (k6 itself kept up).
- Autoscaler: 2 to 6 replicas, CPU target 70% of the 100m request. Observed: first scale-up decision at t=82 s; peak 6 replicas, first reached at t=112 s; back to 2 replicas at t=427 s.
- Runner: Docker image grafana/k6:latest. Docker Desktop: 8 CPUs, 7.6 GiB RAM. k6, kind, Prometheus, Grafana and the services all share this one machine, so absolute numbers are indicative only.

## Autoscaler timeline

k6 ended at t=244 s.

| t (s) | replicas | desired | CPU vs request (target 70%) |
|---|---|---|---|
| 0 | 2 | 2 | 4% |
| 10 | 2 | 2 | 4% |
| 20 | 2 | 2 | 17% |
| 31 | 2 | 2 | 17% |
| 41 | 2 | 2 | 36% |
| 51 | 2 | 2 | 44% |
| 61 | 2 | 2 | 44% |
| 71 | 2 | 2 | 65% |
| 82 | 2 | 4 | 120% |
| 92 | 2 | 4 | 120% |
| 102 | 4 | 6 | 181% |
| 112 | 6 | 6 | 178% |
| 122 | 6 | 6 | 131% |
| 133 | 6 | 6 | 131% |
| 143 | 6 | 6 | 114% |
| 153 | 6 | 6 | 106% |
| 163 | 6 | 6 | 106% |
| 173 | 6 | 6 | 109% |
| 184 | 6 | 6 | 105% |
| 194 | 6 | 6 | 105% |
| 204 | 6 | 6 | 114% |
| 214 | 6 | 6 | 102% |
| 224 | 6 | 6 | 102% |
| 234 | 6 | 6 | 95% |
| 245 | 6 | 6 | 161% |
| 255 | 6 | 6 | 161% |
| 265 | 6 | 6 | 7% |
| 275 | 6 | 6 | 5% |
| 285 | 6 | 6 | 5% |
| 295 | 6 | 6 | 4% |
| 306 | 6 | 6 | 4% |
| 316 | 6 | 6 | 4% |
| 326 | 6 | 5 | 4% |
| 336 | 5 | 5 | 4% |
| 346 | 5 | 5 | 4% |
| 356 | 5 | 4 | 4% |
| 366 | 4 | 4 | 4% |
| 377 | 4 | 4 | 4% |
| 387 | 4 | 3 | 4% |
| 397 | 3 | 3 | 5% |
| 407 | 3 | 3 | 5% |
| 417 | 3 | 2 | 4% |
| 427 | 2 | 2 | 5% |

## k6 summary

```text


   THRESHOLDS 

    dropped_iterations
     'count<1' count=0

    http_req_duration
     'p(95)<500' p(95)=45.57ms

    http_req_failed
     'rate<0.005' rate=0.00%


   TOTAL RESULTS 

    checks_total.......: 20549   85.623856/s
    checks_succeeded...: 100.00% 20549 out of 20549
    checks_failed......: 0.00%   0 out of 20549

     order confirmed

    HTTP
    http_req_duration..............: avg=17.14ms med=9.46ms p(90)=19.67ms p(95)=45.57ms p(99)=215.6ms max=485.24ms
      { expected_response:true }...: avg=17.14ms med=9.46ms p(90)=19.67ms p(95)=45.57ms p(99)=215.6ms max=485.24ms
    http_req_failed................: 0.00%  0 out of 20550
    http_reqs......................: 20550  85.628022/s

    EXECUTION
    dropped_iterations.............: 0      0/s
    iteration_duration.............: avg=17.6ms  med=9.87ms p(90)=20.42ms p(95)=46.12ms p(99)=216.1ms max=486.41ms
    iterations.....................: 20549  85.623856/s
    vus............................: 0      min=0          max=44
    vus_max........................: 50     min=50         max=50

    NETWORK
    data_received..................: 4.7 MB 20 kB/s
    data_sent......................: 4.3 MB 18 kB/s
```

