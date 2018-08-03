---
Hierarchical data in relational database
---
### Agenda
* @color[#D33682](Introduction)
* Adjacency list
* Closure table
* Nested set
* Database specific implementations
* Conclusion
+++
### Part 1: Introduction
* What is hierarchical data?
* Why stores in relational database?
* Common ways to store hierarchical data in relational database
+++
### What is hierarchical data?
Data that has parent-child relationship such as

* File system: directory - file
* Forum post
+++
### File system
![HN](static/finder.png)
+++
### Forum post
![HN](static/hacker_news.png)
+++
### Why stores in relational database?
* No additional database needed
* Can join together with other types of relational data
+++
### Operations
* Insert/move/delete
* Query parents/children
* Query ancestors/descendants
+++
## Common strategies
* Adjacency list
* Closure table
* Nested set
* Others (not discussed today)
	* Materialized path/path enumeration
	* Lineage column
+++
### End of part 1
---
### Agenda
* Introduction
* @color[#D33682](Adjacency list)
* Closure table
* Nested set
* Database specific implementations
* Conclusion
+++
### Part 2: Adjacency list
+++
@snap[north-west left]
<h4>Structure</h4>
<ul>
    <li>Each node has a pointer to its' parent</li>
    <li>Storage cost: 1 extra column</li>
</ul>
@snapend

@snap[north-east diagram]
![Adjacency list](static/adjacency_list_db_diagram.png)
@snapend

+++
@snap[north-west diagram]
![](static/tree_structure.png)
@snapend

@snap[north-east]
<table>
<tr>
    <th>ID</th>
    <th>Parent ID</th>
</tr>
<tr>
    <td>1</td>
    <td>NULL</td>
</tr>
<tr>
    <td>2</td>
    <td>1</td>
</tr>
<tr>
    <td>3</td>
    <td>1</td>
</tr>
<tr>
    <td>4</td>
    <td>2</td>
</tr>
<tr>
    <td>5</td>
    <td>3</td>
</tr>
</table>
@snapend
+++
### Insert/Move
Insert a new node

    insert into folder (id, parent_id) values(5, 3)

Move a node to a different parent

    update folder set parent_id = 2 where id = 5
+++
### Query children/parent
Children

    select id from folder where parent_id = X

Parent

    select id from folder where id = X.parent_id
+++
### Ancestors/Descendants
Need to loop and send multiple queries (N + 1 problem), or...
+++
### Get descendants (PostgreSQL)
Get all descendants of X:

    with recursive tree (id) as (
      select F.id from folder F
      where F.parent_id = X.id
      union
      select F.id from folder F, tree T
      where F.parent_id = T.id
    )
    select * from tree;
+++
### Get ancestors (PostgreSQL)

    with recursive tree (id, path) as (
      select F.parent_id as id, array[F.parent_id]::integer[] as path
      from folder F
      where id = X.id
      union
      select F.parent_id, tree.path || F.parent_id
      from folder F
      join tree on tree.id = C.id
    ) select path from tree
    where id = 0
+++
### Recursive CTE
* Supported by:
    * PostgreSQL 8.4 (2009)
    * MySQL 8.0 (2017)
    * Oracle 11g Release 2 (2009)
    * SQL Server 2005 (2005)
	* SQLite 3.8.3.1 (2014)
	* IBM DB2 UDB 8 (2002)
+++
<h3>Performance</h3>

<table>
<tr>
	<th>Operation</th>
	<th>Performance</th>
</tr>
<tr>
	<td>Insert</td>
	<td>O(1)</td>
</tr>
<tr>
	<td>Move</td>
	<td>O(1)</td>
</tr>
<tr>
	<td>Delete</td>
	<td>O(1)</td>
</tr>
<tr>
	<td>Ancestors</td>
	<td>O(m)</td>
</tr>
<tr>
	<td>Descendants</td>
	<td>O(m)</td>
</tr>
</table>
+++
### When to use
* A lot of mutations: Insert/move/delete
* Database supports recursive CTE
+++
### End of part 2
---
### Agenda
* Introduction
* Adjacency list
* @color[#D33682](Closure table)
* Nested set
* Database specific implementations
* Conclusion
+++
### Part 3: Closure table
+++
### Structure
A separate table called "closure table" that stores all paths from each node to another

![](static/closure_table_db_diagram.png)
+++
@snap[west diagram]
![](static/tree_structure.png)
@snapend
@snap[east half]
<table>
<tr>
    <th>Ancestor</th>
    <th>Descendant</th>
    <th>Depth</th>
</tr>
<tr>
    <td>1</td>
    <td>2</td>
    <td>1</td>
</tr>
<tr>
    <td>1</td>
    <td>3</td>
    <td>1</td>
</tr>
<tr>
    <td>1</td>
    <td>4</td>
    <td>2</td>
</tr>
<tr>
    <td>1</td>
    <td>5</td>
    <td>2</td>
</tr>
<tr>
    <td>2</td>
    <td>4</td>
    <td>1</td>
</tr>
<tr>
    <td>3</td>
    <td>5</td>
    <td>1</td>
</tr>
</table>
@snapend
+++
### Insert

    insert into folder (id, name);

    insert into closure (ancestor_id, descendant_id, depth)
    select ancestor_id, <id>, depth + 1 from closure
    where descendant_id = <parent_id>;
+++
### Move
Move `<id>` to under `<new_parent_id>`

    delete from closure
	where descendant_id = <id> and ancestor_id != <id>;

    insert into closure (ancestor_id, descendant_id, depth)
    select ancestor_id, <id>, depth + 1 from closure
    where descendant_id = <new_parent_id>;
+++
### Delete

    delete from closure where descendant_id = <id>
+++
### Query children

    select F.id, F.name
    from folder F left join closure C on ancestor_id = id
    where C.depth = 1
+++
### Query parent

    select F.id, F.name
    from folder F left join closure C on descendant_id = id
    where C.depth = 1
+++
### Ancestors

    select F.id, F.name
    from folder F left join closure C on descendant_id = id
+++
### Descendants

    select F.id, F.name
    from folder F left join closure C on ancestor_id = id
+++
<h3>Performance</h3>

<table>
<tr>
	<th>Operation</th>
	<th>Performance</th>
</tr>
<tr>
	<td>Insert</td>
	<td>O(m)</td>
</tr>
<tr>
	<td>Move</td>
	<td>O(m)</td>
</tr>
<tr>
	<td>Delete</td>
	<td>O(m)</td>
</tr>
<tr>
	<td>Ancestors</td>
	<td>O(m)</td>
</tr>
<tr>
	<td>Descendants</td>
	<td>O(m)</td>
</tr>
</table>
+++
### When to use
* Balanced, decently fast for all cases
* Extra storage cost for the closure table is fine
+++
### End of part 3
---
### Agenda
* Introduction
* Adjacency list
* Closure table
* @color[#D33682](Nested set)
* Database specific implementations
* Conclusion
+++
### Part 4: Nested set
+++
### Structure
Extra 2 columns: `left` and `right`

![](static/nested_set.png)
+++
@snap[north-west diagram]
![](static/nested_set_tree.png)
@snapend

@snap[north-east]
<table>
<tr>
    <th>ID</th>
    <th>Left</th>
    <th>Right</th>
</tr>
<tr>
    <td>1</td>
    <td>1</td>
    <td>10</td>
</tr>
<tr>
    <td>2</td>
    <td>2</td>
    <td>5</td>
</tr>
<tr>
    <td>3</td>
    <td>6</td>
    <td>9</td>
</tr>
<tr>
    <td>4</td>
    <td>3</td>
    <td>4</td>
</tr>
<tr>
    <td>5</td>
    <td>7</td>
    <td>8</td>
</tr>
</table>
@snapend

@snap[south-west diagram]
Rule: descendants' left and right numbers are between ancestor's numbers
@snapend
+++
### Insert

![](static/nested_set_insert_1.png)
+++
### Insert (cont)

![](static/nested_set_insert_2.png)
+++
### Insert (cont)
Insert under parent (id, left, right) of (4, 3, 4)

	update folder
	set left =
		case when left > <parent.left> then left + 2 else left end,
		right = right + 2
	where right > <parent.left>;

	insert into folder (6, <parent.left> + 1, <parent.left> + 2)
+++
### Delete

Just delete the row since it does not affect the nested set's rule.

	delete from folders where id = <id>
+++
### Move

Combination of delete and insert.
+++
### Query ancestors

![](static/nested_set_tree.png)
+++
### Query ancestors

	select A.id, A.name from folder D
	join folder A
	on D.left between A.left and A.right
	where D.id = <id>
+++
### Query descendants

![](static/nested_set_tree.png)
+++
### Query descendants

	select C.id, C.name from folder A
	join folder D
	on D.left between A.left and A.right
	where A.id = <id>
+++
### Parent
Parent is an ancestor that does not have descendant which is ancestor of given node

	select A.id, A.name from folders D
	join folders A
	on D.left between A.left and A.right
	left outer join folders B
	on D.left between B.left and B.right and B.left between A.left and A.right
	where D.id = <id> and B.id IS NULL
+++
### Children
Child is a descendant that does not have ancestor which is descendant of given node

	select D.id, D.name from folders A
	join folders D
	on D.left between A.left and A.right
	left outer join folders B
	on D.left between B.left and B.right and B.left between A.left and A.right
	where A.id = <id> and B.id IS NULL
+++
<h3>Performance</h3>

<table>
<tr>
	<th>Operation</th>
	<th>Performance</th>
</tr>
<tr>
	<td>Insert</td>
	<td>O(n/2)</td>
</tr>
<tr>
	<td>Move</td>
	<td>O(n/2)</td>
</tr>
<tr>
	<td>Delete</td>
	<td>O(n/2)</td>
</tr>
<tr>
	<td>Ancestors</td>
	<td>O(m)</td>
</tr>
<tr>
	<td>Descendants</td>
	<td>O(m)</td>
</tr>
</table>
+++
### When to use
* Very few mutations (insert/move/delete) such as forum posts
* Database does not support recursive CTE (e.g. MySQL < 8.0)
+++
### Variants
* Nested intervals:
	* Use real/float instead of integer for `left` and `right` indexes
* [Matrix encoding](http://vadimtropashko.files.wordpress.com/2011/07/ch5.pdf)
+++
### Conclusion
Nested Sets is a clever solution – maybe too clever. It also fails to support referential integrity. It’s best used when you need to query a tree more frequently than you need to modify the tree. - _SQL Antipatterns_
+++
### Performance comparison
<table>
<tr>
	<th>Operation</th>
	<th>Adjacency list</th>
	<th>Closure table</th>
	<th>Nested set</th>
</tr>
<tr>
	<td>Insert</td>
	<td>O(1)</td>
	<td>O(m)</td>
	<td>O(n/2)</td>
</tr>
<tr>
	<td>Move</td>
	<td>O(1)</td>
	<td>O(m)</td>
	<td>O(n/2)</td>
</tr>
<tr>
	<td>Delete</td>
	<td>O(1)</td>
	<td>O(m)</td>
	<td>O(n/2)</td>
</tr>
<tr>
	<td>Ancestors</td>
	<td>O(m)</td>
	<td>O(m)</td>
	<td>O(m)</td>
</tr>
<tr>
	<td>Descendants</td>
	<td>O(m)</td>
	<td>O(m)</td>
	<td>O(m)</td>
</tr>
</table>
+++
### End of part 4
---
### Agenda
* Introduction
* Adjacency list
* Closure table
* Nested set
* @color[#D33682](Database specific implementations)
* Conclusion
+++
### Part 5: Database specific implementations
+++
### PostgreSQL

* Recursive CTE
* [ltree](https://www.postgresql.org/docs/current/static/ltree.html) for materialized path
* Recommended: adjacency list
+++
### MySQL

* Recursive CTE (since 8.0)
* If not supported, use [session variable](https://explainextended.com/2009/09/29/adjacency-list-vs-nested-sets-mysql/) and triggers.
* Recommended: adjacency list for MySQL >= 8.0, nested set or closure table otherwise
+++
### Oracle

* Use `CONNECT BY` for adjacency list
* Recommended: adjacency list
+++
### SQL Server

* Use recursive CTE for adjacency list
* Use [HierarchyId](https://docs.microsoft.com/en-us/sql/t-sql/data-types/hierarchyid-data-type-method-reference?view=sql-server-2017) for lineage column
* Recommended: adjacency list
+++
Discussion for adjacency list vs nested set for various types of databases can be found [here](https://explainextended.com/2009/09/24/adjacency-list-vs-nested-sets-postgresql/)
+++
### End of part 5
---
### Agenda
* Introduction
* Adjacency list
* Closure table
* Nested set
* Database specific implementations
* @color[#D33682](Conclusion)
+++
### Conclusion
* Use adjacency list first
* If existing table cannot be modified use closure table with triggers
* If not fast enough then try other approaches
* Different strategies can be combined
* If makes sense, use grapth databases such as Neo4J
---
### Questions?
---
### Other topics
* Validation, cycle detection
* Use of indexes


