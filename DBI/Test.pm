{
    package DBI::Test;
    use base 'Class::DBI';
    use Class::DBI::FormBuilder PrettyPrint => 1;
    # use the db set up in 01.create.t
    DBI::Test->set_db("Main", "dbi:SQLite2:dbname=test.db");
}

{   # might_have
    package Job;
    use base 'DBI::Test';
    Job->table( 'job' );
    Job->columns( All => qw/id person jobtitle employer salary/ );
    Job->columns( Stringify => qw/jobtitle/ );  
    Job->has_a( person => 'Person' );  
}
 
{   # has_a
    package Town;
    use base 'DBI::Test';
    #Town->form_builder_defaults( { smartness => 3 } );
    Town->table("town");
    Town->columns(All => qw/id name pop lat long country/);
    Town->columns(Stringify => qw/name/);
}

{   # has_many
    # this one must be declared before Person, because Person will 
    # examine the has_a in Toy when setting up its has_many toys.
    package Toy;
    use base 'DBI::Test';
    Toy->table('toy');
    Toy->columns( All => qw/id person name descr/ );
    Toy->columns( Stringify => qw/name/ );
    Toy->has_a( person => 'Person' );
}

{    
    package Person;
    use base 'DBI::Test';
    #Person->form_builder_defaults( { smartness => 3 } );
    Person->table("person");
    Person->columns(All => qw/id name town street/);
    Person->columns(Stringify => qw/name/);
    Person->has_a( town => 'Town' );
    Person->has_many( toys => 'Toy' );
    Person->might_have( job => Job => qw/jobtitle employer salary/ );
}

{    
    package Wackypk;
    use base 'DBI::Test';
    Wackypk->table("wackypk");
    # wooble is the pk
    Wackypk->columns(All => qw/flooble wooble flump poo/);
    Wackypk->columns(Primary => 'wooble'); # or put wooble 1st in the list above
}

{
    package Alias;
    use base 'DBI::Test';
    Alias->table( 'alias' );
    Alias->columns(All => qw/id colour fruit town/);
    Alias->columns(Stringify => 'fruit' );
    
    Alias->has_a( town => 'Town' );
    
    Alias->has_many( alias_has_many => 'AliasHasMany' );
    Alias->might_have( job => Job => qw/jobtitle employer salary/ );
    
    
    sub accessor_name { "get_$_[1]" }
    sub mutator_name  { "set_$_[1]" }
}

{
    package AliasHasMany;
    use base 'DBI::Test';
    AliasHasMany->table( 'alias_has_many' );
    AliasHasMany->columns( All => qw/id alias foo/ );
    AliasHasMany->columns( Stringify => 'foo' );
    AliasHasMany->has_a( alias => 'Alias' );
}    
    
    
1;
