### 1.1.1 / 2024-08-27
* Support for `redis-client` client (used by Sidekiq 7)
* Remove `Sidekiq::DeadSet#kill` extension.
* `module Sidekiq::Killswitch; end` replaced with `module Sidekiq; module Killswitch; ...`.
* We're now using `warn` instead of `info` to log worker blackholed/dead_queued messaged. 

### 1.1.0 / 2024-07-01
* Add in warning banner to Sidekiq UI so users are linked to docs and informed of the difference of sending jobs to blackhole vs. dead queue

### 1.0.0 / 2018-02-20
* `1.0.0.pre2` released as `1.0.0`.

### 1.0.0.pre2 / 2017-08-14
* Bugfix: job hash serialization before putting to the dead queue 

### 1.0.0.pre1 / 2017-08-14
* Initial release - wip
