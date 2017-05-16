---
# Job abstraction layer
---
## Why need jobs?

* Executing query synchronously means the Rails web app hangs why the query is being executed
* Production has only 16 Unicorn workers per node, meaning it can only runs 16 queries at the same time
---
## Sidekiq

* Most popular job processing framework for Ruby
* Uses threads to handle multiple jobs at the same time
* Uses Redis to store job metadata and as synchronization server
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
## New worker for everything!

	QueryReportWorker.perform_async(report_id, job.id)
	DataTranformWorker.perform_async(data_tranform_id, job.id)
	DataImportWorker.perform_async(data_import_id, job.id)
	BlahBlahWorker.perform_async
---
## Problems

* Need to create a new worker class for new use case
* Sidekiq's advanced queue management is limited: no deduplication, no custom retry, no queue limit, etc.
---
## How about this?

	class QueryReport
	  include Queueable
	end

    # Look, ma, no Worker class!
    def submit_query
      job = @report.async.execute(current_user.id, params)
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
---
## Queuing system in Postgres

* Job abstraction layer depend on Job class for queuing
* Need to build a robust queuing mechanism on top of Postgres
---
## Job life cycle

* created
* queued (sent to Sidekiq)
* running (being executed by Sidekiq)
* successful (completes successfully)
* failed (throw error during execution)
---
## How do we send the jobs to Sidekiq?

*  As soon as it is created - simplest but can't support per queue limit
* Create a third coordinator that polls the jobs table and send it to Sidekiq - complex architecture
* Currently used - when a job completes executation, it scan for the next queable job and send that to Sidekiq
---
## Naive strategy - can you spot the issue?

	# When a report job finishes, get next queuable job
	job = Job.where(tag: 'report', status: 'created')
		.order(:created_at).limit(1)

    job.update(status: 'queued')
    job.send_to_sidekiq
---
## Need lock to avoid double execution

	# When a report job finishes, get next queuable job
	job = Job.where(tag: 'report', status: 'created')
		.order(:created_at).limit(1)

	# Lock that row in Ruby
	job.with_lock do
	  if job.status == 'created'
        job.update(status: 'queued')
        job.send_to_sidekiq
	  end
	end
---
## Still has issue?

* One job can be fetched by multiple workers but only one can execute it next
* Fetching multiple jobs instead causes other issues: job queued in random order, job exceeds queue limit, excessive locking time, etc.

---
## How to solve all these issues?
---
## Using SKIP LOCKED, available since Postgres 9.5:

    select id from jobs
	where tag = 'report' and status = 'created'
	order by created_at
	for update skip locked
	limit 1

It 'skips' all the rows that are being locked, avoiding same job to be fetched by multiple workers
---
## Question?
