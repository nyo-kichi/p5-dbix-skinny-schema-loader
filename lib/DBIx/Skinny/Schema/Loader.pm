package DBIx::Skinny::Schema::Loader;
use strict;
use warnings;

our $VERSION = '0.17';

use Carp;
use DBI;
use DBIx::Skinny::Schema;

sub import {
    my ($class, @args) = @_;
    my $caller = caller;

    my @functions = qw(
    make_schema_at
    );

    for my $func ( @args ) {
        if ( grep { $func } @functions ) {
            no strict 'refs';
            *{"$caller\::$func"} = \&$func;
        }
    }
}

sub new {
    my ($class) = @_;
    bless {}, $class;
}

sub supported_drivers {
    qw(
        SQLite
        mysql
        Pg
    );
}

sub connect {
    my $self = shift;
    return if defined $self->{ impl };

    my $opts;
    if (@_ == 1) {
        $opts = +{
            dsn             => $_[0]->{dsn}             || '',
            user            => $_[0]->{username}        || '',
            pass            => $_[0]->{password}        || '',
            connect_options => $_[0]->{connect_options} || {},
        };
    } else {
        my ($dsn, $user, $pass, $connect_options) = @_;
        $opts = {
            dsn             => $dsn             || '',
            user            => $user            || '',
            pass            => $pass            || '',
            connect_options => $connect_options || {},
        };
    }
    $opts->{dsn} =~ /^dbi:([^:]+):/;
    my $driver = $1 or croak "Could not parse DSN";
    croak "$driver is not supported by DBIx::Skinny::Schema::Loader yet"
        unless grep { /^$driver$/ } $self->supported_drivers;
    my $impl = __PACKAGE__ . "::DBI::$driver";
    eval "use $impl"; ## no critic
    die $@ if $@;
    $self->{ impl } = $impl->new($opts);
}

sub load_schema {
    my ($class, $connect_info) = @_;
    my $self = $class->new;
    $connect_info ||= $class->get_skinny_connect_info;
    $self->connect(
        $connect_info->{ dsn },
        $connect_info->{ username },
        $connect_info->{ password },
        $connect_info->{ connect_options },
    );

    my $schema = $class->schema_info;
    for my $table ( @{ $self->{ impl }->tables } ) {
        my $pk = $self->{ impl }->table_pk($table);
        $schema->{ $table }->{ pk } = $pk if $pk;
        $schema->{ $table }->{ columns } = $self->{ impl }->table_columns($table);
    }
    return $self;
}

sub get_skinny_connect_info {
    my ($class, $connect_info) = @_;
    $class = ref $class || $class;
    (my $skinny_class = $class) =~ s/::Schema//;
    my $attr = $skinny_class->attribute;
    $connect_info->{ $_ } = $attr->{ $_ } for qw/dsn username password connect_options/;
    return $connect_info;
}

sub make_schema_at {
    my $self = (ref $_[0] eq 'DBIx::Skinny::Schema::Loader') ? shift : __PACKAGE__->new;
    my ($schema_class, $options, $connect_info) = @_;

    $self->connect(ref $connect_info eq 'HASH' ? $connect_info : @{ $connect_info });

    my $schema = $self->_insert_header;
    $schema .= "package $schema_class;\nuse DBIx::Skinny::Schema;\n\n";

    $schema .= $self->_insert_template($options->{ before_template });
    $schema .= $self->_insert_template($options->{ template });
    $schema .= $self->_make_install_table_text(
        {
            table   => $_,
            pk      => $self->{ impl }->table_pk($_),
            columns => $self->{ impl }->table_columns($_),
        },
        $options->{ table_template }
    ) for @{ $self->_get_tables($options->{ ignore_rules }) };
    $schema .= $self->_insert_template($options->{ after_template });

    $schema .= "1;";
    return $schema;
}

