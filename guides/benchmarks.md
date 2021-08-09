# Benchmarks

## JSON

AbsintheGraphqlWS allows for alternate JSON libraries to be configured.

```text
Operating System: macOS
CPU Information: Intel(R) Core(TM) i9-9980HK CPU @ 2.40GHz
Number of Available Cores: 16
Available memory: 64 GB
Elixir 1.12.2
Erlang 24.0.3

Benchmark suite executing with the following configuration:
warmup: 2 s
time: 5 s
memory time: 0 ns
parallel: 1
inputs: Jason, eljiffy
Estimated total run time: 1.40 min

Benchmarking large decode with input Jason...
Benchmarking large decode with input eljiffy...
Benchmarking large encode with input Jason...
Benchmarking large encode with input eljiffy...
Benchmarking medium decode with input Jason...
Benchmarking medium decode with input eljiffy...
Benchmarking medium encode with input Jason...
Benchmarking medium encode with input eljiffy...
Benchmarking small decode with input Jason...
Benchmarking small decode with input eljiffy...
Benchmarking small encode with input Jason...
Benchmarking small encode with input eljiffy...

##### With input Jason #####
Name                    ips        average  deviation         median         99th %
small decode      1103.70 K        0.91 μs  ±4312.20%           1 μs           1 μs
small encode      1078.35 K        0.93 μs  ±3463.63%           1 μs           1 μs
medium encode      103.78 K        9.64 μs    ±79.58%           8 μs          38 μs
medium decode       85.70 K       11.67 μs    ±46.50%          11 μs          37 μs
large encode         3.99 K      250.75 μs    ±29.34%         217 μs         546 μs
large decode         2.64 K      378.97 μs    ±22.34%         375 μs         689 μs

Comparison:
small decode      1103.70 K
small encode      1078.35 K - 1.02x slower +0.0213 μs
medium encode      103.78 K - 10.63x slower +8.73 μs
medium decode       85.70 K - 12.88x slower +10.76 μs
large encode         3.99 K - 276.75x slower +249.84 μs
large decode         2.64 K - 418.27x slower +378.07 μs

##### With input eljiffy #####
Name                    ips        average  deviation         median         99th %
small encode       893.73 K        1.12 μs  ±2376.27%           1 μs           2 μs
small decode       695.66 K        1.44 μs  ±1905.46%           1 μs           3 μs
medium encode      127.91 K        7.82 μs   ±131.83%           7 μs          34 μs
medium decode       39.59 K       25.26 μs    ±39.96%          22 μs          73 μs
large encode         5.50 K      181.85 μs    ±36.52%         163 μs      388.35 μs
large decode         2.92 K      342.55 μs    ±47.92%         374 μs      767.51 μs

Comparison:
small encode       893.73 K
small decode       695.66 K - 1.28x slower +0.32 μs
medium encode      127.91 K - 6.99x slower +6.70 μs
medium decode       39.59 K - 22.57x slower +24.14 μs
large encode         5.50 K - 162.53x slower +180.73 μs
large decode         2.92 K - 306.15x slower +341.43 μs
```
