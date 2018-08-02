## Adjacency list
Table folder {
    id integer
    parent_id integer
    name character
}

Ref { folder.id - folder.parent_id }
