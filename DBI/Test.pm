{
    package DBI::Test;
    use base 'Class::DBI';
    use Class::DBI::FormBuilder;
    # use the db set up in 01.create.t
    DBI::Test->set_db("Main", "dbi:SQLite2:dbname=test.db");
#    DBI::Test->table("test");
}
 
{    
    package Town;
    use base 'DBI::Test';
    Town->form_builder_defaults( { smartness => 3 } );
    Town->table("town");
    Town->columns(All => qw/id name pop lat long country/);
    Town->columns(Stringify => qw/name/);
}

{
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
    Person->form_builder_defaults( { smartness => 3 } );
    Person->table("person");
    Person->columns(All => qw/id name town street/);
    Person->columns(Stringify => qw/name/);
    Person->has_a( town => 'Town' );
    Person->has_many( toys => 'Toy' );
}


1;
