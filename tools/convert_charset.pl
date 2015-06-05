#!/usr/bin/env perl
# See bottom of file for license and copyright information
#
# Foswiki inherited a horrible legacy, in that it is configured with a
# "site charset".  The site charset dictates the encoding used with
# character strings. The default encoding is iso-8859-1 which is a
# reasonable choice for most western languages.  However there are many
# languages that have characters that do not appear in this character
# set (for example, chinese, hebrew). If you didn't consider the
# possibility when you set up your wiki that your users might want to
# include text using these characters, then you may well have accepted
# the default for this setting. Unfortunately once you have chosen a
# character set, it becomes impossible to change the character set in
# the wiki, as the character set is associated with the wiki, and not
# with individual topic revisions.
#
# The solution to this problem is to convert your wiki to use the
# international UTF-8 encoding. That's what this module does. Even if
# you don't have an immediate need for non-western character sets this
# is worth doing, as Foswiki is moving in the direction of standardising
# on UTF-8 for all data. Using UTF-8 resolves many problems of character
# set conversion, most notably with WYSIWYG, so is highly recommended.
#
# Note that this module converts all the histories of all your topics,
# as well as the latest version of the topic. It also maps all web,
# topic and attachment names. It does not, however, touch the content of
# attachments.
#
# cd to the tools directory to run it
#

use strict;
use warnings;
use Encode;

BEGIN { do '../bin/setlib.cfg'; }

use Foswiki;
use Foswiki::Contrib::CharsetConverterContrib;

# Parse command-line arguments
my %args;
while ( my $a = shift @ARGV ) {
    if ( $a =~ /(.*?)=(.*)/ ) {
        $args{$1} = $2;
    }
    else {
        $args{$a} = 1;
    }
}

unless ( $args{-i} ) {
    local $/ = undef;
    print <<'INFORM';

Foswiki RCS database character set conversion

This script will convert the Foswiki RCS database pointed at by
{DataDir} and {PubDir} from the existing character set (as set
by {Site}{CharSet}) to UTF8.

For more information, see System.CharsetConverterContrib in your local
wiki or http://foswiki.org/Extensions/CharsetConverterContrib
INFORM
    die 'Cannot proceed without backup confirmation'
      unless ask(
"Have you backed up your data ($Foswiki::cfg{DataDir}) and pub ($Foswiki::cfg{PubDir}) directories"
      );
    die 'Cannot proceed without confirmation of access permissions'
      unless ask(
"Do you have write permission on all files and directories in $Foswiki::cfg{DataDir} and $Foswiki::cfg{PubDir}"
      );
    die
'Cannot proceed until you confirm that data is consistent with this setting'
      unless ask(
"\$Foswiki::cfg{Site}{CharSet} is set to '$Foswiki::cfg{Site}{CharSet}'. Is that correct for the data in your Foswiki database"
      );
}

Foswiki::Contrib::CharsetConverterContrib::convert_database(%args);

# Prompt user for a confirmation
sub ask {
    my $q = shift;
    my $reply;

    local $/ = "\n";

    $q .= '?' unless $q =~ /\?\s*$/;

    print $q. ' [y/n] ';
    while ( ( $reply = <STDIN> ) !~ /^[yn]/i ) {
        print "Please answer yes or no\n";
    }
    return ( $reply =~ /^y/i ) ? 1 : 0;
}

1;

__END__
Copyright (C) 2011 Foswiki Contributors.

Author: Crawford Currie http://c-dot.co.uk

For licensing info read LICENSE file in the Foswiki root.
This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details, published at
http://www.gnu.org/copyleft/gpl.html

As per the GPL, removal of this notice is prohibited.
