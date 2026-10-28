# Checkout load test results

Run on 2026-10-26 21:06 against the local kind cluster. **FAIL - at least one threshold was crossed.**

- Load: 10 req/s -> 300 req/s (open model, `ramping-arrival-rate`), warm 30s, ramp 60s, hold 120s, cool 30s. Every request is `POST /checkout` and must return 201.
- Pass/fail thresholds are the checkout SLOs: failed requests < 0.5%, p95 < 500 ms, and no dropped iterations (k6 itself kept up).
- Autoscaler: 3 to 6 replicas, CPU target 70% of the 100m request. Observed: first scale-up decision at t=81 s; peak 6 replicas, first reached at t=92 s; back to 3 replicas at t=431 s.
- Runner: Docker image grafana/k6:latest. Docker Desktop: 8 CPUs, 7.6 GiB RAM. k6, kind, Prometheus, Grafana and the services all share this one machine, so absolute numbers are indicative only.

## Autoscaler timeline

k6 ended at t=244 s.

| t (s) | replicas | desired | CPU vs request (target 70%) |
|---|---|---|---|
| 0 | 3 | 3 | 5% |
| 10 | 3 | 3 | n/a |
| 20 | 3 | 3 | n/a |
| 31 | 3 | 3 | 29% |
| 41 | 3 | 3 | 29% |
| 51 | 3 | 3 | 23% |
| 61 | 3 | 3 | 42% |
| 71 | 3 | 3 | 42% |
| 81 | 3 | 6 | 138% |
| 92 | 6 | 6 | 263% |
| 102 | 6 | 6 | 263% |
| 112 | 6 | 6 | 298% |
| 122 | 6 | 6 | 255% |
| 132 | 6 | 6 | 255% |
| 142 | 6 | 6 | 251% |
| 153 | 6 | 6 | 238% |
| 163 | 6 | 6 | 238% |
| 173 | 6 | 6 | 257% |
| 183 | 6 | 6 | 250% |
| 193 | 6 | 6 | 250% |
| 204 | 6 | 6 | 234% |
| 214 | 6 | 6 | 233% |
| 224 | 6 | 6 | 233% |
| 234 | 6 | 6 | 176% |
| 244 | 6 | 6 | 172% |
| 255 | 6 | 6 | 172% |
| 265 | 6 | 6 | 129% |
| 309 | 6 | 6 | 58% |
| 319 | 6 | 6 | 58% |
| 329 | 6 | 6 | 5% |
| 339 | 6 | 6 | 2% |
| 349 | 6 | 6 | 2% |
| 360 | 6 | 5 | 4% |
| 370 | 5 | 5 | 4% |
| 380 | 5 | 5 | 4% |
| 390 | 5 | 4 | 4% |
| 401 | 4 | 4 | 4% |
| 411 | 4 | 3 | 4% |
| 421 | 4 | 3 | 4% |
| 431 | 3 | 3 | 4% |

## k6 summary

```text


  █ THRESHOLDS 

    dropped_iterations
    ✗ 'count<1' count=16870

    http_req_duration
    ✗ 'p(95)<500' p(95)=6.06s

    http_req_failed
    ✗ 'rate<0.005' rate=2.75%


  █ TOTAL RESULTS 

    checks_total.......: 33379  139.083271/s
    checks_succeeded...: 97.24% 32461 out of 33379
    checks_failed......: 2.75%  918 out of 33379

    ✗ order confirmed
      ↳  97% — ✓ 32461 / ✗ 918

    HTTP
    http_req_duration..............: avg=2.21s med=1.67s p(90)=5.74s p(95)=6.06s p(99)=6.59s max=7.08s
      { expected_response:true }...: avg=2.19s med=1.64s p(90)=5.75s p(95)=6.07s p(99)=6.6s  max=7.08s
    http_req_failed................: 2.75%  918 out of 33380
    http_reqs......................: 33380  139.087438/s

    EXECUTION
    dropped_iterations.............: 16870  70.293741/s
    iteration_duration.............: avg=2.22s med=1.68s p(90)=5.74s p(95)=6.06s p(99)=6.59s max=7.08s
    iterations.....................: 33379  139.083271/s
    vus............................: 0      min=0            max=500
    vus_max........................: 500    min=50           max=500

    NETWORK
    data_received..................: 7.6 MB 32 kB/s
    data_sent......................: 7.0 MB 29 kB/s

--- k6 log (stderr) ---
time="2026-10-26T15:36:41Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-26T15:37:55Z" level=warning msg="Insufficient VUs, reached 500 active VUs and cannot initialize more" executor=ramping-arrival-rate scenario=checkout
time="2026-10-26T15:39:09Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-26T15:39:09Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-26T15:39:10Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-26T15:39:10Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-26T15:39:10Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-26T15:39:10Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-26T15:39:10Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-26T15:39:10Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-26T15:39:11Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-26T15:39:11Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-26T15:39:11Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-26T15:39:11Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-26T15:39:12Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-26T15:39:12Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-26T15:39:12Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-26T15:39:12Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-26T15:39:12Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-26T15:39:12Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-26T15:39:12Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-26T15:39:12Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-26T15:39:12Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-26T15:39:13Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-26T15:39:13Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-26T15:39:13Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-26T15:39:13Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-26T15:40:29Z" level=error msg="thresholds on metrics 'dropped_iterations, http_req_duration, http_req_failed' have been crossed"
```

