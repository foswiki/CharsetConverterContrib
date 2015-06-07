# See bottom of file for default license and copyright information

=begin TML

---+ package Foswiki::Contrib::CharsetConverterContrib

Static charset converter. Converts the character set used in a Foswiki
DB to UTF8.

ONLY FOR USE ON RCS STORES (RcsWrap, RcsLite)

=cut

package Foswiki::Contrib::CharsetConverterContrib;

# Always use strict to enforce variable scoping
use strict;
use warnings;
use File::Copy;

our $VERSION = '1.2';
our $RELEASE = '1 Jun 2015';
our $SHORTDESCRIPTION =
  'Convert entire Foswiki RCS databases from one character set to UTF-8';

our $options;
our $session;

my $convertCount = 0;
my $renameCount  = 0;

my $storeEncoding;
my $storeVersion;

sub report {
    return if $options->{-q};
    print STDERR join( ' ', @_ ) . "\n";
}

sub warning {
    print STDERR "WARNING: " . join( ' ', @_ ) . "\n";
}

sub error {
    if ( $options->{-a} ) {
        die join( ' ', @_ );
    }
    else {
        print STDERR "ERROR: " . join( ' ', @_ );
    }
}

sub detect_encoding {
    my $str = shift;

    return;
}

# Convert a byte string encoded in the {Site}{CharSet} to a byte
# string encoded in utf8
# Return 1 if a conversion happened, 0 otherwise
sub _convert_string {
    my ( $old, $where, $extra ) = @_;
    return 0 unless defined $old;
    my $e = $storeEncoding;

    if ( $options->{-r} ) {
        my $i = $where . ( $extra eq 'name of' ? ':N' : '' );
        if ( $options->{$i} ) {
            $e = $options->{$i};
            warning("Encoding of $extra $where forced to $e by options");
        }
        else {
            require Encode::Detect::Detector;
            my $de = Encode::Detect::Detector::detect($old);
            if ( $de && $de !~ /^$storeEncoding$/i ) {

                # Support overrides
                if ( $options->{$de} ) {
                    $e = $options->{$de};
                    warning(
"Detected encoding $de overridden by options to $options->{$de} in $extra $where"
                    );
                }
                else {
                    warning(
                        "Inconsistent $de encoding detected in $extra $where");
                }
            }
        }
    }

    # Special case: if the site encoding is iso-8859-* or utf-8 and the string
    # contains only 7-bit characters, then don't bother transcoding it
    # (irrespective of any (probably incorrect) detected encoding)
    if (   $storeEncoding =~ /^(utf-8|iso-8859-1)$/
        && $old !~ /[^\x00-~]/ )
    {
        return 0;
    }

    # Convert octets encoded using site charset to unicode codepoints.
    # Note that we use Encode::FB_HTMLCREF; this should be a nop as
    # unicode can accomodate all characters.
    my $t;
    eval { $t = Encode::decode( $e, $old, Encode::FB_CROAK ); };
    if ($@) {
        warning(
"Broken encoding detected in $extra $where - falling back to HTML entities"
        );

        # Broken encoding; try using the {Site}{CharSet} with
        # HTMLCREF (good luck with that!)
        $t = Encode::decode( $e, $old, Encode::FB_HTMLCREF );
    }

    # Convert to utf-8 bytes.
    $_[0] = Encode::encode_utf8($t);

    return ( $_[0] ne $old ) ? 1 : 0;
}

sub _rename {
    my ( $from, $to ) = @_;
    report "Move $from";
    unless ( $options->{-i} ) {
        File::Copy::move( $from, $to )
          || error "Failed to rename $from: $!";
    }
}

=begin TML

---++ StaticMethod convert_database(%args)

Given the name of a collection (/ separated web name or empty
string for the root) convert
the topics and filenames in that collection to a UTF8 namespace.

=cut

sub convert_database {
    my (%args) = @_;

    $options = \%args;

    if ( $Foswiki::VERSION < 1.1.999 ) {
        report "Detected Foswiki Version 1.1 or older";
        $storeVersion = 1;
    }
    else {
        report "Detected Foswiki Version >= 1.2";
        $storeVersion = 2;
    }

    if ( $options->{-encoding} ) {
        $storeEncoding = $options->{-encoding};
        report "Store encoding ignored, using encoding $storeEncoding";
    }
    elsif ( $storeVersion == 2 ) {
        $storeEncoding = $Foswiki::cfg{Store}{Encoding} || 'utf-8';
        report "Foswiki 1.2 Database, using encoding $storeEncoding";
    }
    else {
        $storeEncoding = $Foswiki::cfg{Site}{CharSet};
        report "Foswiki 1.1 Database, using encoding $storeEncoding";
    }

    my $web = $options->{-web} || '';
    report "Processing restriced to $web web" if $web;

    # Must do this before we construct the session object, otherwise the store
    # cache gets populated with Wrap handlers
    $Foswiki::cfg{Store}{Implementation} = 'Foswiki::Store::RcsLite';
    $session = new Foswiki();

    # First we rename all webs and files as necessary by
    # calling the recursive collection rename on the root web
    foreach my $tree ( $Foswiki::cfg{DataDir}, $Foswiki::cfg{PubDir} ) {
        _rename_collection( $tree, $web );
    }

    # All file and directory names should now be utf8

    # Now we convert the content of topics
    _convert_topics_contents($web);

    # And that's it!
    report "CONVERSION FINISHED: "
      . ( ( $options->{-i} ) ? '(simulated) ' : '' )
      . "Moved: $renameCount, Converted $convertCount\n";

    $session->finish();
}

