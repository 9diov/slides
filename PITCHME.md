---
---
### Agenda
* Introduction
* The process
* Our problems and how we fixed them
* Other tips
---
### Part 1: Introduction
* Holistics
* Holistics stack
---
### Holistics

* Data analytics/BI platform
---
### Stack
* Backend: Rails/Sidekiq/PostgreSQL/Redis
* Frontend: VueJS/Yarn/Webpack
---
### End of part 1
---
### Part 2: The process
* Performance monitoring
* Identify slow queries
* Debugging slow queries
* Fix the issue
---
### How do I know something is slow?
* Reported by angry customers (bad)
* Alerts from monitoring tools (good)
---
### The journey of a thousand miles start with...
---
### ...tracking
---
### Things to track
* Rails log
* Events log
* Database log
* Server log (CPU/memory/disk/network etc.)
---
### Tools
* ELK stack
* Tracking provided by hosting services (AWS/DO/GCP/Azure...)
* Commercials: Scout
* Query visualization/alerting tools: Holistics
---
![DO](static/do_charts.png)
---
![Kibana](static/kibana.png)
---
![Scout](static/scoutapp.png)
---
### How to use the results
* Generate summary statistics
* Identify the bottlenecks
* Propose root cause hypothesis
* Validate hypothesis
---
### Summary statistics
* Mean: 250ms
* Standard deviation: ~200ms
* 95th percentile: ~1200ms
* 99th percentile: ~18000ms
---?image=static/summary_statistics.gif&size=auto 90%
---
### Proprosing hypothesis
* n + 1 problem
* Inefficient queries
* Lack of indexes
* Lack of database maintenance
---
### Validating hypothesis
* Check the logs
* Fix and benchmark on big enough sample size
---
### Fix the issue
* Database maintenance
* Rewrite queries
* Adding indexes
---
### End of part 2
---
### Part 3: Our problems and how we fixed them
* Slow hieriarchical query
* N + 1 problem
* Slow query on huge table
* Slow search
---
### Problem 1: Folder structure navigation is very slow
![Holistics](static/holistics_folders.png)
---
Problem: Buidling folder structure with permission checking is very slow

Root cause hypothesis: n + 1 problem related to hieriarchical query
---
Scout shows that `/cats/<cat_id>/children.json` endpoint is:
* sending out ~200 of database queries per request
* db queries responsible to 80% of request duration
---
### Slow hieriarchical query

* Retrieve ancestor folders of a report
* Retrieve descendants of a folder
---
### Code

    class Folder < ActiveRecord::Base
      has_one :parent
    end
    
    class Report < ActiveRecord::Base
      has_one :parent_folder
    end
---
### Old implementation

    def ancestors(report)
      return [] unless report.folder.present?
      folder = report.folder
      while folder.present?
        res << folder
        folder = folder.parent
      end
      res.reverse
    end
---
### The recursive CTE way

    with recursive tree as (
      select R.parent_id as id, array[R.parent_id]::integer[] as path
      from #{Folder.table_name} R
      where id = #{folder_id}

      union

      select C.parent_id, tree.path || C.parent_id
      from #{Folder.table_name} C
      join tree on tree.id = C.id
    ) select path from tree
    where id = 0