sub _insert_header {
    "# THIS FILE IS AUTOGENERATED BY DBIx::Skinny::Schema::Loader $VERSION, DO NOT EDIT DIRECTLY.\n\n";
}

sub _insert_template {
    my ($self, $template) = @_;
    return '' unless $template;
    chomp $template;

    "# ---- beginning of custom template ----\n" .
    $template . "\n" .
    "# ---- end of custom template ----\n\n";
}

sub _make_install_table_text {
    my ($self, $params, $template) = @_;
    my $table   = $params->{ table };
    my $pk      = join " ", @{ $params->{ pk    }   };
    my $columns = join " ", @{ $params->{ columns } };
    unless ($template) {
        $template  = "install_table [% table %] => schema {\n";
        $template .= "    pk qw/[% pk %]/;\n" if $pk;
        $template .= "    columns qw/[% columns %]/;\n};\n\n";
    }

    $template =~ s/\[% table %\]/$table/g;
    $template =~ s/\[% pk %\]/$pk/g;
    $template =~ s/\[% columns %\]/$columns/g;
    return $template;
}

sub _get_tables {
    my ($self, $ignore_rules) = @_;
    my @tables;
    for my $table ( @{ $self->{ impl }->tables } ) {
        my $ignore;
        for my $rule ( @$ignore_rules ) {
            $ignore++ and last if $table =~ $rule;
        }
        push @tables, $table unless $ignore;
    }
    return \@tables;
}

1;
__END__

=head1 NAME

DBIx::Skinny::Schema::Loader - Schema loader for DBIx::Skinny

=head1 SYNOPSIS

Run-time schema loading:

  package Your::DB::Schema;
  use base qw/DBIx::Skinny::Schema::Loader/;

  __PACKAGE__->load_schema;

  1;

Preloaded schema:

Given a the following source code as F<publish_schema.pl>:

  use DBIx::Skinny::Schema::Loader qw/make_schema_at/;
  print make_schema_at(
    'Your::DB::Schema',
    {
      # options here
    },
    [ 'dbi:SQLite:test.db', '', '' ]
  );

you can execute

    $ perl publish_schema.pl > Your/DB/Schema.pm

to create a static schema class.

=head1 DESCRIPTION

DBIx::Skinny::Schema::Loader is schema loader for DBIx::Skinny.
It can dynamically load schema at run-time or statically publish
them.

It supports MySQL and SQLite, and PostgreSQL.

=head1 METHODS

=head2 connect( $dsn, $user, $pass, $connect_options )

=head2 connect( { dsn => ..., username => ..., password => ..., connect_options => ... } )

Probably no need for public use.

Instead, 
invoke concrete db driver class named "DBIx::Skinny::Schema::Loader::DBI::XXXX".

=head2 load_schema

Dynamically load the schema

  package Your::DB::Schema;
  use base qw/DBIx::Skinny::Schema::Loader/;

  __PACKAGE__->load_schema;

  1;

C<load_schema> refers to C<connect info> in your Skinny class.
When your schema class is named C<Your::DB::Schema>,
Loader considers C<Your::DB> as a Skinny class.

C<load_schema> executes C<install_table> for all tables, automatically
setting primary key and columns.

Also the sections C<how loader find primary keys> and 
C<additional settings for load_schema>.

=head2 make_schema_at( $schema_class, $options, $connect_info )

Return schema file content as a string. This function is exportable.

  use DBIx::Skinny::Schema::Loader qw/make_schema_at/;
  print make_schema_at(
      'Your::DB::Schema',
      {
        # options here
      },
      [ 'dbi:SQLite:test.db', '', '' ]
  );

C<$schema_class> is schema class name that you want publish.

C<$options> are described in the C<options of make_schema_at> section.

C<$connect_info> is ArrayRef or HashRef. If it is an arrayref, it contains dsn, username, password to connect to the database. If it is an hashref, it contains same parameters as DBIx::Skinny->new(\%opts).

=head1 HOW LOADER FINDS PRIMARY KEYS

