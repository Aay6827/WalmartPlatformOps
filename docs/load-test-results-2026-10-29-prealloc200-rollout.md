# Checkout load test results

Run on 2026-10-29 09:35 against the local kind cluster. **FAIL - at least one threshold was crossed (NOT A CLEAN RUN: checkout and inventory was redeployed during the test).**

- Load: 10 req/s -> 120 req/s (open model, `ramping-arrival-rate`), warm 30s, ramp 60s, hold 120s, cool 30s. Every request is `POST /checkout` and must return 201.
- Pass/fail thresholds are the checkout SLOs: failed requests < 0.5%, p95 < 500 ms, and no dropped iterations (k6 itself kept up).
- Autoscaler: 2 to 6 replicas, CPU target 70% of the 100m request. Observed: first scale-up decision at t=81 s; peak 6 replicas, first reached at t=122 s; back to 2 replicas at t=419 s.
- Runner: Docker image grafana/k6:latest. Docker Desktop: 8 CPUs, 7.6 GiB RAM. k6, kind, Prometheus, Grafana and the services all share this one machine, so absolute numbers are indicative only.

## Autoscaler timeline

k6 ended at t=256 s.

| t (s) | replicas | desired | CPU vs request (target 70%) |
|---|---|---|---|
| 0 | 2 | 2 | 5% |
| 10 | 2 | 2 | 5% |
| 20 | 2 | 2 | 4% |
| 31 | 2 | 2 | 18% |
| 41 | 2 | 2 | 18% |
| 51 | 2 | 2 | 39% |
| 61 | 2 | 2 | 57% |
| 71 | 2 | 2 | 57% |
| 81 | 2 | 3 | 101% |
| 92 | 3 | 5 | 148% |
| 102 | 3 | 5 | 148% |
| 112 | 5 | 6 | 139% |
| 122 | 6 | 6 | 169% |
| 132 | 6 | 6 | 169% |
| 142 | 6 | 6 | 106% |
| 153 | 6 | 6 | 85% |
| 163 | 6 | 6 | 85% |
| 174 | 6 | 6 | 85% |
| 184 | 6 | 6 | 85% |
| 205 | 6 | 6 | 97% |
| 216 | 6 | 6 | 97% |
| 226 | 6 | 6 | 64% |
| 236 | 6 | 6 | 276% |
| 246 | 6 | 6 | 276% |
| 256 | 6 | 6 | 3% |
| 267 | 6 | 6 | 18% |
| 277 | 6 | 6 | 18% |
| 287 | 6 | 6 | 10% |
| 297 | 6 | 6 | 4% |
| 307 | 6 | 6 | 4% |
| 317 | 6 | 5 | 4% |
| 327 | 5 | 5 | 4% |
| 338 | 5 | 5 | 4% |
| 348 | 5 | 4 | 4% |
| 358 | 4 | 4 | 4% |
| 368 | 4 | 4 | 4% |
| 378 | 4 | 3 | 4% |
| 388 | 3 | 3 | 4% |
| 398 | 3 | 3 | 4% |
| 409 | 3 | 2 | 5% |
| 419 | 2 | 2 | 4% |

## k6 summary

```text


   THRESHOLDS 

    dropped_iterations
     'count<1' count=18

    http_req_duration
     'p(95)<500' p(95)=36.78ms

    http_req_failed
     'rate<0.005' rate=0.15%


   TOTAL RESULTS 

    checks_total.......: 20531  81.704355/s
    checks_succeeded...: 99.84% 20500 out of 20531
    checks_failed......: 0.15%  31 out of 20531

     order confirmed
        99%   20500 /  31

    HTTP
    http_req_duration..............: avg=36.8ms  med=8.01ms p(90)=15.42ms p(95)=36.78ms p(99)=1.39s max=11.29s
      { expected_response:true }...: avg=36.85ms med=8.02ms p(90)=15.44ms p(95)=36.79ms p(99)=1.39s max=11.29s
    http_req_failed................: 0.15%  31 out of 20532
    http_reqs......................: 20532  81.708335/s

    EXECUTION
    dropped_iterations.............: 18     0.071632/s
    iteration_duration.............: avg=80.68ms med=8.4ms  p(90)=17.03ms p(95)=40.52ms p(99)=1.58s max=30s   
    iterations.....................: 20531  81.704355/s
    vus............................: 0      min=0           max=205
    vus_max........................: 216    min=200         max=216

    NETWORK
    data_received..................: 4.7 MB 19 kB/s
    data_sent......................: 4.3 MB 17 kB/s

--- k6 log (stderr) ---
time="2026-10-29T04:06:41Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": EOF"
time="2026-10-29T04:06:49Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": dial: i/o timeout"
time="2026-10-29T04:06:50Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": dial: i/o timeout"
time="2026-10-29T04:06:51Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": dial: i/o timeout"
time="2026-10-29T04:06:51Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": dial: i/o timeout"
time="2026-10-29T04:06:52Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": dial: i/o timeout"
time="2026-10-29T04:06:52Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": dial: i/o timeout"
time="2026-10-29T04:06:53Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": dial: i/o timeout"
time="2026-10-29T04:06:53Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": dial: i/o timeout"
time="2026-10-29T04:06:53Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": dial: i/o timeout"
time="2026-10-29T04:06:53Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": dial: i/o timeout"
time="2026-10-29T04:06:54Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": dial: i/o timeout"
time="2026-10-29T04:06:54Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": dial: i/o timeout"
time="2026-10-29T04:07:09Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": dial: i/o timeout"
time="2026-10-29T04:07:09Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": dial: i/o timeout"
time="2026-10-29T04:07:09Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": dial: i/o timeout"
time="2026-10-29T04:07:09Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": dial: i/o timeout"
time="2026-10-29T04:07:09Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": dial: i/o timeout"
time="2026-10-29T04:07:09Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": dial: i/o timeout"
time="2026-10-29T04:07:09Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": dial: i/o timeout"
time="2026-10-29T04:07:09Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": dial: i/o timeout"
time="2026-10-29T04:07:10Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": dial: i/o timeout"
time="2026-10-29T04:07:10Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": dial: i/o timeout"
time="2026-10-29T04:07:10Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": dial: i/o timeout"
time="2026-10-29T04:07:10Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": dial: i/o timeout"
time="2026-10-29T04:07:10Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": dial: i/o timeout"
time="2026-10-29T04:07:10Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": dial: i/o timeout"
time="2026-10-29T04:07:10Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": dial: i/o timeout"
time="2026-10-29T04:07:10Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": dial: i/o timeout"
time="2026-10-29T04:07:10Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": dial: i/o timeout"
time="2026-10-29T04:07:11Z" level=warning msg="Request Failed" error="Post \"http://host.docker.internal:31000/checkout\": dial: i/o timeout"
time="2026-10-29T04:10:05Z" level=error msg="thresholds on metrics 'dropped_iterations' have been crossed"
```