---
### Problem 2: Slow generating list of models
---
### Classic n + 1 problem
Query to retrieve all shared filters with extra information:
* Is the filter locked?
* How many reports/dashboards contain the filter
---
### How to detect/solve n + 1 problem with ActiveRecord?
* Detection: bullet gem (https://github.com/flyerhzm/bullet)
* Eager loading
* Custom query using Arel
---
### Model

	class SharedFilter < ActiveRecord::Base
      belongs_to :tenant
	  has_one :object_lock
	  has_many :reports
	  has_many :dashboards
	end
---
### Eager loading

	SharedFilter
	  .where(tenant_id: tenant_id)
	  .include(:object_locks, :reports, :dashboards)
---
### Eager loading

Number of queries: 4

    select * from shared_filters where tenant_id = $1
    select * from object_locks where filter_id = $1
    select * from reports where id in ($1)
    select * from dashboards where id in ($1)
---
### Custom query with scopes

    SharedFilter
      .filter_tenant(tenant.id)
      .select_all
      .include_object_locks
      .include_report_count
      .include_dashboard_count
---
### Scopes implementation

    def select_all
      select("#{self.table_name}.*").group("#{self.table_name}.id")
    end
  
    def filter_adhoc(bool)
      where("#{self.table_name}.is_adhoc = ?", bool)
    end
---
### Scopes implementation (cont.)

    def include_object_locks
      select('object_locks.id as object_lock_id')
        .joins("LEFT JOIN object_locks ON #{self.table_name}.id = object_locks.subject_id AND object_locks.subject_class = '#{self.to_s}'")
        .group('object_locks.id')
    end

    def include_report_count
      select('count(NR.id) as report_count')
        .joins("LEFT JOIN filter_ownerships NR ON NR.shared_filter_id = shared_filters.id AND NR.filterable_type = 'QueryReport'")
    end

    def include_dashboard_count
      select('count(ND.id) as dashboard_count')
        .joins("LEFT JOIN filter_ownerships ND ON ND.shared_filter_id = shared_filters.id AND ND.filterable_type = 'Dashboard'")
    end
---
### Scopes implementation

Number of queries: 1

Careful with SQL injection though
---
### Problem 3: Slow query on huge table
Problem: Complex job queuing query takes more than 1 second to run
---
![sql_query](static/big_sql_query.png)
---
Root cause hypothesis: The query is not optimized
---
### Debugging query performance
---
### EXPLAIN ANALYZE
![query_plan](static/query_plan.png)
---
Postgres Explain Visualizer: http://tatiyants.com/pev/

![PEV](static/pev_plan.png)
---
Commandline visualizer: https://github.com/simon-engledew/gocmdpev

![cmdpev](static/gocmdpev.png)
---
### Rewriting queries
* Use appropriate JOIN type (LEFT/INNER/RIGHT)
* Move filtering inside CTE
* Avoid SELECT DISTINCT on whole table
---
### Results: wrong!

Performance did improve, but not by much
---
Root cause hypothesis: lack of proper database maintenance
---
### Vacuum/analyze
* Vacuum: clean up dead rows from disk
* Analayze: Update statistics on table for accurate query planning
---
Custom autovacuum/autoanalyze frequency

    ALTER TABLE <table> SET (autovacuum_vacuum_scale_factor = 0.0);
    ALTER TABLE <table> SET (autovacuum_vacuum_threshold = 1000);
    ALTER TABLE <table> SET (autovacuum_analyze_scale_factor = 0.0);
    ALTER TABLE <table> SET (autovacuum_analyze_threshold = 1000);
---
Vacuum/analyze every time

`(number of table rows * scale_factor + threshold)` rows

got inserted/updated/deleted
---
# Results
Reduce query time from mean 2000ms -> 150ms
---
### Problem 4: Search is slow
Problem: Search takes a long time to load

Root cause hypothesis: Lack of index on the relevant column
---
### Trigram index
* Speed up LIKE/ILIKE query
* Example: https://about.gitlab.com/2016/03/18/fast-search-using-postgresql-trigram-indexes/
* Reduce search time ~200ms -> ~1ms
---
### Trigram index

    # Query
    select title from query_reports where title ILIKE '%some%text%'

    # Adding index
    class AddGinIndexToReportsTitle < ActiveRecord::Migration
      def up
        execute 'create extension if not exists pg_trgm'
        execute 'CREATE INDEX IF NOT EXISTS' +
        'index_query_reports_on_title_trigram' +
        'ON query_reports USING gin (title gin_trgm_ops);'
      end
    end
---
### End of part 3 conclusion
We solved the following issues:
* Slow hieriarchical query
* N + 1 problem
* Slow query on huge table
* Slow search
---
### Part 4: Other tips
* Expresion/partial indexes
* Useful queries
---
### Adding indexes
Remember to set algorithm: concurrently

    add_index :users, :tenant_id, algorithm: :concurrently
---
### Expression index

    # Query
    User.where("LOWER(email) = LOWER(?)", params[:email])

    # Adding index
    class IndexUsersOnLowerEmail < ActiveRecord::Migration
      def up
        execute 'CREATE INDEX users_on_lower_email ON users(LOWER(email))'
      end
    end
---
### Partial index

    SELECT COUNT(*)
    FROM event
    WHERE
      (data->>'type') = 'submit' AND
      (data->>'path') = '/signup/' AND
    time BETWEEN 1409554800000 AND 1410159600000
---

    CREATE INDEX event_signups ON event (time)
    WHERE (data->>'type') = 'submit' AND (data->>'path') = '/signup/'
---
### Index tradeoff
* Extra time to do INSERT/UPDATE/DELETE
* Extra disk space needed
---
### Useful queries
---
Unused indexes: https://gist.github.com/9diov/fa9c7f41b92f8e8c528ff9184a2b4e15
![unused_index](static/unused_index.png)
---
Index suggestion: https://gist.github.com/9diov/6174289564ba4ee0f296974ca3638024
![Index suggestion](static/index_suggestion.png)
---
## Conclusion
* Monitoring is essential
* Validate your hypothesis
* Avoid n + 1 issue
* Maintain your database
* Use the index, Luke!
---
## Question?