# Rename a web and all it's contents if necessary
# Note that this works recursively; it renames a directory, and
# then recursively renames the contents in the renamed position.
# As such the web passed in is always the 'new' name of that web.
sub _rename_collection {
    my ( $tree, $web ) = @_;
    my $dir;

    my $webpath = "$tree/$web/";
    return unless -d $webpath;
    my %rename;
    my @subcoll;
    opendir( $dir, $webpath ) || die "Failed to open '$webpath' $!";

    #print STDERR "Collecting $webpath\n";
    foreach my $e ( readdir($dir) ) {
        next if $e =~ /^\./;

        #print STDERR "Collected $e $storeEncoding\n";
        my $ne = $e;
        if ( _convert_string( $ne, "$web/$ne", "name of" ) ) {
            if ( $ne ne $e ) {
                $renameCount++;
                $rename{"$webpath$e"} = "$webpath$ne";
            }
        }
        if ( -d $webpath . $e ) {
            push( @subcoll, $web ? "$web/$ne" : $ne );
        }
    }
    closedir($dir);
    while ( my ( $old, $new ) = each %rename ) {
        _rename( $old, $new );
    }
    foreach my $sweb (@subcoll) {
        _rename_collection( $tree, $sweb );
    }
}

# Convert the contents (*not* the name) of a topic
# The history conversion is done by loading the topic into
# RCSLite and performing the charset conversion on the fields.
sub _convert_topic {
    my ( $web, $topic ) = @_;
    my $converted = 0;

    # Convert .txt,v
    my $handler;

    if ( $storeVersion == 2 ) {
        $handler =
          Foswiki::Store::Rcs::RcsLiteHandler->new( $session->{store}, $web,
            $topic );
    }
    else {
        $handler =
          Foswiki::Store::VC::RcsLiteHandler->new( $session->{store}, $web,
            $topic );
    }
    my $uh = Encode::decode_utf8("$web.$topic");

    # Force reading of the topic history, all the way down to revision 1
    $handler->getRevision(1);

    if ( $handler->{state} ne 'nocommav' ) {

        # need to convert fields
        my $t  = ( stat( $handler->{rcsFile} ) )[9];
        my $n  = 1;
        my $in = "$uh,v";
        foreach my $rev ( @{ $handler->{revs} } ) {
            $converted += _convert_string( $rev->{text}, $in, "content of" )
              if defined $rev->{text};
            $converted += _convert_string( $rev->{log}, $in, "log in" )
              if defined $rev->{log};
            $converted += _convert_string( $rev->{comment}, $in, "comment in" )
              if defined $rev->{comment};
            $converted += _convert_string( $rev->{desc}, $in, "desc in" )
              if defined $rev->{desc};
            $converted += _convert_string( $rev->{author}, $in, "author of" )
              if defined $rev->{author};
        }
        if ($converted) {
            report "Converted $uh.txt,v ($converted changes)";
            $convertCount++;
            unless ( $options->{-i} ) {
                eval {
                    $handler->_writeMe();
                    utime( $t, $t, $handler->{rcsFile} );
                };
                if ($@) {
                    error
"Failed to write $uh history. Existing history may be corrupt: $@";
                }
            }
        }
    }
    else {
        report "No $uh history to convert" unless $options->{-i};
    }

    # Convert .txt
    my $t   = ( stat( $handler->{file} ) )[9];
    my $raw = $handler->readFile( $handler->{file} );
    $converted = _convert_string( $raw, $handler->{file}, "content of" );
    if ($converted) {
        report "Converted $uh.txt";
        $convertCount++;
        unless ( $options->{-i} ) {
            $handler->saveFile( $handler->{file}, $raw );
            utime( $t, $t, $handler->{file} );
        }
    }
}

# Convert the contents (*not* the names) of topics found in a web dir
sub _convert_topics_contents {
    my $web = shift;
    my $dir;

    opendir( $dir, "$Foswiki::cfg{DataDir}/$web" )
      || die "Failed to open '$web' $!";
    foreach my $e ( readdir($dir) ) {
        next if $e =~ /^\./;
        if ( $web && $e =~ /^(.*)\.txt$/ ) {
            _convert_topic( $web, $1 );
        }
        elsif (-d "$Foswiki::cfg{DataDir}/$web/$e"
            && -e "$Foswiki::cfg{DataDir}/$web/$e/WebPreferences.txt" )
        {
            _convert_topics_contents( $web ? "$web/$e" : $e );
        }
    }
}

1;

__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Author: CrawfordCurrie

Copyright (C) 2011-2014 Foswiki Contributors. Foswiki Contributors
are listed in the AUTHORS file in the root of this distribution.
NOTE: Please extend that file, not this notice.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.
