# Checkout load test results

Run on 2026-10-28 20:28 against the local kind cluster. **FAIL - at least one threshold was crossed.**

- Load: 10 req/s -> 300 req/s (open model, `ramping-arrival-rate`), warm 30s, ramp 60s, hold 120s, cool 30s. Every request is `POST /checkout` and must return 201.
- Pass/fail thresholds are the checkout SLOs: failed requests < 0.5%, p95 < 500 ms, and no dropped iterations (k6 itself kept up).
- Autoscaler: 3 to 6 replicas, CPU target 70% of the 100m request. Observed: first scale-up decision at t=82 s; peak 6 replicas, first reached at t=112 s; back to 3 replicas at t=397 s.
- Runner: Docker image grafana/k6:latest. Docker Desktop: 8 CPUs, 7.6 GiB RAM. k6, kind, Prometheus, Grafana and the services all share this one machine, so absolute numbers are indicative only.

## Autoscaler timeline

k6 ended at t=245 s.

| t (s) | replicas | desired | CPU vs request (target 70%) |
|---|---|---|---|
| 0 | 3 | 3 | 4% |
| 10 | 3 | 3 | 4% |
| 21 | 3 | 3 | 5% |
| 31 | 3 | 3 | 5% |
| 41 | 3 | 3 | 20% |
| 51 | 3 | 3 | 24% |
| 61 | 3 | 3 | 24% |
| 71 | 3 | 3 | 65% |
| 82 | 3 | 5 | 116% |
| 92 | 5 | 6 | 273% |
| 102 | 5 | 6 | 273% |
| 112 | 6 | 6 | 333% |
| 123 | 6 | 6 | 298% |
| 133 | 6 | 6 | 298% |
| 143 | 6 | 6 | 199% |
| 153 | 6 | 6 | 200% |
| 163 | 6 | 6 | 200% |
| 173 | 6 | 6 | 195% |
| 184 | 6 | 6 | 194% |
| 194 | 6 | 6 | 194% |
| 204 | 6 | 6 | 207% |
| 214 | 6 | 6 | 215% |
| 224 | 6 | 6 | 215% |
| 235 | 6 | 6 | 197% |
| 245 | 6 | 6 | 204% |
| 255 | 6 | 6 | 204% |
| 265 | 6 | 6 | 165% |
| 275 | 6 | 6 | 35% |
| 285 | 6 | 6 | 35% |
| 295 | 6 | 6 | 5% |
| 306 | 6 | 6 | 4% |
| 316 | 6 | 6 | 4% |
| 326 | 6 | 5 | 3% |
| 336 | 5 | 5 | 3% |
| 346 | 5 | 5 | 3% |
| 356 | 5 | 4 | 4% |
| 366 | 4 | 4 | 4% |
| 377 | 4 | 4 | 4% |
| 387 | 4 | 3 | 4% |
| 397 | 3 | 3 | 4% |

## k6 summary

```text


   THRESHOLDS 

    dropped_iterations
     'count<1' count=19314

    http_req_duration
     'p(95)<500' p(95)=5.1s

    http_req_failed
     'rate<0.005' rate=0.08%


   TOTAL RESULTS 

    checks_total.......: 30935  128.898926/s
    checks_succeeded...: 99.91% 30908 out of 30935
    checks_failed......: 0.08%  27 out of 30935

     order confirmed
        99%   30908 /  27

    HTTP
    http_req_duration..............: avg=2.33s med=2.29s p(90)=4.59s p(95)=5.1s p(99)=6.04s max=6.65s
      { expected_response:true }...: avg=2.33s med=2.29s p(90)=4.59s p(95)=5.1s p(99)=6.04s max=6.65s
    http_req_failed................: 0.08%  27 out of 30936
    http_reqs......................: 30936  128.903093/s

    EXECUTION
    dropped_iterations.............: 19314  80.476931/s
    iteration_duration.............: avg=2.33s med=2.29s p(90)=4.6s  p(95)=5.1s p(99)=6.04s max=6.65s
    iterations.....................: 30935  128.898926/s
    vus............................: 0      min=0           max=500
    vus_max........................: 500    min=50          max=500

    NETWORK
    data_received..................: 7.1 MB 29 kB/s
    data_sent......................: 6.5 MB 27 kB/s

--- k6 log (stderr) ---
time="2026-10-28T14:59:37Z" level=warning msg="Insufficient VUs, reached 500 active VUs and cannot initialize more" executor=ramping-arrival-rate scenario=checkout
time="2026-10-28T15:00:28Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-28T15:00:29Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-28T15:00:29Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-28T15:00:29Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-28T15:00:29Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-28T15:00:29Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-28T15:00:29Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-28T15:00:29Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-28T15:00:29Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-28T15:00:30Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-28T15:00:30Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-28T15:00:30Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-28T15:00:30Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-28T15:00:30Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-28T15:00:30Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-28T15:00:30Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-28T15:00:30Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-28T15:00:30Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-28T15:00:30Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-28T15:00:30Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-28T15:00:31Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-28T15:00:31Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-28T15:00:32Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-28T15:00:32Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-28T15:00:32Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-28T15:01:06Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-28T15:01:06Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-28T15:02:08Z" level=error msg="thresholds on metrics 'dropped_iterations, http_req_duration' have been crossed"
```