surely primary key defined at DB, use it as PK.

in case of primary key is not defined at DB, Loader find PK following logic.
1. if table has only one column, use it
2. if table has column 'id', use it

=head1 ADDITIONAL SETTINGS FOR load_schema

Here is how to use additional settings:

  package Your::DB::Schema;
  use base qw/DBIx::Skinny::Schema::Loader/;

  use DBIx::Skinny::Schema;  # import schema functions

  install_utf8_columns qw/title content/;

  install_table books => schema {
    trigger pre_insert => sub {
      my ($class, $args) = @_;
      $args->{ created_at } ||= DateTime->now;
    };
  };

  __PACKAGE__->load_schema;

  1;

'use DBIx::Skinny::Schema' works to import schema functions.
you can write instead of it, 'BEGIN { DBIx::Skinny::Schema->import }'
because 'require DBIx::Skinny::Schema' was done by Schema::Loader.

You might be concerned that calling install_table 
without pk and columns doesn't work. However, 
DBIx::Skinny allows C<install_table> to be called twice or more.

=head1 OPTIONS OF make_schema_at

=head2 before_template

insert your custom template before install_table block.

  my $tmpl = << '...';
  # custom template
  install_utf8_columns qw/title content/;
  ...

  install_table books => schema {
    trigger pre_insert => sub {
      my ($class, $args) = @_;
      $args->{ created_at } ||= DateTime->now;
    }
  }

  print make_schema_at(
      'Your::DB::Schema',
      {
          before_template => $tmpl,
      },
      [ 'dbi:SQLite:test.db', '', '' ]
  );

then you get content inserted your template before install_table block.

=head2 after_template

after_template works like before_template mostly.
after_template inserts template after install_table block.

  print make_schema_at(
      'Your::DB::Schema',
      {
          before_template => $before,
          after_template  => $after,
      },
      [ 'dbi:SQLite:test.db', '', '' ]
  );

there are more detailed example in C<$before_template> section.

you can use both before_template and after_template all together.

=head2 template

DEPRECATED. this option is provided for backward compatibility.

you can use before_template instead of this.

=head2 table_template

use your custom template for install_table.

  my $table_template = << '...';
  install_table [% table %] => schema {
      pk qw/[% pk %]/;
      columns qw/[% columns %]/;
      trigger pre_insert => $created_at;
  };

  ...

  print make_schema_at(
      'Your::DB::Schema',
      {
          table_template => $table_template,
      },
      [ 'dbi:SQLite:test.db', '', '' ]
  );

your schema's install_table block will be

  install_table books => schema {
      pk 'id';
      columns qw/id author_id name/;
      tritter pre_insert => $created_at;
  };

C<make_schema_at> replaces some following variables.
[% table %]   ... table name
[% pk %]      ... primary keys joined by a space
[% columns %] ... columns joined by a space

=head2 ignore_rules

you can exclude tables that matching any rules declared in ignore_rules from the schema.

  ignore_rules => [ qr/rs$/, qr/^no/ ],

=head1 LAZY SCHEMA LOADING

if you write Your::DB class without setup sentence,

  package MyApp::DB;
  use DBIx::Skinny;
  1;

you should not call C<load_schema> in your class file.

  package MyApp::DB::Schema;
  use base qw/DBIx::Skinny::Schema::Loader/;
  1;

call load_schema with dsn manually in your app.

  my $db = MyApp::DB->new;
  my $connect_info = {
      dsn      => $dsn,
      username => $user,
      password => $password,
  };
  $db->connect($connect_info);
  $db->schema->load_schema($connect_info);

=head1 AUTHOR

Ryo Miyake E<lt>ryo.studiom {at} gmail.comE<gt>

=head1 SEE ALSO

L<DBIx::Skinny>, L<DBIx::Class::Schema::Loader>

=head1 AUTHOR

Ryo Miyake  C<< <ryo.studiom __at__ gmail.com> >>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
