# Checkout load test results

Run on 2026-10-26 20:25 against the local kind cluster. **FAIL - at least one threshold was crossed.**

- Load: 10 req/s -> 300 req/s (open model, `ramping-arrival-rate`), warm 30s, ramp 60s, hold 120s, cool 30s. Every request is `POST /checkout` and must return 201.
- Pass/fail thresholds are the checkout SLOs: failed requests < 0.5%, p95 < 500 ms, and no dropped iterations (k6 itself kept up).
- Autoscaler: 2 to 6 replicas, CPU target 70% of the 100m request. Observed: first scale-up decision at t=61 s; peak 6 replicas, first reached at t=92 s; back to 2 replicas at t=870 s.
- Runner: Docker image grafana/k6:latest. Docker Desktop: 8 CPUs, 7.6 GiB RAM. k6, kind, Prometheus, Grafana and the services all share this one machine, so absolute numbers are indicative only.

## Autoscaler timeline

k6 ended at t=687 s.

| t (s) | replicas | desired | CPU vs request (target 70%) |
|---|---|---|---|
| 0 | 2 | 2 | 5% |
| 10 | 2 | 2 | 4% |
| 21 | 2 | 2 | 7% |
| 31 | 2 | 2 | 35% |
| 41 | 2 | 2 | 35% |
| 51 | 2 | 2 | 44% |
| 61 | 2 | 4 | 141% |
| 71 | 2 | 4 | 141% |
| 82 | 4 | 6 | 251% |
| 92 | 6 | 6 | 336% |
| 102 | 6 | 6 | 336% |
| 112 | 6 | 6 | 268% |
| 122 | 6 | 6 | 209% |
| 133 | 6 | 6 | 209% |
| 143 | 6 | 6 | 202% |
| 153 | 6 | 6 | 201% |
| 163 | 6 | 6 | 201% |
| 173 | 6 | 6 | 218% |
| 183 | 6 | 6 | 231% |
| 194 | 6 | 6 | 231% |
| 204 | 6 | 6 | 216% |
| 214 | 6 | 6 | 208% |
| 224 | 6 | 6 | 208% |
| 677 | 6 | 6 | 210% |
| 687 | 6 | 6 | 111% |
| 697 | 6 | 6 | 111% |
| 707 | 6 | 6 | 56% |
| 718 | 6 | 6 | 17% |
| 728 | 6 | 6 | 17% |
| 738 | 6 | 6 | 5% |
| 748 | 6 | 6 | 4% |
| 758 | 6 | 6 | 4% |
| 768 | 6 | 5 | 4% |
| 779 | 5 | 5 | 4% |
| 789 | 5 | 5 | 4% |
| 799 | 5 | 4 | 4% |
| 809 | 4 | 4 | 5% |
| 819 | 4 | 3 | 4% |
| 829 | 4 | 3 | 4% |
| 839 | 3 | 3 | 4% |
| 850 | 3 | 2 | 4% |
| 860 | 3 | 2 | 4% |
| 870 | 2 | 2 | 5% |

## k6 summary

```text


  █ THRESHOLDS 

    dropped_iterations
    ✗ 'count<1' count=18024

    http_req_duration
    ✗ 'p(95)<500' p(95)=4.99s

    http_req_failed
    ✗ 'rate<0.005' rate=7.98%


  █ TOTAL RESULTS 

    checks_total.......: 32225  47.223093/s
    checks_succeeded...: 92.01% 29653 out of 32225
    checks_failed......: 7.98%  2572 out of 32225

    ✗ order confirmed
      ↳  92% — ✓ 29653 / ✗ 2572

    HTTP
    http_req_duration..............: avg=3.82s med=2.07s p(90)=4.53s p(95)=4.99s p(99)=5.66s max=7m26s
      { expected_response:true }...: avg=3.31s med=2.1s  p(90)=4.57s p(95)=5s    p(99)=5.61s max=7m26s
    http_req_failed................: 7.98%  2572 out of 32226
    http_reqs......................: 32226  47.224559/s

    EXECUTION
    dropped_iterations.............: 18024  26.412693/s
    iteration_duration.............: avg=2.14s med=2.06s p(90)=4.5s  p(95)=4.96s p(99)=5.51s max=8.28s
    iterations.....................: 32225  47.223093/s
    vus............................: 0      min=0             max=500
    vus_max........................: 500    min=50            max=500

    NETWORK
    data_received..................: 7.3 MB 11 kB/s
    data_sent......................: 6.8 MB 9.9 kB/s

--- k6 log (stderr) ---
time="2026-10-26T14:57:22Z" level=warning msg="Insufficient VUs, reached 500 active VUs and cannot initialize more" executor=ramping-arrival-rate scenario=checkout
time="2026-10-26T14:59:34Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-26T14:59:34Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-26T15:07:12Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-26T15:07:12Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-26T15:07:17Z" level=error msg="thresholds on metrics 'dropped_iterations, http_req_duration, http_req_failed' have been crossed"
```

