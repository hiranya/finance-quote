#!/usr/bin/perl -w
#
#    Copyright (C) 1998, Dj Padzensky <djpadz@padz.net>
#    Copyright (C) 1998, 1999 Linas Vepstas <linas@linas.org>
#    Copyright (C) 2000, Yannick LE NY <y-le-ny@ifrance.com>
#    Copyright (C) 2000, Paul Fenwick <pjf@cpan.org>
#    Copyright (C) 2000, Brent Neal <brentn@users.sourceforge.net>
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA
#    02111-1307, USA
#
# This code derived from Padzensky's work on package Finance::YahooQuote,
# but extends its capabilites to encompas a greater number of data sources.
#
# This package provides a base class for the various Yahoo services,
# and is based upon code by Xose Manoel Ramos <xmanoel@bigfoot.com>.
# Improvements based upon patches supplied by Peter Thatcher have
# also been integrated.

package Finance::Quote::Yahoo::Base;
require 5.004;

use strict;
use LWP::UserAgent;
use HTTP::Request::Common;
use Exporter;

use vars qw/$VERSION @FIELDS @FIELD_ENCODING $MAX_REQUEST_SIZE @ISA
            @EXPORT @EXPORT_OK/;

@ISA = qw/Exporter/;
@EXPORT = qw//;
@EXPORT_OK = qw/yahoo_request base_yahoo_labels/;

$VERSION = '0.19';

# This is the maximum number of stocks we'll batch into one operation.
# If this gets too big (>50 or thereabouts) things will break because
# some proxies and/or webservers cannot handle very large URLS.

$MAX_REQUEST_SIZE = 40;

# Yahoo uses encodes the desired fields as 1-2 character strings
# in the URL.  These are recorded below, along with their corresponding
# field names.

@FIELDS = qw/symbol name last date time net p_change volume bid ask
             close open day_range year_range eps pe div_date div div_yield
	     cap ex_div avg_vol/;

@FIELD_ENCODING = qw/s n l1 d1 t1 c1 p2 v b a p o m w e r r1 d y j1 q a2/;

# This returns a list of labels that are provided, so that code
# that make use of this module can know what it's dealing with.
# It also means that if we extend the code in the future to provide
# more information, we simply need to change this in one spot.

sub base_yahoo_labels {
	return (@FIELDS,"price","high","low");
}

# yahoo_request (restricted function)
#
# This function expects a Finance::Quote object, a base URL to use,
# and a list of symbols to lookup.  It relies upon the fact that
# the various Yahoo's all work the same way.

sub yahoo_request {
	my $quoter = shift;
	my $base_url = shift;
	my @symbols;
	my %info;
	my $ua = $quoter->user_agent;

	# Generate a suitable URL, now all it needs is the
	# ticker symbols.
	$base_url .= "?f=".join("",@FIELD_ENCODING)."&e=.csv&s=";

	while (@symbols = splice(@_,0,$MAX_REQUEST_SIZE)) {
		my $url = $base_url . join("+",@symbols);
		my $response = $ua->request(GET $url);
		return unless $response->is_success;

		# Okay, we have the data.  Just stuff it in
		# the hash now.

		foreach (split('\015?\012',$response->content)) {
			my @q = $quoter->parse_csv($_);
			my $symbol = $q[0];

			# If we weren't using a two dimesonal
			# hash, we could do the following with
			# a hash-slice.  Alas, we can't.

			for (my $i=0; $i < @FIELDS; $i++) {
				$info{$symbol,$FIELDS[$i]} = $q[$i];
			}

			$info{$symbol,"price"} = $info{$symbol,"last"};

			# Yahoo returns a line filled with N/A's if we
			# look up a non-existant symbol.  AFAIK, the
			# date flag will /never/ be defined properly
			# unless we've looked up a real stock.  Hence
			# we can use this to check if we've
			# successfully obtained the stock or not.

			if ($info{$symbol,"date"} eq "N/A") {
				$info{$symbol,"success"} = 0;
				$info{$symbol,"errormsg"} = "Stock lookup failed";
			} else {
				$info{$symbol,"success"} = 1;
			}

			# Extract the high and low values from the
			# day-range, if available

			if ($info{$symbol,"day_range"} =~ m{^"?\s*(\S+)\s*-\s*(\S+)"?$}) {
				$info{$symbol, "low"}  = $1;
				$info{$symbol, "high"} = $2;
			}
		} # End of processing each stock line.
	} # End of lookup loop.

	# Return undef's rather than N/As.  This makes things more suitable
	# for insertion into databases, etc.  Also remove silly HTML that
	# Yahoo inserts to put in little Euro symbols and stuff.  It's
	# pretty stupid to have HTML tags in a CSV file in the first
	# place, don't you think?

	foreach my $key (keys %info) {
		$info{$key} =~ s/<[^>]*>//g;
		undef $info{$key} if (defined($info{$key}) and 
                                      $info{$key} eq "N/A");
	}
	return %info if wantarray;
	return \%info;
}