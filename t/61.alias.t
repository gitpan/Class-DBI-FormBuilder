#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Exception;


if ( ! DBD::SQLite2->require ) 
{
    plan skip_all => "Couldn't load DBD::SQLite2";
}

plan tests => 2;

use DBI::Test; 

$ENV{REQUEST_METHOD} = 'GET';
$ENV{QUERY_STRING}   = 'set_colour=orange&set_fruit=orange&set_town=2&_submitted=1';

{

    my $data = { colour => 'orange', 
                 fruit  => 'orange',
                 town   => 2,
                 };
                 
                 
    my $form = Alias->as_form;
    
    my $orange;
     
    lives_ok { $orange = Alias->create_from_form( $form ) };
    
    # this fails because the form is built with set_foo field names
    isa_ok( $orange, 'Class::DBI' );
    
    
    #warn $form->render( PrettyPrint => 1 );
    
    
}