# Checkout load test results

Run on 2026-10-29 09:01 against the local kind cluster. **FAIL - at least one threshold was crossed.**

- Load: 10 req/s -> 120 req/s (open model, `ramping-arrival-rate`), warm 30s, ramp 60s, hold 120s, cool 30s. Every request is `POST /checkout` and must return 201.
- Pass/fail thresholds are the checkout SLOs: failed requests < 0.5%, p95 < 500 ms, and no dropped iterations (k6 itself kept up).
- Autoscaler: 2 to 6 replicas, CPU target 70% of the 100m request. Observed: first scale-up decision at t=91 s; peak 6 replicas, first reached at t=122 s; back to 2 replicas at t=406 s.
- Runner: Docker image grafana/k6:latest. Docker Desktop: 8 CPUs, 7.6 GiB RAM. k6, kind, Prometheus, Grafana and the services all share this one machine, so absolute numbers are indicative only.

## Autoscaler timeline

k6 ended at t=243 s.

| t (s) | replicas | desired | CPU vs request (target 70%) |
|---|---|---|---|
| 0 | 2 | 2 | 4% |
| 10 | 2 | 2 | 4% |
| 20 | 2 | 2 | 4% |
| 30 | 2 | 2 | 16% |
| 41 | 2 | 2 | 20% |
| 51 | 2 | 2 | 20% |
| 61 | 2 | 2 | 28% |
| 71 | 2 | 2 | 65% |
| 81 | 2 | 2 | 65% |
| 91 | 2 | 4 | 112% |
| 101 | 4 | 6 | 201% |
| 112 | 4 | 6 | 201% |
| 122 | 6 | 6 | 312% |
| 132 | 6 | 6 | 109% |
| 142 | 6 | 6 | 109% |
| 152 | 6 | 6 | 83% |
| 162 | 6 | 6 | 64% |
| 172 | 6 | 6 | 64% |
| 182 | 6 | 6 | 59% |
| 193 | 6 | 6 | 62% |
| 203 | 6 | 6 | 62% |
| 213 | 6 | 6 | 79% |
| 223 | 6 | 6 | 73% |
| 233 | 6 | 6 | 73% |
| 243 | 6 | 6 | 63% |
| 253 | 6 | 6 | 42% |
| 263 | 6 | 6 | 42% |
| 273 | 6 | 6 | 9% |
| 284 | 6 | 6 | 5% |
| 294 | 6 | 6 | 5% |
| 304 | 6 | 5 | 4% |
| 314 | 5 | 5 | 4% |
| 324 | 5 | 5 | 4% |
| 335 | 5 | 4 | 4% |
| 345 | 4 | 4 | 4% |
| 355 | 4 | 4 | 4% |
| 365 | 4 | 3 | 6% |
| 375 | 3 | 3 | 5% |
| 385 | 3 | 3 | 5% |
| 396 | 3 | 2 | 4% |
| 406 | 2 | 2 | 5% |

## k6 summary

```text


   THRESHOLDS 

    dropped_iterations
     'count<1' count=45

    http_req_duration
     'p(95)<500' p(95)=44.72ms

    http_req_failed
     'rate<0.005' rate=0.00%


   TOTAL RESULTS 

    checks_total.......: 20504   85.436557/s
    checks_succeeded...: 100.00% 20504 out of 20504
    checks_failed......: 0.00%   0 out of 20504

     order confirmed

    HTTP
    http_req_duration..............: avg=24.11ms med=5.83ms p(90)=12.06ms p(95)=44.72ms p(99)=649.1ms max=1.41s
      { expected_response:true }...: avg=24.11ms med=5.83ms p(90)=12.06ms p(95)=44.72ms p(99)=649.1ms max=1.41s
    http_req_failed................: 0.00%  0 out of 20505
    http_reqs......................: 20505  85.440724/s

    EXECUTION
    dropped_iterations.............: 45     0.187507/s
    iteration_duration.............: avg=24.47ms med=6.1ms  p(90)=12.53ms p(95)=45.13ms p(99)=651.6ms max=1.42s
    iterations.....................: 20504  85.436557/s
    vus............................: 0      min=0          max=83
    vus_max........................: 91     min=50         max=91

    NETWORK
    data_received..................: 4.7 MB 20 kB/s
    data_sent......................: 4.3 MB 18 kB/s

--- k6 log (stderr) ---
time="2026-10-29T03:35:56Z" level=error msg="thresholds on metrics 'dropped_iterations' have been crossed"
```

