# Checkout load test results

Run on 2026-10-29 09:17 against the local kind cluster. **FAIL - at least one threshold was crossed.**

- Load: 10 req/s -> 120 req/s (open model, `ramping-arrival-rate`), warm 30s, ramp 60s, hold 120s, cool 30s. Every request is `POST /checkout` and must return 201.
- Pass/fail thresholds are the checkout SLOs: failed requests < 0.5%, p95 < 500 ms, and no dropped iterations (k6 itself kept up).
- Autoscaler: 2 to 6 replicas, CPU target 70% of the 100m request. Observed: first scale-up decision at t=81 s; peak 6 replicas, first reached at t=122 s; back to 2 replicas at t=417 s.
- Runner: Docker image grafana/k6:latest. Docker Desktop: 8 CPUs, 7.6 GiB RAM. k6, kind, Prometheus, Grafana and the services all share this one machine, so absolute numbers are indicative only.

## Autoscaler timeline

k6 ended at t=244 s.

| t (s) | replicas | desired | CPU vs request (target 70%) |
|---|---|---|---|
| 0 | 2 | 2 | 5% |
| 10 | 2 | 2 | 4% |
| 20 | 2 | 2 | 7% |
| 31 | 2 | 2 | 7% |
| 41 | 2 | 2 | 31% |
| 51 | 2 | 2 | 35% |
| 61 | 2 | 2 | 50% |
| 71 | 2 | 2 | 50% |
| 81 | 2 | 4 | 114% |
| 92 | 4 | 5 | 171% |
| 102 | 4 | 5 | 171% |
| 112 | 5 | 6 | 251% |
| 122 | 6 | 6 | 135% |
| 132 | 6 | 6 | 135% |
| 143 | 6 | 6 | 101% |
| 153 | 6 | 6 | 107% |
| 163 | 6 | 6 | 107% |
| 173 | 6 | 6 | 114% |
| 183 | 6 | 6 | 113% |
| 193 | 6 | 6 | 113% |
| 204 | 6 | 6 | 94% |
| 214 | 6 | 6 | 85% |
| 224 | 6 | 6 | 85% |
| 234 | 6 | 6 | 81% |
| 244 | 6 | 6 | 62% |
| 254 | 6 | 6 | 62% |
| 265 | 6 | 6 | 49% |
| 275 | 6 | 6 | 13% |
| 285 | 6 | 6 | 13% |
| 295 | 6 | 6 | 4% |
| 305 | 6 | 5 | 4% |
| 315 | 6 | 5 | 4% |
| 325 | 5 | 5 | 4% |
| 335 | 5 | 4 | 4% |
| 346 | 5 | 4 | 4% |
| 356 | 4 | 4 | 4% |
| 366 | 4 | 3 | 4% |
| 376 | 4 | 3 | 4% |
| 386 | 3 | 3 | 4% |
| 396 | 3 | 2 | 4% |
| 407 | 3 | 2 | 4% |
| 417 | 2 | 2 | 5% |

## k6 summary

```text


   THRESHOLDS 

    dropped_iterations
     'count<1' count=10

    http_req_duration
     'p(95)<500' p(95)=23.22ms

    http_req_failed
     'rate<0.005' rate=0.00%


   TOTAL RESULTS 

    checks_total.......: 20539  85.584589/s
    checks_succeeded...: 99.99% 20538 out of 20539
    checks_failed......: 0.00%  1 out of 20539

     order confirmed
        99%   20538 /  1

    HTTP
    http_req_duration..............: avg=14.3ms med=8.49ms p(90)=14.61ms p(95)=23.22ms p(99)=182.21ms max=680.97ms
      { expected_response:true }...: avg=14.3ms med=8.49ms p(90)=14.61ms p(95)=23.23ms p(99)=182.22ms max=680.97ms
    http_req_failed................: 0.00%  1 out of 20540
    http_reqs......................: 20540  85.588756/s

    EXECUTION
    dropped_iterations.............: 10     0.041669/s
    iteration_duration.............: avg=14.7ms med=8.86ms p(90)=15.15ms p(95)=23.84ms p(99)=183.31ms max=681.88ms
    iterations.....................: 20539  85.584589/s
    vus............................: 0      min=0          max=32
    vus_max........................: 59     min=50         max=59

    NETWORK
    data_received..................: 4.7 MB 20 kB/s
    data_sent......................: 4.3 MB 18 kB/s

--- k6 log (stderr) ---
time="2026-10-29T03:48:05Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-29T03:51:52Z" level=error msg="thresholds on metrics 'dropped_iterations' have been crossed"
```

