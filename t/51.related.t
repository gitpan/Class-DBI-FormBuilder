
use strict;
use warnings;

use Test::More qw(no_plan);
use Test::Exception;

if ( ! require DBD::SQLite2 ) 
{
    plan skip_all => "Couldn't load DBD::SQLite2";
}

#plan tests => 5;

use DBI::Test; 


$ENV{REQUEST_METHOD} = 'GET';
$ENV{QUERY_STRING}   = 'id=1&_submitted=1';

# basic tests
{
    my $dbaird = Person->retrieve( 1 );
    
    my $form1 = $dbaird->as_form;
    
    my $form2 = Toy->retrieve( 1 )->as_form;
    
    my $field1 = $form1->{fieldrefs}{street};
    
    delete $field1->{_form};
    
    #$field1->{_form} = $form2;
    
    $form2->{fieldrefs}{street} = $field1;
    push @{$form2->{fields}}, $field1;
    
    #warn Dumper( $field1 );
    
    #warn $form2->render;
    
    my $form = $dbaird->as_form_with_related;
    
    my $html = $form->render;

#    my $form = Person->as_form_with_related;
    
#    my $dbaird = Person->retrieve_from_form( $form );
    
    isa_ok( $dbaird, 'Class::DBI' );
    
#    my $html = $form->render;
    
    #warn $html;   
    
    #use Data::Dumper;
    
    #warn Dumper( $dbaird );
}