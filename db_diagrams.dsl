## Adjacency list
Table folder {
    id integer
    parent_id integer
    name character
}

Ref { folder.id - folder.parent_id }

## Closure table
Table folder {
    id integer
    name character
}

Table closure {
    ancestor_id integer
    descendant_id integer
}

Ref { folder.id < closure.ancestor_id }
Ref { folder.id < closure.descendant_id }

## Nested set
Table folder {
	id integer
	name character
	left integer
	right integer
}
