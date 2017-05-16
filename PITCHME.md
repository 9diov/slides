---
### Motivation
---
## Before job abstraction layer
* Create a new worker class
* Manually store the result in cache
* Manually polling and retrieving data from cache
* Custom code for each worker class when deduplication, retry is needed
---
## Old async code

	class QueryReportWorker
	  include Sidekiq::Worker

	  def perform(report_id, user_id, job_id, params)
		# run query and store to cache
	  end
	end

    def submit_query
      job = Job.new(source: @report)
      QueryReportWorker.perform_async(@report.id, current_user.id, job.id, params)
      render_json_dump({job_id: job.id})
    end
---
## Examples
* `QueryReportWorker.perform_async(1, 2, 3)`
* `DataTranformWorker.perform_async(1, 2, 3)`
* `DataImportWorker.perform_async(1, 2, 3)`
* `BlahBlahWorker.perform_async(1, 2, 3)`
* @.@
---
## How about this?
* `job = report.async.do_something_cool(arg1, arg2)`
* `result = job.fetch_cache_data`
* Look, ma, no Worker class!
---
## After
* No need to add Worker class each time we need to run an async job
* Additional job management features like deduplication, custom caching, retry, custom queues, etc.
---
## But how?
* `delegator = report.async(async_options)` returns an AsyncDelegator that stores async_options
* `delegator.do_something_cool(arg1, arg2)` uses `method_missing` to store the method name and arguments
* `job = delegator.new_job` creates a new job with async_options,method name, method arguments, cache key, etc.
* `job.queue` internally calls JobWorker.perform_async(job_id)

