---
# Job abstraction layer
---
## Motivation
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
      QueryReportWorker.perform_async(@report.id,
		  current_user.id, job.id, params)
      render_json_dump({job_id: job.id})
    end
---
## Examples

	# New worker for everything!
	QueryReportWorker.perform_async(1, 2, 3)
	DataTranformWorker.perform_async(1, 2, 3)
	DataImportWorker.perform_async(1, 2, 3)
	BlahBlahWorker.perform_async(1, 2, 3)
---
## How about this?

	class QueryReport
	  include Queueable
	end

    # Look, ma, no Worker class!
    def submit_query
      job = @report.async.execute(user_id, params)
      render_json_dump({job_id: job.id})
    end
---
## After
* No need to add Worker class each time we need to run an async job
* Additional job management features like deduplication, custom caching, retry, custom queues, etc.
---
## But how?

    #returns an AsyncDelegator that stores async_options
    delegator = report.async(async_options)

    # When a method is sent to the delegator
    delegator.do_something_cool(arg1, arg2)

    # Use 'method_missing' to store the method name and arguments,
    # then creates a new job with async_options, method name,
    # method arguments, cache key, etc.
    job = delegator.new_job

    # finally calls JobWorker.perform_async(job_id)
    job.queue
---
## Limitation

* `.async` only supports ActiveModel objects or class static methods
  since it is reinstantiated later inside `job.execute` method.
* Method arguments must be serializable to database (string, number, hash, array etc.)
---
### Additional async options
---
## Caching options

* cache_duration (in seconds): duration which the cache is kepts
* cache_key: string that specifies the cache key for returned data
* cache_method: name of method that is executed to generate the cache key, can't be used together with cache_keyoption
---
## Deduplication

* merge_duplicate: job with the exact same source object id, execution method and params as another job within the last duplicate_duration will not be created. Instead, the older identical job will be returned.
* duplicate_duration (in seconds): see merge_duplicate option. Default to 10*60 seconds or 10 minutes
---
## Custom queues

* tag: tag used together with tenant level job limiting, can be either filter, report, or anything else which will be merged to default limit.
* worker_options: options that will be passed over to the lower job execution layer, e.g. Sidekiq
---
## Others
* execute_inline (boolean): options that allow for the job to be executed inline (synchronously) instead of sending it to the background job layer. This is useful for case when you want to execute synchronous code but still want to have duplication detection, caching, etc. like an async job.

