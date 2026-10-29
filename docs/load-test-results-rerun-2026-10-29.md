# Checkout load test results

Run on 2026-10-29 08:40 against the local kind cluster. **FAIL - at least one threshold was crossed.**

- Load: 10 req/s -> 120 req/s (open model, `ramping-arrival-rate`), warm 30s, ramp 60s, hold 120s, cool 30s. Every request is `POST /checkout` and must return 201.
- Pass/fail thresholds are the checkout SLOs: failed requests < 0.5%, p95 < 500 ms, and no dropped iterations (k6 itself kept up).
- Autoscaler: 2 to 6 replicas, CPU target 70% of the 100m request. Observed: first scale-up decision at t=81 s; peak 6 replicas, first reached at t=122 s; back to 2 replicas at t=407 s.
- Runner: Docker image grafana/k6:latest. Docker Desktop: 8 CPUs, 7.6 GiB RAM. k6, kind, Prometheus, Grafana and the services all share this one machine, so absolute numbers are indicative only.

## Autoscaler timeline

k6 ended at t=244 s.

| t (s) | replicas | desired | CPU vs request (target 70%) |
|---|---|---|---|
| 0 | 2 | 2 | 4% |
| 10 | 2 | 2 | 4% |
| 20 | 2 | 2 | 11% |
| 31 | 2 | 2 | 22% |
| 41 | 2 | 2 | 22% |
| 51 | 2 | 2 | 36% |
| 61 | 2 | 2 | 66% |
| 71 | 2 | 2 | 66% |
| 81 | 2 | 3 | 88% |
| 92 | 3 | 5 | 169% |
| 102 | 5 | 6 | 188% |
| 112 | 5 | 6 | 188% |
| 122 | 6 | 6 | 165% |
| 132 | 6 | 6 | 172% |
| 143 | 6 | 6 | 172% |
| 153 | 6 | 6 | 202% |
| 163 | 6 | 6 | 3% |
| 173 | 6 | 6 | 3% |
| 183 | 6 | 6 | 54% |
| 194 | 6 | 6 | 96% |
| 204 | 6 | 6 | 96% |
| 214 | 6 | 6 | 115% |
| 224 | 6 | 6 | 114% |
| 234 | 6 | 6 | 114% |
| 245 | 6 | 6 | 85% |
| 255 | 6 | 6 | 39% |
| 265 | 6 | 6 | 39% |
| 275 | 6 | 6 | 10% |
| 285 | 6 | 6 | 4% |
| 296 | 6 | 6 | 4% |
| 306 | 6 | 5 | 4% |
| 316 | 5 | 5 | 4% |
| 326 | 5 | 5 | 4% |
| 336 | 5 | 4 | 4% |
| 346 | 4 | 4 | 4% |
| 357 | 4 | 4 | 4% |
| 367 | 4 | 3 | 4% |
| 377 | 3 | 3 | 5% |
| 387 | 3 | 3 | 5% |
| 397 | 3 | 2 | 4% |
| 407 | 2 | 2 | 5% |

## k6 summary

```text


   THRESHOLDS 

    dropped_iterations
     'count<1' count=19

    http_req_duration
     'p(95)<500' p(95)=40.43ms

    http_req_failed
     'rate<0.005' rate=0.00%


   TOTAL RESULTS 

    checks_total.......: 20530  85.542846/s
    checks_succeeded...: 99.99% 20528 out of 20530
    checks_failed......: 0.00%  2 out of 20530

     order confirmed
        99%   20528 /  2

    HTTP
    http_req_duration..............: avg=17ms    med=9.03ms p(90)=20.22ms p(95)=40.43ms p(99)=167.75ms max=860.37ms
      { expected_response:true }...: avg=17ms    med=9.03ms p(90)=20.22ms p(95)=40.43ms p(99)=167.76ms max=860.37ms
    http_req_failed................: 0.00%  2 out of 20531
    http_reqs......................: 20531  85.547013/s

    EXECUTION
    dropped_iterations.............: 19     0.079168/s
    iteration_duration.............: avg=17.46ms med=9.44ms p(90)=20.95ms p(95)=41.01ms p(99)=169.67ms max=860.58ms
    iterations.....................: 20530  85.542846/s
    vus............................: 0      min=0          max=60
    vus_max........................: 67     min=50         max=67

    NETWORK
    data_received..................: 4.7 MB 20 kB/s
    data_sent......................: 4.3 MB 18 kB/s

--- k6 log (stderr) ---
time="2026-10-29T03:12:39Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-29T03:14:07Z" level=error msg="thresholds on metrics 'dropped_iterations' have been crossed"
```

