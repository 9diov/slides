---
## Writing Sidekiq background worker

* If you want to convert something to async `myObject.doSomethingAwesome(1, 2, 3)`, you need to create a new worker class:

`MyWorker.perform_async(1, 2, 3)`
---
