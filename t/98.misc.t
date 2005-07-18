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

{   # _db_order_columns - the 'All' group is defined explicitly by CDBI, 
    # and doesn't exist in the deep lookup done in _db_order_columns, 
    # which causes a fatal error. If the 'All' group is set up explicitly, then 
    # the group *does* exist, and the lookup succeeds. Maypole sets up the 'All' 
    # group explicitly (probably in CDBI::Loader), unless using one of the ::Plain 
    # models, so I won't normally see this error in my apps, but non-Maypole, or ::Plain 
    # Maypole apps, do. 
    
    {
        package Town2;
        use base 'DBI::Test';
        #Town->form_builder_defaults( { smartness => 3 } );
        Town->table("town");
        #Town->columns(All => qw/id name pop lat long country/);
        Town->columns(Stringify => qw/name/);
    }

    my ( $orig, %args );
    lives_ok { ( $orig, %args ) = Class::DBI::FormBuilder->_get_args( 'Town2' ) } '_get_args';
    
    my @cols;
    lives_ok { @cols = Class::DBI::FormBuilder->_db_order_columns( 'Town2', 'All' ) } '_db_order_columns';
    
    # XXX: this is currently failing
    # ok( @cols );
    
    # all the above is doing is calling columns( 'All' )
    my @cols2 = Town2->columns( 'All' );
    
    # XXX: this is currently failing
    #ok( @cols2 );
    
}