# Sidekiq::Killswitch
![Brought to you by Square](https://github.com/square/sidekiq-killswitch/raw/master/examples/square-logo.svg)

## Description

Cross-host Sidekiq worker killswitches. 

## Features
- Blackhole a worker - new jobs won't be pushed to Redis. Already queued jobs will be marked as processed without being executed.
- Send a worker to the dead queue - Sidekiq will put all jobs for this worker to the "Dead jobs" list without executing them.
- Sidekiq Web UI integration.
- Worker class verification. Disabled by default.


### How does it work?

`Sidekiq::Killswitch` works as Sidekiq server and client middleware.

*Blackholed workers* - when `YourWorker#perform_async` is called, `Sidekiq::Killswitch::Middleware::Client` checks 
if `YourWorker` was blackholed. If yes, it will reject pushing a job to Redis. When someone blackholes a worker that 
already has some jobs in the queue, `Sidekiq::Killswitch::Middleware::Server` will mark those as processed without 
actually executing them. 
    
*Dead-queued workers* - before executing job on the server, `Sidekiq::Killswitch::Middleware::Server` checks if the worker
was dead-queued. If yes, it sends a job directly to the Sidekiq "Dead jobs", without running it.  
_\* Sidekiq does not store unlimited number of jobs in Dead queue forever. 
By default, right after adding a new job to the Dead queue, 
it removes all but last `10_000` dead jobs (`Sidekiq.options[:dead_max_jobs]`),
it also removes all dead jobs older than 6 months (`Sidekiq.options[:dead_timeout_in_seconds]`)._  

*Worker class validation (Web UI)* - since you need to type in worker class name manually in the web interface to either 
blackhole it or add it to the dead-queue, there is an optional feature that performs Sidekiq Worker class validation.
When worker class name is being submitted for dead-queuing or blackholing **via Web UI (only)**, 
`Sidekiq::Killswitch` will only allow it if it includes `Sidekiq::Worker` in it's ancestor list.    
To enable it:
```ruby
# In your ./config/initializer/sidekiq_killswitch.rb 

Sidekiq::Killswitch.configure do |config|
  config.validate_worker_class_in_web # Enables Sidekiq Worker class validation in Web UI. Optional. Disabled by default.
end
```

It's disabled by default, because Sidekiq Web UI by default is a standalone Rack application which doesn't have to know
anything about your main Ruby app. 
 

`Sidekiq::Killswitch` uses the same Redis database as `Sidekiq` under the hood.    

The logs are written to `Sidekiq::Killswitch.logger` which you can customize (see *Configuration* section).


## Installation

Add this line to your application's Gemfile:
```ruby
gem 'sidekiq-killswitch'
```
And then execute:
```ruby
bundle
```

## Configuration
```ruby
# In your ./config/initializer/sidekiq_killswitch.rb 

Sidekiq::Killswitch.configure do |config|
  config.logger = MyLogger.new # Defaults to Rails.logger first, then Sidekiq.logger. Optional.
  config.validate_worker_class_in_web # Enables Sidekiq Worker class validation in Web UI. Optional. Disabled by default.
  config.web_ui_worker_validator = proc do |worker_name| # Manually set Web UI worker class validator
    !worker_name.nil? && worker_name.end_with?('Worker') # Only allow to dead-queue/blackhole classes that end with "Worker" suffix. <= bad idea, only used here as an example.
  end
end
```

Add Killswitch middleware to Sidekiq:
```ruby
# In your config/initializers/sidekiq.rb
require 'sidekiq/killswitch/middleware/load_all'
```
or you can load all parts manually:
```ruby
# In your config/initializers/sidekiq.rb
 
Sidekiq.configure_server do |config|
  config.server_middleware do |chain|
    chain.add Sidekiq::Killswitch::Middleware::Server
  end

  config.client_middleware do |chain|
    # The jobs running in the Sidekiq server can themselves push new jobs to Sidekiq.
    chain.add Sidekiq::Killswitch::Middleware::Client 
  end  
end

Sidekiq.configure_client do |config|
  config.client_middleware do |chain|
    chain.add Sidekiq::Killswitch::Middleware::Client
  end
end
```

Load Killswitch Sidekiq Web UI extension: 
1. Find a file where you `require 'sidekiq/web'`
2. Add `require 'sidekiq/killswitch/web'` after that line.
```
# In your ./config/routes.rb or ./config.ru 

require 'sidekiq/web'
require 'sidekiq/killswitch/web'
... 
```

## Usage

### Web UI
![Web UI](https://github.com/square/sidekiq-killswitch/raw/master/examples/killswitch-web-ui.png)

`Sidekiq::Killswitch` integrates into Sidekiq Web app. A new tab "Kill Switches" will be added to Sidekiq admin panel
when you load the extension (see steps above for how to load it).   
There are two sections in Web UI: "Blackholed Workers" and "Dead Queue Workers". Each section lists all Blackholed/Dead-Queued
workers, also allows you add or remove workers from those lists.

### API
```ruby
# worker_name argument can be a String or a Class
#
# Blackhole
Sidekiq::Killswitch.blackhole_add_worker(worker_name) 
Sidekiq::Killswitch.blackhole_remove_worker(worker_name)
Sidekiq::Killswitch.blackhole_worker?(worker_name)
Sidekiq::Killswitch.blackhole_workers
# Dead queue
Sidekiq::Killswitch.dead_queue_add_worker(worker_name)
Sidekiq::Killswitch.dead_queue_remove_worker(worker_name)
Sidekiq::Killswitch.dead_queue_worker?(worker_name)
Sidekiq::Killswitch.dead_queue_workers
```

## Copyright

Copyright 2017 Square Inc.
 
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at
 
    http://www.apache.org/licenses/LICENSE-2.0
 
Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
