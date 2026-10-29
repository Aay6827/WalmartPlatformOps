# Checkout load test results

Run on 2026-10-29 09:53 against the local kind cluster. **PASS - every threshold held.**

- Load: 10 req/s -> 120 req/s (open model, `ramping-arrival-rate`), warm 30s, ramp 60s, hold 120s, cool 30s. Every request is `POST /checkout` and must return 201.
- Pass/fail thresholds are the checkout SLOs: failed requests < 0.5%, p95 < 500 ms, and no dropped iterations (k6 itself kept up).
- Autoscaler: 2 to 6 replicas, CPU target 70% of the 100m request. Observed: first scale-up decision at t=82 s; peak 6 replicas, first reached at t=123 s; back to 2 replicas at t=418 s.
- Runner: Docker image grafana/k6:latest. Docker Desktop: 8 CPUs, 7.6 GiB RAM. k6, kind, Prometheus, Grafana and the services all share this one machine, so absolute numbers are indicative only.

## Autoscaler timeline

k6 ended at t=245 s.

| t (s) | replicas | desired | CPU vs request (target 70%) |
|---|---|---|---|
| 0 | 2 | 2 | 5% |
| 10 | 2 | 2 | 5% |
| 20 | 2 | 2 | n/a |
| 31 | 2 | 2 | 32% |
| 41 | 2 | 2 | 32% |
| 51 | 2 | 2 | 38% |
| 61 | 2 | 2 | 49% |
| 72 | 2 | 2 | 49% |
| 82 | 2 | 3 | 98% |
| 93 | 3 | 5 | 156% |
| 103 | 5 | 6 | 199% |
| 113 | 5 | 6 | 199% |
| 123 | 6 | 6 | 257% |
| 133 | 6 | 6 | 104% |
| 143 | 6 | 6 | 104% |
| 153 | 6 | 6 | 84% |
| 164 | 6 | 6 | 82% |
| 174 | 6 | 6 | 82% |
| 184 | 6 | 6 | 82% |
| 194 | 6 | 6 | 83% |
| 204 | 6 | 6 | 83% |
| 214 | 6 | 6 | 85% |
| 225 | 6 | 6 | 85% |
| 235 | 6 | 6 | 85% |
| 245 | 6 | 6 | 82% |
| 256 | 6 | 6 | 60% |
| 266 | 6 | 6 | 60% |
| 276 | 6 | 6 | 45% |
| 286 | 6 | 6 | 6% |
| 296 | 6 | 6 | 6% |
| 306 | 6 | 6 | 4% |
| 317 | 6 | 5 | 4% |
| 327 | 6 | 5 | 4% |
| 337 | 5 | 5 | 5% |
| 347 | 5 | 4 | 4% |
| 357 | 4 | 4 | 5% |
| 367 | 4 | 4 | 5% |
| 377 | 4 | 3 | 4% |
| 388 | 3 | 3 | 4% |
| 398 | 3 | 3 | 4% |
| 408 | 3 | 2 | 5% |
| 418 | 2 | 2 | 5% |

## k6 summary

```text


   THRESHOLDS 

    dropped_iterations
     'count<1' count=0

    http_req_duration
     'p(95)<500' p(95)=15.69ms

    http_req_failed
     'rate<0.005' rate=0.00%


   TOTAL RESULTS 

    checks_total.......: 20549   85.62588/s
    checks_succeeded...: 100.00% 20549 out of 20549
    checks_failed......: 0.00%   0 out of 20549

     order confirmed

    HTTP
    http_req_duration..............: avg=9ms    med=7.48ms p(90)=12.14ms p(95)=15.69ms p(99)=38.54ms max=166.98ms
      { expected_response:true }...: avg=9ms    med=7.48ms p(90)=12.14ms p(95)=15.69ms p(99)=38.54ms max=166.98ms
    http_req_failed................: 0.00%  0 out of 20550
    http_reqs......................: 20550  85.630047/s

    EXECUTION
    dropped_iterations.............: 0      0/s
    iteration_duration.............: avg=9.54ms med=7.83ms p(90)=13.42ms p(95)=17.74ms p(99)=39.11ms max=167.29ms
    iterations.....................: 20549  85.62588/s
    vus............................: 0      min=0          max=6  
    vus_max........................: 200    min=200        max=200

    NETWORK
    data_received..................: 4.7 MB 20 kB/s
    data_sent......................: 4.3 MB 18 kB/s
```

